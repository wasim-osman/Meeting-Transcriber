import SwiftUI

// Renders a markdown-like meeting summary with color-coded headings.
struct FormattedSummaryView: View {

    let text: String
    var fontSize: Double = 13.0

    // Each ## heading cycles through this palette in order of appearance.
    private static let headingPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint
    ]

    // ── Line model ─────────────────────────────────────────────────────────────
    private enum Line {
        case boxRow(String)            // ╔╗╚╝ section header rows
        case h1(String)                // # Title
        case h2(String, Color)         // ## Title
        case bullet(String)            // - text
        case unchecked(String)         // - [ ] text
        case checked(String)           // - [x] text
        case separator                 // ---
        case body(String)
        case blank
    }

    private var lines: [Line] {
        var result: [Line] = []
        var h2Index = 0

        for raw in text.components(separatedBy: "\n") {
            // Box-drawing rows (section headers in "All Versions" mode)
            if raw.hasPrefix("╔") || raw.hasPrefix("║") || raw.hasPrefix("╚") {
                result.append(.boxRow(raw))
                continue
            }
            // Headings
            if raw.hasPrefix("### ") {
                result.append(.body(String(raw.dropFirst(4))))
                continue
            }
            if raw.hasPrefix("## ") {
                let color = Self.headingPalette[h2Index % Self.headingPalette.count]
                h2Index += 1
                result.append(.h2(String(raw.dropFirst(3)), color))
                continue
            }
            if raw.hasPrefix("# ") {
                result.append(.h1(String(raw.dropFirst(2))))
                continue
            }
            // Checkboxes (before plain bullet to match first)
            if raw.hasPrefix("- [ ] ") || raw.hasPrefix("* [ ] ") {
                result.append(.unchecked(String(raw.dropFirst(6))))
                continue
            }
            if raw.hasPrefix("- [x] ") || raw.hasPrefix("- [X] ")
                || raw.hasPrefix("* [x] ") || raw.hasPrefix("* [X] ") {
                result.append(.checked(String(raw.dropFirst(6))))
                continue
            }
            // Plain bullets
            if raw.hasPrefix("- ") || raw.hasPrefix("* ") {
                result.append(.bullet(String(raw.dropFirst(2))))
                continue
            }
            // Horizontal rule
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.separator)
                continue
            }
            if trimmed.isEmpty {
                result.append(.blank)
                continue
            }
            result.append(.body(raw))
        }
        return result
    }

    // ── View ───────────────────────────────────────────────────────────────────
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(for: line)
            }
        }
    }

    @ViewBuilder
    private func lineView(for line: Line) -> some View {
        switch line {

        case .boxRow(let raw):
            Text(raw)
                .font(.system(size: max(fontSize - 1, 9), weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)

        case .h1(let t):
            Text(t)
                .font(.system(size: fontSize + 6, weight: .heavy))
                .foregroundStyle(.primary)
                .padding(.top, 14)
                .padding(.bottom, 4)

        case .h2(let t, let color):
            HStack(alignment: .center, spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 3, height: fontSize + 4)
                Text(t)
                    .font(.system(size: fontSize + 2, weight: .bold))
                    .foregroundStyle(color)
            }
            .padding(.top, 14)
            .padding(.bottom, 3)

        case .bullet(let t):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(.system(size: fontSize))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .frame(width: 10, alignment: .leading)
                    .padding(.top, 1)
                Text(inlineFormatted(t))
                    .font(.system(size: fontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1.5)

        case .unchecked(let t):
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "square")
                    .font(.system(size: max(fontSize - 1, 9)))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .padding(.top, 1)
                Text(inlineFormatted(t))
                    .font(.system(size: fontSize))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1.5)

        case .checked(let t):
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: max(fontSize - 1, 9)))
                    .foregroundStyle(.green)
                    .frame(width: 14)
                    .padding(.top, 1)
                Text(inlineFormatted(t))
                    .font(.system(size: fontSize))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1.5)

        case .separator:
            Divider()
                .padding(.vertical, 8)

        case .body(let t):
            Text(inlineFormatted(t))
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 1.5)

        case .blank:
            Spacer().frame(height: 5)
        }
    }

    // Handles **bold** and *italic* inline formatting.
    private func inlineFormatted(_ raw: String) -> AttributedString {
        var result = AttributedString(raw)
        // **bold**
        result = applyStyle(to: result, pattern: "\\*\\*(.+?)\\*\\*") { range, str in
            str[range].font = .system(size: fontSize, weight: .semibold)
        }
        // *italic*
        result = applyStyle(to: result, pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)") { range, str in
            str[range].font = .system(size: fontSize).italic()
        }
        return result
    }

    private func applyStyle(
        to attr: AttributedString,
        pattern: String,
        apply: (Range<AttributedString.Index>, inout AttributedString) -> Void
    ) -> AttributedString {
        var result = attr
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let plain = String(attr.characters)
        let matches = regex.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for m in matches.reversed() {
            guard let range = Range(m.range, in: plain),
                  let attrRange = result.range(of: String(plain[range])) else { continue }
            apply(attrRange, &result)
        }
        return result
    }
}
