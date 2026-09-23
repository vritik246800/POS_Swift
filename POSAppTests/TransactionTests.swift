import Foundation
import Testing
@testable import POSApp

@Suite("Transação da venda")
struct TransactionTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Teste", username: "teste", passwordHash: "", role: .admin)
    }

    private func makeTempUser() -> Int? {
        let username = "tmp-\(UUID().uuidString.prefix(8))"
        guard db.createUser(name: "Temp", username: username, passwordHash: "x", role: .cashier) else { return nil }
        return db.fetchUserByUsername(username)?.id
    }

    private func makeProduct(stock: Int) throws -> Product {
        asAdmin()
        let barcode = "TST-\(UUID().uuidString.prefix(12))"
        #expect(db.createProduct(name: "Produto de teste venda", barcode: barcode,
                                 priceBase: 10, ivaRate: 16, profitMargin: 0, stock: stock))
        return try #require(db.fetchProductByBarcode(barcode))
    }

    private func item(_ product: Product, _ quantity: Int) -> SaleItem {
        SaleItem(id: 0, saleId: 0, productId: product.id, productName: product.name,
                 quantity: quantity, unitPrice: product.priceFinal,
                 subtotal: product.priceFinal * Double(quantity))
    }

    @Test("Venda válida grava venda, itens, pagamentos e desconta stock")
    func commitsEverything() throws {
        asAdmin()
        let userId = try #require(makeTempUser())
        let product = try makeProduct(stock: 10)
        defer {
            _ = db.deleteProduct(id: product.id)
            _ = db.deleteUser(id: userId)
        }

        let payments = [Payment(id: 0, saleId: 0, method: .cash, amount: product.priceFinal * 3, reference: "")]
        let saleId = try #require(db.createSaleAtomic(userId: userId, clientName: "Cliente", clientNIF: "",
                                                     items: [item(product, 3)],
                                                     total: product.priceFinal * 3,
                                                     payments: payments))
        defer { _ = db.deleteSale(id: saleId) }

        #expect(db.fetchSaleItems(saleId: saleId).count == 1)
        #expect(db.fetchPayments(saleId: saleId).count == 1)
        #expect(db.availableStock(productId: product.id) == 7)
        #expect(db.fetchProduct(id: product.id)?.stock == 7)
    }

    @Test("Stock insuficiente: nada é gravado (ROLLBACK)")
    func rollsBackWhenStockMissing() throws {
        asAdmin()
        let userId = try #require(makeTempUser())
        let product = try makeProduct(stock: 2)
        defer {
            _ = db.deleteProduct(id: product.id)
            _ = db.deleteUser(id: userId)
        }

        let salesBefore = db.fetchSales().count
        let result = db.createSaleAtomic(userId: userId, clientName: "Cliente", clientNIF: "",
                                         items: [item(product, 5)],
                                         total: product.priceFinal * 5,
                                         payments: [])
        #expect(result == nil)
        #expect(db.fetchSales().count == salesBefore)
        #expect(db.availableStock(productId: product.id) == 2)   // stock intacto
    }

    @Test("Um item inválido no meio anula a venda inteira")
    func rollsBackWholeSale() throws {
        asAdmin()
        let userId = try #require(makeTempUser())
        let good = try makeProduct(stock: 10)
        let bad = try makeProduct(stock: 1)
        defer {
            _ = db.deleteProduct(id: good.id)
            _ = db.deleteProduct(id: bad.id)
            _ = db.deleteUser(id: userId)
        }

        let salesBefore = db.fetchSales().count
        let result = db.createSaleAtomic(userId: userId, clientName: "", clientNIF: "",
                                         items: [item(good, 2), item(bad, 5)],
                                         total: 0, payments: [])
        #expect(result == nil)
        #expect(db.fetchSales().count == salesBefore)
        #expect(db.availableStock(productId: good.id) == 10)     // o item bom também foi revertido
        #expect(db.availableStock(productId: bad.id) == 1)
    }

    @Test("O helper transaction faz ROLLBACK quando o corpo devolve nil")
    func helperRollsBack() {
        let username = "rollback-\(UUID().uuidString.prefix(8))"
        let result: Bool? = db.transaction {
            _ = db.createUser(name: "Descartável", username: username, passwordHash: "x", role: .cashier)
            return nil        // força ROLLBACK
        }
        #expect(result == nil)
        #expect(db.fetchUserByUsername(username) == nil)
    }
}
