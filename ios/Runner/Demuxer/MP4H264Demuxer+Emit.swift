//! SPDX-License-Identifier: GPL-3.0-or-later
import CoreMedia
import Foundation
import VideoToolbox

extension MP4H264Demuxer {
    /// Creates the CMVideoFormatDescription from the SPS/PPS parameter sets found in avcC.
    /// This validates the configured nalLengthSize, initializes fmtDesc on success, publishes
    /// coded dimensions via onAspectRatio, and resets the scheduling anchor so the next frame
    /// can align the playback clock.
    func buildFormatDescription() {
        guard fmtDesc == nil, let sps = spsNALs.first, let pps = ppsNALs.first else { return }

        // We must pass exactly the SPS and PPS parameter sets (without start codes) to this API.
        // The nalLengthSize passed here is how many bytes we use for length prefixes when encoding samples.
        var desc: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress!
                let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress!
                let paramPtrs: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let paramSizes: [Int] = [sps.count, pps.count]

                // Create a CMVideoFormatDescription from the SPS/PPS sets. Apple docs require
                // these parameters so the decompression session or display layer knows resolution,
                // profile, level, etc. (https://developer.apple.com/documentation/coremedia/)
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: paramPtrs,
                    parameterSetSizes: paramSizes,
                    nalUnitHeaderLength: Int32(nalLengthSize),
                    formatDescriptionOut: &desc
                )
            }
        }

        if status == noErr, let d = desc {
            fmtDesc = d

            // Extract the coded width & height from the format description
            let dims = CMVideoFormatDescriptionGetDimensions(d)
            emitDebug(
                "[MP4] fmtDesc created \(dims.width)x\(dims.height), nalLenSize=\(nalLengthSize)")

            // Start the latency overlay on the main thread
            Task { @MainActor in
                latencyOverlay.start(on: self.view)
            }

            // Only call the aspect callback when dimensions are valid
            if dims.width > 0 && dims.height > 0 {
                onAspectRatio?(Double(dims.width) / Double(dims.height))
            }
            // We’re reconfiguring—so allow the next frame to anchor the clock
            firstAfterFmtDesc = true
            schedNextPTS = .zero
        } else {
            emitDebug("[MP4] fmtDesc create failed: \(status)")
        }
    }

    /// Ensures a format description exists by invoking buildFormatDescription() if needed.
    /// Call this before constructing any CMSampleBuffer to guarantee the decoder is configured.
    func ensureFormatDescription() {
        if fmtDesc == nil { buildFormatDescription() }
    }

    /// Builds a contiguous AVCC buffer from a list of NAL units, optionally prepending length
    /// prefixes when the input NALs are raw. The result is copied into a CMBlockBuffer that
    /// can be attached to a sample buffer without further mutation.
    private func makeBlockBuffer(from nals: [Data], alreadyLengthPrefixed: Bool) -> CMBlockBuffer? {
        // Compute total byte length to allocate: either sum raw NAL lengths + prefix lengths,
        // or sum already length-prefixed NALs directly.
        var total = 0
        if alreadyLengthPrefixed {
            for n in nals { total += n.count }
        } else {
            for n in nals { total += nalLengthSize + n.count }
        }

        var combined = Data()
        combined.reserveCapacity(total)

        for n in nals {
            if alreadyLengthPrefixed {
                combined.append(n)
            } else {
                var beLen = UInt32(n.count).bigEndian
                // Prepend big-endian length prefix for each raw NAL (per AVCC format).
                let lenData = withUnsafeBytes(of: &beLen) { Data($0) }
                combined.append(lenData)
                combined.append(n)
            }
        }

        // Create a CMBlockBuffer referencing the contiguous memory of combined.
        // According to Apple docs, CMBlockBufferCreateWithMemoryBlock may copy or reference,
        // depending on flags and custom block source.
        var bb: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: combined.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: combined.count,
            flags: 0,
            blockBufferOut: &bb
        )
        guard status == kCMBlockBufferNoErr, let block = bb else { return nil }

        // Copy the bytes into the CMBlockBuffer. This ensures the block buffer has the actual data.
        combined.withUnsafeBytes { ptr in
            _ = CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: combined.count
            )
        }

        return block
    }

    /// Enqueues a completed access unit composed of one or more NALs. The method computes the
    /// next presentation timestamp using the view’s timebase, applies sync and display-immediately
    /// attachments, posts the buffer to the UI, and advances the frame counter.
    func enqueueAU(_ nals: [Data], isIDR: Bool, alreadyLengthPrefixed: Bool) {
        guard let fmt = fmtDesc else {
            emitDebug("[MP4] skip AU: fmtDesc not ready")
            return
        }
        guard let bb = makeBlockBuffer(from: nals, alreadyLengthPrefixed: alreadyLengthPrefixed)
        else {
            emitDebug("[MP4] blockBuffer failed")
            return
        }

        // Compute frame duration from SPS/VUI; then pick the next PTS in sync with the display layer timebase.
        let frameDur = currentFrameDuration()
        let (pts, isFirst) = nextClockAlignedPTS(frameDur)

        // Start latency overlay processing before building sample buffer
        latencyOverlay.onAvccNalArray(nals: nals, pts: pts)

        var timing = CMSampleTimingInfo(
            duration: frameDur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)

        let ptsSec = CMTimeGetSeconds(pts)
        emitDebug(
            "[MP4] AU #\(frameIndex) pts=\(String(format: "%.3f", ptsSec)) idr=\(isIDR ? 1 : 0) first=\(isFirst ? 1 : 0)"
        )

        var sbuf: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: fmt,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sbuf)
        guard status == noErr, let sb = sbuf else {
            emitDebug("[MP4] CMSampleBuffer create failed: \(status)")
            return
        }

        // Mark sync frames (IDR) vs non-sync, and optionally display immediately for the first sample
        if let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(att, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(isIDR ? kCFBooleanFalse : kCFBooleanTrue).toOpaque())
            if isFirst {
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }

        // Hand off to UI (main thread) for actual enqueue
        postToUI(sb, isIDR: isIDR, isFirst: isFirst)
        emitDebug("[MP4] enqueued AU #\(frameIndex) key=\(isIDR ? 1 : 0)")
        frameIndex += 1
    }

    /// Emits a single AVCC-framed sample that already contains length-prefixed NAL units.
    /// The method schedules the sample using VUI-derived frame duration, sets sync flags based
    /// on whether the sample contains an IDR slice, and forwards it to the display layer.
    func emitSample(avccSample sample: Data) {
        // Require a valid format description and nonempty sample
        guard let fmtDesc = fmtDesc, sample.count > 0 else { return }

        // Use the derived frame duration from SPS/VUI
        let frameDur = currentFrameDuration()
        let (pts, isFirst) = nextClockAlignedPTS(frameDur)

        // Notify latency overlay of the sample being emitted
        latencyOverlay.onAvccSample(sample: sample, nalLengthSize: nalLengthSize, pts: pts)

        // Build a CMBlockBuffer for the sample bytes
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: sample.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: sample.count,
                flags: 0,
                blockBufferOut: &block) == kCMBlockBufferNoErr,
            let bb = block
        else { return }

        // Copy the sample bytes into the CMBlockBuffer
        _ = sample.withUnsafeBytes { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: sample.count)
        }

        // Set up timing info; decodeTimeStamp left invalid since we use presentation time only
        var timing = CMSampleTimingInfo(
            duration: frameDur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sbuf: CMSampleBuffer?
        // Create a ready CMSampleBuffer wrapping the block buffer + format descriptor + timing
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: bb,
                formatDescription: fmtDesc,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: [sample.count],
                sampleBufferOut: &sbuf) == noErr,
            let sb = sbuf
        else { return }

        // Decide whether this sample is a sync frame (IDR) by scanning its NAL units
        let isIDR = sampleHasIdr(avccSample: sample, nalLengthSize: nalLengthSize)

        // Configure sample attachments dictionary:
        // kCMSampleAttachmentKey_NotSync = false for IDR, true otherwise
        // For the first frame after reconfiguration or flush, set kCMSampleAttachmentKey_DisplayImmediately
        if let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(att, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(isIDR ? kCFBooleanFalse : kCFBooleanTrue).toOpaque())
            if isFirst {
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }

        // Forward to UI / display layer
        postToUI(sb, isIDR: isIDR, isFirst: isFirst)
        emitDebug("[MP4] displayed sample PTS=\(pts.seconds) (IDR=\(isIDR))")
    }

    /// Scans an AVCC sample to determine if any NAL unit is an IDR slice. The routine walks the
    /// length-prefixed NALs using nalLengthSize and returns true on the first type-5 slice.
    private func sampleHasIdr(avccSample data: Data, nalLengthSize: Int) -> Bool {
        var i = 0
        while i + nalLengthSize <= data.count {
            var n = 0
            for j in 0..<nalLengthSize { n = (n << 8) | Int(data[i + j]) }
            i += nalLengthSize
            guard i + n <= data.count else { break }
            if (data[i] & 0x1F) == 5 { return true }  // IDR
            i += n
        }
        return false
    }

    /// Returns the current per-frame duration. This implementation uses VUI timing exclusively
    /// and yields .invalid until SPS timing has been parsed, ensuring scheduling does not start
    /// with an arbitrary fallback.
    @inline(__always)
    func currentFrameDuration() -> CMTime {
        // SPS VUI timing 
        // Android's MediaCodec does not; fall back to ~33 ms
        // Frames are scheduled no earlier than they arrive anyway
        if let d = derivedFrameDur, d.isValid { return d }
        if !warnedNoVuiTiming {
            warnedNoVuiTiming = true
            emitDebug("[MP4] no SPS VUI timing; assuming 30 fps for scheduling")
        }
        return CMTime(value: 1, timescale: 30)
    }
    // Computes the next presentation timestamp aligned to the display layer’s timebase, keeping
    /// a small lead to avoid late frames. The first frame after configuration anchors the timebase
    /// and may be marked to display immediately to establish the clock.
    @inline(__always)
    private func nextClockAlignedPTS(_ frameDur: CMTime) -> (pts: CMTime, isFirst: Bool) {
        // Ensure PTS is never "behind" the display layer's timebase.
        let tbNow = view.timebaseNow()
        let lead = CMTimeMultiply(frameDur, multiplier: leadFrames)

        // Initialize if needed
        if CMTIME_IS_INVALID(schedNextPTS) || schedNextPTS == .zero {
            schedNextPTS = CMTIME_IS_VALID(tbNow) ? CMTimeAdd(tbNow, lead) : .zero
        }

        // Keep PTS at least lead ahead of the TB (prevents late drops)
        if CMTIME_IS_VALID(tbNow) {
            let minPTS = CMTimeAdd(tbNow, lead)
            if CMTimeCompare(schedNextPTS, minPTS) < 0 {
                schedNextPTS = minPTS
            }
        }

        let pts = schedNextPTS
        schedNextPTS = CMTimeAdd(schedNextPTS, frameDur)

        // First frame after (re)config anchors the timebase and bypasses scheduling.
        let first = firstAfterFmtDesc || !view.isAnchored()
        firstAfterFmtDesc = false
        return (pts, first)
    }

    /// Enqueues the prepared CMSampleBuffer on the display layer on the main thread. This isolates UI work from the demuxer actor, preserves thread-safety, and passes through whether the buffer is a keyframe and whether it should bypass scheduling to establish the timebase anchor on the very first frame.

    private func postToUI(_ sb: CMSampleBuffer, isIDR: Bool, isFirst: Bool) {
        Task { @MainActor in
            guard !view.isShuttingDown else { return }
            view.enqueue(sb, isIDR: isIDR, isFirst: isFirst)
        }
    }

    /// Emits the currently accumulated AVCC access unit as a single sample. The AU is constructed from length-prefixed NALs gathered during mdat draining; after enqueue the local buffers are cleared and the keyframe flag is reset for the next AU.
    @inline(__always)
    func emitAVCCAU() {
        guard !avccAU.isEmpty else { return }
        enqueueAU(avccAU, isIDR: avccAUIsIDR, alreadyLengthPrefixed: true)
        avccAU.removeAll(keepingCapacity: true)
        avccAUIsIDR = false
    }

}
