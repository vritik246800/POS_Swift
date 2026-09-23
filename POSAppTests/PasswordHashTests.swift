import Foundation
import CryptoKit
import Testing
@testable import POSApp

@Suite("Hash de password (PBKDF2)")
struct PasswordHashTests {

    @Test("Formato pbkdf2$sha256$<iter>$<sal>$<hash>")
    func format() {
        let hash = AuthViewModel().hashPassword("Segredo123!")
        let parts = hash.components(separatedBy: "$")
        #expect(parts.count == 5)
        #expect(parts[0] == "pbkdf2")
        #expect(parts[1] == "sha256")
        #expect((Int(parts[2]) ?? 0) >= 210_000)
        #expect(Data(base64Encoded: parts[3])?.count == 16)   // sal de 16 bytes
        #expect(Data(base64Encoded: parts[4])?.count == 32)   // SHA-256 → 32 bytes
    }

    @Test("Sal aleatório: a mesma password nunca dá o mesmo hash")
    func randomSalt() {
        let vm = AuthViewModel()
        #expect(vm.hashPassword("mesma") != vm.hashPassword("mesma"))
    }

    @Test("Verificação aceita a password certa e recusa a errada")
    func verify() {
        let vm = AuthViewModel()
        let hash = vm.hashPassword("Correta!")
        #expect(vm.verifyPassword("Correta!", storedHash: hash))
        #expect(vm.verifyPassword("Errada!", storedHash: hash) == false)
        #expect(vm.verifyPassword("", storedHash: hash) == false)
    }

    @Test("Hash antigo (SHA-256 hex) continua a validar, com e sem prefixo")
    func legacyHash() {
        let vm = AuthViewModel()
        let legacy = SHA256.hash(data: Data("admin123".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(vm.verifyPassword("admin123", storedHash: legacy))
        #expect(vm.verifyPassword("admin123", storedHash: "sha256$" + legacy))
        #expect(vm.verifyPassword("outra", storedHash: legacy) == false)
    }

    @Test("Hash malformado é recusado sem rebentar")
    func malformed() {
        let vm = AuthViewModel()
        #expect(vm.verifyPassword("x", storedHash: "pbkdf2$sha256$nao-e-numero$$") == false)
        #expect(vm.verifyPassword("x", storedHash: "pbkdf2$sha256$210000$@@@$@@@") == false)
    }
}

// MARK: - Bateria hostil de login (R18)

@Suite("Login — entrada hostil", .serialized)
struct LoginInputTests {

    private let db = DatabaseManager.shared

    /// Cria um utilizador com password real e devolve o username usado.
    private func makeUser(username: String, password: String) -> String {
        let hash = AuthViewModel().hashPassword(password)
        #expect(db.createUser(name: "Teste login", username: username, passwordHash: hash, role: .cashier))
        return username
    }

    private func cleanUp(_ username: String) {
        db.currentUser = User(id: -1, name: "Admin", username: "admin-teste", passwordHash: "", role: .admin)
        if let user = db.fetchUserByUsername(username) { _ = db.deleteUser(id: user.id) }
        db.currentUser = nil
    }

    @Test("Username acima de 64 caracteres é recusado mesmo com a password certa")
    func usernameTooLong() {
        let long = String(repeating: "u", count: 100)
        let username = makeUser(username: long, password: "Segredo123!")
        defer { cleanUp(username) }

        let vm = AuthViewModel()
        vm.login(username: long, password: "Segredo123!")

        #expect(vm.isLoggedIn == false)
        #expect(vm.errorMessage == "Credenciais inválidas.")
        #expect(vm.loginFailureCount == 1)
    }

    @Test("Password acima de 128 caracteres é recusada antes do KDF")
    func passwordTooLong() {
        let huge = String(repeating: "p", count: 200)
        let username = makeUser(username: "pwlong-\(UUID().uuidString.prefix(6))", password: huge)
        defer { cleanUp(username) }

        let vm = AuthViewModel()
        vm.login(username: username, password: huge)

        #expect(vm.isLoggedIn == false)
        #expect(vm.errorMessage == "Credenciais inválidas.")
    }

    @Test("Caracteres de controlo no username são recusados")
    func controlCharactersRejected() {
        let hostile = "ctl-\(UUID().uuidString.prefix(6))\u{0007}x"
        let username = makeUser(username: hostile, password: "Segredo123!")
        defer { cleanUp(username) }

        let vm = AuthViewModel()
        vm.login(username: hostile, password: "Segredo123!")

        #expect(vm.isLoggedIn == false)
        #expect(db.currentUser == nil)
    }

    @Test("Username vazio ou só espaços nunca chega à base de dados")
    func emptyUsername() {
        let vm = AuthViewModel()
        vm.login(username: "   ", password: "Segredo123!")
        #expect(vm.isLoggedIn == false)

        vm.login(username: "alguem", password: "")
        #expect(vm.isLoggedIn == false)
        #expect(vm.loginFailureCount == 2)
    }

    @Test("Espaços à volta do username não impedem o login")
    func trimsSurroundingWhitespace() {
        let username = makeUser(username: "trim-\(UUID().uuidString.prefix(6))", password: "Segredo123!")
        defer { cleanUp(username) }

        let vm = AuthViewModel()
        vm.login(username: "  \(username)  ", password: "Segredo123!")

        #expect(vm.isLoggedIn)
        #expect(vm.currentUser?.username == username)
        vm.logout()
    }

    @Test("Cada rejeição incrementa o contador que dispara a animação")
    func failureCounterFeedsAnimation() {
        let username = makeUser(username: "cnt-\(UUID().uuidString.prefix(6))", password: "Segredo123!")
        defer { cleanUp(username) }

        let vm = AuthViewModel()
        #expect(vm.loginFailureCount == 0)
        vm.login(username: username, password: "errada")
        #expect(vm.loginFailureCount == 1)
        vm.login(username: username, password: "outra errada")
        #expect(vm.loginFailureCount == 2)
        #expect(vm.isLoggedIn == false)
    }
}

// MARK: - Ligação de texto ao SQLite (SQLITE_TRANSIENT)

@Suite("Login — leitura estável do utilizador", .serialized)
struct UserLookupStabilityTests {

    private let db = DatabaseManager.shared

    /// Com `SQLITE_STATIC` (o `nil` antigo) o ponteiro da `NSString` temporária
    /// podia morrer antes do `sqlite3_step` e a consulta devolvia `nil` de vez
    /// em quando — o login recusava credenciais certas. Repetir a consulta com
    /// churn de autorelease pelo meio apanha essa instabilidade.
    @Test("fetchUserByUsername devolve sempre o mesmo utilizador, consulta após consulta")
    func lookupIsStable() throws {
        let username = "look-\(UUID().uuidString.prefix(8))"
        #expect(db.createUser(name: "Estabilidade", username: username,
                              passwordHash: "x", role: .cashier))
        defer {
            db.currentUser = User(id: -1, name: "Admin", username: "admin-teste",
                                  passwordHash: "", role: .admin)
            if let user = db.fetchUserByUsername(username) { _ = db.deleteUser(id: user.id) }
            db.currentUser = nil
        }

        let expected = try #require(db.fetchUserByUsername(username))
        for _ in 0..<60 {
            autoreleasepool {
                // lixo de strings temporárias entre consultas
                _ = (0..<40).map { "\(UUID().uuidString)-\($0)" }.joined()
                let found = db.fetchUserByUsername(username)
                #expect(found?.id == expected.id)
                #expect(found?.username == username)
            }
        }
    }

