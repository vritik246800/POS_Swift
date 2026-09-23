import Foundation

enum UserRole: String, Codable {
    case admin = "admin"
    case cashier = "cashier"
}

struct User: Identifiable, Codable {
    let id: Int
    var name: String
    var username: String
    var passwordHash: String
    var role: UserRole
}
