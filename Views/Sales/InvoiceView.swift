import SwiftUI

struct InvoiceView: View {
    let saleId: Int
    @EnvironmentObject var saleViewModel: SaleViewModel
    @Environment(\.dismiss) var dismiss
    @State private var sale: Sale? = nil
    @State private var payments: [Payment] = []
    @State private var pdfURL: URL? = nil
    @State private var isGeneratingPDF = false
    @State private var showPrintOptions = false

    var body: some View {
        NavigationStack {
            Group {
                if let sale = sale {
                    ScrollView {
                        VStack(spacing: 24) {

                            // MARK: - Cabeçalho sucesso
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.12))
                                        .frame(width: 80, height: 80)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.green)
                                }
                                Text("Venda Concluída")
                                    .font(.system(size: 20, weight: .bold))

                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "number.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Text("Fatura #\(sale.id)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Text(sale.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.green.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            // MARK: - Dados do cliente
                            if !sale.clientName.isEmpty || !sale.clientNIF.isEmpty {
                                ClientInfoSection(sale: sale)
                            }

                            // MARK: - Artigos
                            ArticlesSection(items: sale.items)

                            // MARK: - Total
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "sum")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                    Text("Total")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Spacer()
                                Text(formatMT(sale.total))
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.blue)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.blue.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(16)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("A carregar fatura...")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Fatura")
            .toolbar {
                // MARK: - Botão Fechar (esquerda, neutro — não é acção destrutiva)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }

                // MARK: - Partilhar + Imprimir
                // Um único ToolbarItem: no macOS um segundo `.confirmationAction`
                // não chegava a ser desenhado e o botão de partilha desaparecia.
                ToolbarItem(placement: .confirmationAction) {
                    // `.fixedSize()`: sem isto a toolbar comprimia o último botão
                    // e "Imprimir" aparecia truncado ("Impri…").
                    HStack(spacing: 8) {
                        shareButton

                        Button {
                            showPrintOptions = true
                        } label: {
                            Label("Imprimir", systemImage: "printer.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(sale == nil)
                        .help("Imprimir em talão 80 mm ou folha A4")
                    }
                    .fixedSize()
                }
            }
            .onAppear { loadSale() }
            .sheet(isPresented: $showPrintOptions) {
                if let sale {
                    PrintFormatSheet(sales: [sale], payments: payments)
                }
            }
        }
        #if os(macOS)
        // Folga na largura: com a janela mais estreita a toolbar cortava o
        // botão "Imprimir".
        .frame(minWidth: 580, minHeight: 620)
        #endif
    }

    // MARK: - Botão Partilhar PDF (gera o PDF à primeira e depois partilha)
    @ViewBuilder
    private var shareButton: some View {
        if let url = pdfURL {
            ShareLink(item: url) {
                shareLabel
            }
            .buttonStyle(.plain)
        } else if isGeneratingPDF {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("A gerar...")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        } else {
            Button {
                guard let s = sale else { return }
                isGeneratingPDF = true
                Task {
                    pdfURL = await ReportService().exportGroupPDF(sales: [s])
                    isGeneratingPDF = false
                }
            } label: {
                shareLabel
            }
            .buttonStyle(.plain)
            .disabled(sale == nil)
            .help("Gerar PDF da fatura para partilhar")
        }
    }

    private var shareLabel: some View {
        Label("Partilhar", systemImage: "square.and.arrow.up")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadSale() {
        let all = saleViewModel.salesHistory.isEmpty
            ? { saleViewModel.loadSalesHistory(); return saleViewModel.salesHistory }()
            : saleViewModel.salesHistory
        sale = all.first(where: { $0.id == saleId })
        payments = DatabaseManager.shared.fetchPayments(saleId: saleId)
    }
}

// MARK: - Section Header
private struct InvoiceSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
// MARK: - Client Info Section
private struct ClientInfoSection: View {
    let sale: Sale
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InvoiceSectionHeader(icon: "person.fill", title: "Cliente")
            Divider()

            if !sale.clientName.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text(sale.clientName)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !sale.clientNIF.isEmpty {
                if !sale.clientName.isEmpty { 
                    Divider().padding(.leading, 44) 
                }
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.purple)
                        .frame(width: 20)
                    Text("NIF: \(sale.clientNIF)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Articles Section
private struct ArticlesSection: View {
    let items: [SaleItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InvoiceSectionHeader(icon: "shoppingbag.fill", title: "Artigos")
            Divider()

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { 
                    Divider().padding(.leading, 14) 
                }

                ArticleRow(item: item)
            }
        }
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Article Row
private struct ArticleRow: View {
    let item: SaleItem
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 28, height: 28)
                Text("\(item.quantity)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
            }

            Text(item.productName)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMT(item.subtotal))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\(item.quantity) × \(formatMT(item.unitPrice))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

