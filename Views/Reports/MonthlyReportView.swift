import SwiftUI

struct MonthlyReportView: View {
    @StateObject private var reportViewModel = ReportViewModel()
    @State private var selectedMonth = Date()
    @State private var searchText = ""
    @StateObject private var exportState = ReportExportState()

    private var filteredSales: [Sale] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return reportViewModel.monthlySales
        }
        let q = searchText.lowercased()
        return reportViewModel.monthlySales.filter { sale in
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

                // MARK: Header + Seletor de mês
                MonthSelectorHeader(selectedMonth: $selectedMonth) {
                    searchText = ""
                    reportViewModel.loadMonthlySales(date: selectedMonth)
                }

                // MARK: Cards + top de produtos (sempre sobre o total do mês, não filtrado)
                ReportSummaryHeader(
                    totalLabel: "Total Faturado",
                    totalValue: reportViewModel.total(for: reportViewModel.monthlySales),
                    salesCount: reportViewModel.monthlySales.count,
                    itemCount: reportViewModel.totalItems(for: reportViewModel.monthlySales),
                    topProducts: reportViewModel.topProducts(for: reportViewModel.monthlySales)
                )
                .padding(.horizontal, 20)

                // MARK: Gráficos do mês (facturação, nº de vendas e itens por dia)
                if !reportViewModel.monthlySales.isEmpty {
                    VStack(spacing: 16) {
                        VerticalBarsCard(
                            title: "Facturação por dia",
                            entries: reportViewModel.salesByDay(for: reportViewModel.monthlySales).map {
                                BarEntry(label: $0.day, value: $0.total, display: formatMT($0.total))
                            }
                        )
                        HStack(alignment: .top, spacing: 16) {
                            VerticalBarsCard(
                                title: "Nº de vendas por dia",
                                entries: reportViewModel.salesCountByDay(for: reportViewModel.monthlySales).map {
                                    BarEntry(label: $0.day, value: Double($0.count), display: "\($0.count)")
                                },
                                tint: AppTheme.brandGreen
                            )
                            VerticalBarsCard(
                                title: "Itens vendidos por dia",
                                entries: reportViewModel.itemsByDay(for: reportViewModel.monthlySales).map {
                                    BarEntry(label: $0.day, value: Double($0.items), display: "\($0.items)")
                                },
                                tint: AppTheme.brandOrange
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // MARK: Cabeçalho da lista + pesquisa inline
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("Vendas do Mês")
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
                                ? "Sem vendas neste mês."
                                : "Sem resultados para \"\(searchText)\"."
                        )
                    } else {
                        SaleCardsGrid(groups: filteredGroupedByClient)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Relatório Mensal")
        .toolbar {
            ToolbarItem {
                ReportExportMenu(
                    state: exportState,
                    exportCSV: { ReportService().exportMonthlyCSV(sales: reportViewModel.monthlySales, date: selectedMonth) },
                    exportPDF: { await ReportService().exportMonthlyPDF(sales: reportViewModel.monthlySales, date: selectedMonth) }
                )
            }
        }
        .overlay(alignment: .top) { ReportExportToast(state: exportState) }
        .onAppear {
            reportViewModel.loadMonthlySales(date: selectedMonth)
        }
    }

}
