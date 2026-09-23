import SwiftUI

struct MainView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var batchViewModel: BatchViewModel
    @StateObject private var productViewModel = ProductViewModel()
    @StateObject private var saleViewModel = SaleViewModel()
    @State private var selectedTab: AppTab = .sales
    @State private var showCloseAlert = false           // NOVO
    @State private var showExpiryAlert = false          // 2.3
    @State private var showStaleAlert = false           // Administração
    @State private var staleCount = 0
    @State private var startupChecksDone = false
    /// Nome do programa configurado em Definições — reflete sem reiniciar.
    @AppStorage(Constants.appNameKey) private var appName = Constants.defaultAppName

    enum AppTab {
        case sales, products, reports, dayClose, admin, settings
    }

    /// Lotes fora de `.safe`/`.none` — alimenta o badge do separador Produtos.
    private var expiringBatchCount: Int {
        batchViewModel.batches.filter { $0.expiryStatus.isAlerting }.count
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    var macOSLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Perfil Caixa não tem Produtos, Relatórios nem Administração —
                // a barreira real está na camada de dados; aqui só se esconde.
                List(selection: $selectedTab) {
                    Label("Vendas", systemImage: "cart")
                        .tag(AppTab.sales)
                    if authViewModel.isAdmin {
                        HStack {
                            Label("Produtos", systemImage: "cube.box")
                            Spacer()
                            ExpiryBadge(count: expiringBatchCount)
                        }
                        .tag(AppTab.products)
                        Label("Relatórios", systemImage: "chart.bar")
                            .tag(AppTab.reports)
                    }
                    Label("Fecho de Caixa", systemImage: "lock.circle")
                        .tag(AppTab.dayClose)
                    if authViewModel.isAdmin {
                        Label("Administração", systemImage: "chart.bar.doc.horizontal")
                            .tag(AppTab.admin)
                        Label("Definições", systemImage: "gearshape")
                            .tag(AppTab.settings)
                    }
                }
                .navigationTitle(appName)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        POSGuideWindowController.shared.open(isAdmin: authViewModel.isAdmin)
                    } label: {
                        Label("Guia", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Abrir guia de utilização (⌘?)")
                }
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        authViewModel.logout()
                    } label: {
                        Label("Sair", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        } detail: {
            currentView
        }
        // MARK: Alerta de fecho pendente
        .alert("Fecho de Caixa Pendente", isPresented: $showCloseAlert) {
            Button("Ir para Fecho") { selectedTab = .dayClose }
            Button("Ignorar", role: .cancel) { checkStaleProducts() }
        } message: {
            Text("O dia de hoje ainda não foi fechado. Recomenda-se fazer o fecho antes de terminar a sessão.")
        }
        .alert("Produtos parados", isPresented: $showStaleAlert) {
            Button("Ver e fazer promoção") { dismissStaleAlertToday(); selectedTab = .admin }
            Button("Agora não", role: .cancel) { dismissStaleAlertToday() }
        } message: {
            Text("\(staleCount) produto(s) com stock não vendem há mais de 6 meses. Uma promoção ajuda a escoá-los.")
        }
        .sheet(isPresented: $showExpiryAlert, onDismiss: checkPendingClose) {
            expiryAlertSheet
        }
        .onAppear { runStartupChecks() }
    }
    #endif

    // MARK: - iOS

    var iOSLayout: some View {
        TabView(selection: $selectedTab) {
            currentSalesView
                .tabItem { Label("Vendas", systemImage: "cart") }
                .tag(AppTab.sales)

            if authViewModel.isAdmin {
                currentProductsView
                    .tabItem { Label("Produtos", systemImage: "cube.box") }
                    .badge(expiringBatchCount)
                    .tag(AppTab.products)

                currentReportsView
                    .tabItem { Label("Relatórios", systemImage: "chart.bar") }
                    .tag(AppTab.reports)
            }

            currentDayCloseView
                .tabItem { Label("Fecho", systemImage: "lock.circle") }
                .tag(AppTab.dayClose)

            if authViewModel.isAdmin {
                currentAdminView
                    .tabItem { Label("Admin", systemImage: "chart.bar.doc.horizontal") }
                    .tag(AppTab.admin)

                currentSettingsView
                    .tabItem { Label("Definições", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
        }
        .overlay(alignment: .bottomLeading) {
            POSGuideButtoniPad(isAdmin: authViewModel.isAdmin)
        }
        .alert("Fecho de Caixa Pendente", isPresented: $showCloseAlert) {
            Button("Ir para Fecho") { selectedTab = .dayClose }
            Button("Ignorar", role: .cancel) { checkStaleProducts() }
        } message: {
            Text("O dia de hoje ainda não foi fechado.")
        }
        .alert("Produtos parados", isPresented: $showStaleAlert) {
            Button("Ver e fazer promoção") { dismissStaleAlertToday(); selectedTab = .admin }
            Button("Agora não", role: .cancel) { dismissStaleAlertToday() }
        } message: {
            Text("\(staleCount) produto(s) com stock não vendem há mais de 6 meses. Uma promoção ajuda a escoá-los.")
        }
        .sheet(isPresented: $showExpiryAlert, onDismiss: checkPendingClose) {
            expiryAlertSheet
        }
        .onAppear { runStartupChecks() }
    }

    // MARK: - Alerta de validade no arranque (2.3)

    private var expiryAlertSheet: some View {
        ExpiryAlertView { selectedTab = .products }
            .environmentObject(batchViewModel)
            .environmentObject(productViewModel)
    }

    /// Ordem de arranque: primeiro o alerta de validade (sheet), o fecho pendente
    /// só depois de o sheet fechar — evitar alert e sheet em simultâneo.
    private func runStartupChecks() {
        guard !startupChecksDone else { return }
        startupChecksDone = true

        productViewModel.loadProducts()
        batchViewModel.loadBatches()
        categoryViewModel.loadCategories()

        if batchViewModel.shouldShowExpiryAlert() {
            showExpiryAlert = true
        } else {
            checkPendingClose()
        }
    }

    /// Produtos com stock parado há mais de 6 meses. Só interessa ao Admin — é
    /// ele que decide a promoção — e aparece no máximo uma vez por dia.
    private func checkStaleProducts() {
        guard authViewModel.isAdmin,
              UserDefaults.standard.string(forKey: Constants.staleAlertDismissedDateKey) != Constants.todayKey()
        else { return }

        let admin = AdminViewModel()
        admin.load()
        let stale = admin.staleProducts()
        guard !stale.isEmpty else { return }
        staleCount = stale.count
        showStaleAlert = true
    }

    private func dismissStaleAlertToday() {
        UserDefaults.standard.set(Constants.todayKey(), forKey: Constants.staleAlertDismissedDateKey)
    }

    // MARK: - Verifica fecho pendente

    private func checkPendingClose() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        // Só mostra o alerta se houver vendas hoje e o dia não estiver fechado
        let db = DatabaseManager.shared
        let hasSales = !db.fetchSalesByDate(date: today).isEmpty
        let isClosed = db.isDayAlreadyClosed(date: today)
        if hasSales && !isClosed {
            showCloseAlert = true
        } else {
            checkStaleProducts()
        }
    }

    // MARK: - Vista actual (macOS)

    @ViewBuilder
    var currentView: some View {
        switch selectedTab {
        case .sales:    currentSalesView
        case .products: currentProductsView
        case .reports:  currentReportsView
        case .dayClose: currentDayCloseView
        case .admin:    currentAdminView
        case .settings: currentSettingsView
        }
    }

    var currentAdminView: some View {
        NavigationStack {
            AdminView()
                .environmentObject(authViewModel)
                .environmentObject(productViewModel)
        }
    }

    var currentSalesView: some View {
        NavigationStack {
            SaleView()
                .environmentObject(saleViewModel)
                .environmentObject(productViewModel)
                .environmentObject(authViewModel)
        }
    }

    var currentProductsView: some View {
        NavigationStack {
            ProductListView()
                .environmentObject(productViewModel)
        }
    }

    var currentReportsView: some View {
        NavigationStack {
            // Picker segmentado em vez de `TabView`: o `TabView` instancia todas as
            // secções ao mesmo tempo e os `.toolbar` de cada uma fundiam-se na mesma
            // barra — apareciam os botões "Exportar" do Diário e do Mensal juntos.
            // Com o picker só existe a secção activa, logo só o seu botão.
            ReportsHomeView()
                .environmentObject(authViewModel)
        }
    }

    var currentDayCloseView: some View {
        NavigationStack {
            DayCloseView()
                .environmentObject(authViewModel)
        }
    }

    var currentSettingsView: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(authViewModel)
        }
    }
}

