import SwiftUI

// MARK: - Validade e stock (Administração)
//
// Substitui os cartões de estado e o painel lateral que viviam na lista de
// Produtos. Aqui há espaço para mostrar o produto **e** os seus lotes, com a
// acção de promoção à mão.

struct AdminExpiryView: View {
    @EnvironmentObject var vm: AdminViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scope: Scope = .risk
    @State private var promoProduct: Product? = nil
    /// Lote em edição (validade e quantidade) — separadores "Em risco" e "Expirados".
    @State private var editingBatch: Batch? = nil
    /// Produto em reposição de stock — separador "Stock baixo".
    @State private var stockProduct: Product? = nil

    enum Scope: String, CaseIterable, Identifiable {
        case risk = "Em risco"
        case expired = "Expirados"
        case lowStock = "Stock baixo"

        var id: String { rawValue }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCards
                scopePicker
                content

                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ExpiryStatus.expired.color)
                        .transition(.opacity)
                }
            }
            .padding(16)
        }
        .animation(animation, value: scope)
        .overlay(alignment: .top) { promotionOverlay }
        .sheet(item: $editingBatch) { batch in
            BatchEditSheet(batch: batch, productName: vm.productName(batch.productId)) { edited in
                vm.updateBatch(edited)
            }
        }
        .sheet(item: $stockProduct) { product in
            StockEditSheet(product: product) { newStock in
                vm.updateStock(productId: product.id, newStock: newStock)
            }
        }
        .onAppear { vm.load() }
    }

    // MARK: - Resumo

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            AdminKPICard(icon: ExpiryStatus.expired.icon, title: "Perda real",
                         value: formatCurrency(vm.realLoss),
                         detail: "\(vm.expiredBatches.count) lote(s) expirado(s)",
                         color: ExpiryStatus.expired.color)

            AdminKPICard(icon: ExpiryStatus.days.icon, title: "Em risco",
                         value: formatCurrency(vm.riskValue),
                         detail: "\(vm.riskBatches.count) lote(s) por escoar",
                         color: ExpiryStatus.days.color)

            AdminKPICard(icon: "shippingbox.and.arrow.backward.fill", title: "Stock baixo (≤ 10)",
                         value: "\(vm.lowStockProducts.count) produto(s)",
                         detail: "repor antes de esgotar",
                         color: AppTheme.brandOrange)
        }
    }

    private var scopePicker: some View {
        Picker("Secção", selection: $scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .risk:
            riskSection

        case .expired:
            entryGrid(vm.lossEntries,
                      emptyTitle: "Sem perdas",
                      emptySubtitle: "Nenhum lote expirou.")

        case .lowStock:
            lowStockGrid
        }
    }

    // MARK: - Em risco
    //
    // Aqui a pergunta é "o que tenho de escoar primeiro" — por isso a ordem é a
    // do prazo (mais urgente em cima) e não a do valor, e cada produto diz em
    // quantos dias parte o lote mais próximo.

    /// Dias até o lote expirar. `nil` quando o lote não tem validade.
    private func daysLeft(_ batch: Batch) -> Int? {
        guard let expiry = batch.expiryDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: Date()),
                                       to: calendar.startOfDay(for: expiry)).day
    }

    /// Data do lote que expira mais cedo dentro do produto.
    private func firstExpiry(_ entry: ProductRiskEntry) -> Date {
        entry.batches.compactMap(\.expiryDate).min() ?? .distantFuture
    }

    private func urgencyLabel(_ entry: ProductRiskEntry) -> String {
        guard let batch = entry.batches.min(by: { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }),
              let days = daysLeft(batch) else { return "Sem data de validade" }
        switch days {
        case ..<0:  return "Expirou há \(-days) dia(s)"
        case 0:     return "Expira hoje"
        case 1:     return "Falta 1 dia"
        default:    return "Faltam \(days) dias"
        }
    }

    /// Do prazo mais curto para o mais longo; empate desempata pelo valor.
    private var urgentRiskEntries: [ProductRiskEntry] {
        vm.riskEntries.sorted {
            let a = firstExpiry($0), b = firstExpiry($1)
            if a != b { return a < b }
            return $0.totalValue > $1.totalValue
        }
    }

    @ViewBuilder
    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !vm.riskBreakdown.isEmpty {
                riskBandsPanel
            }
            entryGrid(urgentRiskEntries,
                      emptyTitle: "Nada em risco",
                      emptySubtitle: "Nenhum lote está a aproximar-se do fim do prazo.")
        }
    }

    /// Uma só barra repartida pelas faixas + legenda com lotes e valor.
    /// Substitui as barras soltas: com uma faixa só, a barra antiga era sempre
    /// 100% e não dizia nada.
    private var riskBandsPanel: some View {
        AdminPanel(title: "Prioridade de escoamento",
                   icon: "timer",
                   subtitle: "\(vm.riskBatches.count) lote(s) · \(formatCurrency(vm.riskValue)) em risco") {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(vm.riskBreakdown, id: \.status) { item in
                            Capsule()
                                .fill(item.status.color.gradient)
                                .frame(width: max(6, geo.size.width * fraction(item.total)))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
                .animation(animation, value: vm.riskValue)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 8) {
                    ForEach(vm.riskBreakdown, id: \.status) { item in
                        let lotes = vm.riskBatches.filter { $0.expiryStatus == item.status }.count
                        HStack(spacing: 8) {
                            Image(systemName: item.status.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.status.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.status.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(lotes) lote(s) · \(percentText(item.total))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(formatCurrency(item.total))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(item.status.color)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func fraction(_ value: Double) -> Double {
        vm.riskValue > 0 ? min(max(value / vm.riskValue, 0), 1) : 0
    }

    private func percentText(_ value: Double) -> String {
        (fraction(value) * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    // MARK: - Cartões de produto (em risco e expirados)

    @ViewBuilder
    private func entryGrid(_ entries: [ProductRiskEntry], emptyTitle: String, emptySubtitle: String) -> some View {
        if entries.isEmpty {
            AppEmptyStateView(icon: "checkmark.seal", title: emptyTitle, subtitle: emptySubtitle)
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(entries) { entry in
                    entryCard(entry)
                }
            }
        }
    }

    private func entryCard(_ entry: ProductRiskEntry) -> some View {
        let product = vm.products.first { $0.id == entry.productId }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.worstStatus.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.worstStatus.color)
                    .frame(width: 28, height: 28)
                    .background(entry.worstStatus.color.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text("\(entry.batches.count) lote(s) · \(entry.totalQuantity) un.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(formatCurrency(entry.totalValue))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(entry.worstStatus.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            // Quanto tempo falta — a informação que decide a acção.
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                Text(urgencyLabel(entry))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(entry.worstStatus.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(entry.worstStatus.color.opacity(0.14), in: Capsule())

            Divider()

            // Cada lote é tocável: abre a correcção de validade e quantidade.
            ForEach(entry.batches) { batch in
                Button {
                    editingBatch = batch
                } label: {
                    HStack(spacing: 8) {
                        Text("Lote #\(batch.id)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        StatusBadge(text: batch.expiryStatus.label,
                                    icon: batch.expiryStatus.icon,
                                    color: batch.expiryStatus.color)
                        if let expiry = batch.expiryDate {
                            Text(expiry.formatted(date: .numeric, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        Text("\(batch.quantity) un.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(formatCurrency(batch.lostValue))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Actualizar lote e validade")
                .accessibilityLabel("Lote \(batch.id), \(batch.expiryStatus.label). Actualizar lote e validade.")
            }

            // A promoção só ajuda enquanto o produto ainda se pode vender.
            if let product, entry.worstStatus != .expired {
                Button {
                    withAnimation(animation) { promoProduct = product }
                } label: {
                    Label(product.hasDiscount
                          ? "Promoção activa: −\(product.discountPercent.formatted(.number.precision(.fractionLength(0))))%"
                          : "Fazer promoção",
                          systemImage: "tag.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glass)
                .tint(AppTheme.brandGreen)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stock baixo

    @ViewBuilder
    private var lowStockGrid: some View {
        if vm.lowStockProducts.isEmpty {
            AppEmptyStateView(icon: "checkmark.seal",
                              title: "Stock em ordem",
                              subtitle: "Nenhum produto está abaixo de 10 unidades.")
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                ForEach(vm.lowStockProducts) { product in
                    Button {
                        stockProduct = product
                    } label: {
                        HStack(spacing: 12) {
                            let category = vm.categories.first { $0.id == product.categoryId }
                            Image(systemName: category?.icon ?? "cube.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(category?.color ?? AppTheme.noCategory)
                                .frame(width: 34, height: 34)
                                .background((category?.color ?? AppTheme.noCategory).opacity(0.14),
                                            in: .rect(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(formatCurrency(product.priceWithDiscount))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            Spacer(minLength: 8)

                            StatusBadge(
                                text: product.stock == 0 ? "Sem stock" : "\(product.stock) un.",
                                icon: product.stock == 0 ? "xmark.circle.fill" : "exclamationmark.circle.fill",
                                color: product.stock == 0 ? ExpiryStatus.expired.color : AppTheme.brandOrange
                            )

                            Image(systemName: "plus.forwardslash.minus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Actualizar stock deste produto")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(product.name), \(product.stock) unidades. Actualizar stock.")
                }
            }
        }
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

// MARK: - Peças partilhadas das folhas de edição

/// Cabeçalho comum às folhas da Administração: ícone tingido pelo estado,
/// sobretítulo, nome e, à direita, o selo do estado actual.
private struct EditSheetHeader: View {
    let icon: String
    let tint: Color
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 13))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.9)
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.16), in: Capsule())
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rodapé comum: cancelar em vidro à esquerda, acção principal à direita.
private struct EditSheetFooter: View {
    let saveTitle: String
    let saveDisabled: Bool
    let tint: Color
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.glass)
                    .controlSize(.large)

                Spacer(minLength: 0)

                Button(action: onSave) {
                    Label(saveTitle, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(tint)
                .disabled(saveDisabled)
            }
        }
    }
}

/// Linha de valor com passo em vidro: `−` valor `+`. Substitui o `Stepper`
/// minúsculo do macOS, que num painel deste tamanho era o alvo mais difícil.
private struct StepperField: View {
    let label: String
    @Binding var value: Int
    let tint: Color
    var range: ClosedRange<Int> = 0...100_000

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    stepButton("minus", by: -1)

                    TextField("0", value: $value, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 74)
                        .contentTransition(.numericText())

                    stepButton("plus", by: 1)
                }
            }
        }
    }

    private func stepButton(_ icon: String, by delta: Int) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .tint(tint)
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
        .accessibilityLabel(delta < 0 ? "Diminuir \(label)" : "Aumentar \(label)")
    }
}

// MARK: - Correcção de um lote (quantidade + validade)

/// Aberta a partir dos separadores "Em risco" e "Expirados": é onde se corrige
/// a data de validade de um lote mal introduzido ou se acerta a quantidade que
/// ainda existe em prateleira.
struct BatchEditSheet: View {
    let batch: Batch
    let productName: String
    let onSave: (Batch) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quantity: Int
    @State private var hasExpiry: Bool
    @State private var expiry: Date

    init(batch: Batch, productName: String, onSave: @escaping (Batch) -> Void) {
        self.batch = batch
        self.productName = productName
        self.onSave = onSave
        _quantity = State(initialValue: batch.quantity)
        _hasExpiry = State(initialValue: batch.expiryDate != nil)
        _expiry = State(initialValue: batch.expiryDate ?? Date())
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var status: ExpiryStatus {
        ExpiryStatus.from(expiryDate: hasExpiry ? expiry : nil)
    }

    /// Dias que faltam — o rótulo genérico ("Expira em dias") não chegava para decidir.
    private var deadlineLabel: String {
        guard hasExpiry else { return "Sem data de validade" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: expiry)).day ?? 0
        switch days {
        case ..<0:  return "Expirou há \(-days) dia(s)"
        case 0:     return "Expira hoje"
        case 1:     return "Falta 1 dia"
        default:    return "Faltam \(days) dias"
        }
    }

    private var delta: Int { quantity - batch.quantity }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditSheetHeader(icon: status.icon,
                            tint: status.color,
                            eyebrow: "Lote #\(batch.id)",
                            title: productName,
                            subtitle: "\(batch.quantity) un. em prateleira",
                            badge: status.label)

            VStack(alignment: .leading, spacing: 14) {
                StepperField(label: "Quantidade", value: $quantity, tint: status.color)

                if delta != 0 {
                    Text(delta > 0 ? "+\(delta) un. face ao lote actual" : "\(delta) un. face ao lote actual")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(delta > 0 ? AppTheme.brandGreen : AppTheme.brandOrange)
                        .transition(.opacity)
                }

                Divider()

                Toggle("Tem data de validade", isOn: $hasExpiry.animation(animation))
                    .font(.system(size: 13, weight: .semibold))
                    .toggleStyle(.switch)
                    .tint(status.color)

                if hasExpiry {
                    HStack(spacing: 10) {
                        DatePicker("Validade", selection: $expiry, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Text(deadlineLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(status.color)
                        Spacer(minLength: 0)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(status.color.opacity(0.10)), in: .rect(cornerRadius: 18))

            Label("O stock do produto é a soma dos lotes — mexer aqui actualiza-o.",
                  systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            EditSheetFooter(saveTitle: "Guardar lote",
                            saveDisabled: quantity < 0,
                            tint: status.color,
                            onCancel: { dismiss() },
                            onSave: {
                                var edited = batch
                                edited.quantity = max(0, quantity)
                                edited.expiryDate = hasExpiry ? expiry : nil
                                onSave(edited)
                                dismiss()
                            })
        }
        .padding(22)
        .frame(minWidth: 420)
        .animation(animation, value: hasExpiry)
        .animation(animation, value: quantity)
        .animation(animation, value: expiry)
    }
}

// MARK: - Reposição de stock

/// Aberta a partir do separador "Stock baixo": repõe o stock de um produto sem
/// obrigar a ir ao formulário completo do catálogo.
struct StockEditSheet: View {
    let product: Product
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stock: Int

    init(product: Product, onSave: @escaping (Int) -> Void) {
        self.product = product
        self.onSave = onSave
        _stock = State(initialValue: product.stock)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var tint: Color {
        product.stock == 0 ? ExpiryStatus.expired.color : AppTheme.brandOrange
    }

    private var delta: Int { stock - product.stock }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditSheetHeader(icon: product.stock == 0 ? "xmark.circle.fill" : "shippingbox.and.arrow.backward.fill",
                            tint: tint,
                            eyebrow: "Stock baixo",
                            title: product.name,
                            subtitle: "Actual: \(product.stock) un.",
                            badge: delta == 0 ? nil : (delta > 0 ? "+\(delta) un." : "\(delta) un."))

            VStack(alignment: .leading, spacing: 14) {
                StepperField(label: "Novo stock", value: $stock, tint: tint)

                Divider()

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([5, 10, 20, 50], id: \.self) { step in
                            Button {
                                stock += step
                            } label: {
                                Text("+\(step)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .tint(tint)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: 18))

            Label("A subida entra no lote sem validade (criado se não existir); a descida sai dos lotes mais antigos primeiro.",
                  systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            EditSheetFooter(saveTitle: "Guardar stock",
                            saveDisabled: stock < 0 || stock == product.stock,
                            tint: tint,
                            onCancel: { dismiss() },
                            onSave: {
                                onSave(max(0, stock))
                                dismiss()
                            })
        }
        .padding(22)
        .frame(minWidth: 420)
        .animation(animation, value: stock)
    }
}
