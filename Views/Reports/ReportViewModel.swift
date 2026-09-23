import Foundation
internal import Combine

// MARK: - Entrada do ranking de produtos vendidos

/// Uma linha do "top de produtos": nome, quantidade vendida e valor facturado.
/// O nome do produto é a chave — vendas antigas guardam o nome, não o `productId`.
struct TopProductEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let quantity: Int
    let total: Double
}

class ReportViewModel: ObservableObject {
    @Published var dailySales: [Sale] = []
    @Published var monthlySales: [Sale] = []
    @Published var annualSales: [Sale] = []
    @Published var selectedDate: Date = Date()
    @Published var selectedMonth: Date = Date()
    @Published var selectedYear: Date = Date()
    @Published var exportedURL: URL? = nil
    @Published var showExportConfirmation: Bool = false

    private let db = DatabaseManager.shared
    private let service = ReportService()

    // MARK: - Carregar vendas do dia
    func loadDailySales(date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        dailySales = db.fetchSalesByDate(date: formatter.string(from: date))
    }

    // MARK: - Carregar vendas do mês
    func loadMonthlySales(date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        monthlySales = db.fetchSalesByMonth(yearMonth: formatter.string(from: date))
    }

    // MARK: - Carregar vendas do ano
    func loadAnnualSales(date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        annualSales = db.fetchSalesByYear(year: formatter.string(from: date))
    }

    // MARK: - Export diário
    func exportDailyCSV(date: Date) {
        exportedURL = service.exportDailyCSV(sales: dailySales, date: date)
    }

    func exportDailyPDF(date: Date) {
        Task { @MainActor in
            exportedURL = await service.exportDailyPDF(sales: dailySales, date: date)
        }
    }

    // MARK: - Export mensal
    func exportMonthlyCSV(date: Date) {
        exportedURL = service.exportMonthlyCSV(sales: monthlySales, date: date)
    }

    func exportMonthlyPDF(date: Date) {
        Task { @MainActor in
            exportedURL = await service.exportMonthlyPDF(sales: monthlySales, date: date)
        }
    }

    // MARK: - Export anual
    func exportAnnualCSV(date: Date) {
        exportedURL = service.exportAnnualCSV(sales: annualSales, date: date)
    }

    func exportAnnualPDF(date: Date) {
        Task { @MainActor in
            exportedURL = await service.exportAnnualPDF(sales: annualSales, date: date)
        }
    }

    // MARK: - Export de grupo (botões individuais)
    func exportGroupCSV(sales: [Sale]) {
        exportedURL = service.exportGroupCSV(sales: sales)
        showExportConfirmation = true
    }

    func exportGroupPDF(sales: [Sale]) {
        Task { @MainActor in
            exportedURL = await service.exportGroupPDF(sales: sales)
            showExportConfirmation = true
        }
    }

    // MARK: - Utilitários
    func total(for sales: [Sale]) -> Double {
        sales.reduce(0) { $0 + $1.total }
    }

