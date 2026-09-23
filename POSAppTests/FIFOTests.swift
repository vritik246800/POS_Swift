import Foundation
import Testing
@testable import POSApp

@Suite("Consumo de stock por FIFO")
struct FIFOTests {

    private let db = DatabaseManager.shared

    private func asAdmin() {
        db.currentUser = User(id: -1, name: "Teste", username: "teste", passwordHash: "", role: .admin)
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    /// Produto novo sem stock — o teste cria os lotes que quer.
    private func makeProduct() throws -> Product {
        asAdmin()
        let barcode = "TST-\(UUID().uuidString.prefix(12))"
        #expect(db.createProduct(name: "Produto de teste FIFO", barcode: barcode,
                                 priceBase: 10, ivaRate: 16, profitMargin: 0, stock: 0))
        return try #require(db.fetchProductByBarcode(barcode))
    }

    @Test("Venda que atravessa dois lotes esvazia primeiro o mais antigo")
    func consumesAcrossTwoBatches() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 5, priceBase: 10, expiryDate: day(10)))
        #expect(db.createBatch(productId: product.id, quantity: 5, priceBase: 20, expiryDate: day(40)))
        #expect(db.createBatch(productId: product.id, quantity: 5, priceBase: 30, expiryDate: nil))
        #expect(db.availableStock(productId: product.id) == 15)
        #expect(db.fetchProduct(id: product.id)?.stock == 15)

        // 7 unidades: esgota o lote de 10 dias (5) e tira 2 ao de 40 dias.
        #expect(db.consumeStockFIFO(productId: product.id, quantity: 7))

        let batches = db.fetchBatches(productId: product.id)
        #expect(batches.count == 2)
        #expect(batches.contains { $0.expiryDate == nil && $0.quantity == 5 })
        #expect(batches.contains { $0.expiryDate != nil && $0.quantity == 3 })
        #expect(batches.contains { $0.priceBase == 10 } == false)   // lote mais antigo apagado
        #expect(db.availableStock(productId: product.id) == 8)
        #expect(db.fetchProduct(id: product.id)?.stock == 8)        // cache sincronizada
    }

    @Test("Lote sem validade fica para o fim")
    func nullExpiryLast() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 3, priceBase: 5, expiryDate: nil))
        #expect(db.createBatch(productId: product.id, quantity: 3, priceBase: 5, expiryDate: day(20)))

        #expect(db.consumeStockFIFO(productId: product.id, quantity: 3))
        let remaining = db.fetchBatches(productId: product.id)
        #expect(remaining.count == 1)
        #expect(remaining.first?.expiryDate == nil)
    }

    @Test("Stock insuficiente não consome nada (ROLLBACK)")
    func insufficientStockRollsBack() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 4, priceBase: 10, expiryDate: day(5)))
        #expect(db.consumeStockFIFO(productId: product.id, quantity: 9) == false)
        #expect(db.availableStock(productId: product.id) == 4)
    }

    @Test("updateStock ajusta lotes em vez de escrever Products.stock")
    func updateStockGoesThroughBatches() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 2, priceBase: 10, expiryDate: day(5)))

        // Aumento cria/alimenta o lote sem validade.
        #expect(db.updateStock(productId: product.id, newStock: 6))
        #expect(db.availableStock(productId: product.id) == 6)
        #expect(db.fetchBatches(productId: product.id).reduce(0) { $0 + $1.quantity } == 6)

        // Redução consome por FIFO.
        #expect(db.updateStock(productId: product.id, newStock: 3))
        #expect(db.availableStock(productId: product.id) == 3)
        #expect(db.fetchProduct(id: product.id)?.stock == 3)

        #expect(db.updateStock(productId: product.id, newStock: -1) == false)
    }

    @Test("Lote expirado não conta como stock vendável nem é consumido na venda")
    func expiredBatchIsNotSellable() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 4, priceBase: 10, expiryDate: day(-3)))
        #expect(db.createBatch(productId: product.id, quantity: 6, priceBase: 10, expiryDate: day(30)))

        #expect(db.availableStock(productId: product.id) == 10)
        #expect(db.sellableStock(productId: product.id) == 6)

        // A venda salta o lote expirado: consome do lote válido.
        #expect(db.consumeStockFIFO(productId: product.id, quantity: 6, excludeExpired: true))
        let batches = db.fetchBatches(productId: product.id)
        #expect(batches.count == 1)
        #expect(batches.first?.expiryStatus == .expired)
        #expect(db.sellableStock(productId: product.id) == 0)

        // Só sobra stock expirado — não há nada para vender.
        #expect(db.consumeStockFIFO(productId: product.id, quantity: 1, excludeExpired: true) == false)
    }

    @Test("Produto só com lotes expirados não entra no carrinho")
    func expiredProductBlockedInCart() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 5, priceBase: 10, expiryDate: day(-1)))

        let vm = SaleViewModel()
        vm.addToCart(product: try #require(db.fetchProduct(id: product.id)), quantity: 1)
        #expect(vm.cartItems.isEmpty)
        #expect(vm.errorMessage == "Produto expirado. Não pode ser vendido.")
    }

    @Test("Promoção aplica desconto ao preço do carrinho")
    func discountAppliedToCartPrice() throws {
        let product = try makeProduct()
        defer { _ = db.deleteProduct(id: product.id) }

        #expect(db.createBatch(productId: product.id, quantity: 5, priceBase: 10, expiryDate: day(10)))
        #expect(db.setProductDiscount(productId: product.id, percent: 25))

        let discounted = try #require(db.fetchProduct(id: product.id))
        #expect(discounted.discountPercent == 25)
        #expect(abs(discounted.priceWithDiscount - discounted.priceFinal * 0.75) < 0.0001)

        let vm = SaleViewModel()
        vm.addToCart(product: discounted, quantity: 2)
        #expect(vm.cartItems.first?.unitPrice == discounted.priceWithDiscount)
        #expect(abs(vm.cartTotal - discounted.priceWithDiscount * 2) < 0.0001)

        // Fora de gama é rejeitado.
        #expect(db.setProductDiscount(productId: product.id, percent: 95) == false)
    }
}
