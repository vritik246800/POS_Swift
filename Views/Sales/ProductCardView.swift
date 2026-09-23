import SwiftUI

// MARK: - Card quadrado de produto na grelha de vendas
//
// Substitui a antiga `ProductSaleRowView`. Só apresentação: a categoria e a
// faixa de validade chegam já resolvidas pelo ecrã que compõe a grelha.

struct ProductCardView: View {
    let product: Product
    let category: Category?
    /// Faixa do lote mais próximo do fim. `.none`/`.safe` não desenham badge.
    let expiryStatus: ExpiryStatus
    /// Stock dentro do prazo — é o único que se pode vender.
    let sellableStock: Int
    let onAdd: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quantity = 1

    private var isOutOfStock: Bool { sellableStock == 0 }

    /// Tem stock, mas está todo fora do prazo — não se vende.
    private var isExpiredOnly: Bool { product.stock > 0 && sellableStock == 0 }

    /// Regra herdada da antiga linha de venda: 0 = sem stock, < 5 = a acabar.
    private var stockColor: Color {
        if product.stock == 0 { return .red }
        if product.stock < 5 { return .orange }
        return AppTheme.brandGreen
    }

    private var stockIcon: String {
        if product.stock == 0 { return "xmark.circle.fill" }
        if product.stock < 5 { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var iconColor: Color { category?.color ?? AppTheme.noCategory }

    var body: some View {
        VStack(spacing: 10) {

            // 1 — Ícone da categoria
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: category?.icon ?? "cube.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityLabel(category?.name ?? "Sem categoria")

            // 2 — Nome
            Text(product.name)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)

            // 3 — Preço final (com promoção, quando existe)
            VStack(spacing: 2) {
                Text(formatCurrency(product.priceWithDiscount))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(product.hasDiscount ? AppTheme.brandGreen : AppTheme.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if product.hasDiscount {
                    HStack(spacing: 5) {
                        Text(formatCurrency(product.priceFinal))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text("−\(product.discountPercent.formatted(.number.precision(.fractionLength(0))))%")
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.brandGreen)
                    }
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            // 4 e 5 — Badges de stock e de validade
            HStack(spacing: 6) {
                badge(icon: stockIcon, text: "\(product.stock)", color: stockColor)
                    .accessibilityLabel("Stock: \(product.stock)")
                if isExpiredOnly {
                    badge(icon: ExpiryStatus.expired.icon, text: "Expirado", color: ExpiryStatus.expired.color)
                        .accessibilityLabel("Produto expirado — não pode ser vendido")
                        .help("Todo o stock está fora do prazo — não pode ser vendido.")
                } else if expiryStatus.isAlerting {
                    badge(icon: expiryStatus.icon, text: nil, color: expiryStatus.color)
                        .accessibilityLabel(expiryStatus.label)
                        .help(expiryStatus.label)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }

            Spacer(minLength: 0)

            // 6 — Stepper compacto + Adicionar
            HStack(spacing: 12) {
                stepButton("minus", enabled: quantity > 1) { quantity -= 1 }
                Text("\(quantity)")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 30)
                stepButton("plus", enabled: quantity < max(1, sellableStock)) { quantity += 1 }
            }
            .disabled(isOutOfStock)

            Button {
                onAdd(quantity)
                quantity = 1
            } label: {
                Label(isExpiredOnly ? "Expirado" : "Adicionar",
                      systemImage: isExpiredOnly ? "xmark.octagon.fill" : "cart.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(isExpiredOnly ? ExpiryStatus.expired.color.opacity(0.55)
                                : isOutOfStock ? AppTheme.brandGreen.opacity(0.35)
                                : AppTheme.brandGreen,
                                in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isOutOfStock)
        }
        .padding(14)
        // Altura mínima em vez de `aspectRatio(1)`: o quadrado encolhia o card
        // ao ponto de o nome e o preço ficarem ilegíveis em grelhas estreitas.
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .top)
        // Um único plano de vidro por card — nada de vidro dentro de vidro.
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .opacity(isOutOfStock ? (isExpiredOnly ? 0.6 : 0.4) : 1.0)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.2), value: quantity)
        .animation(.easeInOut(duration: 0.2), value: product.stock)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.3), value: product.discountPercent)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Peças

    @ViewBuilder
    private func badge(icon: String, text: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            if let text {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: .capsule)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? AppTheme.accent : Color.secondary)
                .background(Color.secondary.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "Diminuir quantidade" : "Aumentar quantidade")
    }
}
