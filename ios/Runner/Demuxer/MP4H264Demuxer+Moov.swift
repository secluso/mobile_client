//! SPDX-License-Identifier: GPL-3.0-or-later

import CoreMedia
import Foundation

extension MP4H264Demuxer {

    /// Parses a complete moov box and extracts the single best video track. This walks
    /// its child boxes, picks the video trak, pulls SPS/PPS and nalLengthSize from
    /// its avcC, and reads sample sizing from stsz. If the SPS advertises VUI
    /// timing, a frame duration is derived and cached. When enough information is
    /// available, a CMVideoFormatDescription is built and the aspect-ratio callback
    /// is fired.
    func parseMoov(_ data: Data) {
        emitDebug("[MP4] parsing moov (\(data.count) B)")
        var cursor = 0
        var bestTrack: Trak? = nil

        while cursor + 8 <= data.count {
            // Read the 32-bit big-endian box size and ASCII fourCC of the child box inside moov.
            // In ISO BMFF / QTFF, every box starts with size(4) + type(4). Size==1 signals a 64-bit
            // largesize that follows, and size==0 means “extends to end of file/parent box.”  [oai_citation:0‡Apple Developer](https://developer.apple.com/library/archive/sitemap.php)
            guard let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { break }
            var boxSize = Int(size32)
            var headerLen = 8

            // Handle extended size (largesize) when size==1. Validate the computed bounds against moov.
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { break }
                boxSize = Int(size64)
                headerLen = 16
            }
            // Ensure the declared box fully fits inside the current moov payload.
            guard boxSize >= headerLen, cursor + boxSize <= data.count else { break }

            // Compute the child box payload range and copy it out to avoid aliasing the parent buffer.
            let payloadStart = cursor + headerLen
            let payloadEnd = cursor + boxSize
            guard let payload = safeSlice(data, payloadStart, payloadEnd) else { break }

            // We only care about trak boxes here. Keep the *best* (i.e., first valid video) track.
            if typ == "trak", var t = parseTrak(payload), t.isVideo {
                bestTrack = t
            }

            // Advance to the next child box within moov.
            cursor += boxSize
        }

        // No usable video track in this moov—log and bail out early.
        guard bestTrack?.isVideo == true else {
            emitDebug("[MP4] moov: no video track found")
            return
        }

        // Pull AVC decoder configuration from the chosen track’s avcC (AVCDecoderConfigurationRecord):
        // this yields nalLengthSize and the SPS/PPS arrays required to create a format description.
        // (AVC configuration is defined in ISO/IEC 14496-15.)
        nalLengthSize = bestTrack!.avcC.nalLengthSize
        spsNALs = bestTrack!.avcC.sps
        ppsNALs = bestTrack!.avcC.pps

        // Read sample sizing from stsz: either a single default size (CBR-like) or a table of sizes.
        defaultSampleSize = bestTrack!.stsz.defaultSize
        sampleSizes = bestTrack!.stsz.sizes

        // Record the track ID of the chosen video track for later matching against traf boxes in fragments.
        videoTrackID = bestTrack!.trackID
        emitDebug("[MP4] moov: videoTrackID=\(videoTrackID)")

        // Derive frame duration from SPS VUI timing if present. This is preferred to table deltas
        // because it encodes the intended frame rate in the elementary stream itself.
        if let sps = spsNALs.first, let fd = deriveFrameDurationFromSPS(sps) {
            derivedFrameDur = fd
            let fps = 1.0 / CMTimeGetSeconds(fd)
            emitDebug(String(format: "[MP4] SPS VUI-derived fps ≈ %.3f", fps))
        }

