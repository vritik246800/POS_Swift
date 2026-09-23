import SwiftUI

/// Alerta de validade apresentado no arranque (tarefa 2.3).
/// Secções por faixa, da mais grave para a menos grave.
struct ExpiryAlertView: View {
    @EnvironmentObject var batchViewModel: BatchViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.dismiss) private var dismiss

    /// Fecha o alerta e leva o utilizador ao separador Produtos.
    let onShowProducts: () -> Void

    /// Faixas com lotes, ordenadas da mais grave para a menos grave.
    private var sections: [(status: ExpiryStatus, batches: [Batch])] {
        batchViewModel.expiringGroups
            .sorted { $0.key.severity > $1.key.severity }
            .map { (status: $0.key, batches: $0.value.sorted { lhs, rhs in
                (lhs.expiryDate ?? .distantFuture) < (rhs.expiryDate ?? .distantFuture)
            }) }
    }

    private func productName(_ productId: Int) -> String {
        productViewModel.products.first { $0.id == productId }?.name ?? "Produto #\(productId)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if sections.isEmpty {
                    AppEmptyStateView(
                        icon: "checkmark.seal",
                        title: "Nada a expirar",
                        subtitle: "Nenhum lote está fora do prazo nos próximos meses."
                    )
                } else {
                    List {
                        ForEach(sections, id: \.status) { section in
                            Section {
                                ForEach(section.batches) { batch in
                                    row(batch)
                                }
                            } header: {
                                Label(section.status.label, systemImage: section.status.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(section.status.color)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Validades")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dispensar hoje") {
                        batchViewModel.dismissExpiryAlertToday()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ver produtos") {
                        dismiss()
                        onShowProducts()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 460, idealHeight: 560)
        #endif
    }

    // MARK: - Cabeçalho com os totais

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                total(
                    icon: ExpiryStatus.expired.icon,
                    label: "Perda real",
                    value: batchViewModel.realLoss,
                    color: ExpiryStatus.expired.color
                )
                total(
                    icon: ExpiryStatus.days.icon,
                    label: "Em risco",
                    value: batchViewModel.riskValue,
                    color: ExpiryStatus.days.color
                )
            }
            Text("Calculado com o preço base de cada lote.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(16)
    }

    private func total(icon: String, label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(value))
                    .font(.headline)
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formatCurrency(value))")
    }

    // MARK: - Linha de lote

    private func row(_ batch: Batch) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(productName(batch.productId))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label("\(batch.quantity)", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let expiry = batch.expiryDate {
                        Label(expiry.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(batch.expiryStatus.color)
                    }
                }
            }

            Spacer()

            Text(formatCurrency(batch.lostValue))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(batch.expiryStatus.color)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