    @Test("Login com credenciais certas entra em todas as tentativas seguidas")
    func repeatedLoginSucceeds() {
        let username = "rep-\(UUID().uuidString.prefix(8))"
        let password = "Segredo123!"
        #expect(db.createUser(name: "Repetido", username: username,
                              passwordHash: AuthViewModel().hashPassword(password),
                              role: .cashier))
        defer {
            db.currentUser = User(id: -1, name: "Admin", username: "admin-teste",
                                  passwordHash: "", role: .admin)
            if let user = db.fetchUserByUsername(username) { _ = db.deleteUser(id: user.id) }
            db.currentUser = nil
        }

        for _ in 0..<5 {
            let vm = AuthViewModel()
            vm.login(username: username, password: password)
            #expect(vm.isLoggedIn)
            #expect(vm.errorMessage.isEmpty)
            vm.logout()
        }
    }

    /// Guarda determinista: o bug não se reproduz à ordem (depende de quando o
    /// autorelease pool esvazia), por isso o que se testa é a regra no código —
    /// nenhuma ligação de texto pode voltar a passar `SQLITE_STATIC` (`nil`).
    @Test("Nenhum sqlite3_bind_text volta a usar SQLITE_STATIC")
    func noStaticTextBinding() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // POSAppTests/
            .deletingLastPathComponent()      // raiz do projeto
        let source = root.appendingPathComponent("Database/DatabaseManager.swift")
        let code = try String(contentsOf: source, encoding: .utf8)

        let offenders = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.element.contains("sqlite3_bind_text(") && $0.element.hasSuffix("nil)") }
            .map { $0.offset + 1 }

        #expect(offenders.isEmpty, "sqlite3_bind_text com SQLITE_STATIC nas linhas \(offenders)")
    }
}
