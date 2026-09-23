import Foundation
internal import Combine

// MARK: - Modelos de apoio da área de Administração

/// Um ponto da série diária do dashboard.
struct DailyRevenuePoint: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    let revenue: Double
    let sales: Int
}

/// Série de receita do dashboard: pontos já com os intervalos vazios e a unidade de tempo
/// que o gráfico usa no eixo X.
struct RevenueSeries {
    let points: [DailyRevenuePoint]
    let unit: Calendar.Component

    var total: Double { points.reduce(0) { $0 + $1.revenue } }
    var isEmpty: Bool { points.allSatisfy { $0.revenue == 0 } }

    /// Título do painel, à medida da granularidade.
    var title: String {
        switch unit {
        case .hour:  return "Receita por hora"
        case .day:   return "Receita por dia"
        case .month: return "Receita por mês"
        default:     return "Receita"
        }
    }
}

/// Uma linha do top de produtos.
/// Uma caixa no período: quantas vendas fez e quanto valem.
struct CashierPerformance: Identifiable {
    let userId: Int
    let name: String
    let numSales: Int
    let total: Double

    var id: Int { userId }
}

struct ProductRanking: Identifiable, Hashable {
    var id: Int { productId }
    let productId: Int
    let name: String
    let quantity: Int
    let revenue: Double
}

/// Receita agregada por categoria.
struct CategoryRevenue: Identifiable, Hashable {
    var id: Int { categoryId ?? -1 }
    let categoryId: Int?
    let name: String
    let revenue: Double
}

/// Produto sem vendas há muito tempo — candidato a promoção.
struct StaleProduct: Identifiable {
    var id: Int { product.id }
    let product: Product
    /// `nil` = nunca foi vendido.
    let lastSale: Date?
    /// Lotes ainda com stock parado.
    let batches: [Batch]

    var stock: Int { batches.reduce(0) { $0 + $1.quantity } }
    /// Capital imobilizado, ao preço base pago em cada lote.
    var tiedValue: Double { batches.reduce(0) { $0 + $1.lostValue } }

    var daysIdle: Int {
        guard let lastSale else { return Int.max }
        return Calendar.current.dateComponents([.day], from: lastSale, to: Date()).day ?? 0
    }

    var idleLabel: String {
        guard lastSale != nil else { return "Nunca vendido" }
        let months = daysIdle / 30
        return "Sem venda há \(months) mês(es)"
    }
}

/// Estado da caixa de um utilizador num dia.
struct CashierDayStatus: Identifiable {
    var id: Int { user.id }
    let user: User
    let sales: [Sale]
    let payments: [Payment]
    /// `nil` = caixa ainda por fechar.
    let close: CashierClose?

    var total: Double { sales.reduce(0) { $0 + $1.total } }
    var numSales: Int { sales.count }
    var isClosed: Bool { close != nil }

