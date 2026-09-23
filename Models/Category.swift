import Foundation

/// Categoria de produto. Sem SwiftUI — a cor derivada vive em `Utils/AppTheme.swift`.
struct Category: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var icon: String        // SF Symbol
    var colorHex: String    // ex: "5856D6"
    var sortOrder: Int
}
