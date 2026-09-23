import Foundation
import Testing
@testable import POSApp

/// 1.1 — O Caixa tem de ver a sua caixa do dia e conseguir fechá-la.
/// O ecrã só mostra o botão quando `cashierStatuses` devolve a caixa do próprio
/// utilizador com vendas — é isso que este teste percorre, sem UI.
@Suite("Fecho da própria caixa (perfil Caixa)")
struct CashierCloseFlowTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Admin", username: "admin-teste", passwordHash: "", role: .admin)
    }

    @Test("Caixa vê a sua caixa com vendas e consegue fechá-la")
    func cashierSeesOwnCashier() throws {
        asAdmin()

        // Utilizador Caixa
        let username = "caixa-\(UUID().uuidString.prefix(8))"
        #expect(db.createUser(name: "Caixa Teste", username: username, passwordHash: "x", role: .cashier))
        let cashier = try #require(db.fetchUserByUsername(username))
        defer { asAdmin(); _ = db.deleteUser(id: cashier.id) }

        // Produto com stock
        let barcode = "TST-\(UUID().uuidString.prefix(12))"
        #expect(db.createProduct(name: "Produto fecho caixa", barcode: barcode,
                                 priceBase: 10, ivaRate: 16, profitMargin: 0, stock: 5))
        let product = try #require(db.fetchProductByBarcode(barcode))
        defer { asAdmin(); _ = db.deleteProduct(id: product.id) }

        // Venda feita pelo Caixa, com o Caixa autenticado
        db.currentUser = cashier
        let item = SaleItem(id: 0, saleId: 0, productId: product.id, productName: product.name,
                            quantity: 1, unitPrice: 20, subtotal: 20)
        let saleId = try #require(db.createSaleAtomic(
            userId: cashier.id, clientName: "", clientNIF: "",
            items: [item], total: 20,
            payments: [Payment(id: 0, saleId: 0, method: .cash, amount: 20, reference: "")]
        ))
        defer { asAdmin(); _ = db.deleteSale(id: saleId) }

        // O que o ecrã do Caixa mostra
        let vm = AdminViewModel()
        vm.load()
        let mine = vm.cashierStatuses(date: Date()).filter { $0.user.id == cashier.id }
        let status = try #require(mine.first, "O Caixa não vê a sua própria caixa")
        #expect(status.numSales == 1)
        #expect(status.total == 20)
        #expect(status.amount(for: .cash) == 20)
        #expect(!status.isClosed)

        // E consegue fechá-la (é o que o botão faz)
        #expect(vm.closeCashier(status, date: Date(), notes: "teste"))
        vm.load()
        let after = try #require(vm.cashierStatuses(date: Date()).first { $0.user.id == cashier.id })
        #expect(after.isClosed)

        asAdmin()
        _ = db.reopenCashierClose(date: Constants.todayKey(), userId: cashier.id)
    }
}
