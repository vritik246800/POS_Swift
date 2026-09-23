import SwiftUI
internal import Combine

// MARK: - Vista principal de Fecho

struct DayCloseView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var vm = DayCloseViewModel()
    @State private var selectedSection: Section = .cashiers

    /// O histórico de fechos passou para Administração. O perfil Caixa só vê
    /// "Caixas" — é lá que fecha a sua própria caixa.
    enum Section: String, CaseIterable, Identifiable {
        case cashiers = "Caixas"
        case day = "Fecho do Dia"
        case month = "Fecho do Mês"
        case year = "Fecho do Ano"

        var id: String { rawValue }
    }

    private var sections: [Section] {
        authViewModel.isAdmin ? Section.allCases : [.cashiers]
    }

    /// Picker segmentado nas duas plataformas (como nos Relatórios): em iOS
    /// evita barras de tabs aninhadas e em macOS tira o painel cinzento que o
    /// `TabView` desenha, deixando o fundo igual ao dos outros separadores.
    var body: some View {
        VStack(spacing: 0) {
            if sections.count > 1 {
                Picker("Secção", selection: $selectedSection) {
                    ForEach(sections) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            switch selectedSection {
            case .cashiers:
                CashierCloseAdminView()
                    .environmentObject(authViewModel)
            case .day:
                DayCloseTabView()
                    .environmentObject(authViewModel)
                    .environmentObject(vm)
            case .month:
                MonthCloseTabView()
                    .environmentObject(authViewModel)
                    .environmentObject(vm)
            case .year:
                YearCloseTabView()
                    .environmentObject(authViewModel)
                    .environmentObject(vm)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSection)
        .navigationTitle("Fecho de Caixa")
    }
}

// MARK: - Fecho do Dia

struct DayCloseTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var vm: DayCloseViewModel
    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var showConfirm = false
    @State private var successMessage = ""
    @State private var isExporting = false

    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    /// Verdadeiro se existirem vendas após o último fecho registado neste dia
    private var hasNewSalesAfterClose: Bool {
        guard let close = DatabaseManager.shared.fetchDayClose(date: dateStr) else { return false }
        let sales = DatabaseManager.shared.fetchSalesByDate(date: dateStr)
        return sales.contains { $0.date > close.closedAt }
    }

    /// Label e ícone do botão de fecho consoante o estado
    private var closeButtonLabel: (text: String, icon: String, color: Color) {
        if vm.isDayClosed(date: dateStr) {
            return ("Actualizar Fecho do Dia", "lock.rotation", .orange)
        } else {
            return ("Fazer Fecho do Dia", "lock.circle.fill", .blue)
        }
    }

    /// Bloco de notas do fecho. Vive por baixo do gráfico, na coluna direita,
    /// e estica-se até ao fundo dos cartões de método.
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notas")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            TextField("Observações do fecho...", text: $notes, axis: .vertical)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .lineLimit(3, reservesSpace: true)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: Header data
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fecho do Dia")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { vm.loadDay(date: dateStr) }
                }
                .padding(.horizontal, 20)

                // MARK: Badge estado do fecho
                if vm.isDayClosed(date: dateStr) {
                    if hasNewSalesAfterClose {
                        // Há vendas depois do fecho — aviso de sessão nova
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Existem vendas após o último fecho. Actualiza o fecho para incluí-las.")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                        )
                        .padding(.horizontal, 20)
                    } else {
                        // Fecho feito, sem novas vendas
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Este dia já foi fechado")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.2), lineWidth: 1))
                        )
                        .padding(.horizontal, 20)
                    }
                }

                // MARK: Cards resumo — as Notas entram na coluna do gráfico,
                // por baixo dele, em vez de ficarem à largura toda do ecrã.
                if let summary = vm.daySummary {
                    CloseSummarySection(summary: summary, chartHeight: 250) {
                        notesField
                    }
                    .padding(.horizontal, 20)
                } else {
                    EmptyCloseView(message: "Sem vendas para esta data.")
                    notesField
                        .padding(.horizontal, 20)
                }

                // MARK: Mensagem de sucesso
                if !successMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(successMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // MARK: Acções admin
                if authViewModel.isAdmin {
                    VStack(spacing: 10) {

                        // Botão de fecho — visível sempre que existam vendas
                        // Se já fechado: "Actualizar Fecho" (nova sessão)
                        // Se não fechado: "Fazer Fecho do Dia"
                        if vm.daySummary != nil {
                            let btn = closeButtonLabel
                            Button {
                                showConfirm = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: btn.icon)
                                    Text(btn.text)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(btn.color)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            ExportCloseButton(title: "Excel", icon: "tablecells.fill", color: .green) {
                                isExporting = true
                                Task { await vm.exportDayExcel(date: selectedDate); isExporting = false }
                            }
                            ExportCloseButton(title: "PDF", icon: "doc.richtext.fill", color: .red) {
                                isExporting = true
                                Task { await vm.exportDayPDF(date: selectedDate); isExporting = false }
                            }
                        }

                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("A exportar...").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }

                        if let url = vm.exportedURL {
                            ShareLink(item: url) {
                                Label("Partilhar ficheiro exportado", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 24)
        }
        .onAppear { vm.loadDay(date: dateStr) }
        .confirmationDialog(
            vm.isDayClosed(date: dateStr)
                ? "Actualizar Fecho do Dia \(dateStr)?"
                : "Confirmar Fecho do Dia \(dateStr)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(
                vm.isDayClosed(date: dateStr) ? "Confirmar Actualização" : "Confirmar Fecho",
                role: .destructive
            ) {
                if let userId = authViewModel.currentUser?.id, let s = vm.daySummary {
                    let ok = DatabaseManager.shared.saveDayClose(
                        date: dateStr, totalSales: s.totalSales,
                        cash: s.totalCash, card: s.totalCard,
                        bankTransfer: s.totalBankTransfer, mpesa: s.totalMpesa,
                        emola: s.totalEmola, numSales: s.numSales,
                        notes: notes, closedBy: userId
                    )
                    if ok {
                        let action = vm.isDayClosed(date: dateStr) ? "actualizado" : "registado"
                        successMessage = "Fecho do dia \(dateStr) \(action) com sucesso."
                        vm.loadDay(date: dateStr)
                        vm.loadHistory()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { successMessage = "" }
                        }
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Fecho do Mês

struct MonthCloseTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var vm: DayCloseViewModel
    @State private var selectedMonth = Date()
    @State private var isExporting = false

    private var monthStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: selectedMonth)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "pt_PT")
        return f.string(from: selectedMonth).capitalized
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: Header mês
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fecho do Mês")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(monthLabel)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    DatePicker("", selection: $selectedMonth, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedMonth) { vm.loadMonth(month: monthStr) }
                }
                .padding(.horizontal, 20)

                if let summary = vm.monthSummary {
                    CloseSummarySection(summary: summary)
                        .padding(.horizontal, 20)
                } else {
                    EmptyCloseView(message: "Sem dados para este mês.")
                }

                if authViewModel.isAdmin {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            ExportCloseButton(title: "Excel", icon: "tablecells.fill", color: .green) {
                                isExporting = true
                                Task { await vm.exportMonthExcel(date: selectedMonth); isExporting = false }
                            }
                            ExportCloseButton(title: "PDF", icon: "doc.richtext.fill", color: .red) {
                                isExporting = true
                                Task { await vm.exportMonthPDF(date: selectedMonth); isExporting = false }
                            }
                        }

                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("A exportar...").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }

                        if let url = vm.exportedURL {
                            ShareLink(item: url) {
                                Label("Partilhar ficheiro exportado", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 24)
        }
        .onAppear { vm.loadMonth(month: monthStr) }
    }
}

