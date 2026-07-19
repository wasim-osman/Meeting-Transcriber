import FoundationModels
import Foundation

// ── Summary modes ──────────────────────────────────────────────────────────────
enum SummaryMode: String, CaseIterable, Identifiable {
    case comprehensive = "Comprehensive"
    case contemporary  = "Contemporary"
    case succinct      = "Succinct"
    case all           = "All Versions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .comprehensive: "doc.richtext.fill"
        case .contemporary:  "doc.text.fill"
        case .succinct:      "list.bullet.rectangle.portrait.fill"
        case .all:           "doc.on.doc.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .comprehensive: "Full"
        case .contemporary:  "Balanced"
        case .succinct:      "Brief"
        case .all:           "All"
        }
    }

    // The three real summary styles (excludes the legacy .all aggregate).
    static var realCases: [SummaryMode] {
        [.succinct, .contemporary, .comprehensive]
    }
}

// ── Prompts ────────────────────────────────────────────────────────────────────
private func buildPrompt(mode: SummaryMode, transcript: String) -> String {
    let instruction: String
    let extraSection: String

    switch mode {
    case .comprehensive:
        instruction = "Produce a COMPREHENSIVE, DETAILED summary. Include all context, nuance, and detail. Be exhaustive — leave nothing important out."
        extraSection = "\n## Additional Context & Background\n- Include any important context, background information, or detailed notes worth preserving for future reference."
    case .contemporary:
        instruction = "Produce a BALANCED summary — cover everything discussed but keep it concise. Avoid padding; omit nothing important."
        extraSection = ""
    case .succinct:
        instruction = "Produce a BRIEF summary using only short bullet points. Absolute essentials only. Each bullet = one sentence maximum. Skip sections with nothing notable."
        extraSection = ""
    case .all:
        instruction = ""  // handled separately
        extraSection = ""
    }

    return """
    You are an expert meeting analyst. \(instruction)

    ## Executive Summary
    \(mode == .succinct ? "1–2 sentences only." : "2–4 sentences capturing the main purpose and outcomes.")

    ## Key Discussion Points
    - \(mode == .comprehensive ? "Detailed point with context" : "Concise point")

    ## Decisions Made
    - Decision (or "None noted")

    ## Action Items
    - [ ] Action — Owner: [name if mentioned] — Due: [date if mentioned]

    ## Next Steps / Follow-up
    - Item (or "None noted")\(extraSection)
    ---
    Transcript:

    \(transcript)
    """
}

private let KEYPOINTS_PROMPT = """
Extract the key discussion points, decisions, and action items from this meeting segment. \
Use bullet points only, no section headers.

Segment:
%@
"""

// ── Engine ─────────────────────────────────────────────────────────────────────
private let DIRECT_CHARS = 6_000
private let CHUNK_CHARS  = 5_500

enum SummarizationEngine {

    static func isAvailable() -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    // Generates all three summary styles (succinct, contemporary, comprehensive)
    // and returns them keyed by mode, while streaming tokens to onToken so the
    // UI can show a live preview. The caller picks which mode to display.
    static func summarize(
        transcript: String,
        onProgress: @MainActor @escaping (String) -> Void,
        onToken: @MainActor @escaping (String) -> Void,
        onModeProgress: @MainActor @escaping (Double) -> Void
    ) async throws -> [SummaryMode: String] {

        try await summarizeAll(
            transcript: transcript,
            onProgress: onProgress,
            onToken: onToken,
            onModeProgress: onModeProgress
        )
    }

    // ── "All Versions" path ───────────────────────────────────────────────────

    private static func summarizeAll(
        transcript: String,
        onProgress: @MainActor @escaping (String) -> Void,
        onToken: @MainActor @escaping (String) -> Void,
        onModeProgress: @MainActor @escaping (Double) -> Void
    ) async throws -> [SummaryMode: String] {
        let modes: [SummaryMode] = [.succinct, .contemporary, .comprehensive]
        var result: [SummaryMode: String] = [:]

        for (i, m) in modes.enumerated() {
            try Task.checkCancellation()
            let base  = Double(i) / 3.0
            let scale = 1.0 / 3.0

            // Emit the section header as streamed tokens (live preview only)
            let divider = sectionDivider(for: m)
            await onToken(divider)

            let part = try await summarizeSingle(
                transcript: transcript,
                mode: m,
                onProgress: onProgress,
                onToken: onToken,
                onModeProgress: onModeProgress,
                progressBase: base,
                progressScale: scale
            )
            result[m] = part

            if i < modes.count - 1 {
                await onToken("\n\n")
            }
            await onModeProgress(Double(i + 1) / 3.0)
        }
        return result
    }

