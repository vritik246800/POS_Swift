// MARK: - Card de venda no relatório (quadrado, detalhe em sheet)

import SwiftUI

/// Card quadrado de uma factura (ou grupo de facturas do mesmo cliente).
/// Pensado para viver dentro de uma `LazyVGrid` — o detalhe e a exportação
/// abrem em sheet, para o card se manter sempre com o mesmo tamanho.
struct SaleReportRowView: View {
    let sales: [Sale]

    @State private var showDetail = false

    private var lead: Sale { sales[0] }

    private var clientLabel: String {
        lead.clientName.isEmpty ? "Cliente anónimo" : lead.clientName
    }

    private var groupTotal: Double {
        sales.reduce(0) { $0 + $1.total }
    }

    private var itemCount: Int {
        sales.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: lead.clientName.isEmpty ? "person.crop.circle.dashed" : "person.crop.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accent.opacity(0.14), in: .circle)

                    Spacer(minLength: 0)

                    if sales.count > 1 {
                        Text("\(sales.count)×")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.brandPurple.opacity(0.16), in: .capsule)
                            .foregroundStyle(AppTheme.brandPurple)
                    }
                }

                Spacer(minLength: 8)

                Text(clientLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(lead.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(formatMT(groupTotal))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("\(itemCount) \(itemCount == 1 ? "item" : "itens")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .aspectRatio(1, contentMode: .fit)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clientLabel), \(formatMT(groupTotal)), \(itemCount) itens")
        .accessibilityHint("Abrir detalhe e exportar")
        .sheet(isPresented: $showDetail) {
            SaleGroupDetailView(sales: sales, clientLabel: clientLabel, groupTotal: groupTotal)
        }
    }
}

// MARK: - Detalhe do grupo + exportação

struct SaleGroupDetailView: View {
    let sales: [Sale]
    let clientLabel: String
    let groupTotal: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var csvURL: URL?
    @State private var pdfURL: URL?
    @State private var isExportingPDF = false
    @State private var showPrintOptions = false
    @State private var payments: [Payment] = []

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var itemCount: Int {
        sales.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sales) { sale in
                        invoiceCard(sale)
                    }
                }
                .padding(20)
            }

            Divider()

            actionBar
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 520)
        .animation(animation, value: csvURL)
        .animation(animation, value: pdfURL)
        .onAppear {
            payments = sales.flatMap { DatabaseManager.shared.fetchPayments(saleId: $0.id) }
        }
        .sheet(isPresented: $showPrintOptions) {
            PrintFormatSheet(sales: sales, payments: payments)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: clientLabel == "Cliente anónimo"
                      ? "person.crop.circle.dashed" : "person.crop.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accent.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(clientLabel)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                    Text("\(sales.count) \(sales.count == 1 ? "factura" : "facturas") · \(itemCount) \(itemCount == 1 ? "item" : "itens")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Fechar")
            }

            HStack {
                Text("Total")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(formatMT(groupTotal))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .padding(20)
    }

    // MARK: - Cartão de uma factura

    private func invoiceCard(_ sale: Sale) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Venda #\(sale.id)")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.14), in: .capsule)
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Label(sale.date.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !sale.clientNIF.isEmpty {
                Label("NIF \(sale.clientNIF)", systemImage: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(sale.items) { item in
                HStack(spacing: 10) {
                    Text("\(item.quantity)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 26, height: 22)
                        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))

                    Text(item.productName)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatMT(item.subtotal))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                        Text("\(item.quantity) × \(formatMT(item.unitPrice))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Divider()

            HStack {
                Text("Total da venda")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(formatMT(sale.total))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Acções

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                showPrintOptions = true
            } label: {
                Label("Reimprimir factura", systemImage: "printer.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent, in: .rect(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Escolher talão 80 mm ou folha A4 e a impressora")

            HStack(spacing: 12) {
                exportButton(
                    title: "CSV",
                    icon: "doc.text",
                    color: AppTheme.brandGreen,
                    url: csvURL,
                    busy: false
                ) {
                    csvURL = ReportService().exportGroupCSV(sales: sales)
                }

                exportButton(
                    title: "PDF",
                    icon: "doc.richtext",
                    color: AppTheme.brandOrange,
                    url: pdfURL,
                    busy: isExportingPDF
                ) {
                    isExportingPDF = true
                    Task {
                        pdfURL = await ReportService().exportGroupPDF(sales: sales)
                        isExportingPDF = false
                    }
                }
            }
        }
        .padding(20)
    }

    /// Antes de exportar mostra "gerar"; depois de existir ficheiro, vira `ShareLink`.
    @ViewBuilder
    private func exportButton(
        title: String,
        icon: String,
        color: Color,
        url: URL?,
        busy: Bool,
        generate: @escaping () -> Void
    ) -> some View {
        if let url {
            ShareLink(item: url) {
                label("Partilhar \(title)", icon: "square.and.arrow.up", color: color)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: generate) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    label(title, icon: icon, color: color)
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func label(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.14), in: .rect(cornerRadius: 10))
            .foregroundStyle(color)
    }
}