// MARK: - Relatórios (picker segmentado, macOS + iOS)

/// Uma secção de cada vez. Além de evitar barras de tabs aninhadas em iOS,
/// garante que só o `.toolbar` da secção activa chega à barra da janela —
/// é o que impede dois botões "Exportar" ao mesmo tempo em macOS.
struct ReportsHomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedSection: Section = .daily

    /// O histórico de relatórios passou para Administração — aqui ficam só as
    /// secções de consulta do período.
    enum Section: String, CaseIterable, Identifiable {
        case daily = "Diário"
        case monthly = "Mensal"
        case annual = "Anual"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Secção", selection: $selectedSection) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch selectedSection {
            case .daily:
                DailyReportView()
                    .environmentObject(authViewModel)
            case .monthly:
                MonthlyReportView()
            case .annual:
                AnnualReportView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSection)
    }
}

// MARK: - Badge de lotes a expirar (sidebar macOS)

/// Contagem de lotes fora de prazo/em risco. Cor + número — nunca só cor.
struct ExpiryBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ExpiryStatus.expired.color, in: Capsule())
                .accessibilityLabel("\(count) lote(s) a expirar")
        }
    }
}

// MARK: - Botão Guia para iPad

struct POSGuideButtoniPad: View {
    var isAdmin: Bool = false
    @State private var showGuide = false

    var body: some View {
        Button {
            showGuide = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.gradient)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 3)
        }
        .padding(.leading, 20)
        .padding(.bottom, 90)
        .sheet(isPresented: $showGuide) {
            POSGuideView(isAdmin: isAdmin)
        }
    }
}
