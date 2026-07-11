import SwiftUI

struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper Models")
                        .font(.title2.bold())
                    Text("Models are stored inside the app bundle. Deleting the app removes them automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top], 18)
            .padding(.bottom, 12)

            Divider()

            // ── Model list ────────────────────────────────────────────────────
            if modelManager.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading available models…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(40)
            } else if modelManager.models.isEmpty {
                Text("No models found for this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
            } else {
                List(modelManager.models) { model in
                    ModelRowView(model: model, modelManager: modelManager)
                }
                .listStyle(.inset)
            }

            // ── Status bar ────────────────────────────────────────────────────
            if !modelManager.statusMessage.isEmpty {
                Divider()
                Text(modelManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 540, height: 400)
        .task { await modelManager.refresh() }
    }
}

// ─── Model Row ────────────────────────────────────────────────────────────────
private struct ModelRowView: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.isDownloaded ? .green : Color.secondary.opacity(0.4))
                .font(.system(size: 18))
                .frame(width: 22)

            // Name + badge + progress
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                    if model.isRecommendedDefault {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                if model.isDownloading {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                        .animation(.easeInOut, value: model.downloadProgress)
                }
                Text(statusText(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button
            Group {
                if model.isDownloading {
                    Button("Cancel") { modelManager.cancelDownload(model.name) }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                } else if model.isDownloaded {
                    Button("Delete") {
                        try? modelManager.delete(model.name)
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        modelManager.startDownload(model.name)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func statusText(for model: ModelInfo) -> String {
        if model.isDownloading {
            let pct = Int(model.downloadProgress * 100)
            return "Downloading… \(pct)%"
        }
        return model.isDownloaded ? "Ready" : "Not downloaded"
    }
}
