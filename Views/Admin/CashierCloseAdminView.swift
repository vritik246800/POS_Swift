import SwiftUI

// MARK: - Fecho por caixa
//
// O Admin vê todas as caixas do dia e fecha as que faltarem; o Caixa vê só a
// sua e fecha-a. O fecho da loja (`DayCloseTabView`) continua a ser o agregado
// do dia — esta secção é o fecho individual de cada utilizador.

struct CashierCloseAdminView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var vm = AdminViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var feedback = ""

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    /// O Caixa só vê a sua própria caixa; o Admin vê todas.
    private var statuses: [CashierDayStatus] {
        let all = vm.cashierStatuses(date: selectedDate)
        guard !authViewModel.isAdmin else { return all }
        return all.filter { $0.user.id == authViewModel.currentUser?.id }
    }

    private var pending: Int { statuses.filter { !$0.isClosed }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if statuses.isEmpty {
                    AppEmptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Sem caixas neste dia",
                        subtitle: "Não há utilizadores com vendas registadas nesta data."
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                        ForEach(statuses) { status in
                            card(status)
                        }
                    }
                }

                if !feedback.isEmpty {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.brandGreen)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ExpiryStatus.expired.color)
                }
            }
            .padding(16)
        }
        .animation(animation, value: selectedDate)
        .animation(animation, value: feedback)
        .onAppear { vm.load() }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caixas")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Spacer(minLength: 0)

                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                AdminKPICard(icon: "person.2", title: "Caixas do dia",
                             value: "\(statuses.count)",
                             detail: "\(statuses.filter(\.isClosed).count) fechada(s)",
                             color: AppTheme.accent)

                AdminKPICard(icon: "lock.open", title: "Por fechar",
                             value: "\(pending)",
                             detail: pending == 0 ? "tudo fechado" : "a aguardar fecho",
                             color: pending == 0 ? AppTheme.brandGreen : AppTheme.brandOrange)

                AdminKPICard(icon: "banknote", title: "Total do dia",
                             value: formatCurrency(statuses.reduce(0) { $0 + $1.total }),
                             detail: "\(statuses.reduce(0) { $0 + $1.numSales }) venda(s)",
                             color: AppTheme.brandGreen)
            }

            TextField("Notas do fecho (opcional)...", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2, reservesSpace: true)
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Cartão de uma caixa

    private func card(_ status: CashierDayStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: status.user.role == .admin ? "person.badge.key.fill" : "person.crop.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.14), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.user.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(status.user.role == .admin ? "Administrador" : "Caixa")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: status.isClosed ? "Fechada" : "Por fechar",
                    icon: status.isClosed ? "lock.fill" : "lock.open",
                    color: status.isClosed ? AppTheme.brandGreen : AppTheme.brandOrange
                )
            }

            HStack(spacing: 16) {
                metric("Vendas", "\(status.numSales)", AppTheme.accent)
                metric("Total", formatCurrency(status.total), AppTheme.brandGreen)
            }

            let methods = PaymentMethod.allCases.filter { status.amount(for: $0) > 0 }
            if !methods.isEmpty {
                Divider()
                ForEach(methods, id: \.self) { method in
                    HStack(spacing: 8) {
                        Image(systemName: method.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.methodColor(method))
                        Text(method.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(formatCurrency(status.amount(for: method)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.methodColor(method))
                            .monospacedDigit()
                    }
                }
            }

            if let close = status.close {
                Text("Fechada às \(close.closedAt.formatted(date: .omitted, time: .shortened))"
                     + (close.closedByAdmin ? " pelo Administrador" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            actions(for: status)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func actions(for status: CashierDayStatus) -> some View {
        let isMine = status.user.id == authViewModel.currentUser?.id

        HStack(spacing: 10) {
            if status.isClosed {
                // A caixa própria nunca fica sem acção: se já foi fechada (por
                // exemplo pelo Admin), o dono ainda pode refazer o fecho com os
                // valores actuais — é o que apanha vendas feitas depois do fecho.
                if isMine {
                    Button {
                        if vm.closeCashier(status, date: selectedDate, notes: notes) {
                            feedback = "Fecho da tua caixa actualizado."
                            notes = ""
                        }
                    } label: {
                        Label("Actualizar o meu fecho", systemImage: "lock.rotation")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(status.numSales == 0)
                    .help("Voltar a gravar o fecho desta caixa com os valores actuais")
                }

                if authViewModel.isAdmin {
                    Button("Reabrir caixa", role: .destructive) {
                        if vm.reopenCashier(status, date: selectedDate) {
                            feedback = "Caixa de \(status.user.name) reaberta."
                        }
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Button {
                    if vm.closeCashier(status, date: selectedDate, notes: notes) {
                        feedback = "Caixa de \(status.user.name) fechada."
                        notes = ""
                    }
                } label: {
                    Label(isMine ? "Fechar a minha caixa" : "Fechar caixa",
                          systemImage: "lock.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .disabled(status.numSales == 0)
                .help(status.numSales == 0 ? "Sem vendas para fechar" : "Registar o fecho desta caixa")
            }
            Spacer(minLength: 0)
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}
