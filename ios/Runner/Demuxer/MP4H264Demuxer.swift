//! SPDX-License-Identifier: GPL-3.0-or-later
import CoreMedia
import Foundation
import VideoToolbox

/**
 A minimal MP4 H.264 demuxer for progressive, non-fragmented
 files. It expects the usual layout of an ftyp and moov box up front,
 followed by one or more mdat boxes containing encoded video samples.
 Fragmented movies that use moof/traf are not supported.

 The demuxer is specialized for files with a single H.264 video track
 carrying avc1 or avc3 sample entries. Within each mdat payload,
 samples are assumed to be framed in AVCC format: each NAL unit is preceded
 by a length field of nalLengthSize bytes. The SPS and PPS NALs required
 to configure decoding are extracted from the avcC box and cached. A
 CMVideoFormatDescription is created once those parameter sets are known.

 Frame timing is derived primarily from the SPS VUI timing fields when
 available, since they provide the most accurate representation of the
 intended frame rate. All state mutations are isolated in this actor,
 ensuring safe concurrency when parsing bytes and scheduling decoded
 frames into a ByteSampleBufferView.
 */

actor MP4H264Demuxer {

    /// Rendering target. A thin wrapper around AVSampleBufferDisplayLayer
    /// with its own CMTimebase. The demuxer enqueues decoded sample buffers
    /// here once the format description is ready.
    let view: ByteSampleBufferView

    // Latency overlay that displays latency timing info on top of the video.
    let latencyOverlay = SeiLatencyOverlay()

    /// Client callbacks. onAspectRatio is invoked once coded width, height,
    /// and pixel aspect ratio are known so that UI can adjust its layout.
    /// onDebug is invoked whenever notable parsing or scheduling events occur.
    var onAspectRatio: ((Double) -> Void)?
    var onDebug: ((String) -> Void)?

    /// Parser state machine. In readingHeaders mode we accumulate and decode
    /// MP4 boxes until moov and a usable track description are available.
    /// Once inside an mdat, we switch to streamingMdat and consume payload
    /// bytes until the declared size (if any) is exhausted.
    enum State { case readingHeaders, streamingMdat }
    var state: State = .readingHeaders
    var buffer = Data()

    /// AVC decoder configuration. The nalLengthSize field (usually 4)
    /// determines how many bytes are used for NAL length prefixes. SPS and
    /// PPS NAL units parsed from the avcC box are stored here until they
    /// can be fed into a format description. The sample entry FourCC is kept
    /// for diagnostics.
    var nalLengthSize: Int = 4
    var spsNALs: [Data] = []
    var ppsNALs: [Data] = []
    var sampleEntryFourCC: String = "avc1"

    /// Frame duration information. If the SPS contains VUI timing info, it
    /// is converted into a CMTime and stored in derivedFrameDur. Otherwise,
    /// a default of ~33 ms per frame is assumed.
    var derivedFrameDur: CMTime?
    var warnedNoVuiTiming = false

    /// Sample size table from the stsz box. Either a single default size
    /// applies to all samples, or an explicit array of per-sample sizes is
    /// provided. sampleIndex tracks which entry we are up to when draining
    /// the payload.
    var sampleSizes: [Int] = []
    var defaultSampleSize: Int = 0
    var sampleIndex: Int = 0

    /// State for consuming mdat payloads. If the box declares a length, it
    /// is counted down in mdatRemaining. Otherwise, nil means until EOF.
    /// The current buffer under inspection is mdatPayload. Any partial NAL
    /// spanning chunk boundaries is stashed in mdatRemainder.
    var inMdat: Bool = false
    var mdatRemaining: Int64? = nil
    var mdatPayload = Data()
    var mdatRemainder = Data()

    /// Access unit assembly. For AVCC, we concatenate length-prefixed NALs
    /// into avccAU, marking whether the unit contains an IDR slice. Once
    /// a complete AU is recognized, it is packaged into a CMSampleBuffer.
    var avccAU: [Data] = []
    var avccAUIsIDR: Bool = false

    /// Decoding configuration. Once SPS/PPS are known we build a
    /// CMVideoFormatDescription and cache it here. All emitted sample
    /// buffers reference this description. Frame scheduling uses a
    /// monotonically increasing counter and the display layer’s timebase
    /// to maintain smooth playback.
    var fmtDesc: CMVideoFormatDescription?
    var frameIndex: Int64 = 0
    var schedNextPTS: CMTime = .zero
    var firstAfterFmtDesc: Bool = true
    let leadFrames: Int32 = 1

    /// Structs to capture MP4 box contents. STSZ wraps sample sizes,
    /// AvcC wraps the AVC decoder config record, and Trak summarizes a
    /// video track’s essentials.
    struct STSZ {
        var defaultSize: Int
        var sizes: [Int]
    }

    struct AvcC {
        var nalLengthSize: Int
        var sps: [Data]
        var pps: [Data]
    }

    struct Trak {
        var isVideo: Bool = false
        var trackID: UInt32 = 0
        var timescale: Int32? = nil
        var stsz: STSZ = .init(defaultSize: 0, sizes: [])
        var avcC: AvcC = .init(nalLengthSize: 4, sps: [], pps: [])
    }

    /// The video track ID, as read from the moov/trak/tkhd box.
    var videoTrackID: UInt32 = 0

    /// Fragmented movie support
    var fragmentVideoSampleSizes: [Int] = []
    /// The video trun's data_offset, as written (relative to the moof start), converted to an offset within the mdat payload.
    var fragmentVideoDataOffset: Int = 0
    /// The video trun's data_offset, as written (relative to the moof start).
    var fragmentVideoMoofRelOffset: Int = 0
    /// How many of the fragment's video samples have been emitted so far.
    var fragmentSampleCursor: Int = 0
    /// True when the current mdat has a video sample plan from its moof
    var haveFragmentPlan: Bool = false
    /// Byte size of the moof preceding the current mdat, to turn a moof-relative
    /// trun data_offset into an offset within the mdat payload.
    var currentMoofSize: Int = 0

    init(view: ByteSampleBufferView) {
        self.view = view
    }

    /// Utility function to forward a debug string to the client’s logging hook.
    @inline(__always)
    func emitDebug(_ s: String) { onDebug?(s) }

    /// Utility function to safely slice a Data buffer and force a copy. Prevents
    /// aliasing or out-of-bounds access when mutating the underlying buffer.
    @inline(__always)
    func safeSlice(_ data: Data, _ start: Int, _ end: Int) -> Data? {
        guard start >= 0, end >= start, end <= data.count else { return nil }
        let s = data.index(data.startIndex, offsetBy: start)
        let e = data.index(s, offsetBy: end - start)
        return Data(data[s..<e])
    }
}
