import Foundation
internal import Combine

// MARK: - Risco de validade por produto

/// Um produto com lotes em alerta de validade — alimenta o painel lateral
/// de "Em risco" na lista de Produtos.
struct ProductRiskEntry: Identifiable {
    var id: Int { productId }
    let productId: Int
    let name: String
    /// Lotes em alerta, do que expira mais cedo para o mais tarde.
    let batches: [Batch]

    var totalQuantity: Int { batches.reduce(0) { $0 + $1.quantity } }
    var totalValue: Double { batches.reduce(0) { $0 + $1.lostValue } }

    /// Faixa mais grave entre os lotes — dá a cor e o ícone da linha.
    var worstStatus: ExpiryStatus {
        batches.map(\.expiryStatus).max { $0.severity < $1.severity } ?? .none
    }
}

class BatchViewModel: ObservableObject {
    @Published var batches: [Batch] = []
    @Published var errorMessage: String = ""

    private let db = DatabaseManager.shared

    func loadBatches() {
        batches = db.fetchAllBatches()
    }

    func batches(for productId: Int) -> [Batch] {
        batches.filter { $0.productId == productId }
    }

    /// Lotes agrupados por faixa de validade — alimenta o alerta de arranque.
    var expiringGroups: [ExpiryStatus: [Batch]] {
        Dictionary(grouping: batches.filter { $0.expiryStatus.isAlerting }, by: \.expiryStatus)
    }

    /// Perda real: valor dos lotes já expirados.
    var realLoss: Double {
        batches.filter { $0.expiryStatus == .expired }.reduce(0) { $0 + $1.lostValue }
    }

    /// Em risco: valor dos lotes a expirar (ainda não expirados).
    var riskValue: Double {
        batches.filter { $0.expiryStatus.isAlerting && $0.expiryStatus != .expired }
            .reduce(0) { $0 + $1.lostValue }
    }

    /// Valor em risco por faixa.
    var riskBreakdown: [ExpiryStatus: Double] {
        expiringGroups
            .filter { $0.key != .expired }
            .mapValues { $0.reduce(0) { $0 + $1.lostValue } }
    }

    // MARK: - Risco por produto (painel lateral em Produtos)

    /// Produtos com lotes a expirar **ainda dentro do prazo** — os já expirados
    /// pertencem só a `lossEntries`, para os dois painéis não repetirem o mesmo lote.
    /// Ordenado do produto com mais valor em risco para o que tem menos.
    func riskEntries(products: [Product]) -> [ProductRiskEntry] {
        entries(products: products) { $0.expiryStatus.isAlerting && $0.expiryStatus != .expired }
    }

    /// Produtos com lotes já expirados — alimenta o painel de "Perda real".
    func lossEntries(products: [Product]) -> [ProductRiskEntry] {
        entries(products: products) { $0.expiryStatus == .expired }
    }

    /// Agrupamento por produto dos lotes que passam no filtro. Ordenado do
    /// produto com mais valor para o que tem menos.
    func entries(products: [Product], where include: (Batch) -> Bool) -> [ProductRiskEntry] {
        return Dictionary(grouping: batches.filter(include), by: \.productId)
            .map { productId, group in
                ProductRiskEntry(
                    productId: productId,
                    name: products.first { $0.id == productId }?.name ?? "Produto #\(productId)",
                    batches: group.sorted {
                        ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture)
                    }
                )
            }
            .sorted {
                if $0.totalValue != $1.totalValue { return $0.totalValue > $1.totalValue }
                return $0.name < $1.name
            }
    }

    /// Valor total em risco/perdido de todos os produtos em alerta.
    func riskEntriesTotal(products: [Product]) -> Double {
        riskEntries(products: products).reduce(0) { $0 + $1.totalValue }
    }

    /// Faixa de validade mais grave entre os lotes de um produto.
    /// `nil` quando nenhum lote está em alerta — a lista não mostra badge.
    func worstStatus(productId: Int) -> ExpiryStatus? {
        batches
            .filter { $0.productId == productId && $0.expiryStatus.isAlerting }
            .map(\.expiryStatus)
            .max { $0.severity < $1.severity }
    }

    // MARK: - CRUD

    @discardableResult
    func create(productId: Int, quantity: Int, priceBase: Double, expiryDate: Date?) -> Bool {
        guard quantity > 0 else {
            errorMessage = "A quantidade tem de ser maior que zero."
            return false
        }
        guard priceBase >= 0 else {
            errorMessage = "O preço base não pode ser negativo."
            return false
        }
        if let expiryDate, expiryDate < Calendar.current.startOfDay(for: Date()) {
            errorMessage = "A data de validade não pode estar no passado."
            return false
        }
        let ok = db.createBatch(productId: productId, quantity: quantity, priceBase: priceBase, expiryDate: expiryDate)
        finish(ok, failure: "Erro ao criar o lote.")
        return ok
    }

    @discardableResult
    func update(_ batch: Batch) -> Bool {
        guard batch.quantity >= 0 else {
            errorMessage = "A quantidade não pode ser negativa."
            return false
        }
        let ok = db.updateBatch(batch)
        finish(ok, failure: "Erro ao actualizar o lote.")
        return ok
    }

    @discardableResult
    func delete(id: Int) -> Bool {
        let ok = db.deleteBatch(id: id)
        finish(ok, failure: "Erro ao apagar o lote.")
        return ok
    }

    private func finish(_ ok: Bool, failure: String) {
        errorMessage = ok ? "" : failure
        loadBatches()
    }

    // MARK: - Alerta de arranque (1.4)

    /// Mostra o alerta se houver lotes fora de `.safe`/`.none` e ainda não tiver sido dispensado hoje.
    func shouldShowExpiryAlert() -> Bool {
        guard batches.contains(where: { $0.expiryStatus.isAlerting }) else { return false }
        return UserDefaults.standard.string(forKey: Constants.expiryAlertDismissedDateKey) != Constants.todayKey()
    }

    func dismissExpiryAlertToday() {
        UserDefaults.standard.set(Constants.todayKey(), forKey: Constants.expiryAlertDismissedDateKey)
    }
}
