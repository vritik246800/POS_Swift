import SwiftUI

struct SaleView: View {
    @EnvironmentObject var saleViewModel: SaleViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var batchViewModel: BatchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var selectedCategoryId: Int?
    @State private var showInvoice = false
    @State private var showConfirmClear = false
    @State private var showScanner = false
    @State private var showPayment = false

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 14)]

    /// Filtro combinado: pesquisa **e** categoria.
    var filteredProducts: [Product] {
        productViewModel.products(inCategory: selectedCategoryId).filter { product in
            searchText.isEmpty
                || product.name.localizedCaseInsensitiveContains(searchText)
                || product.barcode.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasActiveFilter: Bool { !searchText.isEmpty || selectedCategoryId != nil }

    /// Faixa do lote mais próximo do fim de validade deste produto.
    private func nearestExpiry(for product: Product) -> ExpiryStatus {
        batchViewModel.batches(for: product.id)
            .map(\.expiryStatus)
            .max { $0.severity < $1.severity } ?? ExpiryStatus.none
    }

    /// Unidades dentro do prazo — é o que se pode vender (o resto está expirado).
    private func sellableStock(for product: Product) -> Int {
        batchViewModel.batches(for: product.id)
            .filter { $0.expiryStatus != .expired }
            .reduce(0) { $0 + $1.quantity }
    }

    var body: some View {
        HStack(spacing: 0) {

            // MARK: - Coluna esquerda — Produtos
            VStack(spacing: 0) {

                // Barra de pesquisa
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("Nome ou código de barras...", text: $searchText)
                        .font(.system(size: 14))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                // Filtro: só "Todos" ou "Filtrar" — as categorias aparecem
                // ao lado, com animação, quando se abre o filtro.
                CategoryFilterBar(
                    categories: categoryViewModel.categories,
                    selectedCategoryId: $selectedCategoryId
                )

                // Contador
                if hasActiveFilter {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(filteredProducts.count) resultado(s)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                if filteredProducts.isEmpty {
                    if productViewModel.products.isEmpty {
                        AppEmptyStateView(
                            icon: "cube.box",
                            title: "Sem produtos registados",
                            subtitle: "Adiciona produtos no separador Produtos."
                        )
                    } else {
                        AppEmptyStateView(
                            icon: "magnifyingglass",
                            title: "Sem resultados",
                            subtitle: "Nenhum produto corresponde ao filtro atual."
                        )
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filteredProducts) { product in
                                ProductCardView(
                                    product: product,
                                    category: categoryViewModel.category(for: product.categoryId),
                                    expiryStatus: nearestExpiry(for: product),
                                    sellableStock: sellableStock(for: product)
                                ) { qty in
                                    saleViewModel.addToCart(product: product, quantity: qty)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut, value: filteredProducts.count)
            .animation(.easeInOut(duration: 0.2), value: selectedCategoryId)

            Divider()

            // MARK: - Coluna direita — Carrinho
            VStack(spacing: 0) {

                // Header carrinho
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                    Text("Carrinho")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if !saleViewModel.cartItems.isEmpty {
                        Text("\(saleViewModel.cartItems.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                // Dados do cliente
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        TextField("Nome do cliente (opcional)", text: $saleViewModel.clientName)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        TextField("NIF (opcional)", text: $saleViewModel.clientNIF)
                            .font(.system(size: 13))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                Divider()

                // Itens ou estado vazio
                if saleViewModel.cartItems.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("Carrinho vazio")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("Adiciona produtos à esquerda")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(saleViewModel.cartItems) { item in
                            CartItemRowView(
                                item: item,
                                onChangeQuantity: { newQty in
                                    saleViewModel.updateQuantity(productId: item.productId, newQuantity: newQty)
                                },
                                onRemove: {
                                    saleViewModel.removeFromCart(productId: item.productId)
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                    .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.25),
                               value: saleViewModel.cartItems)
                }

                Divider()

                // Rodapé com total e botões
                VStack(spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "sum")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text("Total")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                        Text(formatMT(saleViewModel.cartTotal))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                    }

                    if !saleViewModel.errorMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text(saleViewModel.errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Button {
                            showConfirmClear = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("Limpar")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.red.opacity(0.10))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(saleViewModel.cartItems.isEmpty)
                        .buttonStyle(.plain)

                        Button {
                            showPayment = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "creditcard.fill")
                                Text("Pagar")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(saleViewModel.cartItems.isEmpty ? Color.green.opacity(0.35) : Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(saleViewModel.cartItems.isEmpty)
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .navigationTitle("Vendas")
        .onAppear {
            productViewModel.loadProducts()
            categoryViewModel.loadCategories()
            batchViewModel.loadBatches()
        }
        .sheet(isPresented: $showPayment) {
            PaymentView(total: saleViewModel.cartTotal) { payments in
                guard let userId = authViewModel.currentUser?.id else { return }
                if saleViewModel.finalizeSaleWithPayments(userId: userId, payments: payments) {
                    productViewModel.loadProducts()
                    showInvoice = true
                }
            }
        }
        .sheet(isPresented: $showInvoice) {
            if let saleId = saleViewModel.lastSaleId {
                InvoiceView(saleId: saleId)
                    .environmentObject(saleViewModel)
            }
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView(scannedCode: $searchText)
                .onDisappear { handleBarcodeScanned() }
        }
        .confirmationDialog("Limpar carrinho?", isPresented: $showConfirmClear) {
            Button("Limpar", role: .destructive) { saleViewModel.clearCart() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func handleBarcodeScanned() {
        guard !searchText.isEmpty else { return }
        if let product = productViewModel.findByBarcode(searchText) {
            saleViewModel.addToCart(product: product, quantity: 1)
            searchText = ""
        }
    }
}

// MARK: - Linha de item no carrinho
struct CartItemRowView: View {
    let item: SaleItem
    /// Nova quantidade pedida pelos botões −/+. Zero remove a linha.
    let onChangeQuantity: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Stepper de quantidade — substitui a antiga etiqueta fixa.
            HStack(spacing: 4) {
                quantityButton("minus") {
                    onChangeQuantity(item.quantity - 1)
                }
                Text("\(item.quantity)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .frame(minWidth: 22)
                    .contentTransition(.numericText())
                quantityButton("plus") {
                    onChangeQuantity(item.quantity + 1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.08), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.productName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "multiply")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(formatMT(item.unitPrice))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(formatMT(item.subtotal))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .animation(.easeInOut(duration: 0.18), value: item.quantity)
    }

    private func quantityButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Diminuir quantidade" : "Aumentar quantidade")
    }
}
