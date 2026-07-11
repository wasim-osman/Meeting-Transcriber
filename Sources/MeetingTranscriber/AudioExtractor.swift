import AVFoundation
import Foundation

enum AudioExtractor {
    // Exports any audio/video to a temp M4A (16-bit PCM equivalent via AAC).
    // WhisperKit's AudioProcessor reads M4A natively via AVAudioFile.
    static func extract(from source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)

        // If it's already a plain audio file, pass through directly
        let audioOnly: Set<String> = ["mp3", "wav", "flac", "aac", "ogg", "opus", "m4a", "wma"]
        if audioOnly.contains(source.pathExtension.lowercased()) {
            return source
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioExtractor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetExportSession"])
        }
        // export(to:as:) is the non-deprecated async throws API on macOS 15+
        try await session.export(to: dest, as: .m4a)
        return dest
    }
}
