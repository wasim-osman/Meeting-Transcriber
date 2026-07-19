import SwiftUI
import UniformTypeIdentifiers
import AppKit

// ─── Glass-panel modifier ──────────────────────────────────────────────────────
private struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

// ─── Drop Zone ────────────────────────────────────────────────────────────────
struct DropZoneView: View {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void
    var onBrowse: () -> Void = {}

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [8, 5])
                )
            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "mic.circle.fill" : "mic.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, isActive: isTargeted)
                Text("Click or drop audio / video files here")
                    .font(.headline)
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary)
                Text("MP3  ·  MP4  ·  M4A  ·  WAV  ·  MKV  ·  MOV  ·  FLAC")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 112)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTargeted)
        .onTapGesture { onBrowse() }
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { onDrop(urls) }
            return true
        }
    }
}

// ─── File Queue Row ───────────────────────────────────────────────────────────
struct FileRowView: View {
    @ObservedObject var item: FileItem

    private var icon: String {
        ["mp4", "mkv", "mov", "avi", "webm", "m4v"].contains(item.url.pathExtension.lowercased())
            ? "film" : "waveform"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.status.label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// ─── No-model Banner ─────────────────────────────────────────────────────────
private struct NoModelBanner: View {
    var onManage: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.orange).font(.system(size: 14, weight: .semibold))
            Text("No Whisper model downloaded. Transcription will auto-download, or manage models manually.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Manage") { onManage() }
                .buttonStyle(.plain).font(.caption.bold()).foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassPanel(cornerRadius: 10)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// ─── Progress Row ─────────────────────────────────────────────────────────────
private struct ProgressRow: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value).tint(tint).animation(.easeOut(duration: 0.3), value: value)
        }
    }
}

// ─── Resource Gauge ───────────────────────────────────────────────────────────
private struct ResourceGauge: View {
    let label: String
    let value: Double   // 0…100
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * min(value / 100.0, 1.0))
                }
            }
            .frame(width: 48, height: 5)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// ─── Main Content ─────────────────────────────────────────────────────────────
struct ContentView: View {
    @ObservedObject var state: AppState
    @StateObject private var monitor = SystemMonitor()
    @State private var isDropTargeted  = false
    @State private var showModelManager = false
    @AppStorage("fontSize") private var fontSize: Double = 13.0

