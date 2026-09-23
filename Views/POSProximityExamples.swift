import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Exemplo: Vista iOS/iPadOS - Receptor

/// Vista para dispositivo iOS que aguarda receber lista de stock
struct StockReceiverView: View {
    @StateObject private var proximityService = POSProximityService.shared
    @State private var receivedProducts: [ReceivedProduct] = []
    @State private var showingAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Indicador de estado
                StatusIndicator(
                    isAdvertising: proximityService.isAdvertising,
                    isWaitingForList: proximityService.isWaitingForList
                )
                
                // Botão de toggle
                Button {
                    toggleWaitingState()
                } label: {
                    Label(
                        proximityService.isWaitingForList 
                            ? "Parar de aguardar lista"
                            : "Aguardar lista de stock",
                        systemImage: proximityService.isWaitingForList 
                            ? "pause.circle.fill"
                            : "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(proximityService.isWaitingForList ? Color.orange : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Divider()
                
                // Lista de produtos recebidos
                if receivedProducts.isEmpty {
                    ContentUnavailableView(
                        "Nenhum produto recebido",
                        systemImage: "tray",
                        description: Text(proximityService.isWaitingForList 
                            ? "A aguardar dados do desktop..."
                            : "Active o modo de recepção acima")
                    )
                } else {
                    List(receivedProducts) { product in
                        ReceivedProductRowView(product: product)
                    }
                }
            }
            .navigationTitle("Receber Stock")
            .onAppear {
                startAdvertising()
                setupNotifications()
            }
            .onDisappear {
                proximityService.stopAdvertising()
            }
            .alert("Lista recebida!", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text("Foram recebidos \(receivedProducts.count) produtos.")
            }
        }
    }
    
    private func startAdvertising() {
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? "Unknown Device"
        #endif
        proximityService.startAdvertising(deviceName: deviceName, waitingForList: true)
    }
    
    private func toggleWaitingState() {
        proximityService.updateWaitingForListState(!proximityService.isWaitingForList)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .posStockDataReceived,
            object: nil,
            queue: .main
        ) { notification in
            handleReceivedData(notification)
        }
    }
    
    private func handleReceivedData(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let data = userInfo["data"] as? [String: Any],
              let productsData = data["products"] as? [[String: Any]] else {
            return
        }
        
        receivedProducts = productsData.compactMap { dict -> ReceivedProduct? in
            guard let barcode = dict["barcode"] as? String,
                  let name = dict["name"] as? String,
                  let stock = dict["stock"] as? Int,
                  let orderQty = dict["orderQty"] as? Int,
                  let priceBase = dict["priceBase"] as? Double else {
                return nil
            }
            
            return ReceivedProduct(
                barcode: barcode,
                name: name,
                currentStock: stock,
                orderQuantity: orderQty,
                priceBase: priceBase
            )
        }
        
        showingAlert = true
        
        // Depois de receber, pode optar por desativar o modo de espera
        proximityService.updateWaitingForListState(false)
    }
}

// MARK: - Exemplo: Vista macOS - Emissor

/// Vista para macOS que detecta dispositivos iOS e envia lista de stock
struct StockSenderView: View {
    @StateObject private var proximityService = POSProximityService.shared
    @State private var selectedDevice: POSDevice?
    @State private var isSending = false
    @State private var showingResult = false
    @State private var sendSuccess = false
    
    let products: [Product]
    let orderQuantities: [Int: Int]
    
    var body: some View {
        VStack(spacing: 20) {
            // Cabeçalho
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("Dispositivos Próximos")
                        .font(.headline)
                    Text(proximityService.isDiscovering ? "A procurar..." : "Inativo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Filtro: mostrar apenas a aguardar lista
                if !proximityService.devicesWaitingForList.isEmpty {
                    Text("\(proximityService.devicesWaitingForList.count) a aguardar")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            Divider()
            
            // Lista de dispositivos
            if proximityService.availableDevices.isEmpty {
                ContentUnavailableView(
                    "Nenhum dispositivo encontrado",
                    systemImage: "iphone.slash",
                    description: Text("Certifique-se que o dispositivo iOS está na mesma rede")
                )
            } else {
                List(proximityService.availableDevices, selection: $selectedDevice) { device in
                    DeviceRowView(device: device)
                        .tag(device)
                }
            }
            
            // Botão de envio
            Button {
                sendToSelectedDevice()
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Enviar Lista de Stock", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedDevice == nil || isSending)
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            proximityService.startDiscovery()
        }
        .onDisappear {
            proximityService.stopDiscovery()
        }
        .alert(sendSuccess ? "Enviado!" : "Erro", isPresented: $showingResult) {
            Button("OK") { }
        } message: {
            Text(sendSuccess 
                ? "Lista enviada com sucesso para \(selectedDevice?.name ?? "dispositivo")"
                : "Falha ao enviar lista. Tente novamente.")
        }
    }
    
    private func sendToSelectedDevice() {
        guard let device = selectedDevice else { return }
        
        isSending = true
        
        // Exportar como JSON
        let exporter = LowStockExportService.shared
        guard let url = exporter.exportLowStockJSON(
            products: products,
            orderQuantities: orderQuantities
        ) else {
            isSending = false
            sendSuccess = false
            showingResult = true
            return
        }
        
        // Ler dados
        guard let data = try? Data(contentsOf: url) else {
            isSending = false
            sendSuccess = false
            showingResult = true
            return
        }
        
        // Enviar
        proximityService.sendStockData(data, to: device) { success in
            DispatchQueue.main.async {
                isSending = false
                sendSuccess = success
                showingResult = true
            }
        }
    }
}

// MARK: - Componentes de UI

struct StatusIndicator: View {
    let isAdvertising: Bool
    let isWaitingForList: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.headline)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isWaitingForList {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color(white: 0.95))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        if !isAdvertising {
            return .gray
        } else if isWaitingForList {
            return .orange
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        if !isAdvertising {
            return "Offline"
        } else if isWaitingForList {
            return "A aguardar lista"
        } else {
            return "Online"
        }
    }
    
    private var statusDescription: String {
        if !isAdvertising {
            return "Dispositivo não visível na rede"
        } else if isWaitingForList {
            return "Pronto para receber dados do desktop"
        } else {
            return "Visível mas não a aguardar dados"
        }
    }
}

struct DeviceRowView: View {
    let device: POSDevice
    
    var body: some View {
        HStack {
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(device.platform)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    if device.isWaitingForList {
                        Text("A aguardar 📋")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            if device.isWaitingForList {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var deviceIcon: String {
        switch device.platform.lowercased() {
        case "ios":
            return "iphone"
        case "ipados":
            return "ipad"
        case "macos":
            return "laptopcomputer"
        default:
            return "questionmark.circle"
        }
    }
}

struct ReceivedProductRowView: View {
    let product: ReceivedProduct
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(product.name)
                    .font(.headline)
                
                Spacer()
                
                // Badge de nível de stock
                Text(product.stockLevel.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(product.stockLevel.color.opacity(0.2))
                    .foregroundColor(product.stockLevel.color)
                    .cornerRadius(6)
            }
            
            HStack {
                Label("\(product.currentStock)", systemImage: "cube.box")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if product.orderQuantity > 0 {
                    Label("Encomendar: \(product.orderQuantity)", systemImage: "cart")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Text(product.barcode)
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospaced()
        }
        .padding(.vertical, 4)
    }
}

