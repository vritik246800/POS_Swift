import SwiftUI

/// Ecrã de entrada da app.
///
/// Layout: painel dividido em ecrã largo (marca à esquerda, cartão de vidro à
/// direita), coluna única em ecrã estreito e no iOS.
/// Movimento: entrada escalonada ao abrir a app, abanão + clarão vermelho na
/// rejeição, saída animada no `RootView` quando o login é aceite.
/// Vidro: **um só plano** — o cartão do formulário. O fundo é `MeshGradient`.
struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Nome do programa configurado em Definições — reflete sem reiniciar.
    @AppStorage(Constants.appNameKey) private var appName = Constants.defaultAppName

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @FocusState private var focusedField: Field?

    // S6 — sem utilizadores na base de dados não há login possível:
    // o primeiro arranque cria o Admin aqui, nunca com password fixa em código.
    @State private var needsFirstAdmin: Bool = false
    @State private var adminName: String = ""
    @State private var adminPassword2: String = ""
    @State private var setupError: String = ""

    /// Estado só de animação — não guarda nada do utilizador.
    @State private var appeared: Bool = false
    @State private var drift: Bool = false

    enum Field { case name, username, password, password2 }

    private let minPasswordLength = 8
    /// Abaixo desta largura o ecrã passa a coluna única.
    private static let wideLayoutWidth: CGFloat = 860

    var canLogin: Bool {
        !username.isEmpty && !password.isEmpty
    }

    var canCreateAdmin: Bool {
        !adminName.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= minPasswordLength
            && password == adminPassword2
    }

    // MARK: - Animação

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private func entrance(delay: Double) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0.08).delay(delay)
    }

    /// Amplitude do abanão de rejeição. `Reduce Motion` deixa-a a zero —
    /// fica só o clarão, a UI não salta.
    private var shakeAmplitude: CGFloat { reduceMotion ? 0 : 14 }

    // MARK: - Corpo

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if geo.size.width >= Self.wideLayoutWidth {
                    splitLayout
                } else {
                    compactLayout
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Rejeição — abanão do ecrã inteiro, disparado por cada nova recusa.
        .keyframeAnimator(initialValue: CGFloat.zero,
                          trigger: authViewModel.loginFailureCount) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(shakeAmplitude, duration: 0.06)
                CubicKeyframe(-shakeAmplitude, duration: 0.08)
                CubicKeyframe(shakeAmplitude * 0.55, duration: 0.08)
                CubicKeyframe(-shakeAmplitude * 0.3, duration: 0.08)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .overlay(rejectionGlow)
        .onAppear {
            // Base de dados vazia = primeiro arranque
            needsFirstAdmin = authViewModel.userCount == 0
            appeared = true
            drift = true
            focusedField = needsFirstAdmin ? .name : .username
        }
        .onChange(of: authViewModel.loginFailureCount) {
            // Recusa: o cursor volta à password, o que foi escrito fica.
            focusedField = .password
        }
    }

    // MARK: - Fundo

    private var background: some View {
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            #else
            Color(uiColor: .systemBackground).ignoresSafeArea()
            #endif

            MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
                .ignoresSafeArea()
                // Discreto de propósito: dá profundidade sem pintar o ecrã
                // nem comer o contraste do texto sobre o vidro.
                .opacity(colorScheme == .dark ? 0.22 : 0.16)
                .animation(reduceMotion ? nil
                                        : .easeInOut(duration: 14).repeatForever(autoreverses: true),
                           value: drift)
                .allowsHitTesting(false)
        }
    }

    /// Pontos interiores da malha derivam devagar; os cantos ficam fixos.
    private var meshPoints: [SIMD2<Float>] {
        let d: Float = drift ? 0.10 : -0.08
        return [
            .init(0, 0),          .init(0.5 + d * 0.4, 0),     .init(1, 0),
            .init(0, 0.5 - d * 0.3), .init(0.5 + d, 0.5 - d * 0.5), .init(1, 0.5 + d * 0.3),
            .init(0, 1),          .init(0.5 - d * 0.5, 1),     .init(1, 1)
        ]
    }

    private var meshColors: [Color] {
        let accent = AppTheme.accent
        let purple = AppTheme.brandPurple
        return [
            accent, purple, accent,
            purple, accent, purple,
            accent, purple, accent
        ]
    }

    /// Clarão vermelho no ecrã inteiro quando o login é recusado.
    /// Mantém-se com `Reduce Motion` — é o sinal que substitui o abanão.
    private var rejectionGlow: some View {
        RadialGradient(colors: [.clear, .red.opacity(0.38)],
                       center: .center, startRadius: 140, endRadius: 760)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: 0.0,
                              trigger: authViewModel.loginFailureCount) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.0, duration: 0.10)
                    LinearKeyframe(0.0, duration: 0.50)
                }
            }
    }

    // MARK: - Layouts

    /// Ecrã largo: marca à esquerda, formulário à direita.
    private var splitLayout: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 64)

            VStack {
                card
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
        }
    }

    /// Ecrã estreito e iOS: coluna única, com scroll para o teclado não tapar.
    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 28) {
                compactBrand
                card
                footer
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Marca

    private var logoMark: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.16))
                .frame(width: 76, height: 76)
            Image(systemName: needsFirstAdmin ? "person.badge.key.fill" : "cart.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityHidden(true)
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            logoMark

            VStack(alignment: .leading, spacing: 6) {
                Text(appName)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(needsFirstAdmin
                     ? "Configuração inicial do sistema"
                     : "Vendas, stock e relatórios num só lugar")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                highlight("cart.fill", "Vendas em poucos toques")
                highlight("shippingbox.fill", "Stock e lotes com validade")
                highlight("chart.bar.fill", "Relatórios e fecho de caixa")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .animation(animation, value: needsFirstAdmin)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 22)
        .animation(entrance(delay: 0.05), value: appeared)
    }

    private var compactBrand: some View {
        VStack(spacing: 10) {
            logoMark
            Text(appName)
                .font(.system(.title, design: .rounded, weight: .bold))
            Text(needsFirstAdmin ? "Configuração inicial" : "Sistema de Vendas")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .animation(animation, value: needsFirstAdmin)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .animation(entrance(delay: 0.05), value: appeared)
    }

    private func highlight(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
            Text("Acesso seguro e encriptado")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 18)
        .opacity(appeared ? 1 : 0)
        .animation(entrance(delay: 0.32), value: appeared)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cartão de vidro (plano único)

    private var card: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader

                if needsFirstAdmin {
                    firstAdminForm
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    loginForm
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(24)
            .frame(maxWidth: 400)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .animation(animation, value: needsFirstAdmin)
        .animation(animation, value: authViewModel.errorMessage)
        .animation(animation, value: setupError)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
        .scaleEffect(appeared ? 1 : 0.97)
        .animation(entrance(delay: 0.18), value: appeared)
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(needsFirstAdmin ? "Criar Administrador" : "Bem-vindo de volta")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text(needsFirstAdmin
                 ? "Ainda não existe nenhum utilizador. Esta conta fica com acesso total."
                 : "Entre com o seu utilizador para abrir a caixa.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Formulário de login

    @ViewBuilder
    private var loginForm: some View {
        field(icon: "person.fill", focus: .username) {
            TextField("Utilizador", text: $username)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .onSubmit { focusedField = .password }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }

        passwordField(title: "Password", text: $password, focus: .password) {
            submitLogin()
        }

        if !authViewModel.errorMessage.isEmpty {
            errorBanner(authViewModel.errorMessage)
        }

        Button {
            submitLogin()
        } label: {
            Label("Entrar", systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(AppTheme.accent)
        .disabled(!canLogin)
        .padding(.top, 4)
    }

    private func submitLogin() {
        guard canLogin else { return }
        authViewModel.login(username: username, password: password)
    }

    // MARK: - Criação do primeiro Admin (S6)

    @ViewBuilder
    private var firstAdminForm: some View {
        field(icon: "person.text.rectangle.fill", focus: .name) {
            TextField("Nome completo", text: $adminName)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .username }
        }

        field(icon: "person.fill", focus: .username) {
            TextField("Utilizador", text: $username)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .onSubmit { focusedField = .password }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }

        passwordField(title: "Password (mín. \(minPasswordLength) caracteres)",
                      text: $password, focus: .password) {
            focusedField = .password2
        }
        passwordField(title: "Confirmar password",
                      text: $adminPassword2, focus: .password2) {
            createFirstAdmin()
        }

        if !password.isEmpty && password.count < minPasswordLength {
            hintBanner("A password tem de ter pelo menos \(minPasswordLength) caracteres.")
        } else if !adminPassword2.isEmpty && password != adminPassword2 {
            hintBanner("As passwords não coincidem.")
        }

        if !setupError.isEmpty {
            errorBanner(setupError)
        }

        Button {
            createFirstAdmin()
        } label: {
            Label("Criar Administrador", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(AppTheme.accent)
        .disabled(!canCreateAdmin)
        .padding(.top, 4)
    }

    private func createFirstAdmin() {
        let name = adminName.trimmingCharacters(in: .whitespaces)
        let user = username.trimmingCharacters(in: .whitespaces)

        guard canCreateAdmin else { return }

        let created = authViewModel.createUser(
            name: name,
            username: user,
            password: password,
            role: .admin
        )

        guard created else {
            setupError = "Não foi possível criar o utilizador. Tente outro nome de utilizador."
            return
        }

        // Nunca deixar a password em memória mais do que o necessário
        setupError = ""
        adminName = ""
        adminPassword2 = ""
        password = ""
        username = user
        withAnimation(animation) { needsFirstAdmin = false }
        focusedField = .password
    }

    // MARK: - Componentes de campo

    @ViewBuilder
    private func field<Content: View>(icon: String,
                                      focus: Field,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(focusedField == focus ? AppTheme.accent : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)                       // alvo mínimo de toque
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focusedField == focus ? AppTheme.accent.opacity(0.55) : Color.clear,
                        lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { focusedField = focus }
        .animation(animation, value: focusedField)
    }

    @ViewBuilder
    private func passwordField(title: String,
                               text: Binding<String>,
                               focus: Field,
                               onSubmit: @escaping () -> Void) -> some View {
        field(icon: "lock.fill", focus: focus) {
            // Com "mostrar password" ligado o campo é um `TextField` normal —
            // sem isto o teclado do iOS mete maiúscula automática e correção,
            // e a password escrita deixa de ser a que o utilizador quer.
            if showPassword {
                TextField(title, text: text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
                    .onSubmit(onSubmit)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } else {
                SecureField(title, text: text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
                    .onSubmit(onSubmit)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "Ocultar password" : "Mostrar password")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        banner(message, icon: "exclamationmark.triangle.fill", color: .red)
    }

    private func hintBanner(_ message: String) -> some View {
        banner(message, icon: "info.circle.fill", color: .orange)
    }

    private func banner(_ message: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
    }
}