    private var noModelDownloaded: Bool {
        !state.modelManager.isLoading
            && !state.modelManager.models.isEmpty
            && state.modelManager.bestAvailableModel() == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // ── No-model banner ──────────────────────────────────────────
                if noModelDownloaded {
                    NoModelBanner { showModelManager = true }
                        .transition(.asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity),
                            removal:   .push(from: .bottom).combined(with: .opacity)
                        ))
                }

                // ── Drop zone ────────────────────────────────────────────────
                DropZoneView(isTargeted: $isDropTargeted,
                             onDrop: { state.addFiles($0) },
                             onBrowse: browseFiles)

                // ── Queue panel ───────────────────────────────────────────────
                VStack(spacing: 0) {
                    HStack {
                        Label("Queue", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(state.fileItems.isEmpty
                             ? "empty"
                             : "\(state.fileItems.count) file\(state.fileItems.count == 1 ? "" : "s")")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Clear") { state.clearAll() }
                            .buttonStyle(.plain).font(.subheadline).foregroundStyle(.secondary)
                            .disabled(state.isBusy)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)

                    Divider().opacity(0.5)

                    List {
                        ForEach(state.fileItems) { item in FileRowView(item: item) }
                            .onMove(perform: state.moveItems)
                            .onDelete(perform: state.removeItems)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 72, maxHeight: 155)
                    .overlay {
                        if state.fileItems.isEmpty {
                            Text("No files yet — drop some above")
                                .foregroundStyle(.tertiary).font(.subheadline)
                        }
                    }

                    Divider().opacity(0.5)
                    Text("Drag to reorder  ·  Swipe left or ⌫ to remove")
                        .font(.caption2).foregroundStyle(.quaternary)
                        .padding(.vertical, 7).frame(maxWidth: .infinity)
                }
                .glassPanel(cornerRadius: 14)

                // ── Action rows ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {

                    // Row 1 — Transcribe + Process Summary side by side
                    HStack(spacing: 10) {
                        // Transcribe button
                         Button { state.toggleTranscription() } label: {
                            Label(state.isTranscribing ? "Stop" : "Transcribe",
                                  systemImage: state.isTranscribing ? "stop.fill" : "mic.fill")
                                .frame(minWidth: 150)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(state.isTranscribing ? .red : .accentColor)
                        .disabled(state.isSummarizing || (!state.isTranscribing && state.fileItems.isEmpty))
                        .animation(.easeInOut(duration: 0.15), value: state.isTranscribing)

                        // Process Summary button
                        Button { state.toggleSummary() } label: {
                            Label(state.isSummarizing ? "Stop" : "Process Summary",
                                  systemImage: state.isSummarizing ? "stop.fill" : "sparkles")
                                .frame(minWidth: 150)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(state.isSummarizing ? .red : .purple)
                        .disabled(state.isTranscribing || !state.summarizationAvailable || (!state.isSummarizing && !state.hasTranscripts))
                        .animation(.easeInOut(duration: 0.15), value: state.isSummarizing)

                        Spacer()
                    }

                    // Row 2 — Summary style picker (switch between the three generated styles)
                    HStack(spacing: 10) {
                        Text("Summary style")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $state.summaryMode) {
                            ForEach(SummaryMode.realCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(state.isBusy || !state.summaryReady)
                        .help(state.summaryReady ? "Switch between generated summary styles" : "Summaries are generated when you run the pipeline")

                        Spacer()
                    }
                }

                // ── Progress bars ─────────────────────────────────────────────
                if state.isTranscribing {
                    ProgressRow(label: "Transcribing…",
                                value: state.transcriptionProgress,
                                tint: .accentColor)
                        .transition(.opacity.combined(with: .push(from: .top)))
                }
                if state.isSummarizing {
                    ProgressRow(label: "Generating summaries…",
                                value: state.summaryProgress,
                                tint: .purple)
                        .transition(.opacity.combined(with: .push(from: .top)))
                }

                // ── CPU / GPU resource indicators ──────────────────────────────
                if state.isBusy {
                    HStack(spacing: 8) {
                        ResourceGauge(label: "CPU",
                                      value: monitor.cpuPercent,
                                      icon: "cpu",
                                      color: .blue)
                        if let gpu = monitor.gpuPercent {
                            ResourceGauge(label: "GPU",
                                          value: gpu,
                                          icon: "memorychip",
                                          color: .green)
                        }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .push(from: .top)))
                }

                // ── Status ────────────────────────────────────────────────────
                if !state.statusMessage.isEmpty {
                    Text(state.statusMessage)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }

                // ── Apple Intelligence warning ────────────────────────────────
                if let reason = state.appleIntelligenceUnavailableReason {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.slash").foregroundStyle(.orange)
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassPanel(cornerRadius: 10)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
                }

                // ── Output tabs ───────────────────────────────────────────────
                VStack(spacing: 0) {
                    TabView(selection: $state.selectedTab) {

                        // Transcript tab
                        ScrollView {
                            Text(state.transcript.isEmpty ? "Transcript will appear here…" : state.transcript)
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundStyle(state.transcript.isEmpty ? .tertiary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .textSelection(.enabled)
                        }
                        .tag(0)
                        .tabItem { Label("Transcript", systemImage: "doc.text") }

                        // Summary tab
                        ZStack(alignment: .topTrailing) {
                            ScrollView {
                                if state.summaryIsReady {
                                    FormattedSummaryView(text: state.displayedSummary, fontSize: fontSize)
                                        .padding(14)
                                        .textSelection(.enabled)
                                } else {
                                    Text("Summary will appear here…")
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: fontSize))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                }
                            }

                            // Export menu — floats top-right when summary is ready
                            if state.summaryIsReady {
                                Menu {
                                    ForEach(ExportFormat.allCases, id: \.self) { fmt in
                                        Button {
                                            state.exportSummary(format: fmt)
                                        } label: {
                                            Label(fmt.rawValue, systemImage: fmt.icon)
                                        }
                                    }
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .menuStyle(.borderlessButton)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(10)
                            }
                        }
                        .tag(1)
                        .tabItem { Label("Summary", systemImage: "list.bullet.clipboard") }
                    }
                    .frame(minHeight: 260)
                    .tabViewStyle(.automatic)

                    // Font size slider at bottom of output panel
                    Divider().opacity(0.4)
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Slider(value: $fontSize, in: 10...22, step: 1)
                            .controlSize(.mini)
                            .frame(maxWidth: 140)
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .glassPanel(cornerRadius: 14)
            }
            .padding(18)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: noModelDownloaded)
        .animation(.easeInOut(duration: 0.2), value: state.isTranscribing)
        .animation(.easeInOut(duration: 0.2), value: state.isSummarizing)
        .animation(.easeInOut(duration: 0.2), value: state.isBusy)
        .task {
            await state.modelManager.refresh()
            state.refreshSummarizationAvailability()
        }
        .onChange(of: state.isBusy) { _, busy in
            if busy { monitor.start() } else { monitor.stop() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showModelManager = true } label: { Label("Models", systemImage: "cpu") }
                    .help("Manage Whisper transcription models")
            }
        }
        .sheet(isPresented: $showModelManager) {
            ModelManagerView(modelManager: state.modelManager)
        }
    }

    // Opens a native file picker and adds the chosen files to the queue.
    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = false
        panel.prompt = "Add"
        panel.message = "Select audio or video meeting files"
        if panel.runModal() == .OK {
            state.addFiles(panel.urls)
        }
    }
}
