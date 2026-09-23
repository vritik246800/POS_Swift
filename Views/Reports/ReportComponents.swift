import SwiftUI
import Charts
internal import Combine

// MARK: - Seletor de mês com header estilizado
struct MonthSelectorHeader: View {
    @Binding var selectedMonth: Date
    var onChange: () -> Void

    private var monthYearString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "pt_PT")
        return f.string(from: selectedMonth).capitalized
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(monthYearString)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            DatePicker("", selection: $selectedMonth, displayedComponents: [.date])
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .onChange(of: selectedMonth) { onChange() }
        }
    }
}

// MARK: - Seletor de ano
struct YearSelectorHeader: View {
    @Binding var selectedYear: Date
    var onChange: () -> Void

    /// Ano corrente e os 9 anteriores — chega para o histórico de um POS.
    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 9)...current).reversed()
    }

    private var yearValue: Int {
        Calendar.current.component(.year, from: selectedYear)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(String(yearValue))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .contentTransition(.numericText())

            Picker("Ano", selection: Binding(
                get: { yearValue },
                set: { newYear in
                    var comps = Calendar.current.dateComponents([.month, .day], from: selectedYear)
                    comps.year = newYear
                    selectedYear = Calendar.current.date(from: comps) ?? selectedYear
                }
            )) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .onChange(of: selectedYear) { onChange() }
        }
    }
}

// MARK: - Grelha de facturas (cards quadrados)

/// Agrupa as vendas por cliente: um grupo por nome, cada venda anónima isolada.
func groupSalesByClient(_ sales: [Sale]) -> [[Sale]] {
    let anonymous = sales.filter { $0.clientName.isEmpty }
    let named = sales.filter { !$0.clientName.isEmpty }
    var byName: [String: [Sale]] = [:]
    for sale in named { byName[sale.clientName, default: []].append(sale) }
    var groups: [[Sale]] = byName.values.sorted { $0[0].clientName < $1[0].clientName }
    groups += anonymous.map { [$0] }
    return groups
}

/// Grelha adaptativa dos cards quadrados de factura. Partilhada pelas
/// secções Diário, Mensal e Anual.
struct SaleCardsGrid: View {
    let groups: [[Sale]]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 165, maximum: 240), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(groups, id: \.first?.id) { group in
                SaleReportRowView(sales: group)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 20)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85),
            value: groups.count
        )
    }
}

// MARK: - Valor com animação de contagem

/// Texto de um valor que conta de 0 até ao valor quando o painel aparece,
/// e volta a animar sempre que o valor muda. Fonte única da animação de
/// números dos painéis (relatórios e fecho de caixa).
/// Respeita `Reduce Motion` — aí mostra o valor final de imediato.
struct AnimatedValueText: View {
    let value: Double
    /// Como se escreve o valor (moeda por omissão; contagens usam `Int`).
    var format: (Double) -> String = { formatMT($0) }
    var duration: Double = 0.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        CountingText(value: shown, format: format)
            .monospacedDigit()
            .onAppear { run() }
            .onChange(of: value) { run() }
    }

    private func run() {
        guard !reduceMotion else {
            shown = value
            return
        }
        withAnimation(.easeOut(duration: duration)) { shown = value }
    }
}

/// `Animatable` é o que faz o SwiftUI interpolar o número a cada frame —
/// sem isto o texto saltava directamente para o valor final.
private struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// Contagem inteira (nº de vendas, itens) — evita repetir o formatador.
func formatCount(_ value: Double) -> String { "\(Int(value.rounded()))" }

// MARK: - Card principal (total em destaque)
// Cabeçalho de totais: vidro sobre gradiente de marca.
struct PrimaryMetricCard: View {
    let value: Double
    let label: String
    /// Formatação do valor (moeda por omissão).
    var format: (Double) -> String = { formatMT($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            AnimatedValueText(value: value, format: format)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        // Gradiente de marca por baixo do vidro (nunca por cima, senão tapa-o).
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.30), AppTheme.accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Card secundário (vendas / itens)
struct SecondaryMetricCard: View {
    let value: Double
    let label: String
    let icon: String
    let color: Color
    var format: (Double) -> String = formatCount

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.14), in: .rect(cornerRadius: 8))

