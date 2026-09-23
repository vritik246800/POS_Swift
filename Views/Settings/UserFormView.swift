import SwiftUI

// MARK: - Formulário de utilizador (wizard)
//
// Quatro passos: Dados → Segurança → Função → Revisão. Cada passo valida-se
// a si próprio; o botão "Seguinte" só fica activo com o passo válido, por isso
// o erro aparece cedo e não só no fim.

struct UserFormView: View {
    enum Mode {
        case create
        case edit(User)
    }

    enum Step: Int, CaseIterable, Identifiable {
        case identity, security, role, review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .identity: return "Dados"
            case .security: return "Segurança"
            case .role:     return "Função"
            case .review:   return "Revisão"
            }
        }

        var icon: String {
            switch self {
            case .identity: return "person.text.rectangle"
            case .security: return "lock.shield"
            case .role:     return "person.badge.key"
            case .review:   return "checkmark.seal"
            }
        }

        var subtitle: String {
            switch self {
            case .identity: return "Nome e nome de utilizador"
            case .security: return "Password de acesso"
            case .role:     return "Permissões no sistema"
            case .review:   return "Confirma antes de guardar"
            }
        }
    }

    let mode: Mode
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .identity
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var role: UserRole = .cashier
    @State private var errorMessage = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Validação

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    var passwordsMatch: Bool { password == confirmPassword }
    var passwordStrong: Bool { password.count >= 6 }

    /// Em edição, password vazia significa "manter a actual".
    private var keepsCurrentPassword: Bool { isEditing && password.isEmpty && confirmPassword.isEmpty }

    private var identityValid: Bool {
        trimmedName.count >= 2 && trimmedUsername.count >= 3 && !trimmedUsername.contains(" ")
    }

    private var securityValid: Bool {
        keepsCurrentPassword || (passwordStrong && passwordsMatch)
    }

    private func isValid(_ step: Step) -> Bool {
        switch step {
        case .identity: return identityValid
        case .security: return securityValid
        case .role:     return true
        case .review:   return identityValid && securityValid
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        switch step {
                        case .identity: identityStep
                        case .security: securityStep
                        case .role:     roleStep
                        case .review:   reviewStep
                        }

                        if !errorMessage.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 10))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                navigationBar
            }
            .frame(minWidth: 460, minHeight: 520)
            .navigationTitle(isEditing ? "Editar Utilizador" : "Novo Utilizador")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.88), value: step)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: errorMessage)
            .onAppear {
                if case .edit(let user) = mode {
                    name = user.name
                    username = user.username
                    role = user.role
                }
            }
        }
    }

    // MARK: - Indicador de passos

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases) { s in
                if s != .identity {
                    Rectangle()
                        .fill(s.rawValue <= step.rawValue ? AppTheme.accent : Color.secondary.opacity(0.22))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? AppTheme.accent : Color.secondary.opacity(0.18))
                            .frame(width: 26, height: 26)
                        Image(systemName: s.rawValue < step.rawValue ? "checkmark" : s.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(s.rawValue <= step.rawValue ? .white : .secondary)
                    }
                    Text(s.title)
                        .font(.system(size: 10, weight: s == step ? .semibold : .regular))
                        .foregroundStyle(s == step ? .primary : .secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Passo \(s.rawValue + 1): \(s.title)")
                .accessibilityAddTraits(s == step ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(step.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Passo 1: Dados

    private var identityStep: some View {
        VStack(spacing: 14) {
            WizardField(icon: "person.text.rectangle", color: AppTheme.accent) {
                TextField("Nome completo", text: $name)
                    .textFieldStyle(.plain)
            } hint: {
                trimmedName.isEmpty ? nil : (trimmedName.count >= 2 ? nil : "Mínimo 2 caracteres.")
            }

            WizardField(icon: "at", color: AppTheme.accent) {
                TextField("Nome de utilizador", text: $username)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } hint: {
                if trimmedUsername.isEmpty { return nil }
                if trimmedUsername.contains(" ") { return "Sem espaços." }
                return trimmedUsername.count >= 3 ? nil : "Mínimo 3 caracteres."
            }

            WizardNote("O nome de utilizador é usado no login e tem de ser único.")
        }
    }

    // MARK: - Passo 2: Segurança

    private var securityStep: some View {
        VStack(spacing: 14) {
            WizardField(icon: "key.fill", color: .orange) {
                HStack(spacing: 8) {
                    if showPassword {
                        TextField(isEditing ? "Nova password (opcional)" : "Password", text: $password)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField(isEditing ? "Nova password (opcional)" : "Password", text: $password)
                            .textFieldStyle(.plain)
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Esconder password" : "Mostrar password")

                    if !password.isEmpty {
                        ValidityMark(ok: passwordStrong)
                    }
                }
            } hint: {
                password.isEmpty || passwordStrong ? nil : "Mínimo 6 caracteres."
            }

            WizardField(icon: "lock.shield", color: .orange) {
                HStack(spacing: 8) {
                    if showConfirmPassword {
                        TextField("Confirmar password", text: $confirmPassword)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("Confirmar password", text: $confirmPassword)
                            .textFieldStyle(.plain)
                    }
                    Button { showConfirmPassword.toggle() } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showConfirmPassword ? "Esconder password" : "Mostrar password")

                    if !confirmPassword.isEmpty {
                        ValidityMark(ok: passwordsMatch)
                    }
                }
            } hint: {
                confirmPassword.isEmpty || passwordsMatch ? nil : "As passwords não coincidem."
            }

            PasswordStrengthBar(password: password)

            if isEditing {
                WizardNote("Deixa em branco para manter a password actual.")
            } else {
                WizardNote("A password é guardada apenas em hash — nunca em texto simples.")
            }
        }
    }

    // MARK: - Passo 3: Função

    private var roleStep: some View {
        VStack(spacing: 12) {
            RoleOption(
                selected: role == .cashier,
                icon: "person.fill",
                iconColor: AppTheme.brandGreen,
                title: "Caixa",
                subtitle: "Processa vendas, gere produtos e consulta relatórios do dia."
            ) { role = .cashier }

            RoleOption(
                selected: role == .admin,
                icon: "shield.fill",
                iconColor: AppTheme.accent,
                title: "Administrador",
                subtitle: "Acesso total — fecho de caixa, exportações, utilizadores e definições."
            ) { role = .admin }
        }
    }

    // MARK: - Passo 4: Revisão

    private var reviewStep: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ReviewRow(label: "Nome", value: trimmedName, step: .identity) { step = .identity }
                Divider().padding(.leading, 16)
                ReviewRow(label: "Utilizador", value: trimmedUsername, step: .identity) { step = .identity }
                Divider().padding(.leading, 16)
                ReviewRow(
                    label: "Password",
                    value: keepsCurrentPassword ? "Mantida" : String(repeating: "•", count: max(password.count, 6)),
                    step: .security
                ) { step = .security }
                Divider().padding(.leading, 16)
                ReviewRow(
                    label: "Função",
                    value: role == .admin ? "Administrador" : "Caixa",
                    step: .role
                ) { step = .role }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))

            if role == .admin {
                WizardNote("Administradores podem criar e apagar utilizadores e fazer fechos de caixa.")
            }
        }
    }

    // MARK: - Barra de navegação do wizard

    private var navigationBar: some View {
        HStack(spacing: 12) {
            if step != .identity {
                Button {
                    errorMessage = ""
                    step = Step(rawValue: step.rawValue - 1) ?? .identity
                } label: {
                    Label("Anterior", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.glass)
            }

            Spacer()

            Text("Passo \(step.rawValue + 1) de \(Step.allCases.count)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            if step == .review {
                Button(action: save) {
                    Label(isEditing ? "Guardar" : "Criar Utilizador",
                          systemImage: isEditing ? "checkmark.circle.fill" : "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValid(.review))
            } else {
                Button {
                    errorMessage = ""
                    step = Step(rawValue: step.rawValue + 1) ?? .review
                } label: {
                    Label("Seguinte", systemImage: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValid(step))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Guardar

    private func save() {
        // Revalidação — a UI já bloqueia, mas a validação não pode viver só nos botões.
        guard identityValid else {
            errorMessage = "Verifica o nome e o nome de utilizador."
            step = .identity
            return
        }
        guard securityValid else {
            errorMessage = "A password tem de ter pelo menos 6 caracteres e coincidir."
            step = .security
            return
        }

        if case .edit(let user) = mode {
            var updated = user
            updated.name = trimmedName
            updated.username = trimmedUsername
            updated.passwordHash = password.isEmpty ? user.passwordHash : authViewModel.hashPassword(password)
            updated.role = role
            guard DatabaseManager.shared.updateUser(updated) else {
                errorMessage = "Não foi possível guardar. O nome de utilizador já existe?"
                return
            }
        } else {
            guard authViewModel.createUser(
                name: trimmedName,
                username: trimmedUsername,
                password: password,
                role: role
            ) else {
                errorMessage = "Não foi possível criar. O nome de utilizador já existe?"
                return
            }
        }

        dismiss()
    }
}

// MARK: - Campo do wizard

/// Campo com ícone, conteúdo e uma dica de validação por baixo.
struct WizardField<Content: View>: View {
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    let hint: () -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))

            if let hint = hint() {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: hint())
    }
}

struct ValidityMark: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(ok ? AppTheme.brandGreen : .red)
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.15), value: ok)
    }
}

