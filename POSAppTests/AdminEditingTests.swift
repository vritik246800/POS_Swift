import Foundation
import Testing
@testable import POSApp

/// 1.2/1.3 — Edição de lote e de stock a partir da Administração.
@Suite("Edição na Administração (lote e stock)")
struct AdminEditingTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Admin", username: "admin-teste", passwordHash: "", role: .admin)
    }

    private func makeProduct(stock: Int) throws -> Product {
        asAdmin()
        let barcode = "TST-\(UUID().uuidString.prefix(12))"
        #expect(db.createProduct(name: "Produto edição admin", barcode: barcode,
                                 priceBase: 10, ivaRate: 16, profitMargin: 0, stock: stock))
        return try #require(db.fetchProductByBarcode(barcode))
    }

    @Test("Quantidade negativa não passa a validação do lote")
    func negativeQuantityRejected() throws {
        let product = try makeProduct(stock: 3)
        defer { asAdmin(); _ = db.deleteProduct(id: product.id) }

        let vm = AdminViewModel()
        vm.load()
        var batch = try #require(db.fetchBatches(productId: product.id).first)
        batch.quantity = -1

        #expect(vm.updateBatch(batch) == false)
        #expect(vm.errorMessage == "A quantidade não pode ser negativa.")
        #expect(db.fetchBatches(productId: product.id).first?.quantity == 3)
    }

    @Test("Quantidade e validade do lote são gravadas e o stock acompanha")
    func batchEditIsSaved() throws {
        let product = try makeProduct(stock: 3)
        defer { asAdmin(); _ = db.deleteProduct(id: product.id) }

        let vm = AdminViewModel()
        vm.load()
        var batch = try #require(db.fetchBatches(productId: product.id).first)
        let newExpiry = Calendar.current.date(byAdding: .day, value: 45, to: Date())!
        batch.quantity = 7
        batch.expiryDate = newExpiry

        #expect(vm.updateBatch(batch))
        #expect(vm.errorMessage.isEmpty)

        let saved = try #require(db.fetchBatches(productId: product.id).first)
        #expect(saved.quantity == 7)
        #expect(saved.expiryStatus == .oneMonth)
        #expect(db.fetchProduct(id: product.id)?.stock == 7)
    }

    @Test("Stock negativo é recusado; stock válido é gravado")
    func stockEdit() throws {
        let product = try makeProduct(stock: 2)
        defer { asAdmin(); _ = db.deleteProduct(id: product.id) }

        let vm = AdminViewModel()
        vm.load()

        #expect(vm.updateStock(productId: product.id, newStock: -5) == false)
        #expect(vm.errorMessage == "O stock não pode ser negativo.")
        #expect(db.fetchProduct(id: product.id)?.stock == 2)

        #expect(vm.updateStock(productId: product.id, newStock: 25))
        #expect(vm.errorMessage.isEmpty)
        #expect(db.fetchProduct(id: product.id)?.stock == 25)
    }
}