    func totalItems(for sales: [Sale]) -> Int {
        sales.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }
    }

    /// Produto mais vendido (nome apenas) — derivado de `topProducts`,
    /// para não haver duas contagens diferentes na app.
    func topProduct(for sales: [Sale]) -> String {
        topProducts(for: sales, limit: 1).first?.name ?? "—"
    }

    /// Ranking de produtos vendidos, por quantidade. `limit` corta o topo
    /// (50 por omissão, o que a UI mostra).
    func topProducts(for sales: [Sale], limit: Int = 50) -> [TopProductEntry] {
        var quantities: [String: Int] = [:]
        var totals: [String: Double] = [:]
        for sale in sales {
            for item in sale.items {
                quantities[item.productName, default: 0] += item.quantity
                totals[item.productName, default: 0] += item.subtotal
            }
        }
        return quantities
            .map { TopProductEntry(name: $0.key, quantity: $0.value, total: totals[$0.key] ?? 0) }
            // Empate na quantidade desempata pelo valor, depois pelo nome —
            // sem isto a ordem mudava a cada leitura (dicionário não é ordenado).
            .sorted {
                if $0.quantity != $1.quantity { return $0.quantity > $1.quantity }
                if $0.total != $1.total { return $0.total > $1.total }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map { $0 }
    }

    func salesByHour(for sales: [Sale]) -> [(hour: String, total: Double)] {
        var grouped: [String: Double] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        for sale in sales {
            grouped[formatter.string(from: sale.date), default: 0] += sale.total
        }
        return grouped.sorted { $0.key < $1.key }.map { (hour: "\($0.key)h", total: $0.value) }
    }

    func salesByMonth(for sales: [Sale]) -> [(month: String, total: Double)] {
        var grouped: [String: Double] = [:]
        let key = DateFormatter()
        key.dateFormat = "MM"
        for sale in sales {
            grouped[key.string(from: sale.date), default: 0] += sale.total
        }
        // Nome do mês a partir de uma data desse mês — evita indexar
        // `shortMonthSymbols` à mão.
        let name = DateFormatter()
        name.locale = Locale(identifier: "pt_PT")
        name.dateFormat = "MMM"
        var labels: [String: String] = [:]
        for sale in sales {
            labels[key.string(from: sale.date)] = name.string(from: sale.date).capitalized
        }
        return grouped.sorted { $0.key < $1.key }.map {
            (month: labels[$0.key] ?? $0.key, total: $0.value)
        }
    }

    func salesByDay(for sales: [Sale]) -> [(day: String, total: Double)] {
        var grouped: [String: Double] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        for sale in sales {
            grouped[formatter.string(from: sale.date), default: 0] += sale.total
        }
        return grouped.sorted { $0.key < $1.key }.map { (day: $0.key, total: $0.value) }
    }

    // MARK: - Séries para gráficos (nº de vendas e itens vendidos)

    /// Nº de facturas por mês, na ordem do calendário.
    func salesCountByMonth(for sales: [Sale]) -> [(month: String, count: Int)] {
        countSeries(sales, keyFormat: "MM", labelFormat: "MMM") { _ in 1 }
            .map { (month: $0.label, count: $0.value) }
    }

    /// Itens vendidos por mês.
    func itemsByMonth(for sales: [Sale]) -> [(month: String, items: Int)] {
        countSeries(sales, keyFormat: "MM", labelFormat: "MMM") { sale in
            sale.items.reduce(0) { $0 + $1.quantity }
        }
        .map { (month: $0.label, items: $0.value) }
    }

    /// Nº de facturas por dia do mês.
    func salesCountByDay(for sales: [Sale]) -> [(day: String, count: Int)] {
        countSeries(sales, keyFormat: "dd", labelFormat: "dd") { _ in 1 }
            .map { (day: $0.label, count: $0.value) }
    }

    /// Itens vendidos por dia do mês.
    func itemsByDay(for sales: [Sale]) -> [(day: String, items: Int)] {
        countSeries(sales, keyFormat: "dd", labelFormat: "dd") { sale in
            sale.items.reduce(0) { $0 + $1.quantity }
        }
        .map { (day: $0.label, items: $0.value) }
    }

    /// Agrupa vendas por uma chave de data ordenável (`keyFormat`) e devolve o
    /// somatório de `value`, já com a etiqueta legível (`labelFormat`).
    private func countSeries(
        _ sales: [Sale],
        keyFormat: String,
        labelFormat: String,
        value: (Sale) -> Int
    ) -> [(label: String, value: Int)] {
        let key = DateFormatter()
        key.locale = Locale(identifier: "en_US_POSIX")
        key.dateFormat = keyFormat

        let label = DateFormatter()
        label.locale = Locale(identifier: "pt_PT")
        label.dateFormat = labelFormat

        var totals: [String: Int] = [:]
        var labels: [String: String] = [:]
        for sale in sales {
            let k = key.string(from: sale.date)
            totals[k, default: 0] += value(sale)
            labels[k] = label.string(from: sale.date).capitalized
        }
        return totals.sorted { $0.key < $1.key }.map { (label: labels[$0.key] ?? $0.key, value: $0.value) }
    }


    // MARK: - Filtro do histórico de relatórios (2.1)

    /// Âmbito da pesquisa no histórico: tudo, ou por dia/mês/ano da data escolhida.
    enum ReportSearchScope: String, CaseIterable, Identifiable {
        case all = "Tudo"
        case day = "Dia"
        case month = "Mês"
        case year = "Ano"

        var id: String { rawValue }

        /// Formato do prefixo de `Report.period` correspondente ao âmbito.
        var dateFormat: String? {
            switch self {
            case .all:   return nil
            case .day:   return "yyyy-MM-dd"
            case .month: return "yyyy-MM"
            case .year:  return "yyyy"
            }
        }
    }

    /// Função pura: filtra por tipo e por prefixo de período.
    /// `period` é sempre `yyyy`, `yyyy-MM` ou `yyyy-MM-dd`, logo o prefixo chega —
    /// um âmbito de mês apanha os relatórios diários desse mês.
    static func filterReports(
        _ reports: [Report],
        scope: ReportSearchScope,
        date: Date,
        type: ReportType?
    ) -> [Report] {
        var result = reports
        if let type {
            result = result.filter { $0.type == type }
        }
        if let format = scope.dateFormat {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            let prefix = f.string(from: date)
            result = result.filter { $0.period.hasPrefix(prefix) }
        }
        return result
    }

    @MainActor
    func exportGroupPDFAsync(sales: [Sale]) async {
        exportedURL = await service.exportGroupPDF(sales: sales)
        showExportConfirmation = true
    }
}
