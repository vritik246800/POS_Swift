import SwiftUI

// Os cartões de estado (perda real, em risco, stock baixo) e o painel lateral
// que aqui viviam passaram para **Administração › Validade** — esta vista volta
// a ser só a lista de produtos.

struct ProductListView: View {
    @EnvironmentObject var productViewModel: ProductViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var batchViewModel: BatchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showAddProduct = false
    @State private var productToEdit: Product? = nil
    @State private var searchText = ""
    @State private var selectedCategoryId: Int? = nil   // nil = "Todos"
    @State private var showCategoryManager = false
    /// Produto a que se perguntou se quer promoção (2.7).
    @State private var promoCandidate: Product? = nil
    /// Produto com o painel de promoção aberto.
    @State private var promoProduct: Product? = nil

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var displayedProducts: [Product] {
        let base = searchText.isEmpty ? productViewModel.products : productViewModel.searchResults
        guard let selectedCategoryId else { return base }
        return base.filter { $0.categoryId == selectedCategoryId }
    }

    /// Filtro activo por categoria ou por texto — decide o contador de resultados.
    private var hasActiveFilter: Bool {
        !searchText.isEmpty || selectedCategoryId != nil
    }

    var body: some View {
        VStack(spacing: 0) {

            searchBar

            // MARK: - Barra de filtro por categoria
            categoryFilterBar

            // MARK: - Contador de resultados
            if hasActiveFilter {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                    Text("\(displayedProducts.count) resultado(s)")
                        .font(.system(size: 12))
                        .contentTransition(.numericText())
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
            }

            productList
        }
        .navigationTitle("Produtos")
        // Painel de promoção: desce de cima sobre a lista.
        .overlay(alignment: .top) {
            if let product = promoProduct {
                PromotionPanel(
                    product: product,
                    onApply: { percent in
                        productViewModel.applyDiscount(productId: product.id, percent: percent)
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
        .confirmationDialog(
            "Fazer promoção em \"\(promoCandidate?.name ?? "")\"?",
            isPresented: Binding(
                get: { promoCandidate != nil },
                set: { if !$0 { promoCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sim, aplicar desconto") {
                let product = promoCandidate
                promoCandidate = nil
                withAnimation(animation) { promoProduct = product }
            }
            Button("Agora não", role: .cancel) { promoCandidate = nil }
        } message: {
            Text("Este produto está a aproximar-se do fim do prazo. Um desconto ajuda a escoá-lo antes de expirar.")
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showCategoryManager = true
                } label: {
                    Label("Categorias", systemImage: "tag")
                        .font(.system(size: 14, weight: .medium))
                }
                .help("Gerir categorias")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddProduct = true
                } label: {
                    Label("Novo Produto", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView()
                .environmentObject(categoryViewModel)
                .environmentObject(productViewModel)
        }
        .sheet(isPresented: $showAddProduct) {
            ProductFormView(mode: .create)
                .environmentObject(productViewModel)
        }
        .sheet(item: $productToEdit) { product in
            ProductFormView(mode: .edit(product))
                .environmentObject(productViewModel)
        }
        .onAppear {
            productViewModel.loadProducts()
            categoryViewModel.loadCategories()
            batchViewModel.loadBatches()
        }
    }

    // MARK: - Pesquisa

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            TextField("Nome ou código de barras...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onChange(of: searchText) {
                    productViewModel.searchQuery = searchText
                    productViewModel.search()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    productViewModel.searchQuery = ""
                    productViewModel.search()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar pesquisa")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Lista de produtos / estado vazio

    @ViewBuilder
    private var productList: some View {
        if displayedProducts.isEmpty {
            if hasActiveFilter {
                AppEmptyStateView(
                    icon: "magnifyingglass",
                    title: "Sem resultados",
                    subtitle: "Nenhum produto corresponde ao filtro actual."
                )
            } else {
                AppEmptyStateView(
                    icon: "cube.box",
                    title: "Sem produtos registados",
                    subtitle: "Adiciona o primeiro produto com o botão + acima."
                )
            }
        } else {
            List {
                ForEach(displayedProducts) { product in
                    ProductRowView(
                        product: product,
                        category: categoryViewModel.category(for: product.categoryId),
                        expiryStatus: batchViewModel.worstStatus(productId: product.id),
                        onPromote: { promoCandidate = product }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { productToEdit = product }
                    // Botão direito (ou toque longo em iOS): promoção sem abrir o produto.
                    .contextMenu {
                        Button {
                            withAnimation(animation) { promoProduct = product }
                        } label: {
                            Label(product.hasDiscount ? "Alterar promoção" : "Fazer promoção",
                                  systemImage: "tag.fill")
                        }
                        if product.hasDiscount {
                            Button(role: .destructive) {
                                productViewModel.applyDiscount(productId: product.id, percent: 0)
                            } label: {
                                Label("Remover promoção", systemImage: "tag.slash")
                            }
                        }
                        Divider()
                        Button {
                            productToEdit = product
                        } label: {
                            Label("Editar produto", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            productViewModel.deleteProduct(id: product.id)
                        } label: {
                            Label("Apagar produto", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { i in
                        productViewModel.deleteProduct(id: displayedProducts[i].id)
                    }
                }
            }
            .listStyle(.plain)
            .animation(animation, value: displayedProducts.count)
        }
    }

    // MARK: - Barra de filtro por categoria
    // Mesma barra das Vendas (`CategoryFilterBar`, em Utils/AppTheme.swift).

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !categoryViewModel.categories.isEmpty {
            CategoryFilterBar(
                categories: categoryViewModel.categories,
                selectedCategoryId: $selectedCategoryId
            )
        }
    }
}

// MARK: - Linha de produto na lista

struct ProductRowView: View {
    let product: Product
    var category: Category? = nil
    /// Faixa do lote mais grave deste produto (`nil` = sem problema de validade).
    var expiryStatus: ExpiryStatus? = nil
    /// Pedido de promoção. `nil` esconde a acção (ex.: listas só de leitura).
    var onPromote: (() -> Void)? = nil

    /// A promoção faz sentido enquanto o produto ainda se pode vender:
    /// está a aproximar-se do prazo, mas ainda não expirou.
    private var suggestsPromotion: Bool {
        guard let expiryStatus else { return false }
        return expiryStatus.isAlerting && expiryStatus != .expired
    }

    private var stockColor: Color {
        if product.stock == 0 { return .red }
        if product.stock <= 10 { return AppTheme.brandOrange }
        return AppTheme.brandGreen
    }

    private var stockIcon: String {
        if product.stock == 0 { return "xmark.circle.fill" }
        if product.stock <= 10 { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var stockLabel: String {
        if product.stock == 0 { return "Sem stock" }
        if product.stock <= 10 { return "Stock baixo" }
        return "Em stock"
    }

    var body: some View {
        HStack(spacing: 14) {

            // Ícone do produto (cor e símbolo da categoria, quando existe)
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill((category?.color ?? AppTheme.noCategory).opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: category?.icon ?? "cube.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(category?.color ?? AppTheme.noCategory)
            }

            // Nome, categoria e estados
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(product.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    CategoryChipView(
                        name: category?.name ?? "Sem categoria",
                        icon: category?.icon ?? "tag.slash",
                        color: category?.color ?? AppTheme.noCategory
                    )

                    // Estado do lote com problema de validade
                    if let expiryStatus {
                        StatusBadge(
                            text: expiryStatus.label,
                            icon: expiryStatus.icon,
                            color: expiryStatus.color
                        )
                    }
                }

                HStack(spacing: 12) {
                    metric(icon: "tag", text: formatCurrency(product.priceBase), color: .secondary)
                    metric(icon: "percent",
                           text: "IVA \(product.ivaRate.formatted(.number.precision(.fractionLength(0))))%",
                           color: .purple)
                    metric(icon: "chart.line.uptrend.xyaxis",
                           text: "\(product.profitMargin.formatted(.number.precision(.fractionLength(0))))%",
                           color: AppTheme.brandGreen)
                    if !product.barcode.isEmpty {
                        metric(icon: "barcode", text: product.barcode, color: .secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Promoção: sugerida quando o produto está a expirar, ou já activa.
            if let onPromote, suggestsPromotion || product.hasDiscount {
                Button(action: onPromote) {
                    HStack(spacing: 5) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(product.hasDiscount
                             ? "−\(product.discountPercent.formatted(.number.precision(.fractionLength(0))))%"
                             : "Promoção")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.brandGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.brandGreen.opacity(product.hasDiscount ? 0.22 : 0.12), in: .capsule)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(product.hasDiscount ? "Alterar ou remover a promoção" : "Fazer promoção deste produto")
                .accessibilityLabel("Promoção de \(product.name)")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Preço final e stock
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if product.hasDiscount {
                        Text(formatCurrency(product.priceFinal))
                            .font(.system(size: 12))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(formatCurrency(product.priceWithDiscount))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(product.hasDiscount ? AppTheme.brandGreen : AppTheme.accent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                StatusBadge(
                    text: "\(product.stock) · \(stockLabel)",
                    icon: stockIcon,
                    color: stockColor
                )
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(formatCurrency(product.priceFinal)), \(product.stock) em stock")
    }

    private func metric(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.8))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Painel de promoção (2.7)

/// Painel que desce de cima para aplicar um desconto ao produto que está a
/// aproximar-se do fim do prazo. O desconto vive no produto e é o preço
/// praticado na venda.
struct PromotionPanel: View {
    let product: Product
    let onApply: (Double) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var percent: Double = 10

    private var newPrice: Double { product.priceFinal * (1 - percent / 100) }
    private var saving: Double { product.priceFinal - newPrice }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.brandGreen)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.brandGreen.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Promoção")
                        .font(.system(size: 14, weight: .bold))
                    Text(product.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(5)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Fechar painel de promoção")
            }

            HStack(spacing: 12) {
                Text("\(Int(percent))%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.brandGreen)
                    .monospacedDigit()
                    .frame(width: 78, alignment: .leading)
                    .contentTransition(.numericText())

                Slider(value: $percent, in: 0...90, step: 5)
                    .tint(AppTheme.brandGreen)
                    .accessibilityLabel("Percentagem de desconto")
            }

            HStack(spacing: 10) {
                priceBox(title: "Preço actual", value: product.priceFinal, color: .secondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                priceBox(title: "Com promoção", value: newPrice, color: AppTheme.brandGreen)
                priceBox(title: "Poupança", value: saving, color: AppTheme.brandOrange)
            }

            if !productViewModel.errorMessage.isEmpty {
                Text(productViewModel.errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                if product.hasDiscount {
                    Button("Remover promoção") { onApply(0) }
                        .buttonStyle(.glass)
                        .tint(.red)
                }
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.glass)
                Button("Aplicar desconto") { onApply(percent) }
                    .buttonStyle(.glass)
                    .tint(AppTheme.brandGreen)
                    .disabled(percent == 0 && !product.hasDiscount)
            }
        }
        .padding(16)
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .onAppear { percent = product.hasDiscount ? product.discountPercent : 10 }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: percent)
    }

    private func priceBox(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(formatCurrency(value))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badge de estado reutilizável (validade, stock)

struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
