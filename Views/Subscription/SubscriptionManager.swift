internal import Combine
import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    @Published var isSubscribed = false
    @Published var expirationDate: Date? = nil      // data de fim do período pago
    @Published var isCancelled = false              // cancelado mas ainda no período pago
    @Published var products: [StoreKit.Product] = []
    @Published var isLoading = false

    let productID = "com.posapp.subscription.monthly"

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await checkSubscriptionStatus()
        }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Acesso permitido
    var hasAccess: Bool {
        isSubscribed || TrialManager.shared.isTrialActive
    }

    // MARK: - Data de expiração formatada
    var expirationDateFormatted: String? {
        guard let date = expirationDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    // MARK: - Carregar produto
    func loadProducts() async {
        isLoading = true
        do {
            products = try await StoreKit.Product.products(for: [productID])
        } catch {
            print("Erro StoreKit: \(error)")
        }
        isLoading = false
    }

    // MARK: - Comprar
    func purchase(_ product: StoreKit.Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await checkSubscriptionStatus()
        case .userCancelled, .pending: break
        @unknown default: break
        }
    }

    // MARK: - Verificar estado (com data expiração e estado cancelado)
    func checkSubscriptionStatus() async {
        var active = false
        var expiry: Date? = nil
        var cancelled = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                active = true
                expiry = transaction.expirationDate

                // Verificar se foi cancelado (subscrição não vai renovar)
                if let status = await transaction.subscriptionStatus {
                    if case .expired = status.state {
                        cancelled = true
                    }
                    if case .inBillingRetryPeriod = status.state {
                        cancelled = true
                    }
                    // renewalInfo indica se vai renovar
                    if case .verified(let renewal) = status.renewalInfo {
                        if !renewal.willAutoRenew {
                            cancelled = true
                        }
                    }
                }
            }
        }

        isSubscribed = active
        expirationDate = expiry
        isCancelled = cancelled
    }

    // MARK: - Restaurar
    func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    // MARK: - Listener de transações em tempo real
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.checkSubscriptionStatus()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        guard case .verified(let value) = result else {
            throw StoreKitError.notEntitled
        }
        return value
    }
}
