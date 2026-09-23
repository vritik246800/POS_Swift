import Foundation
import Testing
@testable import POSApp

@Suite("Produtos parados (regra dos 6 meses)")
struct StaleProductTests {

    /// Limite: hoje menos 6 meses.
    private static var limit: Date {
        Calendar.current.date(byAdding: .month, value: -6, to: Date())!
    }

    @Test("Nunca vendido conta como parado")
    func neverSold() {
        #expect(AdminViewModel.isStale(lastSale: nil, limit: Self.limit))
    }

    @Test("Vendido ontem não está parado")
    func soldYesterday() {
        let yesterday = Date().addingTimeInterval(-86_400)
        #expect(!AdminViewModel.isStale(lastSale: yesterday, limit: Self.limit))
    }

    @Test("Vendido há 7 meses está parado")
    func soldSevenMonthsAgo() {
        let old = Calendar.current.date(byAdding: .month, value: -7, to: Date())!
        #expect(AdminViewModel.isStale(lastSale: old, limit: Self.limit))
    }

    @Test("Exactamente no limite ainda não está parado")
    func exactlyAtLimit() {
        let limit = Self.limit
        #expect(!AdminViewModel.isStale(lastSale: limit, limit: limit))
    }
}

@Suite("Fecho por caixa")
struct CashierCloseTests {

    private static func user(_ id: Int, _ role: UserRole = .cashier) -> User {
        User(id: id, name: "U\(id)", username: "u\(id)", passwordHash: "x", role: role)
    }

    private static func sale(_ id: Int, userId: Int, total: Double) -> Sale {
        Sale(id: id, userId: userId, clientName: "", clientNIF: "", items: [],
             total: total, date: Date(), status: .completed)
    }

    private static func payment(_ id: Int, saleId: Int, _ method: PaymentMethod, _ amount: Double) -> Payment {
        Payment(id: id, saleId: saleId, method: method, amount: amount, reference: "")
    }

    private static var status: CashierDayStatus {
        CashierDayStatus(
            user: user(1),
            sales: [sale(10, userId: 1, total: 100), sale(11, userId: 1, total: 50)],
            payments: [payment(1, saleId: 10, .cash, 60),
                       payment(2, saleId: 10, .mpesa, 40),
                       payment(3, saleId: 11, .cash, 50)],
            close: nil
        )
    }

    @Test("Total e número de vendas agregam as vendas do utilizador")
    func aggregates() {
        #expect(Self.status.total == 150)
        #expect(Self.status.numSales == 2)
    }

    @Test("Total por método soma só os pagamentos desse método")
    func perMethod() {
        #expect(Self.status.amount(for: .cash) == 110)
        #expect(Self.status.amount(for: .mpesa) == 40)
        #expect(Self.status.amount(for: .card) == 0)
    }

    @Test("Sem fecho gravado a caixa está por fechar")
    func openByDefault() {
        #expect(!Self.status.isClosed)
    }

    @Test("Com fecho gravado a caixa aparece fechada e sabe quem a fechou")
    func closedByAdmin() {
        let close = CashierClose(id: 1, date: "2026-08-16", userId: 1, totalSales: 150,
                                 totalCash: 110, totalCard: 0, totalBankTransfer: 0,
                                 totalMpesa: 40, totalEmola: 0, numSales: 2, notes: "",
                                 closedBy: 99, closedAt: Date())
        let closed = CashierDayStatus(user: Self.user(1), sales: [], payments: [], close: close)
        #expect(closed.isClosed)
        #expect(close.closedByAdmin)
        #expect(close.grandTotal == 150)
    }
}

@Suite("Vendas por caixa")
struct CashierPerformanceTests {

    private static func user(_ id: Int, _ name: String) -> User {
        User(id: id, name: name, username: "u\(id)", passwordHash: "x", role: .cashier)
    }

    private static func sale(_ id: Int, userId: Int, total: Double) -> Sale {
        Sale(id: id, userId: userId, clientName: "", clientNIF: "", items: [],
             total: total, date: Date(), status: .completed)
    }

    @Test("Agrega número de vendas e total por utilizador")
    func aggregates() {
        let rows = AdminViewModel.cashierPerformance(
            sales: [Self.sale(1, userId: 7, total: 100),
                    Self.sale(2, userId: 7, total: 50),
                    Self.sale(3, userId: 8, total: 30)],
            users: [Self.user(7, "Ana"), Self.user(8, "Bruno")]
        )

        #expect(rows.count == 2)
        #expect(rows.first?.name == "Ana")
        #expect(rows.first?.numSales == 2)
        #expect(rows.first?.total == 150)
        #expect(rows.last?.numSales == 1)
        #expect(rows.last?.total == 30)
    }

    @Test("Ordena do maior total para o menor")
    func sortedByTotal() {
        let rows = AdminViewModel.cashierPerformance(
            sales: [Self.sale(1, userId: 7, total: 10), Self.sale(2, userId: 8, total: 900)],
            users: [Self.user(7, "Ana"), Self.user(8, "Bruno")]
        )
        #expect(rows.map { $0.name } == ["Bruno", "Ana"])
    }

    /// Utilizador apagado não pode fazer desaparecer dinheiro do painel.
    @Test("Venda de utilizador desconhecido conta com nome de recurso")
    func unknownUser() {
        let rows = AdminViewModel.cashierPerformance(
            sales: [Self.sale(1, userId: 42, total: 200)],
            users: []
        )
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Utilizador #42")
        #expect(rows.first?.total == 200)
    }

    /// O total do painel bate certo com a receita do período, sempre.
    @Test("Soma dos caixas é a receita do período")
    func matchesRevenue() {
        let sales = [Self.sale(1, userId: 7, total: 100),
                     Self.sale(2, userId: 8, total: 30),
                     Self.sale(3, userId: 99, total: 5.5)]
        let rows = AdminViewModel.cashierPerformance(sales: sales, users: [Self.user(7, "Ana")])
        let panelTotal: Double = rows.reduce(0) { $0 + $1.total }
        let periodTotal: Double = sales.reduce(0) { $0 + $1.total }
        #expect(panelTotal == periodTotal)
    }

    @Test("Sem vendas não há linhas")
    func empty() {
        #expect(AdminViewModel.cashierPerformance(sales: [], users: [Self.user(7, "Ana")]).isEmpty)
    }
}
