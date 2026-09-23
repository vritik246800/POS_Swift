import Foundation
internal import Combine

class ProductViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var searchResults: [Product] = []
    @Published var searchQuery: String = ""
    @Published var errorMessage: String = ""

    private let db = DatabaseManager.shared

    // Stock baixo: <= 10
    var lowStockProducts: [Product] {
        products.filter { $0.stock <= 10 }
    }

    // MARK: - Carregar produtos
    func loadProducts() {
        products = db.fetchProducts()
    }

    // MARK: - Pesquisar (nome OU código de barras)
    func search() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        searchResults = db.searchProducts(query: searchQuery)
    }

    // MARK: - Criar produto
    @discardableResult
    func createProduct(name: String, barcode: String, priceBase: Double, ivaRate: Double, profitMargin: Double, stock: Int,
                       categoryId: Int? = nil, expiryDate: Date? = nil) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "O nome não pode estar vazio."
            return false
        }
        guard priceBase > 0 else {
            errorMessage = "O preço base tem de ser maior que zero."
            return false
        }
        guard stock >= 0 else {
            errorMessage = "A quantidade não pode ser negativa."
            return false
        }
        guard ivaRate >= 0, profitMargin >= 0 else {
            errorMessage = "IVA e margem não podem ser negativos."
            return false
        }
        if let expiryDate, expiryDate < Calendar.current.startOfDay(for: Date()) {
            errorMessage = "A data de validade não pode estar no passado."
            return false
        }
        let ok = db.createProduct(name: name, barcode: barcode, priceBase: priceBase, ivaRate: ivaRate,
                                  profitMargin: profitMargin, stock: stock,
                                  categoryId: categoryId, expiryDate: expiryDate)
        if ok {
            errorMessage = ""
            loadProducts()
        } else {
            errorMessage = "Erro ao criar produto. O código de barras pode já existir."
        }
        return ok
    }

    // MARK: - Actualizar produto
    @discardableResult
    func updateProduct(_ product: Product) -> Bool {
        guard !product.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "O nome não pode estar vazio."
            return false
        }
        guard product.priceBase > 0 else {
            errorMessage = "O preço base tem de ser maior que zero."
            return false
        }
        let ok = db.updateProduct(product)
        if ok {
            errorMessage = ""
            loadProducts()
        } else {
            errorMessage = "Erro ao actualizar produto. Só um Administrador pode alterar preços, e o código de barras pode já estar em uso."
        }
        return ok
    }

    // MARK: - Promoção (desconto) de um produto a expirar
    /// `percent` em 0…90. Zero remove a promoção.
    @discardableResult
    func applyDiscount(productId: Int, percent: Double) -> Bool {
        guard percent >= 0, percent <= 90 else {
            errorMessage = "O desconto tem de estar entre 0% e 90%."
            return false
        }
        let ok = db.setProductDiscount(productId: productId, percent: percent)
        errorMessage = ok ? "" : "Só um Administrador pode aplicar promoções."
        loadProducts()
        return ok
    }

    // MARK: - Actualizar só o stock (uso interno: LowStockView)
    func updateStockOnly(productId: Int, newStock: Int) {
        guard newStock >= 0 else {
            errorMessage = "O stock não pode ser negativo."
            return
        }
        if db.updateStock(productId: productId, newStock: newStock) {
            errorMessage = ""
        } else {
            errorMessage = "Não foi possível actualizar o stock."
        }
        loadProducts()
    }

    // MARK: - Eliminar produto
    func deleteProduct(id: Int) {
        if db.deleteProduct(id: id) {
            errorMessage = ""
        } else {
            errorMessage = "Não foi possível eliminar o produto. Só um Administrador o pode fazer, e produtos já vendidos são preservados no histórico."
        }
        loadProducts()
    }

    // MARK: - Filtrar por categoria (nil = todos)
    func products(inCategory id: Int?) -> [Product] {
        guard let id else { return products }
        return products.filter { $0.categoryId == id }
    }

    // MARK: - Busca por barcode exacto (para uso no ponto de venda)
    func findByBarcode(_ barcode: String) -> Product? {
        db.fetchProductByBarcode(barcode)
    }
}
