import Foundation
import CryptoKit
import CommonCrypto
internal import Combine

class AuthViewModel: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var isLoggedIn: Bool = false
    @Published var errorMessage: String = ""

    /// Contador de rejeições de login. Só existe para a UI ter um gatilho de
    /// animação que dispara mesmo quando a mensagem de erro se repete.
    /// Não guarda credenciais nem identifica a conta.
    @Published private(set) var loginFailureCount: Int = 0

    private let db = DatabaseManager.shared

    // S10 — bloqueio após tentativas falhadas (estado só em memória)
    private var failedAttempts = 0
    private var lockedUntil: Date?
    private static let maxAttempts = 5
    private static let lockoutSeconds: TimeInterval = 30

    // S2 — PBKDF2-HMAC-SHA256
    private static let iterations = 210_000
    private static let saltBytes = 16
    private static let keyBytes = 32
    private static let prefix = "pbkdf2$sha256$"

    // MARK: - Login
    func login(username: String, password: String) {
        if let lockedUntil, lockedUntil > Date() {
            let seconds = Int(lockedUntil.timeIntervalSinceNow.rounded(.up))
            errorMessage = "Demasiadas tentativas. Tente novamente dentro de \(seconds) s."
            loginFailureCount += 1
            return
        }

        // R18 — entrada hostil recusada antes de tocar na base de dados e no KDF.
        // Mensagem única: não revela qual dos campos falhou nem se a conta existe.
        // Não conta para o bloqueio de 5 tentativas — lixo de teclado não tranca a caixa.
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty,
              !password.isEmpty,
              cleanUsername.count <= Constants.usernameMaxLength,
              password.count <= Constants.passwordMaxLength,
              cleanUsername.rangeOfCharacter(from: .controlCharacters) == nil else {
            loginFailureCount += 1
            errorMessage = "Credenciais inválidas."
            return
        }

        let user = db.fetchUserByUsername(cleanUsername)
        // KDF corre sempre — com utilizador inexistente usa um hash falso,
        // para o tempo de resposta não revelar se a conta existe.
        let isValid: Bool
        if let user {
            isValid = verifyPassword(password, storedHash: user.passwordHash)
        } else {
            _ = Self.derive(password: password, salt: Data(repeating: 0, count: Self.saltBytes), iterations: Self.iterations)
            isValid = false
        }

        guard isValid, let user else {
            failedAttempts += 1
            if failedAttempts >= Self.maxAttempts {
                lockedUntil = Date().addingTimeInterval(Self.lockoutSeconds)
                failedAttempts = 0
            }
            db.logAudit(action: "login_failed", entity: "Users", entityId: user?.id, userId: user?.id)
            errorMessage = "Credenciais inválidas."
            loginFailureCount += 1
            return
        }

        failedAttempts = 0
        lockedUntil = nil
        currentUser = user
        db.currentUser = user       // S3 — autorização na camada de dados
        isLoggedIn = true
        errorMessage = ""

        // S2 — hash antigo (SHA-256) migra para PBKDF2 no primeiro login com sucesso.
        if !user.passwordHash.hasPrefix(Self.prefix) {
            var migrated = user
            migrated.passwordHash = hashPassword(password)
            _ = db.updateUser(migrated)
            currentUser = migrated
            db.currentUser = migrated
        }
    }

    // MARK: - Logout
    func logout() {
        currentUser = nil
        db.currentUser = nil
        isLoggedIn = false
    }

    // MARK: - Criar Utilizador
    func createUser(name: String, username: String, password: String, role: UserRole) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            errorMessage = "Nome, utilizador e password são obrigatórios."
            return false
        }
        let ok = db.createUser(name: name, username: username, passwordHash: hashPassword(password), role: role)
        if ok { db.logAudit(action: "user_created", entity: "Users", entityId: nil) }
        return ok
    }

    // MARK: - Hash de Password (PBKDF2-HMAC-SHA256, sal aleatório por utilizador)

    /// Devolve `pbkdf2$sha256$<iterações>$<sal base64>$<hash base64>`.
    func hashPassword(_ password: String) -> String {
        let salt = Data((0..<Self.saltBytes).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        let key = Self.derive(password: password, salt: salt, iterations: Self.iterations)
        return "\(Self.prefix)\(Self.iterations)$\(salt.base64EncodedString())$\(key.base64EncodedString())"
    }

    /// Valida contra o formato novo e contra os hashes SHA-256 antigos.
    func verifyPassword(_ password: String, storedHash: String) -> Bool {
        if storedHash.hasPrefix(Self.prefix) {
            let parts = storedHash.components(separatedBy: "$")
            guard parts.count == 5,
                  let iterations = Int(parts[2]),
                  let salt = Data(base64Encoded: parts[3]),
                  let expected = Data(base64Encoded: parts[4]) else { return false }
            return Self.constantTimeEquals(Self.derive(password: password, salt: salt, iterations: iterations), expected)
        }
        // Legado: SHA-256 hexadecimal (com ou sem prefixo "sha256$")
        let legacy = storedHash.hasPrefix("sha256$") ? String(storedHash.dropFirst("sha256$".count)) : storedHash
        let computed = SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self.constantTimeEquals(Data(computed.utf8), Data(legacy.utf8))
    }

    private static func derive(password: String, salt: Data, iterations: Int) -> Data {
        var derived = [UInt8](repeating: 0, count: keyBytes)
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt)
        _ = passwordBytes.withUnsafeBytes { passwordRaw in
            saltBytes.withUnsafeBufferPointer { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordRaw.bindMemory(to: CChar.self).baseAddress, passwordBytes.count,
                    saltPtr.baseAddress, saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived, derived.count
                )
            }
        }
        return Data(derived)
    }

    /// Comparação sem short-circuit — o tempo não depende de onde diverge.
    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    // MARK: - Verificar se é Admin
    var isAdmin: Bool {
        currentUser?.role == .admin
    }

    // MARK: - Lista de utilizadores (para verificar limite de subscrição)
    var users: [User] {
        db.fetchUsers()
    }

    var userCount: Int {
        users.count
    }
}
