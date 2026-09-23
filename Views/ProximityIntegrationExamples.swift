import SwiftUI

// MARK: - Exemplo de Integração Completa

/// Este ficheiro demonstra como integrar o sistema de partilha de proximidade
/// numa view existente do teu projeto POS

// MARK: - 1. Adicionar à View Principal de Produtos

struct ProductsMainView_Example: View {
    @EnvironmentObject var productViewModel: ProductViewModel
    @StateObject private var proximityService = POSProximityService.shared
    
    @State private var showLowStockSheet = false
    
    var lowStockCount: Int {
        productViewModel.lowStockProducts.count
    }
    
    var body: some View {
        VStack {
            // Tua lista de produtos existente
            // ...
            
            // Indicador de stock baixo com botão de acesso rápido
            if lowStockCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    
                    Text("\(lowStockCount) produto(s) com stock baixo")
                        .font(.callout)
                    
                    Spacer()
                    
                    Button("Gerir Stock") {
                        showLowStockSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
            }
        }
        .sheet(isPresented: $showLowStockSheet) {
            LowStockView()
                .environmentObject(productViewModel)
        }
        // Inicia descoberta de dispositivos quando a view aparece
        .onAppear {
            if proximityService.isDiscovering {
                proximityService.stopDiscovery()
            }
        }
    }
}

// MARK: - 2. Uso do Serviço de Exportação

struct ExportExample: View {
    @EnvironmentObject var productViewModel: ProductViewModel
    
    func exportStockToiOS() {
        let exporter = LowStockExportService.shared
        let products = productViewModel.lowStockProducts
        
        // Quantidades a encomendar (exemplo)
        let orderQty: [Int: Int] = [
            1: 10,  // Produto ID 1: encomendar 10 unidades
            2: 5,   // Produto ID 2: encomendar 5 unidades
        ]
        
        // Exportar para JSON
        if let jsonURL = exporter.exportLowStockJSON(products: products, orderQuantities: orderQty) {
            print("✅ JSON exportado para: \(jsonURL.path)")
            
            // Agora podes:
            // 1. Enviar via proximidade para iOS
            // 2. Partilhar via ShareLink
            // 3. Importar noutro sistema
        }
        
        // Exportar para CSV
        if let csvURL = exporter.exportLowStockCSV(products: products, orderQuantities: orderQty) {
            print("✅ CSV exportado para: \(csvURL.path)")
        }
    }
    
    var body: some View {
        Button("Exportar Stock") {
            exportStockToiOS()
        }
    }
}

// MARK: - 3. Envio Directo para Dispositivo iOS

struct DirectSendExample: View {
    @StateObject private var proximityService = POSProximityService.shared
    @EnvironmentObject var productViewModel: ProductViewModel
    
    @State private var selectedDevice: POSDevice?
    @State private var isSending = false
    
    var body: some View {
        VStack {
            Text("Dispositivos iOS Disponíveis")
                .font(.headline)
            
            if proximityService.isDiscovering {
                ProgressView("A procurar...")
            } else {
                Button("Iniciar Descoberta") {
                    proximityService.startDiscovery()
                }
            }
            
            List(proximityService.availableDevices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.headline)
                        Text(device.platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if device.isReady {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                    
                    Button("Enviar") {
                        sendToDevice(device)
                    }
                    .disabled(isSending || !device.isReady)
                }
            }
        }
        .onDisappear {
            proximityService.stopDiscovery()
        }
    }
    
    private func sendToDevice(_ device: POSDevice) {
        isSending = true
        
        let exporter = LowStockExportService.shared
        let products = productViewModel.lowStockProducts
        let orderQty: [Int: Int] = [:] // Vazio por agora
        
        guard let jsonURL = exporter.exportLowStockJSON(products: products, orderQuantities: orderQty),
              let data = try? Data(contentsOf: jsonURL) else {
            print("❌ Erro ao preparar dados")
            isSending = false
            return
        }
        
        proximityService.sendStockData(data, to: device) { success in
            DispatchQueue.main.async {
                isSending = false
                
                if success {
                    print("✅ Enviado com sucesso para \(device.name)")
                } else {
                    print("❌ Falha ao enviar para \(device.name)")
                }
            }
        }
    }
}

// MARK: - 4. Recepção no iOS (dentro da App iOS)

struct iOSReceiverExample: View {
    @StateObject private var manager = StockReceiverManager()
    
