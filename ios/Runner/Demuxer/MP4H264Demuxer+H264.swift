//! SPDX-License-Identifier: GPL-3.0-or-later
import CoreMedia
import Foundation

extension MP4H264Demuxer {

    /// Parses the SPS RBSP to extract VUI timing information and returns a frame duration as CMTime.
    /// The method strips the one-byte NAL header and emulation-prevention bytes to form an RBSP, then
    /// walks the sequence parameter set fields until it reaches VUI timing. When both
    /// num_units_in_tick and time_scale are present and non-zero, it computes
    /// duration = (2 * num_units_in_tick) / time_scale and returns it, otherwise it yields nil.
    func deriveFrameDurationFromSPS(_ sps: Data) -> CMTime? {
        guard sps.count > 1 else { return nil }

        // RBSP build:
        // Strip the 1-byte NAL header and remove emulation-prevention bytes (0x000003) so
        // the bitreader sees the SPS payload exactly as defined by the H.264 syntax tables.
        // Ref: ITU-T H.264, Annex B (byte stream) and 7.4.1 (RBSP), VUI in 7.4.1.1.1.
        let rbsp: [UInt8] = {
            var out = [UInt8]()
            out.reserveCapacity(sps.count)
            var i = 1
            var z = 0
            while i < sps.count {
                let b = sps[i]
                if z >= 2 && b == 0x03 {
                    // Byte 0x03 after two consecutive 0x00 is EPB, skip it to reconstruct RBSP.
                    i += 1
                    z = 0
                    continue
                }
                out.append(b)
                z = (b == 0) ? (z + 1) : 0
                i += 1
            }
            return out
        }()

        // Start a bitreader at the SPS RBSP. Fields below are parsed in normative order.
        var br = BitReader(bytes: rbsp)

        // profile_idc / constraints / level_idc / seq_parameter_set_id
        // These gate optional syntax (e.g., scaling matrices) and do not affect VUI timing,
        // but we must advance correctly to reach the VUI payload later.
        let profile_idc = br.readBits(8) ?? 0
        _ = br.readBits(8)  // constraint_set_flags + reserved_zero_2bits
        _ = br.readBits(8)  // level_idc
        _ = br.readUE()  // seq_parameter_set_id

        // High-profile extras:
        // chroma_format_idc, bit depths, and optional scaling lists (8 or 12 lists).
        // We skip list contents but consume their Exp-Golomb deltas to keep alignment.
        if [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].contains(profile_idc) {
            let chroma_format_idc = br.readUE() ?? 1
            if chroma_format_idc == 3 { _ = br.readBits(1) }  // separate_colour_plane_flag
            _ = br.readUE()  // bit_depth_luma_minus8
            _ = br.readUE()  // bit_depth_chroma_minus8
            _ = br.readBits(1)  // qpprime_y_zero_transform_bypass_flag
            let seq_scaling_matrix_present_flag = br.readBits(1) ?? 0
            if seq_scaling_matrix_present_flag == 1 {
                let count = (chroma_format_idc == 3) ? 12 : 8
                for i in 0..<count {
                    let present = br.readBits(1) ?? 0
                    if present == 1 {
                        // Consume scaling list deltas, actual values aren’t needed for timing.
                        skipScalingList(&br, size: (i < 6) ? 16 : 64)
                    }
                }
            }
        }

        // pic_order_cnt_type (+ ancillary fields) and max_num_ref_frames etc.
        // These are not used for timing, but we must march through them to reach VUI.
        _ = br.readUE()  // log2_max_frame_num_minus4
        let pic_order_cnt_type = br.readUE() ?? 0
        if pic_order_cnt_type == 0 {
            _ = br.readUE()  // log2_max_pic_order_cnt_lsb_minus4
        } else if pic_order_cnt_type == 1 {
            _ = br.readBits(1)  // delta_pic_order_always_zero_flag
            _ = br.readSE()  // offset_for_non_ref_pic
            _ = br.readSE()  // offset_for_top_to_bottom_field
            let n = br.readUE() ?? 0
            for _ in 0..<n { _ = br.readSE() }  // offset_for_ref_frame[i]
        }

        _ = br.readUE()  // max_num_ref_frames
        _ = br.readBits(1)  // gaps_in_frame_num_value_allowed_flag
        _ = br.readUE()  // pic_width_in_mbs_minus1
        _ = br.readUE()  // pic_height_in_map_units_minus1
        let frame_mbs_only_flag = (br.readBits(1) ?? 1) == 1
        if !frame_mbs_only_flag { _ = br.readBits(1) }  // mb_adaptive_frame_field_flag
        _ = br.readBits(1)  // direct_8x8_inference_flag
        if (br.readBits(1) ?? 0) == 1 {  // frame_cropping_flag
            _ = br.readUE()
            _ = br.readUE()
            _ = br.readUE()
            _ = br.readUE()
        }

        // VUI presence flag — required to reach timing_info.
        guard (br.readBits(1) ?? 0) == 1 else { return nil }  // vui_parameters_present_flag

        // VUI prelude (aspect ratio / overscan / video_signal_type / chroma_loc_info).
        // We conditionally skip these to land precisely on timing_info_present_flag.
        let arPresent = br.readBits(1) ?? 0
        if arPresent == 1 {
            let arIdc = br.readBits(8) ?? 0
            if arIdc == 255 {
                _ = br.readBits(16)
                _ = br.readBits(16)
            }  // sar_width/height
        }
        if (br.readBits(1) ?? 0) == 1 { _ = br.readBits(1) }  // overscan
        if (br.readBits(1) ?? 0) == 1 {  // video_signal_type
            _ = br.readBits(3)  // video_format
            if (br.readBits(1) ?? 0) == 1 {
                _ = br.readBits(8)
                _ = br.readBits(8)
                _ = br.readBits(8)
            }  // colour_description
        }
        if (br.readBits(1) ?? 0) == 1 {
            _ = br.readUE()
            _ = br.readUE()
        }  // chroma_loc_info

        // timing_info_present_flag — this is the field we need for FPS/period derivation.
        // When present, num_units_in_tick and time_scale define the coded picture timing:
        // fps = time_scale / (2 * num_units_in_tick) for progressive content per common practice.
        // Ref: VUI timing fields in H.264;, CoreMedia duration is expressed as CMTime(value,timescale).
        guard (br.readBits(1) ?? 0) == 1 else { return nil }
        let num_units_in_tick = br.readBits(32) ?? 0
        let time_scale = br.readBits(32) ?? 0
        let fixed_frame_rate = br.readBits(1) ?? 0  // informative for CFR; not strictly required here

        // Validate timing fields; zero indicates timing not signaled.
        guard num_units_in_tick != 0, time_scale != 0 else { return nil }

        // Convert timing into CMTime: duration = (2 * num_units_in_tick) / time_scale seconds.
        // We clamp the CMTime timescale to Int32.max to satisfy CoreMedia API constraints.
        let num = Int64(2 * num_units_in_tick)
        let den = Int32(time_scale > Int32.max ? Int32.max : Int32(time_scale))
        let dur = CMTime(value: num, timescale: den)
        if dur.isValid { return dur }
        return nil
    }