// MARK: - Fecho do Ano

struct YearCloseTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var vm: DayCloseViewModel
    @State private var selectedYear = Date()
    @State private var isExporting = false

    private var yearStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy"
        return f.string(from: selectedYear)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: Header ano
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fecho do Ano")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(yearStr)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    // Só ano — o DatePicker do sistema não tem esse modo.
                    YearPickerField(date: $selectedYear)
                        .onChange(of: selectedYear) { vm.loadYear(year: yearStr) }
                }
                .padding(.horizontal, 20)

                if let summary = vm.yearSummary {
                    CloseSummarySection(summary: summary)
                        .padding(.horizontal, 20)
                } else {
                    EmptyCloseView(message: "Sem dados para este ano.")
                }

                if authViewModel.isAdmin {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            ExportCloseButton(title: "Excel", icon: "tablecells.fill", color: .green) {
                                isExporting = true
                                Task { await vm.exportYearExcel(date: selectedYear); isExporting = false }
                            }
                            ExportCloseButton(title: "PDF", icon: "doc.richtext.fill", color: .red) {
                                isExporting = true
                                Task { await vm.exportYearPDF(date: selectedYear); isExporting = false }
                            }
                        }

                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("A exportar...").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }

                        if let url = vm.exportedURL {
                            ShareLink(item: url) {
                                Label("Partilhar ficheiro exportado", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 24)
        }
        .onAppear { vm.loadYear(year: yearStr) }
    }
}

// MARK: - Histórico de Fechos

struct CloseHistoryView: View {
    @EnvironmentObject var vm: DayCloseViewModel

