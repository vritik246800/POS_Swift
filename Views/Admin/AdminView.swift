import SwiftUI

// MARK: - Área de Administração
//
// Vive entre "Fecho de Caixa" e "Definições" e só existe para o perfil Admin.
// Junta tudo o que é gestão da loja e não é operação de balcão:
// dashboard, validade, produtos parados e os dois históricos (fechos e relatórios).

struct AdminView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @StateObject private var vm = AdminViewModel()
    @StateObject private var closeViewModel = DayCloseViewModel()
    @State private var section: Section = .dashboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case expiry    = "Validade"
        case stale     = "Parados"
        case closes    = "Fechos"
        case reports   = "Relatórios"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.xaxis"
            case .expiry:    return "clock.badge.exclamationmark"
            case .stale:     return "shippingbox"
            case .closes:    return "lock.circle"
            case .reports:   return "doc.text"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Secção", selection: $section) {
                ForEach(Section.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch section {
                case .dashboard: AdminDashboardView().environmentObject(vm)
                case .expiry:    AdminExpiryView().environmentObject(vm).environmentObject(productViewModel)
                case .stale:     StaleProductsView().environmentObject(vm).environmentObject(productViewModel)
                case .closes:    CloseHistoryView().environmentObject(closeViewModel)
                case .reports:   ReportHistoryView()
                }
            }
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
        .navigationTitle("Administração")
        .onAppear { vm.load() }
    }
}

// MARK: - Componentes partilhados da Administração

/// Cartão de indicador: valor grande, rótulo em cima, ícone com a cor do tema.
///
/// `prominent` é o indicador herói de uma secção (o que se lê primeiro): mesmo cartão,
/// mesmo vidro neutro, só maior. O destaque é por tamanho e não por cor de fundo —
/// a Administração tem um único plano de vidro `.regular` em todos os cartões.
struct AdminKPICard: View {
    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    let color: Color
    var prominent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 12 : 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: prominent ? 17 : 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: prominent ? 36 : 30, height: prominent ? 36 : 30)
                    .background(color.opacity(0.14), in: .rect(cornerRadius: prominent ? 11 : 9))
                Text(title)
                    .font(.system(size: prominent ? 12 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: prominent ? 34 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())

            if let detail {
                Text(detail)
                    .font(.system(size: prominent ? 12 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(prominent ? 20 : 14)
        // Estica à altura da linha da grelha para o vidro dos cartões vizinhos alinhar.
        // O conteúdo fica em cima (`alignment: .topLeading`) — sem `Spacer`, que na ronda
        // anterior deixava um vazio grande entre o rótulo e o valor.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Um só plano de vidro, igual em toda a Administração.
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Bloco com título e conteúdo — a unidade de composição do dashboard.
struct AdminPanel<Content: View>: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Barra proporcional usada nos tops (produtos, categorias, métodos).
struct AdminProportionRow: View {
    let label: String
    let value: String
    let fraction: Double
    let color: Color
    var icon: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.12))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * (grown ? min(max(fraction, 0), 1) : 0))
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { grown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