            AnimatedValueText(value: value, format: format)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        // Cor por baixo do vidro, como nos cartões do fecho de caixa
        // (um único plano de vidro por cartão).
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Cabeçalho de resumo (totais + top de produtos ao lado)

/// Bloco de topo partilhado pelas secções Diário, Mensal e Anual:
/// à esquerda o total e os contadores, à direita o ranking de produtos
/// vendidos, a ocupar a altura das duas linhas.
struct ReportSummaryHeader: View {
    let totalLabel: String
    let totalValue: Double
    let salesCount: Int
    let itemCount: Int
    let topProducts: [TopProductEntry]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    PrimaryMetricCard(value: totalValue, label: totalLabel)
                    HStack(spacing: 12) {
                        SecondaryMetricCard(
                            value: Double(salesCount),
                            label: "Vendas",
                            icon: "cart.fill",
                            color: AppTheme.brandGreen
                        )
                        SecondaryMetricCard(
                            value: Double(itemCount),
                            label: "Itens Vendidos",
                            icon: "shippingbox.fill",
                            color: AppTheme.brandOrange
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                TopProductsPanel(entries: topProducts)
                    .frame(width: 330)
            }
        }
        .frame(height: 290)
    }
}

// MARK: - Ranking de produtos mais vendidos

/// Lista dos produtos mais vendidos do período (até 50), com quantidade
/// vendida e valor facturado. Scroll interno — o painel mantém a altura.
struct TopProductsPanel: View {
    let entries: [TopProductEntry]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 28, height: 28)
                    .background(Color.yellow.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mais Vendidos")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("Top \(min(entries.count, 50))")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()
            }

            if entries.isEmpty {
                Text("Sem vendas no período.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(rank: index + 1, entry: entry)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: entries)
    }

    /// Cor da posição: pódio a dourado/prata/bronze, resto neutro.
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:  return .yellow
        case 2:  return .gray
        case 3:  return AppTheme.brandOrange
        default: return .secondary
        }
    }

    private func row(rank: Int, entry: TopProductEntry) -> some View {
        HStack(spacing: 9) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(rankColor(rank))
                .frame(width: 22, height: 22)
                .background(rankColor(rank).opacity(0.15), in: .circle)

            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(entry.quantity)×")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accent)

            Text(formatMT(entry.total))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(entry.name), \(entry.quantity) unidades, \(formatMT(entry.total))")
    }
}

// MARK: - Gráfico de barras verticais

/// Uma barra do gráfico. `display` é o texto do valor (moeda ou contagem)
/// e `color` permite dar cor própria a cada barra (ex.: método de pagamento).
struct BarEntry: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let value: Double
    let display: String
    var color: Color? = nil
}

/// Cartão com gráfico de barras **verticais**. Fonte única dos gráficos de
/// relatórios e de fecho de caixa.
struct VerticalBarsCard: View {
    let title: String
    let entries: [BarEntry]
    var tint: Color = AppTheme.accent
    /// Altura fixa do gráfico. `nil` deixa o cartão esticar até à altura
    /// disponível (usado no fecho de caixa, ao lado dos cartões).
    var height: CGFloat? = 190

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fracção da altura já desenhada: 0 → 1 faz as barras crescerem ao
    /// entrar na aba. Com `Reduce Motion` arranca logo em 1.
    @State private var growth: Double = 0

    /// Com muitas barras as etiquetas de valor sobrepõem-se — só se mostram
    /// quando há espaço para elas.
    private var showsValues: Bool { entries.count <= 12 }

    /// Topo do eixo Y fixo no valor real: sem isto a escala crescia com as
    /// barras e a animação não se via.
    private var yMax: Double { max(entries.map(\.value).max() ?? 1, 1) * 1.1 }

