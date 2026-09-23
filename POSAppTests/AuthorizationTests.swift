import Foundation
import Testing
@testable import POSApp

@Suite("Autorização na camada de dados")
struct AuthorizationTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Admin", username: "admin-teste", passwordHash: "", role: .admin)
    }

    private func asCashier() {
        db.currentUser = User(id: -2, name: "Caixa", username: "caixa-teste", passwordHash: "", role: .cashier)
    }

    private func makeProduct() throws -> Product {
        asAdmin()
        let barcode = "TST-\(UUID().uuidString.prefix(12))"
        #expect(db.createProduct(name: "Produto de teste autz", barcode: barcode,
                                 priceBase: 10, ivaRate: 16, profitMargin: 0, stock: 0))
        return try #require(db.fetchProductByBarcode(barcode))
    }

    private func makeUser(role: UserRole) throws -> User {
        let username = "tmp-\(UUID().uuidString.prefix(8))"
        #expect(db.createUser(name: "Temp", username: username, passwordHash: "x", role: role))
        return try #require(db.fetchUserByUsername(username))
    }

    @Test("Caixa não apaga produtos; Admin apaga")
    func deleteProductIsAdminOnly() throws {
        let product = try makeProduct()
        asCashier()
        #expect(db.deleteProduct(id: product.id) == false)
        #expect(db.fetchProduct(id: product.id) != nil)

        asAdmin()
        #expect(db.deleteProduct(id: product.id))
        #expect(db.fetchProduct(id: product.id) == nil)
    }

    @Test("Caixa não altera preços, mas pode corrigir o nome")
    func priceChangeIsAdminOnly() throws {
        let product = try makeProduct()
        defer { asAdmin(); _ = db.deleteProduct(id: product.id) }

        asCashier()
        var reprice = product
        reprice.priceBase = 999
        #expect(db.updateProduct(reprice) == false)
        #expect(db.fetchProduct(id: product.id)?.priceBase == 10)

        var rename = product
        rename.name = "Nome corrigido"
        #expect(db.updateProduct(rename))
        #expect(db.fetchProduct(id: product.id)?.name == "Nome corrigido")

        asAdmin()
        #expect(db.updateProduct(reprice))
        #expect(db.fetchProduct(id: product.id)?.priceBase == 999)
    }

    @Test("Caixa não apaga utilizadores, vendas nem reabre fechos de caixa")
    func privilegedOperationsBlocked() throws {
        asAdmin()
        let victim = try makeUser(role: .cashier)
        defer { asAdmin(); _ = db.deleteUser(id: victim.id) }

        asCashier()
        #expect(db.deleteUser(id: victim.id) == false)
        #expect(db.deleteSale(id: 999_999) == false)
        #expect(db.reopenDayClose(date: "2999-01-01") == false)
        #expect(db.fetchUserByUsername(victim.username) != nil)
    }

    @Test("Um utilizador pode editar-se a si próprio mas não se promove")
    func selfEditCannotEscalate() throws {
        asAdmin()
        let user = try makeUser(role: .cashier)
        defer { asAdmin(); _ = db.deleteUser(id: user.id) }

        db.currentUser = user
        var renamed = user
        renamed.name = "Nome próprio"
        #expect(db.updateUser(renamed))                       // permitido: é ele próprio

        var promoted = user
        promoted.role = .admin
        #expect(db.updateUser(promoted) == false)             // escalada de perfil bloqueada
        #expect(db.fetchUsers().first { $0.id == user.id }?.role == .cashier)

        // Um utilizador não mexe noutro.
        let other = try { () -> User in asAdmin(); return try makeUser(role: .cashier) }()
        defer { asAdmin(); _ = db.deleteUser(id: other.id) }
        db.currentUser = user
        var hijack = other
        hijack.name = "Invadido"
        #expect(db.updateUser(hijack) == false)
    }

    @Test("O último Admin não é apagado nem despromovido")
    func lastAdminIsProtected() throws {
        asAdmin()
        let admin = try makeUser(role: .admin)
        var cleanedUp = false
        defer { if !cleanedUp { asAdmin(); _ = db.deleteUser(id: admin.id) } }

        if db.adminCount() == 1 {
            // Único Admin na base de dados: nem apagar nem despromover.
            #expect(db.deleteUser(id: admin.id) == false)
            var demoted = admin
            demoted.role = .cashier
            #expect(db.updateUser(demoted) == false)
        } else {
            // Havendo outros Admins, a operação é permitida.
            var demoted = admin
            demoted.role = .cashier
            #expect(db.updateUser(demoted))
            #expect(db.deleteUser(id: admin.id))
            cleanedUp = true
        }

        // Invariante em qualquer caso: nunca se fica sem Admin.
        #expect(db.adminCount() >= 1)
    }
}
