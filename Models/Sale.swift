import Foundation

enum SaleStatus: String, Codable {
    case completed = "completed"
    case cancelled = "cancelled"
}

struct Sale: Identifiable, Codable {
    let id: Int
    var userId: Int
    var clientName: String
    var clientNIF: String
    var items: [SaleItem]
    var total: Double
    var date: Date
    var status: SaleStatus
}
