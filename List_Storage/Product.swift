import Foundation

enum StockStatus: String, Codable {
    case none       // sem flag
    case redFlag    // em falta
    case confirmed  // confirmado/tem stock
}

struct Product: Identifiable, Codable {
    var id = UUID()
    var barcode: String
    var name: String
    var stockActual: Int
    var qtyEncomenda: Int
    var status: StockStatus = .none

    // Compat helpers
    var isRedFlag: Bool { status == .redFlag }
    var isConfirmed: Bool { status == .confirmed }

    enum CodingKeys: String, CodingKey {
        case barcode
        case name
        case stockActual  = "stock_actual"
        case qtyEncomenda = "qty_encomenda"
        case status
    }

    func toCSVRow() -> String {
        "\(barcode),\(name),\(stockActual),\(qtyEncomenda),\(status.rawValue)"
    }
}
