import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var animateIn = false

    private let trial = TrialManager.shared

    var body: some View {
        ZStack {
            // Fundo
            LinearGradient(
                colors: [Color(hex: "0F0F1A"), Color(hex: "1A1030"), Color(hex: "0F0F1A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Círculos decorativos
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: "6B3FA0").opacity(0.15))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.6, y: -80)
                Circle()
                    .fill(Color(hex: "3F6BA0").opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -60, y: geo.size.height * 0.6)
            }

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 16) {
                        // Badge estado trial
                        HStack(spacing: 8) {
                            Circle()
                                .fill(trial.isTrialExpired ? Color.red : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(trial.isTrialExpired ? "TRIAL EXPIRADO" : "TRIAL ATIVO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(trial.isTrialExpired ? .red : .orange)
                                .tracking(2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill((trial.isTrialExpired ? Color.red : Color.orange).opacity(0.12))
                                .overlay(Capsule().stroke((trial.isTrialExpired ? Color.red : Color.orange).opacity(0.3), lineWidth: 1))
                        )

                        if trial.isTrialExpired {
                            Text("Subscrição\nNecessária")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("\(trial.daysRemaining)")
                                .font(.system(size: 72, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [.orange, Color(hex: "FF6B35")], startPoint: .top, endPoint: .bottom)
                                )
                            Text("dias restantes no trial")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }

                        Text(trial.isTrialExpired
                             ? "Subscreve para continuar a usar o POS"
                             : "Subscreve agora e continua sem interrupções")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48).padding(.horizontal, 32)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                    .animation(.easeOut(duration: 0.5), value: animateIn)

                    // MARK: Features
                    VStack(spacing: 10) {
                        FeatureItem(icon: "bolt.fill",           color: Color(hex: "FFB800"), text: "Vendas e carrinho ilimitados")
                        FeatureItem(icon: "person.2.fill",       color: Color(hex: "34C759"), text: "Funcionários ilimitados")
                        FeatureItem(icon: "cube.box.fill",       color: Color(hex: "007AFF"), text: "Gestão de produtos e stock")
                        FeatureItem(icon: "chart.bar.fill",      color: Color(hex: "FF6B35"), text: "Relatórios diários e mensais")
                        FeatureItem(icon: "lock.doc.fill",       color: Color(hex: "AF52DE"), text: "Fecho de caixa e exportação PDF")
                    }
                    .padding(.top, 32).padding(.horizontal, 28)
                    .opacity(animateIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.15), value: animateIn)

                    // MARK: Plano único
                    VStack(spacing: 0) {
                        if subscriptionManager.isLoading {
                            ProgressView().tint(.white).padding(40)
                        } else {
                            // Card do plano
                            VStack(spacing: 16) {
                                // Preço grande em destaque
                                VStack(spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("€9,99")
                                            .font(.system(size: 52, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text("/ mês")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                            .padding(.bottom, 8)
                                    }
                                    // Preço real do StoreKit se disponível
                                    if let product = subscriptionManager.products.first {
                                        Text(product.displayPrice + " cobrado mensalmente")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.35))
                                    } else {
                                        Text("€9,99 cobrado mensalmente")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.white.opacity(0.35))
                                    }
                                }

                                // Destaques do plano
                                HStack(spacing: 20) {
                                    PlanHighlight(value: "∞", label: "Funcionários")
                                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 36)
                                    PlanHighlight(value: "∞", label: "Vendas")
                                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 36)
                                    PlanHighlight(value: "15", label: "Dias trial")
                                }
                                .padding(.horizontal, 8)
                            }
                            .padding(28)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "6B3FA0").opacity(0.35), Color(hex: "3F2080").opacity(0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color(hex: "9B6FD0").opacity(0.4), lineWidth: 1.5)
                                    )
                            )
                            .shadow(color: Color(hex: "6B3FA0").opacity(0.3), radius: 20, y: 8)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 30)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: animateIn)
                        }
                    }
                    .padding(.top, 28).padding(.horizontal, 24)

                    // MARK: CTA
                    VStack(spacing: 14) {
                        if let error = errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }

                        Button {
                            Task { await handlePurchase() }
                        } label: {
                            ZStack {
                                if isPurchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "crown.fill").font(.system(size: 15))
                                        Text("Subscrever por €9,99/mês")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: isPurchasing
                                        ? [Color.gray.opacity(0.4), Color.gray.opacity(0.3)]
                                        : [Color(hex: "7B4FBF"), Color(hex: "5B2FA0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(hex: "7B4FBF").opacity(0.5), radius: 20, y: 8)
                        }
                        .disabled(isPurchasing)
                        .padding(.horizontal, 24)

                        Button("Restaurar compra anterior") {
                            Task { await subscriptionManager.restorePurchases() }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.4))

                        Text("Renovação automática mensal. Cancela em Definições de Sistema → App Store a qualquer momento.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                    .padding(.top, 28)
                    .opacity(animateIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.45), value: animateIn)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 680)
        .onAppear { animateIn = true }
    }

    private func handlePurchase() async {
        guard let product = subscriptionManager.products.first else {
            // Sem produto StoreKit disponível — acontece em desenvolvimento sem StoreKit config ativo
            errorMessage = "Produto não disponível. Verifica a configuração do StoreKit no Scheme."
            return
        }
        isPurchasing = true
        errorMessage = nil
        do {
            try await subscriptionManager.purchase(product)
            // Só fecha se a compra foi bem sucedida (purchase() atualiza isSubscribed)
            if subscriptionManager.isSubscribed {
                dismiss()
            }
        } catch {
            errorMessage = "Erro ao processar pagamento. Tenta novamente."
        }
        isPurchasing = false
    }
}

// MARK: - Plan Highlight
struct PlanHighlight: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feature Item
struct FeatureItem: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "34C759"))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

// NOTA: Color(hex:) e tokens de marca vivem agora em Utils/AppTheme.swift