    func amount(for method: PaymentMethod) -> Double {
        payments.filter { $0.method == method }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - ViewModel

/// Dados da área de Administração: dashboard, produtos parados e fecho por caixa.
///
/// ponytail: agrega em Swift a partir dos fetch que já existem em vez de SQL de
/// agregação novo — à escala de uma loja é irrelevante. Se o histórico crescer
/// ao ponto de o dashboard demorar, passar as somas para `GROUP BY` no SQLite.
class AdminViewModel: ObservableObject {
    @Published var sales: [Sale] = []
    @Published var payments: [Payment] = []
    @Published var products: [Product] = []
    @Published var categories: [Category] = []
    @Published var batches: [Batch] = []
    @Published var lastSales: [Int: Date] = [:]
    @Published var users: [User] = []
    @Published var errorMessage: String = ""

    private let db = DatabaseManager.shared
    private let calendar = Calendar.current

    // MARK: - Carregar

    func load() {
        sales = db.fetchSales().filter { $0.status == .completed }
        products = db.fetchProducts()
        categories = db.fetchCategories()
        batches = db.fetchAllBatches()
        lastSales = db.lastSaleDates()
        users = db.fetchUsers()
        payments = sales.flatMap { db.fetchPayments(saleId: $0.id) }
    }

    // MARK: - Períodos

    enum Period: String, CaseIterable, Identifiable {
        case today = "Hoje"
        case month = "Mês"
        case year = "Ano"
        case all = "Total"

        var id: String { rawValue }
    }

    /// Filtro por partes de data, usado só no período `Total`.
    /// `nil` em cada campo = sem restrição nessa parte.
    struct DateFilter: Equatable {
        var year: Int?
        var month: Int?
        var day: Int?

        var isEmpty: Bool { year == nil && month == nil && day == nil }
    }

    @Published var filter = DateFilter()

    /// `Hoje`, `Mês` e `Ano` são sempre relativos à data de hoje — `isDate(equalTo:toGranularity:)`
    /// compara também as unidades maiores, por isso `Mês` é o mês do ano actual e nunca o mesmo
    /// mês de outros anos. `Total` é o histórico todo, estreitado pelo `filter`.
    func sales(in period: Period) -> [Sale] {
        let now = Date()
        switch period {
        case .today: return sales.filter { calendar.isDate($0.date, inSameDayAs: now) }
        case .month: return sales.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        case .year:  return sales.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .year) }
        case .all:   return Self.apply(filter, to: sales, calendar: calendar)
        }
    }

    /// Regra do filtro isolada da base de dados para ser testável.
    static func apply(_ filter: DateFilter, to sales: [Sale], calendar: Calendar) -> [Sale] {
        guard !filter.isEmpty else { return sales }
        return sales.filter { sale in
            let parts = calendar.dateComponents([.year, .month, .day], from: sale.date)
            if let year = filter.year, parts.year != year { return false }
            if let month = filter.month, parts.month != month { return false }
            if let day = filter.day, parts.day != day { return false }
            return true
        }
    }

