import WhisperKit
import Foundation

// Holds a single WhisperKit instance; re-initialises only when the model name changes.
actor TranscriptionEngine {
    private var kit: WhisperKit?
    private var loadedModelName: String?

    // estimatedChunks — audio duration / 30 s (Whisper's window); used to compute
    // per-file fraction for the progress bar. Pass 0 to skip progress updates.
    func transcribe(
        audioURL: URL,
        modelName: String,
        estimatedChunks: Int = 0,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        if kit == nil || loadedModelName != modelName {
            kit = nil
            // audioEncoderCompute: .all → Core ML chooses the best mix of ANE,
            // GPU, and P-cores for the CNN encoder on each M-series chip.
            // textDecoderCompute: .cpuAndNeuralEngine → ANE handles the
            // autoregressive transformer decoder efficiently.
            kit = try await WhisperKit(
                model: modelName,
                downloadBase: Bundle.main.resourceURL,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .all,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: false,
                logLevel: .none
            )
            loadedModelName = modelName
        }

        let decodeOptions = DecodingOptions(
            usePrefillCache: true,
            skipSpecialTokens: true
        )

        var chunksDone = 0
        let total = estimatedChunks > 0 ? estimatedChunks : 0
        let callback: TranscriptionCallback = { _ in
            chunksDone += 1
            if total > 0 {
                let fraction = min(Double(chunksDone) / Double(total), 0.97)
                onProgress?(fraction)
            }
            return Task.isCancelled ? false : nil
        }

        let results = try await kit!.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions,
            callback: callback
        )
        return results.map(\.text).joined(separator: " ")
                      .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