    /// Advances a scaling list in the SPS/ PPS bitstream syntax without building the list.
    /// This consumes the signed Exp-Golomb deltas while maintaining the running scale state so the
    /// bitreader remains correctly positioned for subsequent fields.
    private func skipScalingList(_ br: inout BitReader, size: Int) {
        var lastScale = 8
        var nextScale = 8
        for _ in 0..<size {
            if nextScale != 0 {
                let delta = br.readSE() ?? 0
                nextScale = (lastScale + delta + 256) % 256
            }
            lastScale = (nextScale == 0) ? lastScale : nextScale
        }
    }

    /// Determines whether a slice NAL starts a new access unit by checking the first_mb_in_slice
    /// Exp-Golomb value. The method removes emulation-prevention bytes from the slice payload, reads
    /// the first macroblock index, and returns true when it equals zero, which indicates an AU
    /// boundary per the H.264 spec.
    private func isFirstSlice(_ nalu: Data) -> Bool {
        guard nalu.count > 1 else { return false }
        var payload = Array(nalu.dropFirst())
        var clean = [UInt8]()
        clean.reserveCapacity(payload.count)
        var i = 0
        while i < payload.count {
            if i + 2 < payload.count && payload[i] == 0 && payload[i + 1] == 0
                && payload[i + 2] == 3
            {
                clean.append(0)
                clean.append(0)
                i += 3
            } else {
                clean.append(payload[i])
                i += 1
            }
        }
        var br = BitReader(bytes: clean)
        if let firstMb = br.readUE() { return firstMb == 0 }
        return false
    }

