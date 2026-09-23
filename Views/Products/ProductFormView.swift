import SwiftUI

// MARK: - Formulário de produto — wizard de 2 passos
//
// Passo 1: Identificação (nome, código de barras, categoria)
// Passo 2: Preços, stock e lote (em `.edit` mostra os lotes existentes)
//
// Janela larga na sheet para não haver scroll. A API pública (`mode`) não muda:
// é chamada a partir de `ProductListView`.

struct ProductFormView: View {
    enum Mode {
        case create
        case edit(Product)
    }

    let mode: Mode
    @EnvironmentObject var productViewModel: ProductViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var batchViewModel: BatchViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Passo 1
    @State private var name: String = ""
    @State private var barcode: String = ""
    @State private var categoryId: Int?

    // Passo 2
    @State private var priceBase: Double = 0.0
    @State private var ivaRate: Double = Constants.defaultIVARate
    @State private var profitMargin: Double = 0.0
    @State private var stock: Int = 0
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var neverExpires: Bool = true

    // Estado do wizard
    @State private var step: Int = 1
    @State private var showScanner = false
    @State private var showNewBatch = false
    @State private var newBatchQuantity: Int = 1
    @State private var newBatchExpires: Bool = false
    @State private var newBatchDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

    // MARK: - Derivados

    var priceFinal: Double {
        Product.calculateFinalPrice(base: priceBase, profit: profitMargin, iva: ivaRate)
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editedProduct: Product? {
        if case .edit(let product) = mode { return product }
        return nil
    }

    var priceWithMargin: Double {
        priceBase * (1 + profitMargin / 100)
    }

    var ivaAmount: Double {
        priceFinal - priceWithMargin
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && priceBase > 0
    }

    private var canAdvance: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Razão visível de o botão estar desativado (STYLE_GUIDE §8).
    private var saveBlockedReason: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Indica o nome do produto." }
        if priceBase <= 0 { return "O preço base tem de ser maior que zero." }
        return nil
    }

    private var productBatches: [Batch] {
        guard let id = editedProduct?.id else { return [] }
        return batchViewModel.batches(for: id).sorted { lhs, rhs in
            switch (lhs.expiryDate, rhs.expiryDate) {
            case let (l?, r?): return l < r
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return lhs.receivedAt < rhs.receivedAt
            }
        }
    }

    // MARK: - Corpo

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                Divider()

                Group {
                    if step == 1 {
                        stepIdentification
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        stepPricing
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.25), value: step)

                if !productViewModel.errorMessage.isEmpty || !batchViewModel.errorMessage.isEmpty {
                    errorBanner
                }

                Divider()

