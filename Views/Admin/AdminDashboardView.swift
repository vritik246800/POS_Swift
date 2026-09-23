import SwiftUI
import Charts

// MARK: - Dashboard da loja
//
// Hierarquia: cabeçalho (período uma só vez) → receita em destaque ao lado dos
// restantes indicadores → gráfico de evolução → distribuições.
// Em ecrã largo divide-se em duas colunas; em ecrã estreito empilha tudo.

struct AdminDashboardView: View {
    @EnvironmentObject var vm: AdminViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: AdminViewModel.Period = .month
    @State private var chartKind: ChartKind = .revenue

    /// As duas perguntas que o painel do gráfico responde, no mesmo lugar do ecrã.
    enum ChartKind: String, CaseIterable, Identifiable {
        case revenue  = "Receita"
        case cashiers = "Vendas por caixa"

        var id: String { rawValue }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private var series: RevenueSeries { vm.revenueSeries(in: period) }
    private var mix: [(method: PaymentMethod, total: Double)] { vm.paymentMix(in: period) }
    private var top: [ProductRanking] { vm.topProducts(in: period) }
    private var byCategory: [CategoryRevenue] { vm.revenueByCategory(in: period) }
    private var cashiers: [CashierPerformance] { vm.cashierPerformance(in: period) }
    private var label: String { vm.periodLabel(period) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        mainColumn
                        sideColumn.frame(width: 340)
                    }
                    VStack(spacing: 16) {
                        mainColumn
                        sideColumn
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .animation(animation, value: period)
        .animation(animation, value: chartKind)
        .animation(animation, value: vm.filter)
        .onAppear { vm.load() }
    }

    // MARK: - Colunas

    /// O que responde às perguntas "quanto entrou", "quando" e "por quem".
    private var mainColumn: some View {
        VStack(spacing: 16) {
            kpiBlock
            chartPanel
        }
    }

    /// As distribuições — "de onde veio" o dinheiro.
    private var sideColumn: some View {
        VStack(spacing: 16) {
            topProductsPanel
            categoryPanel
            paymentPanel
        }
    }

    // MARK: - Cabeçalho

