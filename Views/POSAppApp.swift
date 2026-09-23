import SwiftUI

/* PROMPT
 o programa eu nao estou activo depois de um tempo , quando quero agora testar , como ainda estou a fazer no xcode ...

 * quando faco subscrever ou restourar a compra anterior ele da toda a info mais nao consigo passar para janela de login
 */

/// Raiz da janela: decide entre paywall, login e painel principal.
///
/// Vive numa View (e não dentro do `Scene`) para poder ler `Reduce Motion` do
/// ambiente e animar a troca de ecrã — o login sai a encolher e a esbater-se,
/// o painel entra a crescer.
struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.5, extraBounce: 0.05)
    }

    var body: some View {
        ZStack {
            if !subscriptionManager.hasAccess {
                PaywallView()
                    .transition(.opacity)
            } else if authViewModel.isLoggedIn {
                MainView()
                    .transition(AnyTransition.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.03)),
                        removal: .opacity
                    ))
            } else {
                LoginView()
                    .transition(AnyTransition.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.94))
                    ))
            }
        }
        .animation(transitionAnimation, value: authViewModel.isLoggedIn)
        .animation(transitionAnimation, value: subscriptionManager.hasAccess)
    }
}

@main
struct POSAppApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var categoryViewModel = CategoryViewModel()
    @StateObject private var batchViewModel = BatchViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(batchViewModel)
                .environmentObject(subscriptionManager)
                .onAppear {
                    TrialManager.shared.registerFirstLaunchIfNeeded()
                    categoryViewModel.loadCategories()
                    batchViewModel.loadBatches()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .inactive || newPhase == .background {
                saveEndOfDayReport()
            }
            // Verifica subscrição sempre que a app volta ao primeiro plano
            // Apanha cancelamentos feitos fora da app (App Store)
            if newPhase == .active {
                Task {
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Gravar relatório do dia ao fechar
    private func saveEndOfDayReport() {
        let db = DatabaseManager.shared
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let sales = db.fetchSalesByDate(date: today)
        guard !sales.isEmpty else { return }

        let service = ReportService()
        service.exportDailyCSV(sales: sales, date: Date())
        Task {
            _ = await service.exportDailyPDF(sales: sales, date: Date())
        }
    }

    // MARK: - Gravar relatório do Mês ao fechar
    private func saveEndOfMonthReportIfNeeded() {
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        guard calendar.component(.day, from: tomorrow) == 1 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthStr = formatter.string(from: today)

        let db = DatabaseManager.shared
        let sales = db.fetchSalesByMonth(yearMonth: monthStr)
        guard !sales.isEmpty else { return }

        let service = ReportService()
        service.exportMonthlyCSV(sales: sales, date: today)
        Task {
            _ = await service.exportMonthlyPDF(sales: sales, date: today)
        }
    }
}