    // ── Single-mode path ──────────────────────────────────────────────────────

    private static func summarizeSingle(
        transcript: String,
        mode: SummaryMode,
        onProgress: @MainActor @escaping (String) -> Void,
        onToken: @MainActor @escaping (String) -> Void,
        onModeProgress: @MainActor @escaping (Double) -> Void,
        progressBase: Double,
        progressScale: Double
    ) async throws -> String {
        if transcript.count <= DIRECT_CHARS {
            return try await directSummarize(transcript: transcript, mode: mode,
                                             onToken: onToken)
        }
        return try await chunkedSummarize(
            transcript: transcript,
            mode: mode,
            onProgress: onProgress,
            onToken: onToken,
            onModeProgress: onModeProgress,
            progressBase: progressBase,
            progressScale: progressScale
        )
    }

    private static func directSummarize(
        transcript: String,
        mode: SummaryMode,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        try await stream(prompt: buildPrompt(mode: mode, transcript: transcript), onToken: onToken)
    }

    private static func chunkedSummarize(
        transcript: String,
        mode: SummaryMode,
        onProgress: @MainActor @escaping (String) -> Void,
        onToken: @MainActor @escaping (String) -> Void,
        onModeProgress: @MainActor @escaping (Double) -> Void,
        progressBase: Double,
        progressScale: Double
    ) async throws -> String {
        let chunks = split(transcript, maxChars: CHUNK_CHARS)
        let total  = chunks.count
        var keyPoints: [String] = []

        for (i, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            await onProgress("Analyzing segment \(i + 1) of \(total)…")
            let p = progressBase + progressScale * (Double(i) / Double(total) * 0.75)
            await onModeProgress(p)
            let points = try await stream(prompt: String(format: KEYPOINTS_PROMPT, chunk), onToken: nil)
            keyPoints.append("**Part \(i + 1):**\n\(points)")
        }

        await onProgress("Synthesizing \(total)-part summary…")
        await onModeProgress(progressBase + progressScale * 0.82)

        let combined = keyPoints.joined(separator: "\n\n")
        let capped = combined.count > DIRECT_CHARS
            ? String(combined.prefix(DIRECT_CHARS)) + "\n[truncated]"
            : combined
        let synInput = "Condensed notes from a long meeting (\(total) segments):\n\n" + capped
        return try await directSummarize(transcript: synInput, mode: mode,
                                         onToken: onToken)
    }

    // ── Streaming helper ──────────────────────────────────────────────────────

    static func stream(
        prompt: String,
        onToken: (@MainActor (String) -> Void)?
    ) async throws -> String {
        let session = LanguageModelSession()
        var accumulated = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            let full    = snapshot.content
            let newPart = String(full.dropFirst(accumulated.count))
            if !newPart.isEmpty {
                accumulated = full
                if let onToken { await onToken(newPart) }
            }
        }
        return accumulated
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    private static func split(_ text: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        let sentences = text.components(separatedBy: ". ")
        for (i, s) in sentences.enumerated() {
            let piece = s + (i < sentences.count - 1 ? ". " : "")
            if current.count + piece.count > maxChars, !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = piece
            } else {
                current += piece
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks
    }

    private static func sectionDivider(for mode: SummaryMode) -> String {
        let inner = "  \(mode.rawValue.uppercased()) SUMMARY  "
        let width = max(50, inner.count + 4)
        let bar   = String(repeating: "═", count: width)
        let pad   = String(repeating: " ", count: max(0, (width - inner.count) / 2))
        return "╔\(bar)╗\n║\(pad)\(inner)\(pad)║\n╚\(bar)╝\n\n"
    }
}