    private func grow() {
        guard !reduceMotion else {
            growth = 1
            return
        }
        growth = 0
        // Um ciclo de espera: reposto e animado no mesmo update, o SwiftUI
        // não via mudança nenhuma e as barras apareciam já cheias.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.7)) { growth = 1 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            if entries.isEmpty {
                Text("Sem dados no período.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height ?? 160, maxHeight: height == nil ? .infinity : nil, alignment: .center)
            } else {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Período", entry.label),
                        y: .value("Valor", entry.value * growth),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [entry.color ?? tint, (entry.color ?? tint).opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 3) {
                        if showsValues {
                            Text(entry.display)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .accessibilityLabel(entry.label)
                    .accessibilityValue(entry.display)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...yMax)
                .frame(height: height)
                .frame(maxHeight: height == nil ? .infinity : nil)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: entries)
                .onAppear { grow() }
                .onChange(of: entries) { grow() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Estado vazio
struct EmptySalesView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Campo de pesquisa inline (data / hora)
struct SalesSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focused ? AppTheme.accent : .secondary)

            TextField("data ou hora…", text: $text)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(minWidth: 80, idealWidth: 120, maxWidth: 140)
                // Limpa ao pressionar Escape
                .onKeyPress(.escape) {
                    text = ""
                    focused = false
                    return .handled
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar pesquisa")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: focused)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}

// MARK: - Exportação de relatórios (2.6)
//
// Estado de apresentação partilhado pelo menu da toolbar e pelo toast.
// A exportação em si é do `ReportService` — aqui só se orquestra a UI.

final class ReportExportState: ObservableObject {
    @Published var isExporting = false
    @Published var progressLabel = ""
    @Published var toast: String?
    @Published var toastIsError = false
    @Published var shareURL: URL?

    private var dismissTask: Task<Void, Never>?

    /// Corre a exportação, revela/partilha o ficheiro e mostra o resultado.
    @MainActor
    func run(format: String, export: @escaping () async -> URL?) {
        guard !isExporting else { return }
        isExporting = true
        progressLabel = "A gerar \(format)…"
        toast = nil

        Task {
            let url = await export()
            isExporting = false

            guard let url else {
                show("Não foi possível exportar o \(format).", isError: true)
                return
            }

            #if os(macOS)
            ReportService().revealInFinder(url)
            #else
            shareURL = url
            #endif
            show("\(format) guardado em \(url.path)", isError: false)
        }
    }

    @MainActor
    private func show(_ message: String, isError: Bool) {
        toast = message
        toastIsError = isError
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

/// Botão "Exportar" da toolbar: menu com CSV e PDF.
struct ReportExportMenu: View {
    @ObservedObject var state: ReportExportState
    let exportCSV: () -> URL?
    let exportPDF: () async -> URL?

    var body: some View {
        Menu {
            Button {
                state.run(format: "CSV") { exportCSV() }
            } label: {
                Label("CSV", systemImage: "tablecells")
            }
            Button {
                state.run(format: "PDF", export: exportPDF)
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
        } label: {
            if state.isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .disabled(state.isExporting)
        .accessibilityLabel("Exportar relatório")
    }
}

/// Faixa de progresso/resultado da exportação. Usar em `.overlay(alignment: .top)`.
struct ReportExportToast: View {
    @ObservedObject var state: ReportExportState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if state.isExporting {
                banner(icon: nil, text: state.progressLabel, color: AppTheme.accent)
            } else if let toast = state.toast {
                banner(icon: state.toastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                       text: toast,
                       color: state.toastIsError ? .red : AppTheme.brandGreen)
            }
        }
        .padding(.top, 12)
        .allowsHitTesting(false)   // faixa informativa — não intercepta cliques na lista
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.25), value: state.isExporting)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.25), value: state.toast)
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { state.shareURL != nil },
            set: { if !$0 { state.shareURL = nil } }
        )) {
            if let url = state.shareURL {
                ShareSheet(items: [url])
            }
        }
        #endif
    }

    private func banner(icon: String?, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 520)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
