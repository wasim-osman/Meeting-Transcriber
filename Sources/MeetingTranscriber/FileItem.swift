import Foundation

final class FileItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL

    enum Status {
        case pending
        case processing(String)
        case done
        case failed(String)

        var label: String {
            switch self {
            case .pending:            return "⏳  Pending"
            case .processing(let s): return s
            case .done:               return "✅  Transcribed"
            case .failed(let e):      return "❌  \(e.prefix(60))"
            }
        }
    }

    @Published var status: Status = .pending
    @Published var transcript: String? = nil

    var name: String { url.lastPathComponent }

    init(url: URL) { self.url = url }
}
