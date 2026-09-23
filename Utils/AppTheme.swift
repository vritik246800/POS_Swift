import SwiftUI

// MARK: - Tema visual central da app
//
// Tokens de cor e componentes partilhados de UI.
// Apenas apresentação — sem lógica de negócio nem acesso à base de dados.

enum AppTheme {

    // MARK: Marca
    /// Cor de destaque da app (iguais à definida em AccentColor.colorset)
    static let accent = Color(hex: "5856D6")
    /// Roxo usado no paywall / subscrição
    static let brandPurple = Color(hex: "6B3FA0")
    /// Laranja de acção (partilha, exportação)
    static let brandOrange = Color(hex: "FF6B35")
    /// Verde de sucesso
    static let brandGreen = Color(hex: "34C759")

    // MARK: Métodos de pagamento
    /// Cor semântica de cada método de pagamento — fonte única para toda a app
    static func methodColor(_ method: PaymentMethod) -> Color {
        switch method {
        case .cash:         return .green
        case .card:         return .blue
        case .bankTransfer: return .purple
        case .mpesa:        return .red
        case .emola:        return .orange
        }
    }

    // MARK: Validade
    /// Cor semântica de cada faixa de validade — fonte única para alertas e badges.
    static func expiryColor(_ status: ExpiryStatus) -> Color {
        switch status {
        case .expired:      return .red
        case .days:         return .orange
        case .oneMonth:     return .yellow
        case .twoMonths:    return .mint
        case .threeMonths:  return .teal
        case .safe:         return .green
        case .none:         return .secondary
        }
    }

    /// Cor do produto sem categoria.
    static let noCategory = Color.secondary

    /// Paleta fixa para escolher a cor de uma categoria.
    static let categorySwatches: [String] = [
        "007AFF", "FF9500", "34C759", "5AC8FA", "AF52DE",
        "8E8E93", "FF2D55", "FFCC00", "5856D6", "30B0C7"
    ]
}

// MARK: - Category + cor

extension Category {
    var color: Color { Color(hex: colorHex) }
}

// MARK: - ExpiryStatus + cor

extension ExpiryStatus {
    var color: Color { AppTheme.expiryColor(self) }
}

// MARK: - PaymentMethod + cor

extension PaymentMethod {
    /// Cor semântica do método (ver AppTheme.methodColor)
    var color: Color { AppTheme.methodColor(self) }
}

// MARK: - Color a partir de hexadecimal

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Chip de categoria reutilizável

/// Chip com ícone + nome, na cor da categoria.
/// Fonte única do chip em toda a app: linha de produto, barras de filtro
/// (Produtos e Vendas), seleção no formulário de produto e pré-visualização
/// em `CategoryFormView`. Quem precisa de toque envolve-o num `Button`.
/// `isSelected` marca o chip activo; `showsCheckmark` acrescenta o visto
/// nas grelhas de seleção; `isLarge` dá a versão grande em vidro, usada nas
/// grelhas de escolha de categoria (formulário de produto).
struct CategoryChipView: View {
    let name: String
    let icon: String
    let color: Color
    var isSelected: Bool = false
    var showsCheckmark: Bool = false
    var isLarge: Bool = false

    var body: some View {
        HStack(spacing: isLarge ? 8 : 4) {
            Image(systemName: icon)
                .font(isLarge ? .system(size: 15, weight: .semibold) : .caption2.weight(.semibold))
            Text(name)
                .font(isLarge
                      ? .system(size: 15, weight: isSelected ? .bold : .medium)
                      : .caption.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsCheckmark {
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(isLarge ? .system(size: 14, weight: .bold) : .caption2.weight(.bold))
                }
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, isLarge ? 16 : 8)
        .padding(.vertical, isLarge ? 12 : (showsCheckmark ? 7 : 4))
        // Só a versão grande leva vidro — um chip pequeno dentro de uma linha ou
        // de um card já está sobre vidro, e vidro sobre vidro é proibido.
        .glassEffectIfLarge(isLarge)
        .background(color.opacity(isSelected ? 0.28 : (isLarge ? 0.08 : 0.12)), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(color.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension View {
    @ViewBuilder
    func glassEffectIfLarge(_ isLarge: Bool) -> some View {
        if isLarge {
            glassEffect(.regular, in: .capsule)
        } else {
            self
        }
    }
}

// MARK: - Barra de filtro por categoria (fonte única: Vendas e Produtos)

/// Barra "Todos / Filtrar" com os chips grandes de categoria a abrirem ao lado.
/// Um só scroll horizontal: com muitas categorias os botões deslizam em vez de
/// transbordarem. Um único plano de vidro por botão, tingido pela cor.
struct CategoryFilterBar: View {
    let categories: [Category]
    @Binding var selectedCategoryId: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Filtro fechado por omissão — só "Todos" e "Filtrar" à vista.
    @State private var showFilters = false

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    button(title: "Todos",
                           icon: "square.grid.2x2",
                           color: AppTheme.accent,
                           isActive: selectedCategoryId == nil && !showFilters) {
                        withAnimation(animation) {
                            selectedCategoryId = nil
                            showFilters = false
                        }
                    }

                    button(title: "Filtrar",
                           icon: "line.3.horizontal.decrease.circle",
                           color: AppTheme.brandOrange,
                           isActive: showFilters) {
                        withAnimation(animation) { showFilters.toggle() }
                    }

                    if showFilters {
                        ForEach(categories) { category in
                            button(title: category.name,
                                   icon: category.icon,
                                   color: category.color,
                                   isActive: selectedCategoryId == category.id) {
                                withAnimation(animation) {
                                    selectedCategoryId = (selectedCategoryId == category.id) ? nil : category.id
                                }
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    private func button(title: String, icon: String, color: Color,
                        isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .background(Capsule().fill(color.opacity(isActive ? 0.26 : 0.08)))
            .overlay(Capsule().strokeBorder(color.opacity(isActive ? 0.85 : 0), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Estado vazio reutilizável

/// Vista de estado vazio com ícone, título e subtítulo opcional.
/// (Nome com prefixo: já existe um `EmptyStateView` em POSStockReceiverApp.swift)
struct AppEmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.45))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}