struct WizardNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.accent.opacity(0.07), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Força da password

/// Barra indicativa — comprimento + variedade de caracteres. Só orientação
/// visual; a regra que bloqueia continua a ser o mínimo de 6 caracteres.
struct PasswordStrengthBar: View {
    let password: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var score: Int {
        guard !password.isEmpty else { return 0 }
        var score = 0
        if password.count >= 6 { score += 1 }
        if password.count >= 10 { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 1 }
        return min(score, 4)
    }

    private var label: String {
        switch score {
        case 0:    return "—"
        case 1:    return "Fraca"
        case 2:    return "Razoável"
        case 3:    return "Boa"
        default:   return "Forte"
        }
    }

    private var color: Color {
        switch score {
        case 0, 1: return .red
        case 2:    return .orange
        case 3:    return .yellow
        default:   return AppTheme.brandGreen
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Força da password")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i < score ? color : Color.secondary.opacity(0.18))
                        .frame(height: 4)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: score)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Força da password: \(label)")
    }
}

// MARK: - Linha de revisão

struct ReviewRow: View {
    let label: String
    let value: String
    let step: UserFormView.Step
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .semibold))
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Editar \(label)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Role Option Row
struct RoleOption: View {
    let selected: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? iconColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? iconColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? iconColor : Color.secondary.opacity(0.4))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? iconColor.opacity(0.55) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}