        emitDebug(
            "[MP4] moov: nalLenSize=\(nalLengthSize) sps=\(spsNALs.count) pps=\(ppsNALs.count)")
        // With SPS/PPS available, build a CMVideoFormatDescription and publish aspect ratio.
        buildFormatDescription()
    }
    /// Parses a trak box and returns a summarized Trak if it represents video.
    /// The function looks only at the nested mdia box to collect timing and sample
    /// table pointers, deferring deeper parsing to helper routines.
    func parseTrak(_ data: Data) -> Trak? {
        var t = Trak()
        var cursor = 0

        while cursor + 8 <= data.count {
            // Walk child boxes inside trak. We care primarily about mdia, which holds media header
            // timing and a pointer chain down to the sample table.  [oai_citation:1‡Apple Developer](https://developer.apple.com/library/archive/sitemap.php)
            guard let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { break }
            var boxSize = Int(size32)
            var headerLen = 8
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { break }
                boxSize = Int(size64)
                headerLen = 16
            }
            guard boxSize >= headerLen, cursor + boxSize <= data.count else { break }

            let payloadStart = cursor + headerLen
            let payloadEnd = cursor + boxSize
            guard let payload = safeSlice(data, payloadStart, payloadEnd) else { break }

            // The track ID is stored in the tkhd box. 
            // It is a 32-bit integer at offset 12 for version 0 and offset 20 for version 1.
            //  We read it here to identify the video track later when parsing fragments.
            if typ == "tkhd" {
                if let versionByte = payload.be32(at: 0) {
                    let version = Int((versionByte >> 24) & 0xFF)
                    let idOffset = version == 0 ? 12 : 20
                    if let id = payload.be32(at: idOffset) { t.trackID = id }
                }
            }

            // Delegate to mdia to determine handler type (video vs. other) and collect timing.
            if typ == "mdia" {
                parseMdia(payload, into: &t)
            }

            cursor += boxSize
        }

        // Only return a track summary if it’s a video track (hdlr=vide).
        return t.isVideo ? t : nil
    }

    /// Parses an mdia box, determining whether the track is video from hdlr,
    /// extracting the media timescale from mdhd, and delegating to minf for
    /// sample table discovery. Results are accumulated into the provided Trak.
    private func parseMdia(_ data: Data, into t: inout Trak) {
        var cursor = 0
        var isVideo = false

        while cursor + 8 <= data.count {
            // mdia contains:
            //   • hdlr (handler) → declares the media type (e.g., vide, soun, text)
            //   • mdhd (media header) → media timescale & language
            //   • minf (media information) → points toward the sample table (via stbl)  [oai_citation:2‡Apple Developer](https://developer.apple.com/library/archive/sitemap.php)
            guard let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { break }
            var boxSize = Int(size32)
            var headerLen = 8
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { break }
                boxSize = Int(size64)
                headerLen = 16
            }
            guard boxSize >= headerLen, cursor + boxSize <= data.count else { break }

            let payloadStart = cursor + headerLen
            let payloadEnd = cursor + boxSize
            guard let payload = safeSlice(data, payloadStart, payloadEnd) else { break }

            switch typ {
            case "hdlr":
                // The handler type is a 4-byte code at offset 8 of the hdlr payload in QTFF/ISO BMFF.
                // We mark this track as video only when handler==vide.  [oai_citation:3‡Apple Developer](https://developer.apple.com/library/archive/sitemap.php)
                if let handler = payload.fourCC(at: 8) { isVideo = (handler == "vide") }

            case "mdhd":
                // mdhd is a FullBox. Version 0 uses 32-bit creation/modification times. Version 1 uses
                // 64-bit. The *timescale* field follows those timestamps:
                //   v0 layout: [ver+flags(4)] [ctime(4)] [mtime(4)] [timescale(4)] [duration(4)]
                //   v1 layout: [ver+flags(4)] [ctime(8)] [mtime(8)] [timescale(4)] [duration(8)]
                // We extract the 32-bit timescale, which defines “ticks per second” for this media.  [oai_citation:4‡Apple Developer](https://developer.apple.com/library/archive/sitemap.php)
                guard let versionByte = payload.be32(at: 0) else { break }  // first byte carries version
                let version = Int((versionByte >> 24) & 0xFF)
                if version == 0 {
                    if let ts = payload.be32(at: 12) { t.timescale = Int32(ts) }
                } else {
                    if let ts = payload.be32(at: 4 + 8 + 8) { t.timescale = Int32(ts) }
                }

            case "minf":
                // Descend into minf to reach the sample table branch where codec config and sizing live.
                parseMinf(payload, into: &t)

            default:
                break
            }

            cursor += boxSize
        }

        t.isVideo = isVideo
    }

    /// Parses a minf box and locates the sample table (stbl). When present, it
    /// forwards parsing to parseStbl so codec configuration and sample sizing can
    /// be gathered for later demuxing.
    private func parseMinf(_ data: Data, into t: inout Trak) {
        var cursor = 0
        while cursor + 8 <= data.count {
            // minf contains the media-specific header and a data information box; for demuxing we
            // continue to stbl (sample table), which holds stsd (sample descriptions/codec config)
            // and stsz (sample sizes), among others.
            guard let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { break }
            var boxSize = Int(size32)
            var headerLen = 8
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { break }
                boxSize = Int(size64)
                headerLen = 16
            }
            guard boxSize >= headerLen, cursor + boxSize <= data.count else { break }

            let payloadStart = cursor + headerLen
            let payloadEnd = cursor + boxSize
            guard let payload = safeSlice(data, payloadStart, payloadEnd) else { break }

            if typ == "stbl" {
                // Delegate to the sample table parser to locate avcC inside stsd and read stsz.
                parseStbl(payload, into: &t)
            }

            cursor += boxSize
        }
    }

}
