import SwiftUI

// MARK: - Vista de Pagamento

/// Fecho do pagamento de uma venda: escolhe-se o método, junta-se uma ou mais
/// entradas (pagamento repartido) e confirma-se. O resumo fica sempre visível
/// no fundo — é o que o operador precisa de ver enquanto conta o dinheiro.
struct PaymentView: View {
    let total: Double
    let onConfirm: ([Payment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entries: [PaymentEntry] = []
    @State private var selectedMethod: PaymentMethod = .cash
    @State private var currentAmount: String = ""
    @State private var currentReference: String = ""
    @State private var errorMessage: String = ""
    @FocusState private var amountFocused: Bool

    /// Notas rápidas: somam-se ao valor escrito, como quem recebe notas ao balcão.
    private let quickNotes: [Double] = [50, 100, 200, 500, 1000]

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)
    }

    var paidTotal: Double { entries.reduce(0) { $0 + $1.amount } }
    var remaining: Double { max(0, total - paidTotal) }
    var change: Double { max(0, paidTotal - total) }
    var isComplete: Bool { paidTotal >= total && !entries.isEmpty }

    /// Fracção paga (0…1) — alimenta a barra de progresso do cabeçalho.
    private var progress: Double {
        total > 0 ? min(paidTotal / total, 1) : 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Métodos à esquerda, pagamentos já adicionados à direita:
                    // o operador vê o que lançou sem perder o método de vista.
                    HStack(alignment: .top, spacing: 20) {
                        methodSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !entries.isEmpty {
                            entriesSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    amountSection
                }
                .padding(20)
            }

            summaryBar
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 620)
        .animation(animation, value: entries.count)
        .animation(animation, value: selectedMethod)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: errorMessage)
        .onAppear {
            currentAmount = String(format: "%.2f", total)
            amountFocused = true
        }
    }

    // MARK: - Cabeçalho: total e progresso

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Pagamento", systemImage: "creditcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Fechar")
            }

            Text(formatMT(total))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)

            // Barra de progresso do que já está pago
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.brandGreen, AppTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
            .animation(animation, value: progress)

            HStack(spacing: 6) {
                Image(systemName: remaining > 0 ? "hourglass" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(remaining > 0
                     ? "Falta \(formatMT(remaining))"
                     : (change > 0 ? "Troco \(formatMT(change))" : "Pagamento completo"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(remaining > 0 ? AppTheme.brandOrange : AppTheme.brandGreen)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    // MARK: - Métodos de pagamento

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Método de pagamento", icon: "list.bullet.rectangle.portrait")

            GlassEffectContainer(spacing: 10) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Button {
                            withAnimation(animation) {
                                selectedMethod = method
                                if currentAmount.isEmpty && remaining > 0 {
                                    currentAmount = String(format: "%.2f", remaining)
                                }
                            }
                        } label: {
                            MethodButton(method: method, isSelected: selectedMethod == method)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Valor a pagar

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Valor — \(selectedMethod.label)", icon: selectedMethod.icon,
                         color: selectedMethod.color)

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "banknote")
                        .font(.system(size: 15))
                        .foregroundStyle(selectedMethod.color)
                    TextField("0.00", text: $currentAmount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .focused($amountFocused)
                        .onSubmit { addEntry() }
                    if !currentAmount.isEmpty {
                        Button {
                            currentAmount = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Limpar valor")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selectedMethod.color.opacity(amountFocused ? 0.7 : 0.2), lineWidth: 1.5)
                }

                Button {
                    currentAmount = String(format: "%.2f", remaining)
                } label: {
                    Label("Restante", systemImage: "equal.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(AppTheme.brandOrange.opacity(0.14), in: .rect(cornerRadius: 12))
                        .foregroundStyle(AppTheme.brandOrange)
                }
                .buttonStyle(.plain)
                .disabled(remaining <= 0)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: amountFocused)

            // Notas rápidas — somam ao valor escrito
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickNotes, id: \.self) { note in
                        Button {
                            addToAmount(note)
                        } label: {
                            Text("+\(Int(note))")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Somar \(Int(note))")
                    }
                }
                .padding(.vertical, 1)
            }

            // Referência obrigatória em M-Pesa / e-Mola
            if selectedMethod.isMobile {
                HStack(spacing: 8) {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(selectedMethod.color)
                    TextField("Referência / Nº transacção", text: $currentReference)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                addEntry()
            } label: {
                Label("Adicionar pagamento", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent.opacity(0.14), in: .rect(cornerRadius: 12))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .animation(animation, value: selectedMethod.isMobile)
    }

    // MARK: - Pagamentos já adicionados

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Pagamentos adicionados", icon: "checkmark.rectangle.stack.fill")
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.brandGreen, in: .capsule)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.method.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(entry.method.color)
                        .frame(width: 34, height: 34)
                        .background(entry.method.color.opacity(0.14), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.method.label)
                            .font(.system(size: 13, weight: .semibold))
                        if !entry.reference.isEmpty {
                            Text("Ref: \(entry.reference)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(formatMT(entry.amount))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()

                    Button {
                        withAnimation(animation) {
                            entries.removeAll { $0.id == entry.id }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(7)
                            .background(Color.red.opacity(0.10), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remover \(entry.method.label)")
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    // MARK: - Resumo fixo + confirmação

    private var summaryBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                summaryCell(label: "Pago", value: paidTotal, color: AppTheme.brandGreen)
                Divider().frame(height: 32)
                summaryCell(label: "Restante", value: remaining,
                            color: remaining > 0 ? .red : .secondary)
                if change > 0 {
                    Divider().frame(height: 32)
                    summaryCell(label: "Troco", value: change, color: AppTheme.brandOrange)
                }
            }

            Button {
                confirmPayment()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirmar venda")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isComplete ? AppTheme.brandGreen : Color.secondary.opacity(0.25),
                            in: .rect(cornerRadius: 13))
                .foregroundStyle(isComplete ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isComplete)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
        .animation(animation, value: isComplete)
    }

    private func summaryCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(formatMT(value))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formatMT(value))")
    }

    private func sectionTitle(_ text: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Lógica

    /// Soma uma nota ao valor escrito (o campo pode estar vazio ou com vírgula).
    private func addToAmount(_ note: Double) {
        let current = Double(currentAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        currentAmount = String(format: "%.2f", current + note)
    }

    private func addEntry() {
        errorMessage = ""
        guard let amount = Double(currentAmount.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            errorMessage = "Introduz um valor válido."
            return
        }
        if selectedMethod.isMobile && currentReference.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Para \(selectedMethod.label) é obrigatório introduzir a referência."
            return
        }
        let entry = PaymentEntry(
            method: selectedMethod,
            amount: amount,
            reference: currentReference.trimmingCharacters(in: .whitespaces)
        )
        withAnimation(animation) { entries.append(entry) }
        currentReference = ""
        currentAmount = remaining > 0 ? String(format: "%.2f", remaining) : ""
    }

    private func confirmPayment() {
        guard isComplete else { return }
        let payments = entries.map { entry in
            Payment(id: 0, saleId: 0, method: entry.method, amount: entry.amount, reference: entry.reference)
        }
        onConfirm(payments)
        dismiss()
    }
}

// MARK: - Modelos internos

private struct PaymentEntry: Identifiable {
    let id = UUID()
    let method: PaymentMethod
    let amount: Double
    let reference: String
}

// MARK: - Subviews

private struct MethodButton: View {
    let method: PaymentMethod
    let isSelected: Bool

    var color: Color { method.color }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: method.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? color : .secondary)
                .frame(width: 30, height: 30)
                .background((isSelected ? color : Color.secondary).opacity(0.14), in: .circle)

            Text(method.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(method.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
