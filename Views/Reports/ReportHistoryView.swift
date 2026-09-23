import SwiftUI

struct ReportHistoryView: View {
    @State private var reports: [Report] = []
    @State private var scope: ReportViewModel.ReportSearchScope = .all
    @State private var searchDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sem filtro por tipo — a pesquisa é só por período.
    private var filteredReports: [Report] {
        ReportViewModel.filterReports(reports, scope: scope, date: searchDate, type: nil)
    }

    /// Texto do período pesquisado — usado no resumo e no estado vazio.
    private var scopeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_PT")
        switch scope {
        case .all:   return "todos os períodos"
        case .day:   f.dateFormat = "d 'de' MMMM 'de' yyyy"
        case .month: f.dateFormat = "MMMM 'de' yyyy"
        case .year:  f.dateFormat = "yyyy"
        }
        return f.string(from: searchDate)
    }

    var body: some View {
        HStack(spacing: 0) {
            searchSidebar
                .frame(width: 260)

            Divider()

            reportList
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Histórico de Relatórios")
        .onAppear(perform: loadReports)
    }

    // MARK: - Painel de pesquisa (coluna esquerda)

    private var searchSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("Pesquisa")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }

            // Âmbito da pesquisa por período
            VStack(alignment: .leading, spacing: 8) {
                Text("Período")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                ForEach(ReportViewModel.ReportSearchScope.allCases) { option in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { scope = option }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: scope == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(scope == option ? AppTheme.accent : .secondary)
                            Text(option.rawValue)
                                .font(.system(size: 13, weight: scope == option ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(AppTheme.accent.opacity(scope == option ? 0.7 : 0), lineWidth: 1.5)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == option ? [.isSelected] : [])
                }
            }

            // Data do período escolhido
            if scope != .all {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.accent)

                        switch scope {
                        case .year:
                            YearPickerField(date: $searchDate)
                        default:
                            DatePicker("", selection: $searchDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Resumo dos resultados
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(filteredReports.count) resultado(s)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
            }

            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.22), value: scope)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: filteredReports.count)
    }

    // MARK: - Lista de relatórios (coluna direita)

    @ViewBuilder
    private var reportList: some View {
        if filteredReports.isEmpty {
            AppEmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "Sem relatórios",
                subtitle: scope == .all
                    ? "Ainda não há relatórios guardados."
                    : "Nenhum relatório para \(scopeLabel)."
            )
        } else {
            List {
                ForEach(filteredReports) { report in
                    ReportHistoryRowView(report: report)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86),
                value: filteredReports.map(\.id)
            )
        }
    }

    // MARK: - Dados

    private func loadReports() {
        reports = DatabaseManager.shared.fetchReports()
    }

    /// Apaga o ficheiro em disco **e** o registo na base de dados — sem isto
    /// a linha ficava órfã e reaparecia como "Ficheiro não encontrado".
    private func delete(at offsets: IndexSet) {
        let visible = filteredReports
        for index in offsets {
            let report = visible[index]
            try? FileManager.default.removeItem(atPath: report.filePath)
            _ = DatabaseManager.shared.deleteReport(id: report.id)
        }
        loadReports()
    }
}

// MARK: - Selector de ano compacto

/// Menu de anos (ano corrente e os 9 anteriores). O `DatePicker` do sistema não
/// tem modo "só ano", e este campo é usado no painel de pesquisa do histórico.
struct YearPickerField: View {
    @Binding var date: Date

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 9)...current).reversed()
    }

    var body: some View {
        Picker("Ano", selection: Binding(
            get: { Calendar.current.component(.year, from: date) },
            set: { newYear in
                var comps = Calendar.current.dateComponents([.month, .day], from: date)
                comps.year = newYear
                date = Calendar.current.date(from: comps) ?? date
            }
        )) {
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

// MARK: - Linha de relatório
struct ReportHistoryRowView: View {
    let report: Report

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: report.filePath)
    }

    var fileIcon: String {
        report.filePath.hasSuffix(".pdf") ? "doc.richtext.fill" : "doc.text.fill"
    }

    var fileColor: Color {
        report.filePath.hasSuffix(".pdf") ? .red : .green
    }

    var typeColor: Color {
        switch report.type {
        case .daily:   return .blue
        case .monthly: return .purple
        case .annual:  return AppTheme.brandOrange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.title2)
                .foregroundColor(fileExists ? fileColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(report.type.label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.15))
                        .foregroundColor(typeColor)
                        .cornerRadius(6)
                    Text(report.period)
                        .fontWeight(.semibold)
                }
                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !fileExists {
                    Text("Ficheiro não encontrado")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Partilhar ficheiro — sem UIKit
            if fileExists {
                ShareLink(item: URL(fileURLWithPath: report.filePath)) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .opacity(fileExists ? 1.0 : 0.5)
    }
}
