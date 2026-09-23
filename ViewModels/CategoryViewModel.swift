import Foundation
internal import Combine

class CategoryViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var errorMessage: String = ""

    private let db = DatabaseManager.shared

    func loadCategories() {
        categories = db.fetchCategories()
    }

    /// `nil` = "Sem categoria".
    func category(for id: Int?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// Quantos produtos ficam sem categoria se esta for apagada.
    func productCount(inCategory id: Int) -> Int {
        db.productCount(inCategory: id)
    }

    @discardableResult
    func create(name: String, icon: String, colorHex: String) -> Bool {
        guard validate(name: name, colorHex: colorHex) else { return false }
        let ok = db.createCategory(name: name.trimmingCharacters(in: .whitespaces),
                                   icon: icon, colorHex: colorHex,
                                   sortOrder: categories.count)
        if ok {
            errorMessage = ""
            loadCategories()
        } else {
            errorMessage = "Erro ao criar categoria. Já existe uma com esse nome."
        }
        return ok
    }

    @discardableResult
    func update(_ category: Category) -> Bool {
        guard validate(name: category.name, colorHex: category.colorHex) else { return false }
        let ok = db.updateCategory(category)
        if ok {
            errorMessage = ""
            loadCategories()
        } else {
            errorMessage = "Erro ao actualizar categoria. Já existe uma com esse nome."
        }
        return ok
    }

    @discardableResult
    func delete(id: Int) -> Bool {
        let ok = db.deleteCategory(id: id)
        if ok {
            errorMessage = ""
            loadCategories()
        } else {
            errorMessage = "Erro ao apagar categoria."
        }
        return ok
    }

    /// Reordena por arrastar. Renumera `sortOrder` pela posição e persiste.
    @discardableResult
    func move(from source: IndexSet, to destination: Int) -> Bool {
        let reordered = Self.reordering(categories, from: source, to: destination)
        guard db.reorderCategories(reordered.map(\.id)) else {
            errorMessage = "Erro ao reordenar categorias."
            return false
        }
        errorMessage = ""
        categories = reordered
        return true
    }

    /// Move `source` para `destination` (semântica do `onMove` do SwiftUI) e renumera
    /// `sortOrder` pela posição. Sem SwiftUI aqui — fica testável sem UI nem base de dados.
    static func reordering(_ list: [Category], from source: IndexSet, to destination: Int) -> [Category] {
        let moved = source.sorted().map { list[$0] }
        var result = list
        for index in source.sorted(by: >) { result.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moved, at: insertAt)
        return result.enumerated().map { index, category in
            var copy = category
            copy.sortOrder = index
            return copy
        }
    }

    private func validate(name: String, colorHex: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "O nome da categoria não pode estar vazio."
            return false
        }
        guard colorHex.count == 6, colorHex.allSatisfy(\.isHexDigit) else {
            errorMessage = "Cor inválida."
            return false
        }
        return true
    }
}
