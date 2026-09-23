import Foundation

/// Fonte única das faixas de validade. Sem SwiftUI — as cores vivem em `Utils/AppTheme.swift`.
enum ExpiryStatus: Int, CaseIterable {
    case expired, days, oneMonth, twoMonths, threeMonths, safe, none

    /// Faixa a partir dos dias que faltam:
    /// `< 0` expired · `0...30` days · `31...60` oneMonth · `61...90` twoMonths ·
    /// `91...120` threeMonths · `> 120` safe · sem data → none
    static func from(expiryDate: Date?, now: Date = Date()) -> ExpiryStatus {
        guard let expiryDate else { return .none }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expiryDate)
        ).day ?? 0

        switch days {
        case ..<0:      return .expired
        case 0...30:    return .days
        case 31...60:   return .oneMonth
        case 61...90:   return .twoMonths
        case 91...120:  return .threeMonths
        default:        return .safe
        }
    }

    var label: String {
        switch self {
        case .expired:      return "Já expirado"
        case .days:         return "Expira em dias"
        case .oneMonth:     return "Expira em 1 mês"
        case .twoMonths:    return "Expira em 2 meses"
        case .threeMonths:  return "Expira em 3 meses"
        case .safe:         return "Dentro do prazo"
        case .none:         return "Não expira"
        }
    }

    var icon: String {
        switch self {
        case .expired:      return "xmark.octagon.fill"
        case .days:         return "exclamationmark.triangle.fill"
        case .oneMonth:     return "clock.badge.exclamationmark.fill"
        case .twoMonths:    return "clock.fill"
        case .threeMonths:  return "calendar"
        case .safe:         return "checkmark.seal.fill"
        case .none:         return "infinity"
        }
    }

    /// Quanto maior, mais grave. Ordena as secções do alerta de arranque.
    var severity: Int {
        switch self {
        case .expired:      return 5
        case .days:         return 4
        case .oneMonth:     return 3
        case .twoMonths:    return 2
        case .threeMonths:  return 1
        case .safe, .none:  return 0
        }
    }

    /// Faixas que geram alerta (tudo menos `.safe` e `.none`).
    var isAlerting: Bool { severity > 0 }
}
