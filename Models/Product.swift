import Foundation

struct Product: Identifiable, Codable {
    let id: Int
    var name: String
    var barcode: String        // EAN-13, QR, etc. — PK único na BD
    var priceBase: Double
    var ivaRate: Double        // ex: 16.0
    var profitMargin: Double   // ex: 20.0 (%)
    var priceFinal: Double
    var stock: Int             // cache de leitura: soma das quantidades dos lotes
    /// Categoria (nil = "Sem categoria"). No fim, com valor por omissão,
    /// para o init memberwise existente continuar válido.
    var categoryId: Int? = nil
    /// Promoção: desconto em percentagem sobre `priceFinal` (0 = sem promoção).
    var discountPercent: Double = 0

    /// Preço praticado na venda — já com a promoção aplicada.
    var priceWithDiscount: Double {
        priceFinal * (1 - min(max(discountPercent, 0), 90) / 100)
    }

    var hasDiscount: Bool { discountPercent > 0 }

    // Calcula preço final automaticamente
    static func calculateFinalPrice(base: Double, profit: Double, iva: Double) -> Double {
        let withProfit = base * (1 + profit / 100)
        return withProfit * (1 + iva / 100)
    }
}
