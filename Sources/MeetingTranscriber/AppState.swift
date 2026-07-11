import SwiftUI
import Foundation
import FoundationModels
import WhisperKit
import AVFoundation
import AppKit

private let SUPPORTED_EXTENSIONS: Set<String> = [
    "mp3", "mp4", "m4a", "wav", "flac", "aac", "ogg",
    "mkv", "mov", "avi", "webm", "wma", "opus", "m4v"
]

// ── Export format ──────────────────────────────────────────────────────────────
enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown (.md)"
    case html     = "HTML (.html)"
    case docx     = "Word (.docx)"

    var ext: String {
        switch self { case .markdown: "md"; case .html: "html"; case .docx: "docx" }
    }
    var icon: String {
        switch self { case .markdown: "doc.text"; case .html: "globe"; case .docx: "doc.richtext" }
    }
}

@MainActor
final class AppState: ObservableObject {
    // ── Published state ───────────────────────────────────────────────────────
    @Published var fileItems: [FileItem] = []
    @Published var transcript: String = ""
    @Published var summary: String = ""
    @Published var statusMessage: String = ""
    @Published var isTranscribing = false
    @Published var isSummarizing  = false
    @Published var transcriptionProgress: Double = 0
    @Published var summaryProgress: Double = 0
    @Published var selectedTab: Int = 0
    @Published var appleIntelligenceUnavailableReason: String? = nil

    // Persisted across launches via UserDefaults
    @Published var summaryMode: SummaryMode = {
        SummaryMode(rawValue: UserDefaults.standard.string(forKey: "summaryMode") ?? "") ?? .contemporary
    }() {
        didSet { UserDefaults.standard.set(summaryMode.rawValue, forKey: "summaryMode") }
    }

    var isBusy: Bool { isTranscribing || isSummarizing }

    let modelManager = ModelManager()
    private let engine = TranscriptionEngine()
    private var transcriptionTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?

    // ── File queue ────────────────────────────────────────────────────────────

    func addFiles(_ urls: [URL]) {
        let existing = Set(fileItems.map(\.url))
        let fresh = urls.filter {
            SUPPORTED_EXTENSIONS.contains($0.pathExtension.lowercased()) && !existing.contains($0)
        }
        fileItems.append(contentsOf: fresh.map { FileItem(url: $0) })
        if !fresh.isEmpty {
            statusMessage = "Added \(fresh.count) file\(fresh.count == 1 ? "" : "s") to queue."
        }
    }

    func moveItems(from offsets: IndexSet, to destination: Int) {
        fileItems.move(fromOffsets: offsets, toOffset: destination)
    }

    func removeItems(at offsets: IndexSet) {
        fileItems.remove(atOffsets: offsets)
    }

    func clearAll() {
        fileItems.removeAll(); transcript = ""; summary = ""; statusMessage = ""
    }

    var hasTranscripts: Bool { fileItems.contains { $0.transcript != nil } }

    // ── Toggle actions ────────────────────────────────────────────────────────

