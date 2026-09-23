import SwiftUI

// MARK: - Definições
//
// Layout em cartões de vidro (um plano de vidro por cartão, nunca aninhado),
// agrupados por área: sessão, subscrição, utilizadores e aplicação.

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var users: [User] = []
    @State private var showAddUser = false
    @State private var userToEdit: User? = nil
    @State private var showDeleteConfirm = false
    @State private var userToDelete: User? = nil
    @State private var successMessage = ""
    @State private var showPaywall = false
    @State private var showCancellation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                sessionCard

                SettingsSection(icon: "creditcard", title: "Subscrição") {
                    SubscriptionStatusCard(
                        showPaywall: $showPaywall,
                        showCancellation: $showCancellation
                    )
                }

                // Utilizadores e Aplicação lado a lado; empilham em ecrã estreito.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        usersSection
                        appSection
                    }
                    VStack(spacing: 24) {
                        usersSection
                        appSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Definições")
        .overlay(alignment: .top) { successToast }
        .onAppear { loadUsers() }
        .sheet(isPresented: $showAddUser, onDismiss: loadUsers) {
            UserFormView(mode: .create).environmentObject(authViewModel)
        }
        .sheet(item: $userToEdit, onDismiss: loadUsers) { user in
            UserFormView(mode: .edit(user)).environmentObject(authViewModel)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showCancellation) {
            CancellationFeedbackView()
        }
        .confirmationDialog(
            "Apagar utilizador \(userToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) { deleteUser() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acção é permanente. As vendas já registadas mantêm-se no histórico.")
        }
    }

    // MARK: - Sessão actual

    private var sessionCard: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                if let user = authViewModel.currentUser {
                    HStack(spacing: 16) {
                        UserAvatar(role: user.role, size: 54)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(user.name)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                            HStack(spacing: 5) {
                                Image(systemName: "at")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(user.username)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        RoleBadge(role: user.role)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.24), AppTheme.accent.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                    Button {
                        authViewModel.logout()
                    } label: {
                        Label("Terminar Sessão", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                }
            }
        }
    }

    // MARK: - Secções lado a lado

    @ViewBuilder
    private var usersSection: some View {
        if authViewModel.isAdmin {
            SettingsSection(icon: "person.2", title: "Utilizadores") {
                usersCard
            }
        }
    }

    private var appSection: some View {
        SettingsSection(icon: "gearshape", title: "Aplicação") {
            appCard
        }
    }

    // MARK: - Utilizadores

    private var usersCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                if index > 0 { Divider().padding(.leading, 62) }
                UserRow(
                    user: user,
                    isCurrent: user.id == authViewModel.currentUser?.id,
                    onEdit: { userToEdit = user },
                    onDelete: {
                        userToDelete = user
                        showDeleteConfirm = true
                    }
                )
            }

            if !users.isEmpty { Divider() }

            Button {
                showAddUser = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Adicionar Utilizador")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86),
            value: users.map(\.id)
        )
    }

    // MARK: - Aplicação

    private var appCard: some View {
        VStack(spacing: 0) {
            AppNameRow { flash("Nome do programa actualizado.") }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().padding(.leading, 50)

            InfoRow(icon: "info.circle", iconColor: .blue, label: "Versão", value: Constants.appVersion)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().padding(.leading, 50)

            InfoRow(
                icon: "cylinder",
                iconColor: .purple,
                label: "Base de Dados",
                value: Constants.dbName,
                valueStyle: .caption
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().padding(.leading, 50)

            Button { openDataBaseFolder() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    Text("Abrir pasta da Base de Dados")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Toast de sucesso

    @ViewBuilder
    private var successToast: some View {
        if !successMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.brandGreen)
                Text(successMessage)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Acções

    private func deleteUser() {
        guard let user = userToDelete else { return }
        guard DatabaseManager.shared.deleteUser(id: user.id) else {
            flash("Não foi possível apagar o utilizador.")
            return
        }
        loadUsers()
        flash("Utilizador apagado com sucesso.")
    }

    private func flash(_ message: String) {
        withAnimation { successMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { successMessage = "" }
        }
    }

    private func openDataBaseFolder() {
        guard let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Application Support") else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func loadUsers() {
        users = DatabaseManager.shared.fetchUsers()
    }
}

// MARK: - Secção com cabeçalho

/// Cabeçalho + conteúdo. O vidro vive no conteúdo, nunca no cabeçalho —
/// evita vidro sobre vidro.
struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 4)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Linha de utilizador

struct UserRow: View {
    let user: User
    let isCurrent: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            UserAvatar(role: user.role, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.system(size: 14, weight: .semibold))
                    if isCurrent {
                        Text("tu")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "at")
                        .font(.system(size: 10))
                    Text(user.username)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            RoleBadge(role: user.role)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accent.opacity(0.10), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Editar utilizador")
            .accessibilityLabel("Editar \(user.name)")

            if !isCurrent {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.10), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Apagar utilizador")
                .accessibilityLabel("Apagar \(user.name)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(hovering ? AppTheme.accent.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Avatar por perfil

struct UserAvatar: View {
    let role: UserRole
    var size: CGFloat = 38

    private var color: Color { role == .admin ? AppTheme.accent : AppTheme.brandGreen }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
            Image(systemName: role == .admin ? "shield.fill" : "person.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
}

struct RoleBadge: View {
    let role: UserRole

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: role == .admin ? "shield.fill" : "person.fill")
                .font(.system(size: 9, weight: .bold))
            Text(role == .admin ? "Admin" : "Caixa")
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(role == .admin ? AppTheme.accent.opacity(0.12) : AppTheme.brandGreen.opacity(0.14))
        .foregroundStyle(role == .admin ? AppTheme.accent : AppTheme.brandGreen)
        .clipShape(Capsule())
    }
}

// MARK: - Nome do programa

/// Edita o nome que aparece no login, na barra de título, nos recibos e no
/// cabeçalho dos relatórios e fechos. Guarda em `UserDefaults` pela mesma
/// chave que `Constants.appName` lê — as outras Views usam `@AppStorage` e
/// refletem a mudança sem reiniciar.
struct AppNameRow: View {
    let onSaved: () -> Void

    @AppStorage(Constants.appNameKey) private var storedName = Constants.defaultAppName
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// O nome só se grava se for válido e diferente do actual.
    private var canSave: Bool {
        let clean = Constants.sanitizedAppName(draft)
        return clean != storedName
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.brandPurple)
                .frame(width: 22)

            Text("Nome do programa")
                .font(.system(size: 14))

            Spacer(minLength: 12)

            TextField(Constants.defaultAppName, text: $draft)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 240)
                .focused($focused)
                .onSubmit(save)

            if canSave {
                Button(action: save) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.brandGreen)
                }
                .buttonStyle(.plain)
                .help("Guardar nome")
                .accessibilityLabel("Guardar nome do programa")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.22), value: canSave)
        .onAppear { draft = storedName }
        .onChange(of: storedName) { draft = storedName }
    }

    private func save() {
        let clean = Constants.sanitizedAppName(draft)
        draft = clean
        guard clean != storedName else { return }
        storedName = clean
        focused = false
        onSaved()
    }
}

