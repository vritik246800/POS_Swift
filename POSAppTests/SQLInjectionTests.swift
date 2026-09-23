import Foundation
import Testing
@testable import POSApp

@Suite("Injeção de SQL")
struct SQLInjectionTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Teste", username: "teste", passwordHash: "", role: .admin)
    }

    /// Cria um utilizador temporário (a FK `closed_by` exige um id real) e devolve o seu id.
    private func makeTempUser() -> Int? {
        let username = "tmp-\(UUID().uuidString.prefix(8))"
        guard db.createUser(name: "Temp", username: username, passwordHash: "x", role: .cashier) else { return nil }
        return db.fetchUserByUsername(username)?.id
    }

    @Test("fetchDayCloses(monthPrefix:) liga o prefixo, não o interpola")
    func dayClosesPrefixIsBound() throws {
        asAdmin()
        let userId = try #require(makeTempUser())
        let date = "2999-07-15"
        defer {
            _ = db.reopenDayClose(date: date)
            _ = db.deleteUser(id: userId)
        }

        #expect(db.saveDayClose(date: date, totalSales: 100, cash: 100, card: 0,
                                bankTransfer: 0, mpesa: 0, emola: 0,
                                numSales: 1, notes: "", closedBy: userId))

        // Prefixo legítimo encontra o registo.
        #expect(db.fetchDayCloses(monthPrefix: "2999-07").contains { $0.date == date })

        // Payloads de injeção são tratados como texto: não devolvem tudo nem rebentam.
        for payload in ["2999-07' OR '1'='1",
                        "' OR 1=1 --",
                        "'; DROP TABLE DayCloses; --"] {
            #expect(db.fetchDayCloses(monthPrefix: payload).isEmpty)
        }

        // A tabela sobreviveu ao payload de DROP.
        #expect(db.fetchDayCloses(monthPrefix: "2999-07").contains { $0.date == date })
    }

    @Test("Pesquisa de produtos trata metacaracteres como texto")
    func searchIsBound() {
        #expect(db.searchProducts(query: "' OR 1=1 --").isEmpty)
        #expect(db.fetchProductByBarcode("' OR '1'='1") == nil)
    }
}
