import SwiftUI

// MARK: - Razões de cancelamento
enum CancellationReason: String, CaseIterable, Identifiable {
    case tooExpensive      = "O preço é demasiado alto"
    case missingFeatures   = "Faltam funcionalidades que preciso"
    case switchingApp      = "Vou usar outra aplicação"
    case temporaryPause    = "Pausa temporária no negócio"
    case technicalIssues   = "Problemas técnicos / bugs"
    case notUsingEnough    = "Não estou a usar o suficiente"
    case other             = "Outro motivo"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tooExpensive:    return "eurosign.circle"
        case .missingFeatures: return "puzzlepiece"
        case .switchingApp:    return "arrow.right.circle"
        case .temporaryPause:  return "pause.circle"
        case .technicalIssues: return "wrench.and.screwdriver"
        case .notUsingEnough:  return "clock"
        case .other:           return "ellipsis.circle"
        }
    }
}

// MARK: - CancellationFeedbackView
struct CancellationFeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedReason: CancellationReason? = nil
    @State private var additionalComment = ""
    @State private var isSending = false
    @State private var showConfirmation = false

    // ← MUDA PARA O TEU EMAIL
    private let feedbackEmail = "vritikvalabdas@gmail.com"

    var body: some View {
        ZStack {
            Color(hex: "0F0F1A").ignoresSafeArea()

            if showConfirmation {
                confirmationView
            } else {
                mainFormView
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - Formulário
    var mainFormView: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.12)).frame(width: 64, height: 64)
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.red)
                }
                .padding(.top, 36)

                Text("Lamentamos ver-te partir")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("O teu feedback ajuda-nos a melhorar.\nDemora menos de 30 segundos.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(spacing: 24) {

                    // Razões
                    VStack(alignment: .leading, spacing: 10) {
                        Text("QUAL O MOTIVO PRINCIPAL?")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .tracking(1.5)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(CancellationReason.allCases) { reason in
                                ReasonRow(reason: reason, isSelected: selectedReason == reason)
                                    .onTapGesture { selectedReason = reason }
                            }
                        }
                    }

                    // Comentário adicional
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COMENTÁRIO ADICIONAL (OPCIONAL)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .tracking(1.5)
                            .padding(.horizontal, 4)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))

                            if additionalComment.isEmpty {
                                Text("Conta-nos mais sobre a tua experiência…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.2))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }

                            TextEditor(text: $additionalComment)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minHeight: 80)
                        }
                        .frame(minHeight: 90)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }

            Divider().background(Color.white.opacity(0.08))

            // Botões
            VStack(spacing: 10) {
                // Enviar e ir para cancelamento
                Button {
                    Task { await sendFeedbackAndCancel() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Text("Enviar feedback e cancelar")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedReason != nil ? Color.red.opacity(0.75) : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(.white)
                }
                .disabled(selectedReason == nil || isSending)

                // Cancelar sem feedback
                Button("Cancelar sem deixar feedback") {
                    openManageSubscriptions()
                    dismiss()
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.3))

                // Manter subscrição
                Button {
                    dismiss()
                } label: {
                    Text("Manter a minha subscrição")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "2A2A40")))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Confirmação
    var confirmationView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle().fill(Color(hex: "34C759").opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(hex: "34C759"))
            }

            Text("Feedback recebido")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Obrigado por nos ajudares a melhorar.\nVais ser redirecionado para gerir a tua subscrição na App Store.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                openManageSubscriptions()
                dismiss()
            } label: {
                Text("Gerir subscrição na App Store")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "2A2A40")))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Enviar por email
    private func sendFeedbackAndCancel() async {
        guard let reason = selectedReason else { return }
        isSending = true

        let subject = "[POS Cancelamento] \(reason.rawValue)"
        let body = """
        Motivo: \(reason.rawValue)

        Comentário:
        \(additionalComment.isEmpty ? "(sem comentário)" : additionalComment)

        ---
        App: POS App
        Data: \(formattedDate())
        Plano: €9,99/mês
        """

        sendEmail(to: feedbackEmail, subject: subject, body: body)
        try? await Task.sleep(nanoseconds: 800_000_000)
        isSending = false
        showConfirmation = true
    }

    private func sendEmail(to: String, subject: String, body: String) {
        #if os(macOS)
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(to)?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func openManageSubscriptions() {
        #if os(macOS)
        if let url = URL(string: "macappstores://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}

// MARK: - Reason Row
struct ReasonRow: View {
    let reason: CancellationReason
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: "7B4FBF").opacity(0.3) : Color.white.opacity(0.05))
                    .frame(width: 34, height: 34)
                Image(systemName: isSelected ? "checkmark" : reason.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "9B6FD0") : Color.white.opacity(0.4))
            }
            Text(reason.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.65))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color(hex: "7B4FBF").opacity(0.15) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color(hex: "7B4FBF").opacity(0.5) : Color.clear, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
