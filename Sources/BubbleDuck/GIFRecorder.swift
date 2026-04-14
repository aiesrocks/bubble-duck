// SPDX-License-Identifier: GPL-2.0-or-later
// BubbleDuck — records a short animated GIF of the dock tile simulation.

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Streams rendered frames directly into a CGImageDestination so we never
/// hold more than one frame in memory. Sampling 60 fps → 20 fps (every 3rd
/// frame) keeps GIFs visually smooth and file-size sane (~1–3 MB for 10–30s
/// at 256×256).
@MainActor
final class GIFRecorder {
    /// Output GIF frame rate. wmbubble's 15 ms tick is ~66 fps; 20 fps in the
    /// GIF is plenty for glance-friendly animation without huge files.
    static let gifFPS: Int = 20

    /// Simulation fps (how often `tick` is called by the controller).
    static let simFPS: Int = 60

    /// We take one frame out of every N simulation ticks.
    static var sampleEvery: Int { max(1, simFPS / gifFPS) }

    let outputURL: URL

    private let destination: CGImageDestination
    private let targetFrameCount: Int
    private var simTickCounter: Int = 0
    private var framesAppended: Int = 0
    private var finalized: Bool = false

    /// Invoked once with the GIF URL when recording completes successfully.
    var onComplete: ((URL) -> Void)?

    /// Creates a recorder and opens the destination file immediately.
    /// Throws if a GIF destination can't be created (e.g., disk full, invalid path).
    init(duration: TimeInterval) throws {
        let timestamp = GIFRecorder.timestampFormatter.string(from: Date())
        let picturesURL = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = picturesURL.appendingPathComponent("BubbleDuck-\(timestamp).gif")

        let expected = Int(duration * Double(Self.gifFPS))
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            expected,
            nil
        ) else {
            throw RecorderError.cantCreateDestination(url: url)
        }

        // Loop forever.
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        self.destination = dest
        self.outputURL = url
        self.targetFrameCount = expected
    }

    /// Feed a freshly-rendered frame. Returns `true` once recording is
    /// complete (the caller should release this recorder).
    @discardableResult
    func tick(image: NSImage) -> Bool {
        guard !finalized else { return true }

        simTickCounter += 1
        guard simTickCounter % Self.sampleEvery == 0 else { return false }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            // Missing frame — count the sim tick but don't advance the GIF.
            return false
        }

        let frameDelay: Double = 1.0 / Double(Self.gifFPS)
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]
        CGImageDestinationAddImage(destination, cg, frameProps as CFDictionary)
        framesAppended += 1

        if framesAppended >= targetFrameCount {
            finalize()
            return true
        }
        return false
    }

    /// Stop early and flush whatever's been captured so far.
    func cancel() {
        finalize()
    }

    /// Total seconds of output the recorder expects to produce.
    var durationSeconds: Double {
        Double(targetFrameCount) / Double(Self.gifFPS)
    }

    private func finalize() {
        guard !finalized else { return }
        finalized = true
        CGImageDestinationFinalize(destination)
        onComplete?(outputURL)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    enum RecorderError: Error {
        case cantCreateDestination(url: URL)
    }
}
