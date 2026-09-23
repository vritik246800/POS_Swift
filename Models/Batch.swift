import Foundation

/// Lote de stock de um produto. O stock de um produto é a soma dos seus lotes.
struct Batch: Identifiable, Codable, Hashable {
    let id: Int
    var productId: Int
    var quantity: Int
    var priceBase: Double       // preço base pago neste lote — base do cálculo de perdas
    var expiryDate: Date?       // nil = não expira
    var receivedAt: Date

    /// Valor perdido/em risco deste lote, ao preço base pago.
    var lostValue: Double { Double(quantity) * priceBase }

    var expiryStatus: ExpiryStatus { ExpiryStatus.from(expiryDate: expiryDate) }
}
