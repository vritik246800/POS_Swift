import SwiftUI

struct ProductRow: View {
    let product: Product
    let onCycleStatus: () -> Void
    let onUpdateStock: (Int?, Int?) -> Void

    @State private var showEdit = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCycleStatus) {
                statusIcon
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(labelColor)
                Text(product.barcode)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: { showEdit = true }) {
                HStack(spacing: 8) {
                    StockBadge(label: "Stock", value: product.stockActual,
                               accent: stockColor(product.stockActual))
                    StockBadge(label: "Enc.", value: product.qtyEncomenda, accent: .blue)
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(rowFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 1))
        .sheet(isPresented: $showEdit) {
            EditStockSheet(product: product, onSave: { stock, enc in
                onUpdateStock(stock, enc)
            })
            .presentationDetents([.height(320)])
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch product.status {
        case .none:
            Image(systemName: "flag").foregroundColor(.secondary)
        case .redFlag:
            Image(systemName: "flag.fill").foregroundColor(.red)
        case .confirmed:
            Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
        }
    }

    private var labelColor: Color {
        switch product.status {
        case .none:      return .primary
        case .redFlag:   return .red
        case .confirmed: return .green
        }
    }

    private var rowFill: Color {
        switch product.status {
        case .none:      return Color(.secondarySystemGroupedBackground)
        case .redFlag:   return Color.red.opacity(0.06)
        case .confirmed: return Color.green.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch product.status {
        case .none:      return .clear
        case .redFlag:   return Color.red.opacity(0.3)
        case .confirmed: return Color.green.opacity(0.3)
        }
    }

    private func stockColor(_ qty: Int) -> Color {
        qty == 0 ? .red : qty < 3 ? .orange : .green
    }
}

struct StockBadge: View {
    let label: String
    let value: Int
    let accent: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(accent)
        }
        .frame(minWidth: 36)
    }
}

struct EditStockSheet: View {
    let product: Product
    let onSave: (Int?, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stockText: String
    @State private var encText: String

    init(product: Product, onSave: @escaping (Int?, Int?) -> Void) {
        self.product = product
        self.onSave = onSave
        _stockText = State(initialValue: "\(product.stockActual)")
        _encText   = State(initialValue: "\(product.qtyEncomenda)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Produto") {
                        Text(product.name).foregroundColor(.secondary)
                    }
                    LabeledContent("Código") {
                        Text(product.barcode).foregroundColor(.secondary).monospacedDigit()
                    }
                }
                Section("Actualizar quantidades") {
                    HStack {
                        Label("Stock Actual", systemImage: "shippingbox")
                        Spacer()
                        TextField("0", text: $stockText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Label("Qtd. Encomenda", systemImage: "cart")
                        Spacer()
                        TextField("0", text: $encText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .navigationTitle("Editar Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(Int(stockText), Int(encText))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
