import Foundation
internal import Combine

class SaleViewModel: ObservableObject {
    @Published var cartItems: [SaleItem] = []
    @Published var clientName: String = ""
    @Published var clientNIF: String = ""
    @Published var errorMessage: String = ""
    @Published var lastSaleId: Int? = nil
    @Published var salesHistory: [Sale] = []

    private let db = DatabaseManager.shared

    var cartTotal: Double {
        cartItems.reduce(0) { $0 + $1.subtotal }
    }

    // MARK: - Adicionar produto ao carrinho
    func addToCart(product: Product, quantity: Int) {
        guard quantity > 0 else {
            errorMessage = "A quantidade tem de ser maior que zero."
            return
        }
        // Stock vendável = lotes dentro do prazo. Lotes expirados não se vendem.
        let available = db.sellableStock(productId: product.id)
        guard available > 0 else {
            errorMessage = db.availableStock(productId: product.id) > 0
                ? "Produto expirado. Não pode ser vendido."
                : "Stock insuficiente. Disponível: 0"
            return
        }
        guard available >= quantity else {
            errorMessage = "Stock insuficiente. Disponível: \(available)"
            return
        }
        let unitPrice = product.priceWithDiscount
        if let index = cartItems.firstIndex(where: { $0.productId == product.id }) {
            let newQty = cartItems[index].quantity + quantity
            guard available >= newQty else {
                errorMessage = "Stock insuficiente para quantidade total."
                return
            }
            cartItems[index] = SaleItem(
                id: cartItems[index].id,
                saleId: 0,
                productId: product.id,
                productName: product.name,
                quantity: newQty,
                unitPrice: unitPrice,
                subtotal: unitPrice * Double(newQty)
            )
        } else {
            let item = SaleItem(
                id: cartItems.count,
                saleId: 0,
                productId: product.id,
                productName: product.name,
                quantity: quantity,
                unitPrice: unitPrice,
                subtotal: unitPrice * Double(quantity)
            )
            cartItems.append(item)
        }
        errorMessage = ""
    }

    // MARK: - Alterar quantidade de um item já no carrinho
    /// Usado pelos botões −/+ do painel do carrinho.
    /// `newQuantity <= 0` remove a linha. Nunca ultrapassa o stock dos lotes.
    func updateQuantity(productId: Int, newQuantity: Int) {
        guard let index = cartItems.firstIndex(where: { $0.productId == productId }) else { return }

        guard newQuantity > 0 else {
            removeFromCart(productId: productId)
            errorMessage = ""
            return
        }

        let available = db.sellableStock(productId: productId)
        guard available >= newQuantity else {
            errorMessage = "Stock insuficiente. Disponível: \(available)"
            return
        }

        let item = cartItems[index]
        cartItems[index] = SaleItem(
            id: item.id,
            saleId: item.saleId,
            productId: item.productId,
            productName: item.productName,
            quantity: newQuantity,
            unitPrice: item.unitPrice,
            subtotal: item.unitPrice * Double(newQuantity)
        )
        errorMessage = ""
    }

    // MARK: - Remover item do carrinho
    func removeFromCart(productId: Int) {
        cartItems.removeAll { $0.productId == productId }
    }

    // MARK: - Finalizar venda COM pagamentos (novo método principal)
    func finalizeSaleWithPayments(userId: Int, payments: [Payment]) -> Bool {
        guard !cartItems.isEmpty else {
            errorMessage = "Carrinho vazio."
            return false
        }
        // Sales + SaleItems + consumo FIFO dos lotes + Payments numa só transação.
        // Se qualquer passo falhar (incluindo stock insuficiente), faz ROLLBACK.
        guard let saleId = db.createSaleAtomic(
            userId: userId,
            clientName: clientName,
            clientNIF: clientNIF,
            items: cartItems,
            total: cartTotal,
            payments: payments
        ) else {
            errorMessage = "Erro ao finalizar venda. Verifique o stock disponível."
            return false
        }

        lastSaleId = saleId
        clearCart()
        loadSalesHistory()
        return true
    }

    // MARK: - Finalizar venda (legado — mantido para compatibilidade)
    func finalizeSale(userId: Int) -> Bool {
        guard !cartItems.isEmpty else {
            errorMessage = "Carrinho vazio."
            return false
        }
        let saleId = db.createSale(
            userId: userId,
            clientName: clientName,
            clientNIF: clientNIF,
            items: cartItems,
            total: cartTotal
        )
        if let id = saleId {
            lastSaleId = id
            clearCart()
            loadSalesHistory()
            return true
        } else {
            errorMessage = "Erro ao finalizar venda."
            return false
        }
    }

    // MARK: - Limpar carrinho
    func clearCart() {
        cartItems = []
        clientName = ""
        clientNIF = ""
        errorMessage = ""
    }

    // MARK: - Histórico de vendas
    func loadSalesHistory() {
        salesHistory = db.fetchSales()
    }

    func salesForDay(_ date: String) -> [Sale] {
        return db.fetchSalesByDate(date: date)
    }

    func salesForMonth(_ yearMonth: String) -> [Sale] {
        return db.fetchSalesByMonth(yearMonth: yearMonth)
    }

    func totalFor(sales: [Sale]) -> Double {
        sales.reduce(0) { $0 + $1.total }
    }
}
