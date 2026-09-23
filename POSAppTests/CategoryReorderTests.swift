import Foundation
import Testing
@testable import POSApp

@Suite("Reordenação de categorias")
struct CategoryReorderTests {

    private static func category(_ id: Int, order: Int) -> POSApp.Category {
        POSApp.Category(id: id, name: "C\(id)", icon: "tag", colorHex: "5856D6", sortOrder: order)
    }

    private var list: [POSApp.Category] {
        [Self.category(1, order: 0), Self.category(2, order: 1), Self.category(3, order: 2)]
    }

    @Test("Última para o topo")
    func moveToTop() {
        let result = CategoryViewModel.reordering(list, from: IndexSet(integer: 2), to: 0)
        #expect(result.map(\.id) == [3, 1, 2])
        #expect(result.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("Primeira para o fim (destino é o índice antes da remoção)")
    func moveToBottom() {
        let result = CategoryViewModel.reordering(list, from: IndexSet(integer: 0), to: 3)
        #expect(result.map(\.id) == [2, 3, 1])
        #expect(result.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("Mover para a própria posição não muda nada")
    func noOp() {
        let result = CategoryViewModel.reordering(list, from: IndexSet(integer: 1), to: 1)
        #expect(result.map(\.id) == [1, 2, 3])
    }
}
