import Foundation
import Security

/// Gere o período de teste.
///
/// A data de início vive no **Keychain** (S14): sobrevive à reinstalação da app
/// e não é editável a partir dos ficheiros de preferências, ao contrário do
/// `UserDefaults`. O `UserDefaults` fica só como caminho de migração dos
/// instalações antigas e como recurso se o Keychain não estiver disponível.
class TrialManager {
    static let shared = TrialManager()

    private let keychainService = "com.posapp.trial"
    private let keychainAccount = "trial_start_date"
    private let legacyDefaultsKey = "trial_start_date"
    private let trialDays = 15

    // MARK: - API pública

    func registerFirstLaunchIfNeeded() {
        if let legacy = UserDefaults.standard.object(forKey: legacyDefaultsKey) as? Date {
            // Migração: a data antiga passa para o Keychain e sai das preferências.
            if keychainReadDate() == nil { keychainWrite(legacy) }
            if keychainReadDate() != nil {
                UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            }
            return
        }
        guard trialStartDate == nil else { return }
        keychainWrite(Date())
    }

    var trialStartDate: Date? {
        keychainReadDate() ?? UserDefaults.standard.object(forKey: legacyDefaultsKey) as? Date
    }

    var daysRemaining: Int {
        guard let start = trialStartDate else { return trialDays }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, trialDays - elapsed)
    }

    var isTrialActive: Bool {
        daysRemaining > 0
    }

    var isTrialExpired: Bool {
        !isTrialActive
    }

    // MARK: - Keychain

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private func keychainReadDate() -> Date? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func keychainWrite(_ date: Date) {
        let data = Data(ISO8601DateFormatter().string(from: date).utf8)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemDelete(baseQuery as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            // Keychain indisponível (ex.: alvo sem entitlement): não deixar o
            // período de teste sem data de início, senão nunca expirava.
            UserDefaults.standard.set(date, forKey: legacyDefaultsKey)
        }
    }
}
