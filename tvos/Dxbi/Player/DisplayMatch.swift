// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import AVFoundation
import AVKit
import CoreMedia
import UIKit

/**
 * Match Content: while a video plays, the TV switches to its dynamic range (HDR10, Dolby Vision's HDR,
 * HLG) and frame rate, when the Apple TV is set to (Settings → Video and Audio → Match Content), as
 * Apple's own player does. Back to the Apple TV's own mode a moment after the player closes (not
 * between episodes: the TV would switch back and forth).
 */
@MainActor
enum DisplayMatch {
    private static var resetting: Task<Void, Never>?

    private static var manager: AVDisplayManager? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }?.avDisplayManager
    }

    /** Once mpv knows what the picture is (it takes a moment after the video starts) */
    static func follow(_ mpv: MPV) async {
        for _ in 0..<60 {
            if Task.isCancelled { return }
            if let format = mpv.videoFormat { return apply(format) }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    static func apply(_ format: (transfer: String, width: Int, height: Int, fps: Double)) {
        resetting?.cancel()
        guard let manager, manager.isDisplayCriteriaMatchingEnabled else { return }
        let hdr = format.transfer == "pq" || format.transfer == "hlg"
        // (only a frame rate to match, for a video in the usual range: nothing to ask for without one)
        guard hdr || format.fps > 0 else { return }
        let extensions: [String: Any] = hdr ? [
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String,
            kCMFormatDescriptionExtension_TransferFunction as String: (format.transfer == "hlg" ? kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG : kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ) as String,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String,
        ] : [
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String,
            kCMFormatDescriptionExtension_TransferFunction as String: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String,
        ]
        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_HEVC,
                                                    width: Int32(max(format.width, 1)), height: Int32(max(format.height, 1)),
                                                    extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        guard status == noErr, let description else { return }
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: Float(max(format.fps, 0)), formatDescription: description)
    }

    /**
     * The player closed: the Apple TV's own mode again, straight away. [keep]: the next episode's
     * player follows, so the TV stays as it is for it (it would switch back and forth), unless that
     * doesn't come
     */
    static func reset(keep: Bool) {
        resetting?.cancel()
        guard keep else { return release() }
        resetting = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { release() }
        }
    }

    private static func release() {
        // (only when the TV was switched: asking again for the mode it's in can still blank it)
        if let manager, manager.preferredDisplayCriteria != nil { manager.preferredDisplayCriteria = nil }
    }
}
