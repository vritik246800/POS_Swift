import SwiftUI

// MARK: - Escolha de formato + impressão

/// Folha reutilizável de impressão de facturas: escolhe-se 80 mm ou A4 e o
/// botão "Imprimir" abre o painel de impressão do sistema, onde se escolhe a
/// impressora. Usada na factura da venda e na reimpressão a partir dos relatórios.
struct PrintFormatSheet: View {
    let sales: [Sale]
    /// Pagamentos da(s) venda(s) — saem no fim do talão. Opcional.
    var payments: [Payment] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var format: ReceiptFormat = .thermal80
    @State private var isWorking = false
    @State private var errorMessage = ""

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var total: Double {
        sales.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Cabeçalho
            HStack(spacing: 12) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Imprimir factura")
                        .font(.system(size: 17, weight: .bold))
                    Text(sales.count == 1
                         ? "Factura #\(sales[0].id) · \(formatMT(total))"
                         : "\(sales.count) facturas · \(formatMT(total))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            // MARK: Formatos
            VStack(alignment: .leading, spacing: 12) {
                Text("Formato do papel")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(ReceiptFormat.allCases) { option in
                            Button {
                                withAnimation(animation) { format = option }
                            } label: {
                                formatCard(option)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(format == option ? [.isSelected] : [])
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()

            // MARK: Acções
            HStack(spacing: 12) {
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.glass)

                Spacer()

                Button {
                    startPrinting()
                } label: {
                    HStack(spacing: 7) {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "printer.fill")
                        }
                        Text(isWorking ? "A preparar…" : "Imprimir")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(AppTheme.accent, in: .rect(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isWorking || sales.isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320)
        .animation(animation, value: format)
        .animation(animation, value: errorMessage)
        .animation(animation, value: isWorking)
    }

    // MARK: - Cartão de formato

    private func formatCard(_ option: ReceiptFormat) -> some View {
        let selected = format == option
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: option.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? AppTheme.accent : .secondary)
                .frame(width: 34, height: 34)
                .background((selected ? AppTheme.accent : Color.secondary).opacity(0.14),
                            in: .rect(cornerRadius: 9))

            Text(option.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(option.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(selected ? "Seleccionado" : "Seleccionar")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? AppTheme.accent : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.accent.opacity(selected ? 0.85 : 0), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.label). \(option.detail)")
    }

    // MARK: - Impressão

    private func startPrinting() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""

        let service = ReceiptPrintService()
        guard let url = service.makeReceiptPDF(sales: sales, payments: payments, format: format) else {
            errorMessage = "Não foi possível preparar o talão."
            isWorking = false
            return
        }

        // O painel de impressão é modal — corre no main actor e só volta quando
        // o utilizador escolhe a impressora (ou cancela).
        let printed = service.printPDF(at: url, format: format)
        isWorking = false
        if printed {
            dismiss()
        } else {
            errorMessage = "Impressão cancelada ou impressora indisponível."
        }
    }
}