    /// O período é dito uma só vez, aqui — deixou de se repetir no subtítulo de cada painel.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visão geral")
                        .font(.system(size: 20, weight: .bold))
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                periodPicker
            }
            if period == .all { dateFilterBar }
        }
    }

    // MARK: - Período

    private var periodPicker: some View {
        Picker("Período", selection: $period) {
            ForEach(AdminViewModel.Period.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
        .accessibilityLabel("Período")
    }

    /// Só em "Total": estreitar o histórico por ano, mês e dia.
    /// Mês fica desativado sem ano, e dia sem mês — prevenir em vez de corrigir depois.
    private var dateFilterBar: some View {
        HStack(spacing: 12) {
            Picker("Ano", selection: $vm.filter.year) {
                Text("Todos").tag(Int?.none)
                ForEach(vm.availableYears, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            .frame(maxWidth: 150)

            Picker("Mês", selection: $vm.filter.month) {
                Text("Todos").tag(Int?.none)
                ForEach(Array(monthNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(Int?.some(index + 1))
                }
            }
            .frame(maxWidth: 180)
            .disabled(vm.filter.year == nil)

            Picker("Dia", selection: $vm.filter.day) {
                Text("Todos").tag(Int?.none)
                ForEach(vm.daysInSelectedMonth, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            .frame(maxWidth: 130)
            .disabled(vm.filter.month == nil)

            if !vm.filter.isEmpty {
                Button("Limpar") { vm.filter = .init() }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Limpar filtro de data")
            }

            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .onChange(of: vm.filter.year) { _, new in
            if new == nil { vm.filter.month = nil; vm.filter.day = nil }
        }
        .onChange(of: vm.filter.month) { _, new in
            if new == nil { vm.filter.day = nil }
            else if let day = vm.filter.day, !vm.daysInSelectedMonth.contains(day) { vm.filter.day = nil }
        }
    }

    private var monthNames: [String] { Calendar.current.standaloneMonthSymbols }

    // MARK: - Indicadores

    /// Uma grelha só, de colunas iguais. A contagem divide seis sem resto (3 · 2 · 1),
    /// por isso não sobra buraco na última linha em nenhuma largura de janela.
    /// A Receita lê-se primeiro por ser o primeiro cartão e por ser `prominent`.
    private var kpiBlock: some View {
        ViewThatFits(in: .horizontal) {
            kpiGrid(columns: 3)
            kpiGrid(columns: 2)
            kpiGrid(columns: 1)
        }
    }

    private func kpiGrid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 170), spacing: 12),
                                 count: columns),
                  spacing: 12) {
            AdminKPICard(icon: "banknote", title: "Receita",
                         value: formatCurrency(vm.revenue(in: period)),
                         detail: "\(vm.salesCount(in: period)) venda(s)",
                         color: AppTheme.brandGreen,
                         prominent: true)

            AdminKPICard(icon: "cart", title: "Ticket médio",
                         value: formatCurrency(vm.averageTicket(in: period)),
                         detail: "por venda",
                         color: AppTheme.accent)

            AdminKPICard(icon: "shippingbox", title: "Artigos vendidos",
                         value: "\(vm.itemsSold(in: period))",
                         detail: "unidades",
                         color: AppTheme.brandPurple)

            AdminKPICard(icon: "archivebox", title: "Valor em stock",
                         value: formatCurrency(vm.stockValue),
                         detail: "\(vm.products.count) produto(s)",
                         color: AppTheme.brandOrange)

            AdminKPICard(icon: ExpiryStatus.days.icon, title: "Em risco",
                         value: formatCurrency(vm.riskValue),
                         detail: "\(vm.riskBatches.count) lote(s)",
                         color: ExpiryStatus.days.color)

            AdminKPICard(icon: ExpiryStatus.expired.icon, title: "Perda real",
                         value: formatCurrency(vm.realLoss),
                         detail: "\(vm.expiredBatches.count) lote(s) expirado(s)",
                         color: ExpiryStatus.expired.color)
        }
    }

    // MARK: - Gráfico (receita ou caixas)

    /// Um só painel, duas leituras: quanto entrou ao longo do tempo, ou por quem entrou.
    /// O seletor fica no topo do painel para o gráfico não mudar de sítio ao trocar.
    private var chartPanel: some View {
        AdminPanel(title: chartKind == .revenue ? series.title : "Vendas por caixa",
                   icon: chartKind == .revenue ? "chart.line.uptrend.xyaxis" : "person.text.rectangle",
                   subtitle: chartKind == .revenue
                       ? formatCurrency(series.total)
                       : "\(cashiers.count) caixa(s)") {
            VStack(alignment: .leading, spacing: 12) {
                chartPicker
                Group {
                    switch chartKind {
                    case .revenue:  revenueChart
                    case .cashiers: cashierChart
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var chartPicker: some View {
        Picker("Gráfico", selection: $chartKind) {
            ForEach(ChartKind.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
        .accessibilityLabel("Gráfico")
    }

    @ViewBuilder
    private var revenueChart: some View {
        if series.isEmpty {
            emptyChart("Ainda não há vendas neste intervalo.")
        } else {
            let unit = series.unit
            Chart(series.points) { point in
                AreaMark(
                    x: .value("Data", point.day, unit: unit),
                    y: .value("Receita", point.revenue)
                )
                .foregroundStyle(
                    LinearGradient(colors: [AppTheme.accent.opacity(0.45), AppTheme.accent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Data", point.day, unit: unit),
                    y: .value("Receita", point.revenue)
                )
                .foregroundStyle(AppTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel(format: axisFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            .accessibilityLabel("Gráfico da receita — \(label)")
        }
    }

    /// Quem vendeu mais no período: barra por caixa, ordenada do maior total para o menor.
    @ViewBuilder
    private var cashierChart: some View {
        if cashiers.isEmpty {
            emptyChart("Sem vendas no período.")
        } else {
            Chart(cashiers) { entry in
                BarMark(
                    x: .value("Total", entry.total),
                    y: .value("Caixa", entry.name)
                )
                .foregroundStyle(AppTheme.accent.gradient)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(formatCurrency(entry.total)) · \(entry.numSales) venda(s)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel()
                }
            }
            // Espaço à direita para a anotação do valor não sair do painel.
            .chartXScale(domain: 0...((cashiers.first?.total ?? 1) * 1.45))
            .frame(height: max(190, Double(cashiers.count) * 44))
            .accessibilityLabel("Gráfico de vendas por caixa — \(label)")
        }
    }

    private func emptyChart(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    /// Rótulo do eixo X à medida da granularidade da série.
    private var axisFormat: Date.FormatStyle {
        switch series.unit {
        case .hour:  return .dateTime.hour()
        case .month: return .dateTime.month(.abbreviated).year(.twoDigits)
        default:     return .dateTime.day().month(.abbreviated)
        }
    }

    // MARK: - Distribuições

    private var paymentPanel: some View {
        AdminPanel(title: "Métodos de pagamento", icon: "creditcard") {
            if mix.isEmpty {
                emptyLine("Sem pagamentos registados.")
            } else {
                let total = mix.reduce(0) { $0 + $1.total }
                VStack(spacing: 10) {
                    ForEach(mix, id: \.method) { entry in
                        AdminProportionRow(
                            label: entry.method.label,
                            value: formatCurrency(entry.total),
                            fraction: total > 0 ? entry.total / total : 0,
                            color: AppTheme.methodColor(entry.method),
                            icon: entry.method.icon
                        )
                    }
                }
            }
        }
    }

    private var topProductsPanel: some View {
        AdminPanel(title: "Produtos mais vendidos", icon: "star") {
            if top.isEmpty {
                emptyLine("Sem vendas no período.")
            } else {
                let max = top.first?.revenue ?? 1
                VStack(spacing: 10) {
                    ForEach(top) { item in
                        AdminProportionRow(
                            label: "\(item.name) · \(item.quantity) un.",
                            value: formatCurrency(item.revenue),
                            fraction: max > 0 ? item.revenue / max : 0,
                            color: AppTheme.brandGreen
                        )
                    }
                }
            }
        }
    }

    private var categoryPanel: some View {
        AdminPanel(title: "Receita por categoria", icon: "tag") {
            if byCategory.isEmpty {
                emptyLine("Sem vendas no período.")
            } else {
                let total = byCategory.reduce(0) { $0 + $1.revenue }
                VStack(spacing: 10) {
                    ForEach(byCategory) { entry in
                        let category = vm.categories.first { $0.id == entry.categoryId }
                        AdminProportionRow(
                            label: entry.name,
                            value: formatCurrency(entry.revenue),
                            fraction: total > 0 ? entry.revenue / total : 0,
                            color: category?.color ?? AppTheme.noCategory,
                            icon: category?.icon ?? "tag.slash"
                        )
                    }
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70)
    }
}