    /// Anos com vendas, do mais recente para o mais antigo.
    var availableYears: [Int] {
        Set(sales.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    /// Dias válidos do mês escolhido (28/29/30/31), para o picker de dia não oferecer 31 de Fevereiro.
    var daysInSelectedMonth: [Int] {
        guard let year = filter.year, let month = filter.month,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return Array(range)
    }

    // MARK: - KPIs

    func revenue(in period: Period) -> Double {
        sales(in: period).reduce(0) { $0 + $1.total }
    }

    func salesCount(in period: Period) -> Int {
        sales(in: period).count
    }

    func averageTicket(in period: Period) -> Double {
        let list = sales(in: period)
        guard !list.isEmpty else { return 0 }
        return list.reduce(0) { $0 + $1.total } / Double(list.count)
    }

    func itemsSold(in period: Period) -> Int {
        sales(in: period).flatMap(\.items).reduce(0) { $0 + $1.quantity }
    }

    /// Valor total do stock em mão, ao preço base pago em cada lote.
    var stockValue: Double {
        batches.reduce(0) { $0 + $1.lostValue }
    }

    // MARK: - Séries e distribuições

    /// Série de receita do período escolhido, com os intervalos sem vendas incluídos a zero.
    /// A granularidade acompanha o período: horas num dia, dias num mês, meses num ano ou no total.
    func revenueSeries(in period: Period) -> RevenueSeries {
        let list = sales(in: period)
        let unit = seriesUnit(for: period)
        guard let bounds = seriesBounds(for: period, sales: list, unit: unit) else {
            return RevenueSeries(points: [], unit: unit)
        }

        let grouped = Dictionary(grouping: list) { bucket($0.date, unit: unit) }
        var points: [DailyRevenuePoint] = []
        var cursor = bounds.start
        while cursor <= bounds.end {
            let group = grouped[cursor] ?? []
            points.append(DailyRevenuePoint(day: cursor,
                                            revenue: group.reduce(0) { $0 + $1.total },
                                            sales: group.count))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        return RevenueSeries(points: points, unit: unit)
    }

    /// Granularidade da série: a unidade imediatamente abaixo do intervalo escolhido.
    func seriesUnit(for period: Period) -> Calendar.Component {
        switch period {
        case .today: return .hour
        case .month: return .day
        case .year:  return .month
        case .all:
            if filter.day != nil { return .hour }
            if filter.month != nil { return .day }
            return .month
        }
    }

    private func bucket(_ date: Date, unit: Calendar.Component) -> Date {
        calendar.dateInterval(of: unit, for: date)?.start ?? date
    }

    /// Limites da série. Com intervalo conhecido (dia/mês/ano), abre o intervalo todo mesmo
    /// sem vendas; no `Total` sem filtro, vai da primeira à última venda.
    private func seriesBounds(for period: Period, sales list: [Sale], unit: Calendar.Component) -> (start: Date, end: Date)? {
        let enclosing: DateInterval? = {
            switch period {
            case .today: return calendar.dateInterval(of: .day, for: Date())
            case .month: return calendar.dateInterval(of: .month, for: Date())
            case .year:  return calendar.dateInterval(of: .year, for: Date())
            case .all:
                guard let anchor = filterAnchor else { return nil }
                if filter.day != nil { return calendar.dateInterval(of: .day, for: anchor) }
                if filter.month != nil { return calendar.dateInterval(of: .month, for: anchor) }
                return calendar.dateInterval(of: .year, for: anchor)
            }
        }()

        if let enclosing {
            let end = calendar.date(byAdding: .second, value: -1, to: enclosing.end) ?? enclosing.end
            return (enclosing.start, end)
        }

        let dates = list.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return (bucket(first, unit: unit), bucket(last, unit: unit))
    }

    /// Data que representa o filtro do `Total` (1 de Janeiro quando só há ano, etc.).
    private var filterAnchor: Date? {
        guard let year = filter.year else { return nil }
        return calendar.date(from: DateComponents(year: year,
                                                  month: filter.month ?? 1,
                                                  day: filter.day ?? 1))
    }

    /// Intervalo em texto, para os subtítulos dos painéis.
    func periodLabel(_ period: Period) -> String {
        let now = Date()
        switch period {
        case .today: return "Hoje · " + now.formatted(.dateTime.day().month(.wide).year())
        case .month: return now.formatted(.dateTime.month(.wide).year())
        case .year:  return String(calendar.component(.year, from: now))
        case .all:
            guard let anchor = filterAnchor else { return "Total" }
            if filter.day != nil { return anchor.formatted(.dateTime.day().month(.wide).year()) }
            if filter.month != nil { return anchor.formatted(.dateTime.month(.wide).year()) }
            return String(filter.year ?? calendar.component(.year, from: anchor))
        }
    }

    /// Total recebido por método de pagamento no período.
    func paymentMix(in period: Period) -> [(method: PaymentMethod, total: Double)] {
        let ids = Set(sales(in: period).map(\.id))
        let relevant = payments.filter { ids.contains($0.saleId) }
        return PaymentMethod.allCases.map { method in
            (method, relevant.filter { $0.method == method }.reduce(0) { $0 + $1.amount })
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
    }

    /// Produtos mais vendidos no período, por receita.
    func topProducts(in period: Period, limit: Int = 5) -> [ProductRanking] {
        let items = sales(in: period).flatMap(\.items)
        return Dictionary(grouping: items, by: \.productId)
            .map { productId, group in
                ProductRanking(
                    productId: productId,
                    name: group.first?.productName ?? "Produto #\(productId)",
                    quantity: group.reduce(0) { $0 + $1.quantity },
                    revenue: group.reduce(0) { $0 + $1.subtotal }
                )
            }
            .sorted { $0.revenue > $1.revenue }
            .prefix(limit)
            .map { $0 }
    }

    /// Receita por categoria no período (produtos apagados caem em "Sem categoria").
    func revenueByCategory(in period: Period) -> [CategoryRevenue] {
        var categoryOf: [Int: Int?] = [:]
        for product in products { categoryOf[product.id] = product.categoryId }

        var totals: [Int?: Double] = [:]
        for item in sales(in: period).flatMap(\.items) {
            let key: Int? = categoryOf[item.productId] ?? nil
            totals[key, default: 0] += item.subtotal
        }

        var result: [CategoryRevenue] = []
        for (categoryId, revenue) in totals where revenue > 0 {
            let name = categories.first { $0.id == categoryId }?.name ?? "Sem categoria"
            result.append(CategoryRevenue(categoryId: categoryId, name: name, revenue: revenue))
        }
        return result.sorted { $0.revenue > $1.revenue }
    }

    // MARK: - Produtos parados

    /// Produtos com stock que não vendem há mais de `months` meses — inclui os que
    /// nunca foram vendidos. Ordenado pelo capital imobilizado, do maior para o menor.
    func staleProducts(months: Int = 6) -> [StaleProduct] {
        guard let limit = calendar.date(byAdding: .month, value: -months, to: Date()) else { return [] }
        return products.compactMap { product in
            let stock = batches.filter { $0.productId == product.id && $0.quantity > 0 }
            guard !stock.isEmpty else { return nil }
            let last = lastSales[product.id]
            guard Self.isStale(lastSale: last, limit: limit) else { return nil }
            return StaleProduct(product: product, lastSale: last,
                                batches: stock.sorted { $0.receivedAt < $1.receivedAt })
        }
        .sorted { $0.tiedValue > $1.tiedValue }
    }

    /// Regra dos meses parados, isolada da base de dados para ser testável.
    /// Nunca vendido conta como parado.
    static func isStale(lastSale: Date?, limit: Date) -> Bool {
        guard let lastSale else { return true }
        return lastSale < limit
    }

    // MARK: - Validade (movido dos painéis da lista de Produtos)

    var expiredBatches: [Batch] { batches.filter { $0.expiryStatus == .expired } }

    var riskBatches: [Batch] {
        batches.filter { $0.expiryStatus.isAlerting && $0.expiryStatus != .expired }
    }

    var realLoss: Double { expiredBatches.reduce(0) { $0 + $1.lostValue } }
    var riskValue: Double { riskBatches.reduce(0) { $0 + $1.lostValue } }

    var lowStockProducts: [Product] { products.filter { $0.stock <= 10 } }

    /// Produtos com lotes a expirar (ainda dentro do prazo).
    var riskEntries: [ProductRiskEntry] { entries(from: riskBatches) }

    /// Produtos com lotes já expirados.
    var lossEntries: [ProductRiskEntry] { entries(from: expiredBatches) }

    /// Valor em risco por faixa de validade, da mais grave para a menos grave.
    var riskBreakdown: [(status: ExpiryStatus, total: Double)] {
        Dictionary(grouping: riskBatches, by: \.expiryStatus)
            .map { (status: $0.key, total: $0.value.reduce(0) { $0 + $1.lostValue }) }
            .sorted { $0.status.severity > $1.status.severity }
    }

    private func entries(from list: [Batch]) -> [ProductRiskEntry] {
        Dictionary(grouping: list, by: \.productId)
            .map { productId, group in
                ProductRiskEntry(
                    productId: productId,
                    name: productName(productId),
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

    func productName(_ id: Int) -> String {
        products.first { $0.id == id }?.name ?? "Produto #\(id)"
    }

    // MARK: - Vendas por caixa

    /// Nº de vendas e valor por utilizador no período, do maior total para o menor.
    func cashierPerformance(in period: Period) -> [CashierPerformance] {
        Self.cashierPerformance(sales: sales(in: period), users: users)
    }

    /// Agregação pura — sem base de dados, para poder ser testada directamente.
    /// Venda de um utilizador que já não existe conta na mesma, com nome de recurso:
    /// o total do painel tem de bater certo com a receita do período.
    static func cashierPerformance(sales list: [Sale], users: [User]) -> [CashierPerformance] {
        let names = Dictionary(users.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        return Dictionary(grouping: list, by: \.userId)
            .map { userId, userSales in
                CashierPerformance(
                    userId: userId,
                    name: names[userId] ?? "Utilizador #\(userId)",
                    numSales: userSales.count,
                    total: userSales.reduce(0) { $0 + $1.total }
                )
            }
            .sorted { $0.total == $1.total ? $0.userId < $1.userId : $0.total > $1.total }
    }

    // MARK: - Fecho por caixa

    /// Estado da caixa de cada utilizador numa data. Aparecem todos os utilizadores
    /// com vendas nesse dia mais todos os Caixa (mesmo sem vendas, para se ver que estão a zero).
    func cashierStatuses(date: Date) -> [CashierDayStatus] {
        let key = Constants.todayKey(date)
        let daySales = sales.filter { Constants.todayKey($0.date) == key }
        let closes = db.fetchCashierCloses(date: key)
        let users = db.fetchUsers()
        let salesByUser = Dictionary(grouping: daySales, by: \.userId)
        let relevant = users.filter { $0.role == .cashier || salesByUser[$0.id] != nil }

        return relevant.map { user in
            let userSales = salesByUser[user.id] ?? []
            let ids = Set(userSales.map(\.id))
            return CashierDayStatus(
                user: user,
                sales: userSales,
                payments: payments.filter { ids.contains($0.saleId) },
                close: closes.first { $0.userId == user.id }
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// Fecha a caixa de um utilizador na data indicada.
    @discardableResult
    func closeCashier(_ status: CashierDayStatus, date: Date, notes: String = "") -> Bool {
        let ok = db.saveCashierClose(
            date: Constants.todayKey(date),
            userId: status.user.id,
            totalSales: status.total,
            cash: status.amount(for: .cash),
            card: status.amount(for: .card),
            bankTransfer: status.amount(for: .bankTransfer),
            mpesa: status.amount(for: .mpesa),
            emola: status.amount(for: .emola),
            numSales: status.numSales,
            notes: notes
        )
        errorMessage = ok ? "" : "Não foi possível fechar esta caixa."
        objectWillChange.send()
        return ok
    }

    @discardableResult
    func reopenCashier(_ status: CashierDayStatus, date: Date) -> Bool {
        let ok = db.reopenCashierClose(date: Constants.todayKey(date), userId: status.user.id)
        errorMessage = ok ? "" : "Só um Administrador pode reabrir uma caixa."
        objectWillChange.send()
        return ok
    }

    // MARK: - Edição a partir da Administração (validade e stock)

    /// Corrige um lote (quantidade e/ou data de validade) a partir do painel de
    /// validade. Validação aqui, SQL preparado no `DatabaseManager`.
    @discardableResult
    func updateBatch(_ batch: Batch) -> Bool {
        guard batch.quantity >= 0 else {
            errorMessage = "A quantidade não pode ser negativa."
            return false
        }
        guard batch.priceBase >= 0 else {
            errorMessage = "O preço base não pode ser negativo."
            return false
        }
        let ok = db.updateBatch(batch)
        errorMessage = ok ? "" : "Não foi possível actualizar o lote."
        if ok { load() }
        return ok
    }

    /// Repõe o stock de um produto (distribuído pelos lotes) a partir do painel
    /// de stock baixo.
    @discardableResult
    func updateStock(productId: Int, newStock: Int) -> Bool {
        guard newStock >= 0 else {
            errorMessage = "O stock não pode ser negativo."
            return false
        }
        let ok = db.updateStock(productId: productId, newStock: newStock)
        errorMessage = ok ? "" : "Não foi possível actualizar o stock."
        if ok { load() }
        return ok
    }

    // MARK: - Promoção a partir da Administração

    @discardableResult
    func applyDiscount(productId: Int, percent: Double) -> Bool {
        guard percent >= 0, percent <= 90 else {
            errorMessage = "O desconto tem de estar entre 0% e 90%."
            return false
        }
        let ok = db.setProductDiscount(productId: productId, percent: percent)
        errorMessage = ok ? "" : "Só um Administrador pode aplicar promoções."
        products = db.fetchProducts()
        return ok
    }
}
