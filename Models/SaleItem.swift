import Foundation

struct SaleItem: Identifiable, Codable, Equatable {
    let id: Int
    var saleId: Int
    var productId: Int
    var productName: String
    var quantity: Int
    var unitPrice: Double
    var subtotal: Double
}
