import Foundation

enum PaymentMethod: String, Codable, CaseIterable {
    case cash         = "cash"
    case card         = "card"
    case bankTransfer = "bank_transfer"
    case mpesa        = "mpesa"
    case emola        = "emola"

    var label: String {
        switch self {
        case .cash:         return "Numerário"
        case .card:         return "Cartão"
        case .bankTransfer: return "Transferência Bancária"
        case .mpesa:        return "M-Pesa"
        case .emola:        return "e-Mola"
        }
    }

    var icon: String {
        switch self {
        case .cash:         return "banknote"
        case .card:         return "creditcard"
        case .bankTransfer: return "building.columns"
        case .mpesa:        return "phone.fill"
        case .emola:        return "phone.badge.waveform.fill"
        }
    }

    var isMobile: Bool {
        self == .mpesa || self == .emola
    }
}

struct Payment: Identifiable, Codable {
    let id: Int
    var saleId: Int
    var method: PaymentMethod
    var amount: Double
    var reference: String   // número de transacção Mpesa/Emola ou vazio
}
