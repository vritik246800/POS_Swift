//
//  ProximityReceiverView.swift
//  POS_Sale_list
//
//  Interface para receber arquivos CSV de dispositivos próximos
//

import SwiftUI
import Network
 
struct ProximityReceiverView: View {
    @StateObject private var proximityManager = ProximityManager()
    @Environment(\.dismiss) private var dismiss
    
    var onFileReceived: (URL) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Ícone e título
                    iconHeader
                    
                    // Código de emparelhamento (S5)
                    if !proximityManager.pairingCode.isEmpty {
                        pairingCodeView
                            .transition(.opacity.combined(with: .scale))
                    }

                    // Pedido de ligação à espera de confirmação (S5)
                    if let peer = proximityManager.pendingPeerName {
                        pendingPeerPrompt(peer: peer)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Estado atual
                    stateView

                    Spacer()
                    
                    // Botão cancelar
                    Button(action: {
                        proximityManager.disconnect()
                        dismiss()
                    }) {
                        Text("Cancelar")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                .animation(.easeInOut, value: proximityManager.pairingCode)
                .animation(.easeInOut, value: proximityManager.pendingPeerName)
            }
            .navigationTitle("Dispositivos iOS por Perto")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                proximityManager.startAdvertising()
            }
            .onDisappear {
                proximityManager.stopAdvertising()
            }
            .onChange(of: proximityManager.receivedFileURL) { _, newURL in
                if let url = newURL {
                    // Arquivo recebido com sucesso
                    onFileReceived(url)
                    
                    // Aguardar um pouco e fechar
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var iconHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Dispositivos iOS por Perto")
                .font(.title2.weight(.bold))
        }
    }
    
    /// S5 — o código tem de ser escrito no dispositivo que envia.
    private var pairingCodeView: some View {
        VStack(spacing: 8) {
            Text("Código de emparelhamento")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(proximityManager.pairingCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .tracking(6)
                .accessibilityLabel("Código de emparelhamento \(proximityManager.pairingCode.map(String.init).joined(separator: " "))")

            Text("Escreve este código no dispositivo que envia.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    /// S5 — nenhuma ligação arranca sem o utilizador aceitar.
    private func pendingPeerPrompt(peer: String) -> some View {
        VStack(spacing: 12) {
            Text("Pedido de ligação")
                .font(.headline)

            Text(peer)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Recusar") { proximityManager.rejectPendingConnection() }
                    .buttonStyle(.glass)

                Button("Aceitar") { proximityManager.acceptPendingConnection() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var stateView: some View {
        switch proximityManager.state {
        case .idle, .discovering:
            discoveringView
            
        case .connected:
            connectedView
            
        case .receiving:
            receivingView
            
        case .completed:
            completedView
            
        case .failed(let error):
            errorView(error: error)
        }
    }
    
    private var discoveringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)
            
            Text("A procurar dispositivos iOS na rede local...")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Certifica-te que a app iOS está aberta e no mesmo Wi-Fi")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
    
    private var connectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Conectado")
                .font(.title3.weight(.semibold))
            
            Text("Aguardando transferência...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
    
    private var receivingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: proximityManager.transferProgress)
                .progressViewStyle(.linear)
                .tint(.purple)
                .scaleEffect(y: 2)
            
            Text("Recebendo arquivo...")
                .font(.title3.weight(.semibold))
            
            Text("\(Int(proximityManager.transferProgress * 100))%")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.purple)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
    
    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .symbolEffect(.bounce)
            
            Text("Arquivo Recebido!")
                .font(.title2.weight(.bold))
            
            Text("Importando CSV...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
    
    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Erro")
                .font(.title3.weight(.semibold))
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Mostrar ajuda específica para erro de autorização
            if let nwError = error as? NWError,
               case .posix(let code) = nwError,
               code.rawValue == 1 {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.vertical, 8)
                    
                    Text("💡 Dica")
                        .font(.headline)
                    
                    Text("Verifique se adicionou as permissões necessárias no Info.plist:\n\n• NSLocalNetworkUsageDescription\n• NSBonjourServices (_posapp._tcp)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }
}

#Preview {
    ProximityReceiverView { url in
        print("Arquivo recebido em: \(url)")
    }
}
