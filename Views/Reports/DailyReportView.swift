import SwiftUI

struct DailyReportView: View {
    @StateObject private var reportViewModel = ReportViewModel()
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @StateObject private var exportState = ReportExportState()
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Filtragem reactiva por data/hora
    private var filteredSales: [Sale] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return reportViewModel.dailySales
        }
        let q = searchText.lowercased()
        return reportViewModel.dailySales.filter { sale in
            sale.date.formatted(date: .abbreviated, time: .omitted).lowercased().contains(q)
            || sale.date.formatted(date: .omitted, time: .shortened).lowercased().contains(q)
            || sale.date.formatted(date: .complete, time: .shortened).lowercased().contains(q)
        }
    }

    private var filteredGroupedByClient: [[Sale]] {
        groupSalesByClient(filteredSales)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // MARK: Seletor de data
                VStack(spacing: 6) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .onChange(of: selectedDate) {
                            searchText = ""
                            reportViewModel.loadDailySales(date: selectedDate)
                        }
                }

                // MARK: Cards de resumo + top de produtos ao lado
                // (sempre sobre o total do dia, não filtrado)
                ReportSummaryHeader(
                    totalLabel: "Total do Dia",
                    totalValue: reportViewModel.total(for: reportViewModel.dailySales),
                    salesCount: reportViewModel.dailySales.count,
                    itemCount: reportViewModel.totalItems(for: reportViewModel.dailySales),
                    topProducts: reportViewModel.topProducts(for: reportViewModel.dailySales)
                )
                .padding(.horizontal, 20)

                // MARK: Cabeçalho da lista + pesquisa inline
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Vendas do Dia")
                            .font(.system(size: 17, weight: .semibold))

                        Spacer()

                        SalesSearchField(text: $searchText)

                        Text("\(filteredSales.count) registos")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)

                    // Lista reactiva
                    if filteredSales.isEmpty {
                        EmptySalesView(
                            message: searchText.isEmpty
                                ? "Sem vendas nesta data."
                                : "Sem resultados para \"\(searchText)\"."
                        )
                    } else {
                        SaleCardsGrid(groups: filteredGroupedByClient)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Relatório Diário")
        .toolbar {
            ToolbarItem {
                ReportExportMenu(
                    state: exportState,
                    exportCSV: { ReportService().exportDailyCSV(sales: reportViewModel.dailySales, date: selectedDate) },
                    exportPDF: { await ReportService().exportDailyPDF(sales: reportViewModel.dailySales, date: selectedDate) }
                )
            }
        }
        .overlay(alignment: .top) { ReportExportToast(state: exportState) }
        .onAppear {
            reportViewModel.loadDailySales(date: selectedDate)
        }
    }

}
