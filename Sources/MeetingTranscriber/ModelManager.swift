import WhisperKit
import Foundation

struct ModelInfo: Identifiable {
    var id: String { name }
    let name: String
    var isDownloaded: Bool
    var isRecommendedDefault: Bool
    var downloadProgress: Double = 0
    var isDownloading: Bool = false
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var models: [ModelInfo] = []
    @Published var isLoading = false
    @Published var statusMessage: String = ""

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    var modelsBase: URL? { Bundle.main.resourceURL }

    func isModelDownloaded(_ name: String) -> Bool {
        guard let base = modelsBase else { return false }
        let root = base.appending(path: "models/argmaxinc/whisperkit-coreml")
        guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return false }
        for sub in subdirs where normalizeModelFolder(sub) == name {
            let dir = root.appendingPathComponent(sub)
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            if contents.contains(where: { $0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage") }) {
                return true
            }
        }
        return false
    }

    /// WhisperKit stores variants under folder names like
    /// `openai_whisper-large-v3-v20240930`; map those back to the short
    /// variant name (e.g. `large-v3`) used in the UI / model list.
    private func normalizeModelFolder(_ folder: String) -> String {
        var s = folder
        if s.hasPrefix("openai_whisper-") {
            s = String(s.dropFirst("openai_whisper-".count))
        }
        if let range = s.range(of: #"-v\d{8}$"#, options: .regularExpression) {
            s.removeSubrange(range)
        }
        return s
    }

    func bestAvailableModel() -> String? {
        // Prefer a model already in the UI list that is detected on disk.
        if let inList = (models.first(where: { $0.isDownloaded && $0.isRecommendedDefault })
                         ?? models.first(where: { $0.isDownloaded }))?.name {
            return inList
        }
        // Fallback: scan the on-disk model folders directly (handles the case
        // where the in-memory list hasn't been refreshed yet).
        guard let base = modelsBase else { return nil }
        let root = base.appending(path: "models/argmaxinc/whisperkit-coreml")
        guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return nil }
        for sub in subdirs {
            let dir = root.appendingPathComponent(sub)
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            if contents.contains(where: { $0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage") }) {
                return normalizeModelFolder(sub)
            }
        }
        return nil
    }

    func refresh() async {
        isLoading = true
        let recommended = WhisperKit.recommendedModels()
        let defaultName = recommended.`default`
        var supported = recommended.supported
        if !supported.contains(defaultName) { supported.insert(defaultName, at: 0) }

        models = supported.map { name in
            ModelInfo(
                name: name,
                isDownloaded: isModelDownloaded(name),
                isRecommendedDefault: name == defaultName
            )
        }.sorted {
            if $0.isRecommendedDefault && !$1.isRecommendedDefault { return true }
            if !$0.isRecommendedDefault && $1.isRecommendedDefault { return false }
            return $0.name < $1.name
        }
        isLoading = false
    }

    // Fire-and-forget variant used by the UI (stores Task for cancellation).
    func startDownload(_ name: String) {
        guard downloadTasks[name] == nil,
              let i = models.firstIndex(where: { $0.name == name }),
              !models[i].isDownloading else { return }
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(name)
        }
        downloadTasks[name] = task
    }

    // Awaitable variant used by AppState for auto-download before transcribing.
    func download(_ name: String) async {
        if downloadTasks[name] == nil { startDownload(name) }
        if let task = downloadTasks[name] { await task.value }
    }

    func cancelDownload(_ name: String) {
        downloadTasks[name]?.cancel()
        downloadTasks.removeValue(forKey: name)
        if let i = models.firstIndex(where: { $0.name == name }) {
            models[i].isDownloading = false
            models[i].downloadProgress = 0
        }
        statusMessage = "Download cancelled."
    }

    func delete(_ name: String) throws {
        guard let base = modelsBase else { return }
        let dir = base.appending(path: "models/argmaxinc/whisperkit-coreml/\(name)")
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
        if let i = models.firstIndex(where: { $0.name == name }) {
            models[i].isDownloaded = false
            models[i].downloadProgress = 0
        }
        statusMessage = "Deleted \(name)."
    }

    private func performDownload(_ name: String) async {
        guard let i = models.firstIndex(where: { $0.name == name }) else { return }
        models[i].isDownloading = true
        models[i].downloadProgress = 0
        statusMessage = "Downloading \(name)…"

        do {
            _ = try await WhisperKit.download(
                variant: name,
                downloadBase: modelsBase,
                progressCallback: { [weak self] progress in
                    let frac = progress.fractionCompleted
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              let i = self.models.firstIndex(where: { $0.name == name }) else { return }
                        self.models[i].downloadProgress = frac
                    }
                }
            )
            if let i = models.firstIndex(where: { $0.name == name }) {
                models[i].isDownloaded = true
                models[i].isDownloading = false
                models[i].downloadProgress = 1.0
            }
            statusMessage = "Downloaded \(name)."
        } catch is CancellationError {
            if let i = models.firstIndex(where: { $0.name == name }) {
                models[i].isDownloading = false
                models[i].downloadProgress = 0
            }
        } catch {
            if let i = models.firstIndex(where: { $0.name == name }) {
                models[i].isDownloading = false
                models[i].downloadProgress = 0
            }
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
        downloadTasks.removeValue(forKey: name)
    }
}
