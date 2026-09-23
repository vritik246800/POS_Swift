import SwiftUI

// MARK: - Modelo de Produto Recebido

/// Represents a product received via proximity sharing from the desktop POS system
struct ReceivedProduct: Identifiable {
    let id = UUID()
    let barcode: String
    let name: String
    let currentStock: Int
    let orderQuantity: Int
    let priceBase: Double
    
    var stockLevel: StockLevel {
        if currentStock == 0 { return .critical }
        if currentStock <= 3 { return .low }
        return .medium
    }
    
    enum StockLevel {
        case critical, low, medium

        var label: String {
            switch self {
            case .critical: return "Crítico"
            case .low: return "Baixo"
            case .medium: return "Médio"
            }
        }

        var color: Color {
            switch self {
            case .critical: return .red
            case .low: return .orange
            case .medium: return .yellow
            }
        }
    }
}