    var body: some View {
        VStack {
            if vm.history.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Sem fechos registados")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(vm.history) { close in
                    DayCloseRowView(close: close)
                }
                .listStyle(.plain)
            }
        }
        .onAppear { vm.loadHistory() }
    }
}

struct DayCloseRowView: View {
    let close: DayClose

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(close.date)
                    .font(.system(size: 15, weight: .semibold))
                Text(close.closedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatMT(close.grandTotal))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.blue)
                Text("\(close.numSales) vendas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Cards de resumo por método de pagamento

struct ClosePaymentSummary: View {
    let summary: CloseSummary

    var body: some View {
        // Um só contentor de vidro: os cartões fundem-se entre si (Liquid Glass).
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 12) {

                // Card principal — total geral
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Geral")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.7)
                        AnimatedValueText(value: summary.totalSales)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue.opacity(0.3))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                // Tinta por baixo do vidro — nunca por cima, senão tapa-o.
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

                // Grid 2x3 — métodos + nº vendas (cores centralizadas em AppTheme)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    CloseMethodCard(label: "Numerário",        value: summary.totalCash,          icon: "banknote.fill",             color: PaymentMethod.cash.color)
                    CloseMethodCard(label: "Cartão",           value: summary.totalCard,          icon: "creditcard.fill",           color: PaymentMethod.card.color)
                    CloseMethodCard(label: "Transf. Bancária", value: summary.totalBankTransfer,  icon: "building.columns.fill",     color: PaymentMethod.bankTransfer.color)
                    CloseMethodCard(label: "M-Pesa",           value: summary.totalMpesa,         icon: "phone.fill",                color: PaymentMethod.mpesa.color)
                    CloseMethodCard(label: "e-Mola",           value: summary.totalEmola,         icon: "phone.badge.waveform.fill", color: PaymentMethod.emola.color)
                    CloseMethodCard(label: "Nº Vendas",        value: Double(summary.numSales),   icon: "cart.fill",                 color: .teal, isCount: true)
                }
            }
        }
    }
}