                footer
            }
            .navigationTitle(isEditing ? "Editar Produto" : "Novo Produto")
            .onAppear {
                loadExistingData()
                categoryViewModel.loadCategories()
                batchViewModel.loadBatches()
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView(scannedCode: $barcode)
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560)
        #endif
    }

    // MARK: - Indicador de progresso

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            stepBadge(number: 1, title: "Identificação")
            Rectangle()
                .fill(step > 1 ? AppTheme.accent : Color.secondary.opacity(0.25))
                .frame(height: 2)
                .frame(maxWidth: .infinity)
            stepBadge(number: 2, title: "Preços & Stock")
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func stepBadge(number: Int, title: String) -> some View {
        let isActive = step == number
        let isDone = step > number
        // Passo já concluído é clicável para voltar; avançar exige nome preenchido.
        let reachable = isDone || isActive || canAdvance

        return Button {
            if reachable { step = number }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive || isDone ? AppTheme.accent : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isActive ? .white : .secondary)
                    }
                }
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!reachable)
        .accessibilityLabel("Passo \(number): \(title)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Passo 1 — Identificação

    private var stepIdentification: some View {
        HStack(alignment: .top, spacing: 24) {

            VStack(alignment: .leading, spacing: 16) {
                fieldLabel("Nome do produto", icon: "tag.fill", color: AppTheme.accent)
                TextField("Ex.: Água 1,5 L", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))

                fieldLabel("Código de barras (opcional)", icon: "barcode", color: .secondary)
                HStack(spacing: 8) {
                    TextField("Ler ou escrever", text: $barcode)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .font(.system(size: 15))
                    if !barcode.isEmpty {
                        Button { barcode = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Limpar código de barras")
                    }
                    Button { showScanner = true } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ler código de barras")
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Categoria", icon: "square.grid.2x2", color: AppTheme.accent)

                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], alignment: .leading, spacing: 12) {
                        Button { categoryId = nil } label: {
                            CategoryChipView(
                                name: "Sem categoria",
                                icon: "cube.fill",
                                color: AppTheme.noCategory,
                                isSelected: categoryId == nil,
                                showsCheckmark: true,
                                isLarge: true
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(categoryViewModel.categories) { category in
                            Button { categoryId = category.id } label: {
                                CategoryChipView(
                                    name: category.name,
                                    icon: category.icon,
                                    color: category.color,
                                    isSelected: categoryId == category.id,
                                    showsCheckmark: true,
                                    isLarge: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.8),
                           value: categoryId)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    // MARK: - Passo 2 — Preços, stock e lote

    private var stepPricing: some View {
        HStack(alignment: .top, spacing: 24) {

            // Coluna esquerda — preços
            VStack(alignment: .leading, spacing: 18) {
                fieldLabel("Preço base", icon: "eurosign.circle.fill", color: AppTheme.brandGreen)
                HStack(spacing: 8) {
                    TextField("0.00", value: $priceBase, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(currentCurrencySymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))

                slider(title: "IVA", value: $ivaRate, range: 0...30,
                       icon: "percent", color: .purple)

                slider(title: "Margem de lucro", value: $profitMargin, range: 0...200,
                       icon: "chart.line.uptrend.xyaxis", color: AppTheme.brandGreen)

                // Resumo do preço final
                VStack(spacing: 8) {
                    summaryLine("Preço base", priceBase)
                    summaryLine("Com margem (\(String(format: "%.0f", profitMargin))%)", priceWithMargin)
                    summaryLine("IVA (\(String(format: "%.0f", ivaRate))%)", ivaAmount)
                    Divider()
                    HStack {
                        Label("Preço final", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(formatCurrency(priceFinal))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.28), AppTheme.accent.opacity(0.06)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .animation(.easeInOut(duration: 0.15), value: priceFinal)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Coluna direita — stock e lotes
            VStack(alignment: .leading, spacing: 14) {
                if isEditing {
                    batchesSection
                } else {
                    firstBatchSection
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    /// Modo criar: quantidade + validade do primeiro lote.
    private var firstBatchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("Primeiro lote", icon: "shippingbox.fill", color: AppTheme.brandOrange)

            Stepper("Quantidade: \(stock)", value: $stock, in: 0...99999)
                .font(.system(size: 14))

            Toggle("Não expira", isOn: $neverExpires.animation(.easeInOut(duration: 0.15)))
                .font(.system(size: 14))

            if !neverExpires {
                DatePicker("Validade", selection: $expiryDate, in: Date()..., displayedComponents: .date)
                    .font(.system(size: 14))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("O stock inicial é registado como um lote. A perda é calculada com o preço base deste lote.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Modo editar: lista de lotes existentes, editáveis.
    private var batchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("Lotes", icon: "shippingbox.fill", color: AppTheme.brandOrange)
                Spacer()
                Text("Stock: \(productBatches.reduce(0) { $0 + $1.quantity })")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if productBatches.isEmpty && !showNewBatch {
                Text("Sem lotes registados.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(productBatches) { batch in
                            BatchEditRow(
                                batch: batch,
                                // O stock do produto é derivado dos lotes: recarregar a
                                // lista de produtos mantém a linha de Produtos em dia.
                                onCommit: {
                                    batchViewModel.update($0)
                                    productViewModel.loadProducts()
                                },
                                onDelete: {
                                    batchViewModel.delete(id: batch.id)
                                    productViewModel.loadProducts()
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                }
                .frame(maxHeight: 240)
                .animation(.easeInOut(duration: 0.2), value: productBatches.count)
            }

            if showNewBatch {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Quantidade: \(newBatchQuantity)", value: $newBatchQuantity, in: 1...99999)
                        .font(.system(size: 13))
                    Toggle("Tem validade", isOn: $newBatchExpires.animation(.easeInOut(duration: 0.15)))
                        .font(.system(size: 13))
                    if newBatchExpires {
                        DatePicker("Validade", selection: $newBatchDate, in: Date()..., displayedComponents: .date)
                            .font(.system(size: 13))
                    }
                    HStack(spacing: 8) {
                        Button("Cancelar") { showNewBatch = false }
                            .buttonStyle(.glass)
                        Button("Guardar lote") { addBatch() }
                            .buttonStyle(.glass)
                            .tint(AppTheme.brandGreen)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    newBatchQuantity = 1
                    newBatchExpires = false
                    showNewBatch = true
                } label: {
                    Label("Adicionar lote", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: showNewBatch)
    }

    // MARK: - Rodapé fixo

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 1 {
                Button {
                    step = 1
                } label: {
                    Label("Voltar", systemImage: "chevron.left")
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            Spacer()

            if let reason = saveBlockedReason, step == 2 {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button("Cancelar") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

            if step == 1 {
                Button {
                    step = 2
                } label: {
                    Label("Seguinte", systemImage: "chevron.right")
                }
                .buttonStyle(.glass)
                .tint(AppTheme.accent)
                .disabled(!canAdvance)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    saveProduct()
                } label: {
                    Label(isEditing ? "Guardar" : "Criar", systemImage: "checkmark")
                }
                .buttonStyle(.glass)
                .tint(AppTheme.brandGreen)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(productViewModel.errorMessage.isEmpty ? batchViewModel.errorMessage : productViewModel.errorMessage)
                .foregroundStyle(.red)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .transition(.opacity)
    }

    // MARK: - Peças reutilizadas

    private func fieldLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel(title, icon: icon, color: color)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.0f")%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .tint(color)
        }
    }

    private func summaryLine(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatCurrency(value))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
    }

    // MARK: - Dados

    private func loadExistingData() {
        guard let product = editedProduct else { return }
        name = product.name
        barcode = product.barcode
        priceBase = product.priceBase
        ivaRate = product.ivaRate
        profitMargin = product.profitMargin
        stock = product.stock
        categoryId = product.categoryId
    }

    private func addBatch() {
        guard let productId = editedProduct?.id else { return }
        let ok = batchViewModel.create(
            productId: productId,
            quantity: newBatchQuantity,
            priceBase: priceBase,
            expiryDate: newBatchExpires ? newBatchDate : nil
        )
        if ok {
            showNewBatch = false
            productViewModel.loadProducts()
        }
    }

    private func saveProduct() {
        if var updated = editedProduct {
            updated.name = name
            updated.barcode = barcode
            updated.priceBase = priceBase
            updated.ivaRate = ivaRate
            updated.profitMargin = profitMargin
            updated.priceFinal = priceFinal
            updated.categoryId = categoryId
            // `stock` é derivado dos lotes — editado na secção de lotes, não aqui.
            if productViewModel.updateProduct(updated) { dismiss() }
        } else {
            let created = productViewModel.createProduct(
                name: name,
                barcode: barcode,
                priceBase: priceBase,
                ivaRate: ivaRate,
                profitMargin: profitMargin,
                stock: stock,
                categoryId: categoryId,
                expiryDate: neverExpires ? nil : expiryDate
            )
            if created {
                batchViewModel.loadBatches()
                dismiss()
            }
        }
    }
}

// MARK: - Linha de lote editável
private struct BatchEditRow: View {
    let batch: Batch
    let onCommit: (Batch) -> Void
    let onDelete: () -> Void

    @State private var quantity: Int
    @State private var expires: Bool
    @State private var date: Date

    init(batch: Batch, onCommit: @escaping (Batch) -> Void, onDelete: @escaping () -> Void) {
        self.batch = batch
        self.onCommit = onCommit
        self.onDelete = onDelete
        _quantity = State(initialValue: batch.quantity)
        _expires = State(initialValue: batch.expiryDate != nil)
        _date = State(initialValue: batch.expiryDate ?? Date())
    }

    private var status: ExpiryStatus {
        ExpiryStatus.from(expiryDate: expires ? date : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                Text(status.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(status.color)
                Spacer()
                Text(formatCurrency(Double(quantity) * batch.priceBase))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Apagar lote")
            }

            Stepper("Quantidade: \(quantity)", value: $quantity, in: 0...99999)
                .font(.system(size: 13))

            Toggle("Tem validade", isOn: $expires)
                .font(.system(size: 13))

            if expires {
                DatePicker("Validade", selection: $date, displayedComponents: .date)
                    .font(.system(size: 13))
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.15), value: expires)
        .onChange(of: quantity) { commit() }
        .onChange(of: expires) { commit() }
        .onChange(of: date) { commit() }
    }

    private func commit() {
        var updated = batch
        updated.quantity = quantity
        updated.expiryDate = expires ? date : nil
        guard updated.quantity != batch.quantity || updated.expiryDate != batch.expiryDate else { return }
        onCommit(updated)
    }
}
