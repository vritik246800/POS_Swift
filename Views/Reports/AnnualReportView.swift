import SwiftUI

struct AnnualReportView: View {
    @StateObject private var reportViewModel = ReportViewModel()
    @State private var selectedYear = Date()
    @State private var searchText = ""
    @StateObject private var exportState = ReportExportState()

    private var filteredSales: [Sale] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return reportViewModel.annualSales
        }
        let q = searchText.lowercased()
        return reportViewModel.annualSales.filter { sale in
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

                // MARK: Header + Seletor de ano
                YearSelectorHeader(selectedYear: $selectedYear) {
                    searchText = ""
                    reportViewModel.loadAnnualSales(date: selectedYear)
                }

                // MARK: Cards + top de produtos (sempre sobre o total do ano, não filtrado)
                ReportSummaryHeader(
                    totalLabel: "Total Faturado no Ano",
                    totalValue: reportViewModel.total(for: reportViewModel.annualSales),
                    salesCount: reportViewModel.annualSales.count,
                    itemCount: reportViewModel.totalItems(for: reportViewModel.annualSales),
                    topProducts: reportViewModel.topProducts(for: reportViewModel.annualSales)
                )
                .padding(.horizontal, 20)

                // MARK: Gráficos do ano (barras verticais)
                if !reportViewModel.annualSales.isEmpty {
                    VStack(spacing: 16) {
                        VerticalBarsCard(
                            title: "Facturação por mês",
                            entries: reportViewModel.salesByMonth(for: reportViewModel.annualSales).map {
                                BarEntry(label: $0.month, value: $0.total, display: formatMT($0.total))
                            }
                        )
                        HStack(alignment: .top, spacing: 16) {
                            VerticalBarsCard(
                                title: "Nº de vendas por mês",
                                entries: reportViewModel.salesCountByMonth(for: reportViewModel.annualSales).map {
                                    BarEntry(label: $0.month, value: Double($0.count), display: "\($0.count)")
                                },
                                tint: AppTheme.brandGreen
                            )
                            VerticalBarsCard(
                                title: "Itens vendidos por mês",
                                entries: reportViewModel.itemsByMonth(for: reportViewModel.annualSales).map {
                                    BarEntry(label: $0.month, value: Double($0.items), display: "\($0.items)")
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
                        Text("Vendas do Ano")
                            .font(.system(size: 17, weight: .semibold))

                        Spacer()

                        SalesSearchField(text: $searchText)

                        Text("\(filteredSales.count) registos")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)

                    if filteredSales.isEmpty {
                        EmptySalesView(
                            message: searchText.isEmpty
                                ? "Sem vendas neste ano."
                                : "Sem resultados para \"\(searchText)\"."
                        )
                    } else {
                        SaleCardsGrid(groups: filteredGroupedByClient)
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Relatório Anual")
        .toolbar {
            ToolbarItem {
                ReportExportMenu(
                    state: exportState,
                    exportCSV: { ReportService().exportAnnualCSV(sales: reportViewModel.annualSales, date: selectedYear) },
                    exportPDF: { await ReportService().exportAnnualPDF(sales: reportViewModel.annualSales, date: selectedYear) }
                )
            }
        }
        .overlay(alignment: .top) { ReportExportToast(state: exportState) }
        .onAppear {
            reportViewModel.loadAnnualSales(date: selectedYear)
        }
    }
}

// A distribuição mensal passou a ser um gráfico de barras verticais
// (`VerticalBarsCard` em `ReportComponents.swift`), partilhado com o Mensal
// e com o Fecho de Caixa.