    func toggleTranscription() {
        if isTranscribing {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            isTranscribing = false
            transcriptionProgress = 0
            statusMessage = "Transcription cancelled."
            for item in fileItems { if case .processing = item.status { item.status = .pending } }
        } else {
            guard !fileItems.isEmpty else { return }
            isTranscribing = true
            transcriptionProgress = 0
            transcript = ""
            selectedTab = 0
            transcriptionTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.runTranscription()
            }
        }
    }

    func toggleSummary() {
        if isSummarizing {
            summaryTask?.cancel()
            summaryTask = nil
            isSummarizing = false
            summaryProgress = 0
            statusMessage = "Summary cancelled."
        } else {
            guard hasTranscripts else { return }
            isSummarizing = true
            summaryProgress = 0
            summary = ""
            selectedTab = 1
            summaryTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.runSummary()
            }
        }
    }

    // ── Export ────────────────────────────────────────────────────────────────

    func exportSummary(format: ExportFormat = .markdown) {
        guard !summary.isEmpty else { return }

        let now = Date()
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy-MM-dd_HH-mm"
        let fileStamp = fileFmt.string(from: now)

        let readFmt = DateFormatter()
        readFmt.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        let readableDate = readFmt.string(from: now)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Media Summary \(fileStamp).\(format.ext)"
        panel.title = "Export Summary — \(format.rawValue)"

        let capturedSummary = summary
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                switch format {
                case .markdown: try self.writeMarkdown(capturedSummary, date: readableDate, to: url)
                case .html:     try self.writeHTML(capturedSummary, date: readableDate, to: url)
                case .docx:     try self.writeDocx(capturedSummary, date: readableDate, to: url)
                }
            } catch {
                self.statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // ── Export writers ────────────────────────────────────────────────────────

    private func writeMarkdown(_ text: String, date: String, to url: URL) throws {
        let content = "*Exported: \(date)*\n\n" + text
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeHTML(_ text: String, date: String, to url: URL) throws {
        let hColors = ["#2563eb","#16a34a","#ea580c","#9333ea","#db2777","#0d9488","#4f46e5","#0891b2"]
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Media Summary</title>
        <style>
          body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:800px;margin:40px auto;padding:0 20px;color:#1a1a1a;line-height:1.6}
          .meta{color:#888;font-size:.85em;margin-bottom:2em}
          h1{font-size:1.8em}
          h2{margin-top:1.8em;padding-left:12px;border-left:4px solid}
          ul{padding-left:1.4em}li{margin:4px 0}
          hr{border:none;border-top:1px solid #e5e7eb;margin:20px 0}
          pre{font-family:monospace;background:#f3f4f6;padding:12px;border-radius:6px;overflow-x:auto}
          .ck{text-decoration:line-through;color:#888}
        </style>
        </head>
        <body>
        <p class="meta">Exported: \(esc(date))</p>
        """
        var h2Idx = 0
        var inList = false
        func closeList() { if inList { html += "</ul>\n"; inList = false } }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("╔") || line.hasPrefix("║") || line.hasPrefix("╚") {
                closeList(); html += "<pre>\(esc(line))</pre>\n"
            } else if line.hasPrefix("## ") {
                closeList()
                let c = hColors[h2Idx % hColors.count]; h2Idx += 1
                html += "<h2 style=\"color:\(c);border-left-color:\(c)\">\(esc(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                closeList(); html += "<h1>\(esc(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li>&#9744; \(esc(String(line.dropFirst(6))))</li>\n"
            } else if line.lowercased().hasPrefix("- [x] ") || line.lowercased().hasPrefix("* [x] ") {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li class=\"ck\">&#9745; \(esc(String(line.dropFirst(6))))</li>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li>\(esc(String(line.dropFirst(2))))</li>\n"
            } else if line.trimmingCharacters(in: .whitespaces) == "---" {
                closeList(); html += "<hr>\n"
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeList(); html += "<br>\n"
            } else {
                closeList(); html += "<p>\(esc(line))</p>\n"
            }
        }
        closeList()
        html += "</body></html>"
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeDocx(_ text: String, date: String, to url: URL) throws {
        let attrStr = styledAttrString(text, date: date)
        let data = try attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML,
                .title: "Media Summary"
            ]
        )
        try data.write(to: url)
    }

    private func styledAttrString(_ text: String, date: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body   = NSFont.systemFont(ofSize: 12)
        let mono   = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let palette: [NSColor] = [.systemBlue, .systemGreen, .systemOrange,
                                   .systemPurple, .systemPink, .systemTeal]
        var h2i = 0

        func append(_ s: String, _ attrs: [NSAttributedString.Key: Any]) {
            result.append(NSAttributedString(string: s + "\n", attributes: attrs))
        }

        append("Exported: \(date)", [.font: NSFont.systemFont(ofSize: 10),
                                      .foregroundColor: NSColor.secondaryLabelColor])
        append("", [.font: body])

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("╔") || line.hasPrefix("║") || line.hasPrefix("╚") {
                append(line, [.font: mono])
            } else if line.hasPrefix("## ") {
                let c = palette[h2i % palette.count]; h2i += 1
                append(String(line.dropFirst(3)), [
                    .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                    .foregroundColor: c
                ])
            } else if line.hasPrefix("# ") {
                append(String(line.dropFirst(2)), [.font: NSFont.systemFont(ofSize: 20, weight: .heavy)])
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                append("☐ " + String(line.dropFirst(6)), [.font: body])
            } else if line.lowercased().hasPrefix("- [x] ") {
                append("☑ " + String(line.dropFirst(6)), [.font: body, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                append("• " + String(line.dropFirst(2)), [.font: body])
            } else {
                append(line, [.font: body])
            }
        }
        return result
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // ── Transcription implementation ──────────────────────────────────────────

    private func runTranscription() async {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
            reason: "Media Summarizer: transcribing audio"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            Task { @MainActor [weak self] in
                self?.isTranscribing = false; self?.transcriptionTask = nil
            }
        }

        let modelName: String
        if let available = modelManager.bestAvailableModel() {
            modelName = available
        } else {
            statusMessage = "No model — fetching…"
            await modelManager.refresh()
            let recommended = WhisperKit.recommendedModels().`default`
            statusMessage = "Downloading \(recommended)…"
            await modelManager.download(recommended)
            guard let downloaded = modelManager.bestAvailableModel() else {
                statusMessage = "Could not download model. Open Models to try again."
                return
            }
            modelName = downloaded
        }

        statusMessage = "Starting transcription…"
        let totalFiles = fileItems.count

        for (fileIdx, item) in fileItems.enumerated() {
            if Task.isCancelled { break }
            item.status = .processing("🔊  Extracting audio…")
            statusMessage = "Processing \(item.name)…"
            do {
                let audioURL = try await AudioExtractor.extract(from: item.url)
                let isTemp   = audioURL != item.url
                let assetDur = try? await AVURLAsset(url: item.url).load(.duration).seconds
                let estChunks = assetDur.map { max(1, Int(ceil($0 / 30.0))) } ?? 10

                item.status = .processing("📝  Transcribing…")
                statusMessage = "Transcribing \(item.name)…"

                let text = try await engine.transcribe(
                    audioURL: audioURL, modelName: modelName, estimatedChunks: estChunks,
                    onProgress: { [weak self] fraction in
                        let overall = (Double(fileIdx) + fraction) / Double(totalFiles)
                        Task { @MainActor [weak self] in self?.transcriptionProgress = overall }
                    }
                )
                if isTemp { try? FileManager.default.removeItem(at: audioURL) }
                let outURL = item.url.deletingPathExtension().appendingPathExtension("transcript.txt")
                try? text.write(to: outURL, atomically: true, encoding: .utf8)
                item.transcript = text; item.status = .done
                let sep   = String(repeating: "═", count: 60)
                let block = "\(sep)\n\(item.name)\n\(sep)\n\n\(text)"
                transcript = transcript.isEmpty ? block : transcript + "\n\n" + block
                transcriptionProgress = Double(fileIdx + 1) / Double(totalFiles)
            } catch is CancellationError {
                item.status = .pending; break
            } catch {
                item.status = .failed(error.localizedDescription)
                statusMessage = "❌ \(item.name): \(error.localizedDescription)"
            }
        }
        if !Task.isCancelled {
            let n = fileItems.filter { if case .done = $0.status { true } else { false } }.count
            statusMessage = "Done — \(n) file\(n == 1 ? "" : "s") transcribed."
            transcriptionProgress = 1.0
        }
    }

    // ── Summarization implementation ──────────────────────────────────────────

    private func runSummary() async {
        defer {
            Task { @MainActor [weak self] in
                self?.isSummarizing = false; self?.summaryTask = nil
            }
        }
        guard #available(macOS 26.0, *) else {
            appleIntelligenceUnavailableReason = "Requires macOS 26 or later."
            return
        }
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            if case .unavailable(let reason) = model.availability {
                appleIntelligenceUnavailableReason = "Apple Intelligence not available: \(reason)"
            }
            return
        }
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Media Summarizer: generating summary"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        statusMessage = "Generating \(summaryMode.rawValue) summary…"
        let capturedMode = summaryMode
        let capturedTranscript = transcript

        do {
            let full = try await SummarizationEngine.summarize(
                transcript: capturedTranscript,
                mode: capturedMode,
                onProgress: { [weak self] msg in self?.statusMessage = msg },
                onToken: { [weak self] tok in self?.summary += tok },
                onModeProgress: { [weak self] p in self?.summaryProgress = p }
            )
            summaryProgress = 1.0

            // Auto-save as .md next to source file (with timestamp)
            if let firstURL = fileItems.first?.url {
                let fileFmt = DateFormatter()
                fileFmt.dateFormat = "yyyy-MM-dd_HH-mm"
                let stamp = fileFmt.string(from: Date())
                let stem  = capturedMode.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
                let outURL = firstURL.deletingPathExtension()
                    .appendingPathExtension("\(stem)_summary_\(stamp).md")
                let readFmt = DateFormatter()
                readFmt.dateFormat = "MMMM d, yyyy 'at' h:mm a"
                let content = "*Exported: \(readFmt.string(from: Date()))*\n\n" + full
                try? content.write(to: outURL, atomically: true, encoding: .utf8)
                statusMessage = "Saved → \(outURL.lastPathComponent)"
            }
        } catch is CancellationError {
            statusMessage = "Summary cancelled."; summaryProgress = 0
        } catch {
            statusMessage = "Summary error: \(error.localizedDescription)"
        }
    }
}