struct CloseMethodCard: View {
    let label: String
    let value: Double
    let icon: String
    let color: Color
    var isCount: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)

            AnimatedValueText(value: value, format: { isCount ? formatCount($0) : formatMT($0) })
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.55)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        // Cor do método por baixo do vidro (um único plano de vidro por cartão).
        .background(
            RoundedRectangle(cornerRadius: 14)
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

// MARK: - Resumo do fecho: cartões à esquerda, gráfico à direita

/// Bloco partilhado pelos três fechos (dia, mês e ano): os cartões por método
/// à esquerda e o gráfico de distribuição ao lado, na mesma linha.
struct CloseSummarySection<Below: View>: View {
    let summary: CloseSummary
    /// Altura do gráfico. `nil` (omissão) estica-o até ao fundo dos cartões —
    /// é o que os fechos de Mês e Ano usam. O Fecho do Dia fixa-a para caber
    /// o bloco de Notas por baixo, no espaço que sobrava à direita.
    var chartHeight: CGFloat?
    /// Conteúdo colado por baixo do gráfico, na coluna da direita.
    @ViewBuilder var below: Below

    var body: some View {
        // Grid (e não HStack) porque só o Grid propõe a altura da linha às
        // células — é isso que faz o gráfico esticar até à altura dos cartões.
        Grid(alignment: .top, horizontalSpacing: 16) {
            GridRow {
                ClosePaymentSummary(summary: summary)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    AnimatedBreakdownChart(summary: summary, height: chartHeight)
                    below
                }
                .frame(width: 360)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

extension CloseSummarySection where Below == EmptyView {
    init(summary: CloseSummary, chartHeight: CGFloat? = nil) {
        self.init(summary: summary, chartHeight: chartHeight) { EmptyView() }
    }
}

// MARK: - Gráfico de distribuição por método (barras verticais)

/// Barras verticais, uma por método com valor no período.
/// O desenho em si é do `VerticalBarsCard` (fonte única dos gráficos da app).
struct AnimatedBreakdownChart: View {
    let summary: CloseSummary
    /// `nil` estica o cartão até à altura disponível.
    var height: CGFloat? = 250

    private var entries: [BarEntry] {
        [
            ("Numerário",   summary.totalCash,          PaymentMethod.cash.color),
            ("Cartão",      summary.totalCard,          PaymentMethod.card.color),
            ("T. Bancária", summary.totalBankTransfer,  PaymentMethod.bankTransfer.color),
            ("M-Pesa",      summary.totalMpesa,         PaymentMethod.mpesa.color),
            ("e-Mola",      summary.totalEmola,         PaymentMethod.emola.color)
        ]
        .filter { $0.1 > 0 }
        .map { BarEntry(label: $0.0, value: $0.1, display: formatMT($0.1), color: $0.2) }
    }

    var body: some View {
        VerticalBarsCard(
            title: "Distribuição por Método",
            entries: entries,
            height: height
        )
    }
}

// MARK: - Estado vazio

struct EmptyCloseView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Botão exportar

struct ExportCloseButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

class DayCloseViewModel: ObservableObject {
    @Published var daySummary: CloseSummary? = nil
    @Published var monthSummary: CloseSummary? = nil
    @Published var yearSummary: CloseSummary? = nil
    @Published var history: [DayClose] = []
    @Published var exportedURL: URL? = nil

    private let db = DatabaseManager.shared

    func isDayClosed(date: String) -> Bool {
        db.isDayAlreadyClosed(date: date)
    }

    func loadDay(date: String) {
        let sales = db.fetchSalesByDate(date: date)
        let payments = db.fetchPaymentsByDate(datePrefix: date)
        daySummary = sales.isEmpty ? nil : buildSummary(sales: sales, payments: payments)
    }

    func loadMonth(month: String) {
        let sales = db.fetchSalesByMonth(yearMonth: month)
        let payments = db.fetchPaymentsByDate(datePrefix: month)
        monthSummary = sales.isEmpty ? nil : buildSummary(sales: sales, payments: payments)
    }

    func loadYear(year: String) {
        let sales = db.fetchSalesByYear(year: year)
        let payments = db.fetchPaymentsByDate(datePrefix: year)
        yearSummary = sales.isEmpty ? nil : buildSummary(sales: sales, payments: payments)
    }

    func loadHistory() {
        history = db.fetchDayCloses()
    }

    private func buildSummary(sales: [Sale], payments: [Payment]) -> CloseSummary {
        let total = sales.reduce(0.0) { $0 + $1.total }
        var cash = 0.0, card = 0.0, bank = 0.0, mpesa = 0.0, emola = 0.0
        for p in payments {
            switch p.method {
            case .cash:         cash += p.amount
            case .card:         card += p.amount
            case .bankTransfer: bank += p.amount
            case .mpesa:        mpesa += p.amount
            case .emola:        emola += p.amount
            }
        }
        return CloseSummary(
            totalSales: total, totalCash: cash, totalCard: card,
            totalBankTransfer: bank, totalMpesa: mpesa, totalEmola: emola,
            numSales: sales.count
        )
    }

    func exportDayExcel(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let s = f.string(from: date)
        let sales = db.fetchSalesByDate(date: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = CloseExportService().exportExcel(title: "Fecho Diário \(s)", sales: sales, payments: payments, period: s)
        await MainActor.run { exportedURL = url }
    }

    func exportDayPDF(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let s = f.string(from: date)
        let sales = db.fetchSalesByDate(date: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = await CloseExportService().exportPDF(title: "Fecho Diário — \(s)", sales: sales, payments: payments, period: s, type: "diario")
        await MainActor.run { exportedURL = url }
    }

    func exportMonthExcel(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        let s = f.string(from: date)
        let sales = db.fetchSalesByMonth(yearMonth: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = CloseExportService().exportExcel(title: "Fecho Mensal \(s)", sales: sales, payments: payments, period: s)
        await MainActor.run { exportedURL = url }
    }

    func exportMonthPDF(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        let s = f.string(from: date)
        let sales = db.fetchSalesByMonth(yearMonth: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = await CloseExportService().exportPDF(title: "Fecho Mensal — \(s)", sales: sales, payments: payments, period: s, type: "mensal")
        await MainActor.run { exportedURL = url }
    }

    func exportYearExcel(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy"
        let s = f.string(from: date)
        let sales = db.fetchSalesByYear(year: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = CloseExportService().exportExcel(title: "Fecho Anual \(s)", sales: sales, payments: payments, period: s)
        await MainActor.run { exportedURL = url }
    }

    func exportYearPDF(date: Date) async {
        let f = DateFormatter(); f.dateFormat = "yyyy"
        let s = f.string(from: date)
        let sales = db.fetchSalesByYear(year: s)
        let payments = db.fetchPaymentsByDate(datePrefix: s)
        let url = await CloseExportService().exportPDF(title: "Fecho Anual — \(s)", sales: sales, payments: payments, period: s, type: "anual")
        await MainActor.run { exportedURL = url }
    }
}

// MARK: - Modelo de resumo

struct CloseSummary {
    var totalSales: Double
    var totalCash: Double
    var totalCard: Double
    var totalBankTransfer: Double
    var totalMpesa: Double
    var totalEmola: Double
    var numSales: Int

    var grandTotal: Double { totalCash + totalCard + totalBankTransfer + totalMpesa + totalEmola }
}

// MARK: - Aliases de compatibilidade
typealias PaymentSummaryCards = ClosePaymentSummary
typealias PaymentBreakdownChart = AnimatedBreakdownChart
