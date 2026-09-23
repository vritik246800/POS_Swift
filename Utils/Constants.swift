import Foundation

enum Constants {
    static let defaultIVARate: Double = 16.0   // 16%
    static let dbName: String = "posapp.sqlite"

    /// Chave em `UserDefaults` com o nome do programa escolhido pelo utilizador.
    /// As Views usam `@AppStorage(Constants.appNameKey)` para refletir de imediato.
    static let appNameKey: String = "appName"
    static let defaultAppName: String = "POS App"
    static let appNameMaxLength: Int = 40

    /// Nome do programa — usado na UI, nos recibos, nos relatórios e nos fechos.
    /// Nunca devolve vazio: um valor inválido cai no `defaultAppName`.
    static var appName: String {
        get { sanitizedAppName(UserDefaults.standard.string(forKey: appNameKey) ?? "") }
        set { UserDefaults.standard.set(sanitizedAppName(newValue), forKey: appNameKey) }
    }

    /// Valida o nome introduzido: sem espaços nas pontas, sem quebras de linha,
    /// truncado ao limite. Vazio devolve o nome por omissão.
    static func sanitizedAppName(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return defaultAppName }
        return String(cleaned.prefix(appNameMaxLength))
    }

    /// Limites de comprimento das credenciais de login.
    /// Barreira contra entrada absurda antes de chegar à base de dados e ao KDF —
    /// um username de 10 MB não chega a ser consultado, uma password enorme não
    /// chega a pagar 210 000 iterações de PBKDF2.
    static let usernameMaxLength: Int = 64
    static let passwordMaxLength: Int = 128

    /// Versão da app lida do bundle — evita ter o número escrito à mão na UI.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Chave em `UserDefaults` com a data (`yyyy-MM-dd`) em que o alerta de validade foi dispensado.
    static let expiryAlertDismissedDateKey: String = "expiryAlertDismissedDate"

    /// Chave em `UserDefaults` com a data (`yyyy-MM-dd`) em que o alerta de
    /// produtos parados (sem venda há 6+ meses) foi dispensado.
    static let staleAlertDismissedDateKey: String = "staleAlertDismissedDate"

    /// Data de hoje em `yyyy-MM-dd` — formato usado nas chaves de dia.
    static func todayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - Formatação de valores monetários (locale do dispositivo)

/// Formata um valor monetário usando a moeda e locale do dispositivo.
/// Ex: Moçambique → "1 500,00 MT" | Portugal → "1.500,00 €" | EUA → "$1,500.00"
func formatCurrency(_ value: Double) -> String {
    let locale = Locale.current

    // Tenta usar o formatter de moeda nativo do locale
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale

    if let result = formatter.string(from: NSNumber(value: value)) {
        return result
    }

    // Fallback: decimal com 2 casas
    let symbol = locale.currencySymbol ?? locale.currency?.identifier ?? ""
    let decimalFormatter = NumberFormatter()
    decimalFormatter.numberStyle = .decimal
    decimalFormatter.minimumFractionDigits = 2
    decimalFormatter.maximumFractionDigits = 2
    decimalFormatter.locale = locale
    let num = decimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    return symbol.isEmpty ? num : "\(num) \(symbol)"
}

/// Compatibilidade com chamadas legadas — redireciona para formatCurrency
func formatMT(_ value: Double) -> String {
    formatCurrency(value)
}

/// Símbolo/código da moeda do locale atual (ex: "MT", "€", "$")
var currentCurrencySymbol: String {
    let locale = Locale.current
    return locale.currencySymbol ?? locale.currency?.identifier ?? ""
}
