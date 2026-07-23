import SwiftUI

enum ServerStatus: String {
    case stopped = "Не запущен"
    case starting = "Запускается"
    case running = "Работает"
    case stopping = "Останавливается"
    case failed = "Ошибка"

    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        case .failed: return .red
        }
    }

    var symbol: String {
        switch self {
        case .stopped: return "stop.circle.fill"
        case .starting, .stopping: return "hourglass.circle.fill"
        case .running: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

struct RuntimeHealth: Decodable {
    let ok: Bool
    let runtime: String
    let runtimeVersion: String
    let serverRunning: Bool
    let serverPort: Int?
    let dataDirectory: String
}

struct ControlResult: Decodable {
    let ok: Bool
    let state: String
    let port: Int?
    let error: String?
}

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
    }
}
