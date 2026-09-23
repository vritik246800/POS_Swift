import SwiftUI

// MARK: - Produtos parados (Administração)
//
// Produtos com stock que não vendem há mais de N meses — incluindo os que nunca
// foram vendidos. Mostra os lotes parados e o capital imobilizado, e deixa
// aplicar promoção ali mesmo para os escoar.

struct StaleProductsView: View {
    @EnvironmentObject var vm: AdminViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var months: Int = 6
    @State private var promoProduct: Product? = nil

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private var stale: [StaleProduct] { vm.staleProducts(months: months) }
    private var tiedValue: Double { stale.reduce(0) { $0 + $1.tiedValue } }
    private var tiedUnits: Int { stale.reduce(0) { $0 + $1.stock } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if stale.isEmpty {
                    AppEmptyStateView(
                        icon: "checkmark.seal",
                        title: "Nada parado",
                        subtitle: "Todos os produtos com stock venderam nos últimos \(months) meses."
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                        ForEach(stale) { item in
                            card(item)
                        }
                    }
                }
            }
            .padding(16)
        }
        .animation(animation, value: months)
        .overlay(alignment: .top) { promotionOverlay }
        .onAppear { vm.load() }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                AdminKPICard(icon: "clock.arrow.circlepath", title: "Produtos parados",
                             value: "\(stale.count)",
                             detail: "sem venda há \(months)+ meses",
                             color: AppTheme.brandOrange)

                AdminKPICard(icon: "lock.square.stack", title: "Capital imobilizado",
                             value: formatCurrency(tiedValue),
                             detail: "ao preço base pago",
                             color: ExpiryStatus.expired.color)

                AdminKPICard(icon: "shippingbox", title: "Unidades paradas",
                             value: "\(tiedUnits)",
                             detail: "em stock",
                             color: AppTheme.accent)
            }

            // O rótulo do Picker era desenhado ao lado e partia em duas linhas —
            // o texto que o descreve já está à esquerda.
            HStack(spacing: 10) {
                Text("Sem venda há mais de")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker("Meses", selection: $months) {
                    ForEach([3, 6, 9, 12], id: \.self) { Text("\($0) meses").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sem venda há mais de")
        }
    }

    // MARK: - Cartão de produto parado

    private func card(_ item: StaleProduct) -> some View {
        let category = vm.categories.first { $0.id == item.product.categoryId }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: category?.icon ?? "cube.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(category?.color ?? AppTheme.noCategory)
                    .frame(width: 36, height: 36)
                    .background((category?.color ?? AppTheme.noCategory).opacity(0.14),
                                in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.product.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(item.idleLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.brandOrange)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(item.tiedValue))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ExpiryStatus.expired.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(item.stock) un. paradas")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let last = item.lastSale {
                Text("Última venda: \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Nunca foi vendido desde que entrou em stock.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(item.batches) { batch in
                HStack(spacing: 8) {
                    Text("Lote #\(batch.id)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("entrou \(batch.receivedAt.formatted(date: .numeric, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if batch.expiryStatus.isAlerting {
                        StatusBadge(text: batch.expiryStatus.label,
                                    icon: batch.expiryStatus.icon,
                                    color: batch.expiryStatus.color)
                    }
                    Spacer(minLength: 4)
                    Text("\(batch.quantity) un.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button {
                withAnimation(animation) { promoProduct = item.product }
            } label: {
                Label(item.product.hasDiscount
                      ? "Promoção activa: −\(item.product.discountPercent.formatted(.number.precision(.fractionLength(0))))%"
                      : "Fazer promoção",
                      systemImage: "tag.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .tint(AppTheme.brandGreen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Promoção

    @ViewBuilder
    private var promotionOverlay: some View {
        if let product = promoProduct {
            PromotionPanel(
                product: product,
                onApply: { percent in
                    productViewModel.applyDiscount(productId: product.id, percent: percent)
                    vm.load()
                    withAnimation(animation) { promoProduct = nil }
                },
                onCancel: { withAnimation(animation) { promoProduct = nil } }
            )
            .environmentObject(productViewModel)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(1)
        }
    }
}
