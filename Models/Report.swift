import Foundation

enum ReportType: String, Codable {
    case daily = "daily"
    case monthly = "monthly"
    case annual = "annual"

    var label: String {
        switch self {
        case .daily:   return "Diário"
        case .monthly: return "Mensal"
        case .annual:  return "Anual"
        }
    }
}

struct Report: Identifiable, Codable {
    let id: Int
    var type: ReportType
    var period: String     // ex: "2026-02-23", "2026-02" ou "2026"
    var filePath: String
    var createdAt: Date
}