struct InfoRow: View {
    enum ValueStyle { case regular, caption }

    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var valueStyle: ValueStyle = .regular

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .font(valueStyle == .caption ? .system(size: 11) : .system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Subscription Status Card
struct SubscriptionStatusCard: View {
    @Binding var showPaywall: Bool
    @Binding var showCancellation: Bool
    @ObservedObject private var sub = SubscriptionManager.shared
    private let trial = TrialManager.shared

    var statusColor: Color {
        if sub.isSubscribed && sub.isCancelled { return .orange }
        if sub.isSubscribed { return AppTheme.brandGreen }
        if trial.isTrialActive { return .orange }
        return .red
    }

    var statusIcon: String {
        if sub.isSubscribed && sub.isCancelled { return "clock.badge.xmark" }
        if sub.isSubscribed { return "crown.fill" }
        if trial.isTrialActive { return "clock.fill" }
        return "lock.fill"
    }

    var statusLabel: String {
        if sub.isSubscribed && sub.isCancelled {
            if let date = sub.expirationDateFormatted {
                return "Cancelado — ativo até \(date)"
            }
            return "Cancelado — ainda ativo"
        }
        if sub.isSubscribed { return "Ativo — €9,99/mês" }
        if trial.isTrialActive { return "Trial — \(trial.daysRemaining) dias restantes" }
        return "Sem subscrição ativa"
    }

    var statusSubtitle: String {
        if sub.isSubscribed && sub.isCancelled {
            return "A subscrição não vai renovar. Subscreve novamente quando quiseres."
        }
        if sub.isSubscribed {
            if let date = sub.expirationDateFormatted {
                return "Renova em \(date) • Funcionários ilimitados"
            }
            return "Funcionários ilimitados • Renovação automática"
        }
        if trial.isTrialActive { return "Trial gratuito de 15 dias • Todas as funcionalidades" }
        return "Subscreve para continuar a usar o POS"
    }

    var body: some View {
        VStack(spacing: 0) {

            // Estado principal
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: statusIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(statusSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            // Barra de trial (só quando trial ativo sem subscrição)
            if trial.isTrialActive && !sub.isSubscribed {
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Período Trial")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: trial.daysRemaining <= 3 ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(trial.daysRemaining <= 3 ? .red : .secondary)
                            Text("\(trial.daysRemaining) de 15 dias restantes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(trial.daysRemaining <= 3 ? .red : .secondary)
                        }
                    }
                    .padding(.horizontal, 18)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(trial.daysRemaining <= 3 ? Color.red : Color.orange)
                                .frame(width: geo.size.width * (Double(trial.daysRemaining) / 15.0), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }
            }

            Divider()

            // Botões de ação
            if !sub.isSubscribed {
                subscriptionAction(
                    icon: "crown.fill",
                    title: "Subscrever por €9,99/mês",
                    color: AppTheme.brandPurple
                ) { showPaywall = true }

            } else if sub.isCancelled {
                subscriptionAction(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Reativar subscrição",
                    color: AppTheme.brandPurple
                ) { showPaywall = true }

            } else {
                subscriptionAction(
                    icon: "xmark.circle.fill",
                    title: "Cancelar subscrição",
                    color: .red.opacity(0.85)
                ) { showCancellation = true }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func subscriptionAction(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