    /// Splits the current mdatPayload into AVCC-framed NAL units using nalLengthSize-byte length
    /// prefixes. The routine accumulates NALs into the in-progress access unit, closes and emits the
    /// access unit on access unit delimiters or when a new VCL slice begins, and stashes any partial
    /// tail bytes into mdatRemainder to be completed by the next call. On completion, it advances
    /// mdatPayload by the number of bytes consumed.
    func drainAvccFromMdatPayload() {
        let lenSize = nalLengthSize
        guard (1...4).contains(lenSize) else {
            emitDebug("[MP4] invalid nalLengthSize=\(lenSize)")
            return
        }

        // Work on a snapshot; mutate mdatPayload only once at the end.
        let payload = mdatPayload
        var offset = 0
        let total = payload.count

        func commitAndReturn(stashFrom: Int) {
            // Stash any partial tail (prefix or prefix+partial NAL) for the next call
            if stashFrom < total {
                // Stash the remaining bytes for the next call
                mdatRemainder = safeSlice(payload, stashFrom, total) ?? Data()
            } else {
                mdatRemainder.removeAll(keepingCapacity: true)
            }
            if offset > 0 { mdatPayload.removeFirst(offset) }
        }

        while true {
            // Need a full length prefix
            if offset + lenSize > total {
                commitAndReturn(stashFrom: offset)
                return
            }

            // Read big-endian length
            var naluLen = 0
            for i in 0..<lenSize {
                naluLen = (naluLen << 8)
                naluLen |= Int(payload[payload.index(payload.startIndex, offsetBy: offset + i)])
            }
            // Skip zero-length NALs (do appear in the wild)
            if naluLen == 0 {
                offset += lenSize
                if offset == total {
                    mdatRemainder.removeAll(keepingCapacity: true)
                    if offset > 0 { mdatPayload.removeFirst(offset) }
                    return
                }
                continue
            }

            let start = offset + lenSize
            let end = start + naluLen
            if end > total {
                // Not all bytes for this NAL yet → stash from the prefix and wait
                commitAndReturn(stashFrom: offset)
                emitDebug("[MP4] stashed tail \(mdatRemainder.count)B (waiting for next bytes)")
                return
            }

            // AVCC-framed NAL including its length prefix (what CM expects)
            guard let naluWithLen = safeSlice(payload, offset, end) else {
                commitAndReturn(stashFrom: offset)
                return
            }
            // Raw NAL without the prefix (for type + slice-boundary checks)
            guard let rawNAL = safeSlice(payload, start, end),
                let header = safeByte(payload, start)
            else {
                commitAndReturn(stashFrom: offset)
                return
            }
            let nalType = header & 0x1F

            emitDebug("[MP4] NAL type \(nalType) len \(naluLen)")

            if nalType == 9 {
                // AUD = frame boundary
                if !avccAU.isEmpty {
                    emitDebug(
                        "[MP4] AUD → emit AU (\(avccAU.count) NALs, key=\(avccAUIsIDR ? 1 : 0))")
                    emitAVCCAU()
                }
                // Do NOT include AUD in the AU
            } else {
                let isVCL = (nalType == 1 || nalType == 5)
                let firstSlice = isVCL && isFirstSlice(rawNAL)

                // If a new slice starts and we already have slices → close previous AU
                if isVCL && firstSlice && !avccAU.isEmpty { emitAVCCAU() }

                if isVCL && avccAU.isEmpty { avccAUIsIDR = (nalType == 5) }
                avccAU.append(naluWithLen)
            }

            offset = end
            if offset == total { break }
        }

        // Consumed cleanly
        if offset > 0 { mdatPayload.removeFirst(offset) }
        mdatRemainder.removeAll(keepingCapacity: true)
    }

    /// Safely returns a single byte from a Data buffer at the specified index.
    /// This bounds-checks the access and avoids undefined behavior from out-of-range indices by
    /// returning nil when the position is invalid.
    @inline(__always)
    private func safeByte(_ data: Data, _ idx: Int) -> UInt8? {
        guard idx >= 0, idx < data.count else { return nil }
        let i = data.index(data.startIndex, offsetBy: idx)
        return data[i]
    }

}