    var body: some View {
        NavigationStack {
            List(manager.receivedProducts) { product in
                HStack {
                    VStack(alignment: .leading) {
                        Text(product.name)
                            .font(.headline)
                        Text(product.barcode)
                            .font(.caption)
                            .monospacedDigit()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Stock: \(product.currentStock)")
                            .font(.caption)
                            .foregroundStyle(product.stockLevel.color)
                        
                        if product.orderQuantity > 0 {
                            Text("Enc: \(product.orderQuantity)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Stock Recebido")
            .toolbar {
                ToolbarItem {
                    HStack {
                        Circle()
                            .fill(manager.isOnline ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(manager.isOnline ? "Online" : "Offline")
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            manager.startListening()
        }
        .onDisappear {
            manager.stopListening()
        }
    }
}

// MARK: - 5. Tratamento de Notificações de Dados Recebidos

class CustomStockHandler {
    init() {
        // Observa notificações de dados recebidos
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStockData(_:)),
            name: .posStockDataReceived,
            object: nil
        )
    }
    
    @objc private func handleStockData(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let data = userInfo["data"] as? [String: Any] else {
            return
        }
        
        print("📦 Dados de stock recebidos:")
        print("  Versão: \(data["version"] ?? "unknown")")
        print("  Data: \(data["exportDate"] ?? "unknown")")
        print("  Origem: \(data["source"] ?? "unknown")")
        
        if let products = data["products"] as? [[String: Any]] {
            print("  Produtos: \(products.count)")
            
            // Processar cada produto
            for productDict in products {
                if let name = productDict["name"] as? String,
                   let stock = productDict["stock"] as? Int {
                    print("    - \(name): \(stock) unidades")
                }
            }
            
            // Aqui podes:
            // 1. Actualizar a tua base de dados local
            // 2. Mostrar uma notificação ao utilizador
            // 3. Sincronizar com um servidor
            // 4. Gerar relatórios automáticos
        }
    }
}

// MARK: - 6. Integração com ShareLink (Partilha Tradicional)

struct ShareLinkExample: View {
    let products: [Product]
    let orderQty: [Int: Int]
    
    var csvURL: URL {
        let exporter = LowStockExportService.shared
        return exporter.exportLowStockCSV(products: products, orderQuantities: orderQty) ?? URL(fileURLWithPath: "/tmp/empty.csv")
    }
    
    var body: some View {
        ShareLink(
            item: csvURL,
            subject: Text("Lista de Stock Baixo"),
            message: Text("Produtos com stock crítico - \(Date().formatted())")
        ) {
            Label("Partilhar via AirDrop/Email", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - 7. Monitorização de Estado da Rede

struct NetworkStatusView: View {
    @StateObject private var proximityService = POSProximityService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Estado de anúncio (iOS)
            HStack {
                Image(systemName: proximityService.isAdvertising ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(proximityService.isAdvertising ? .green : .gray)
                
                Text(proximityService.isAdvertising ? "A anunciar presença" : "Não está a anunciar")
                    .font(.callout)
            }
            
            // Estado de descoberta (macOS/iPad)
            HStack {
                Image(systemName: proximityService.isDiscovering ? "magnifyingglass" : "magnifyingglass.circle")
                    .foregroundStyle(proximityService.isDiscovering ? .blue : .gray)
                
                Text(proximityService.isDiscovering ? "A procurar dispositivos" : "Descoberta inactiva")
                    .font(.callout)
            }
            
            // Dispositivos encontrados
            if !proximityService.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dispositivos encontrados:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(proximityService.availableDevices) { device in
                        HStack {
                            Circle()
                                .fill(device.isReady ? .green : .orange)
                                .frame(width: 6, height: 6)
                            
                            Text(device.name)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}

// MARK: - 8. Exemplo Completo de Fluxo

struct CompleteFlowExample: View {
    @StateObject private var proximityService = POSProximityService.shared
    @EnvironmentObject var productViewModel: ProductViewModel
    
    @State private var stage: FlowStage = .idle
    @State private var selectedProducts: [Product] = []
    @State private var orderQuantities: [Int: Int] = [:]
    @State private var selectedDevice: POSDevice?
    
    enum FlowStage: Hashable {
        case idle, selectingProducts, selectingDevice, sending, success, error(String)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Stage indicator
            stageView
            
            // Action buttons
            switch stage {
            case .idle:
                Button("Iniciar Exportação de Stock Baixo") {
                    selectedProducts = productViewModel.lowStockProducts
                    stage = .selectingProducts
                }
                
            case .selectingProducts:
                Text("\(selectedProducts.count) produtos seleccionados")
                
                Button("Continuar para Envio") {
                    proximityService.startDiscovery()
                    stage = .selectingDevice
                }
                
            case .selectingDevice:
                if proximityService.availableDevices.isEmpty {
                    ProgressView("A procurar dispositivos iOS...")
                } else {
                    List(proximityService.availableDevices) { device in
                        Button(device.name) {
                            selectedDevice = device
                            sendData()
                        }
                        .disabled(!device.isReady)
                    }
                }
                
            case .sending:
                ProgressView("A enviar dados...")
                
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Dados enviados com sucesso!")
                
                Button("Concluir") {
                    reset()
                }
                
            case .error(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text(message)
                
                Button("Tentar Novamente") {
                    stage = .selectingDevice
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var stageView: some View {
        HStack {
            ForEach([FlowStage.idle, .selectingProducts, .selectingDevice, .sending], id: \.self) { s in
                Circle()
                    .fill(stageColor(s))
                    .frame(width: 12, height: 12)
            }
        }
    }
    
    private func stageColor(_ s: FlowStage) -> Color {
        // Simplificado - compara estágios
        .gray
    }
    
    private func sendData() {
        guard let device = selectedDevice else { return }
        
        stage = .sending
        
        let exporter = LowStockExportService.shared
        guard let jsonURL = exporter.exportLowStockJSON(products: selectedProducts, orderQuantities: orderQuantities),
              let data = try? Data(contentsOf: jsonURL) else {
            stage = .error("Erro ao preparar dados")
            return
        }
        
        proximityService.sendStockData(data, to: device) { success in
            DispatchQueue.main.async {
                if success {
                    stage = .success
                } else {
                    stage = .error("Falha na transferência")
                }
                
                proximityService.stopDiscovery()
            }
        }
    }
    
    private func reset() {
        stage = .idle
        selectedProducts = []
        orderQuantities = [:]
        selectedDevice = nil
    }
}
