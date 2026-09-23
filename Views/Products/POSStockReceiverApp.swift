import SwiftUI
internal import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - App iOS para Receber Dados de Stock

/// Esta app iOS abre e anuncia presença na rede local
/// Quando recebe dados do desktop, mostra os produtos com stock baixo
/// e permite confirmar encomendas

//@main
struct POSStockReceiverApp: App {
    @StateObject private var stockManager = StockReceiverManager()
    
    var body: some Scene {
        WindowGroup {
            StockReceiverMainView()
                .environmentObject(stockManager)
                .onAppear {
                    stockManager.startListening()
                }
                .onDisappear {
                    stockManager.stopListening()
                }
        }
    }
}

// MARK: - Manager de Recepção

class StockReceiverManager: ObservableObject {
    @Published var isOnline = false
    @Published var receivedProducts: [ReceivedProduct] = []
    @Published var lastUpdate: Date?
    @Published var deviceName: String = ""
    
    private let proximityService = POSProximityService.shared
    
    init() {
        #if canImport(UIKit)
        deviceName = UIDevice.current.name
        #else
        deviceName = Host.current().localizedName ?? "Unknown Device"
        #endif
        
        // Observa notificações de dados recebidos
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReceivedData(_:)),
            name: .posStockDataReceived,
            object: nil
        )
    }
    
    func startListening() {
        proximityService.startAdvertising(deviceName: deviceName)
        isOnline = true
        print("📱 iOS App pronta para receber dados de stock")
    }
    
    func stopListening() {
        proximityService.stopAdvertising()
        isOnline = false
    }
    
    @objc private func handleReceivedData(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let data = userInfo["data"] as? [String: Any],
              let productsData = data["products"] as? [[String: Any]] else {
            return
        }
        
        DispatchQueue.main.async {
            self.receivedProducts = productsData.compactMap { dict in
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
            
            self.lastUpdate = Date()
            
            // Feedback háptico
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
            
            print("✅ Recebidos \(self.receivedProducts.count) produtos")
        }
    }
}

// MARK: - View Principal iOS

struct StockReceiverMainView: View {
    @EnvironmentObject var manager: StockReceiverManager
    @State private var searchText = ""
    @State private var showExportSheet = false
    
    var filteredProducts: [ReceivedProduct] {
        if searchText.isEmpty {
            return manager.receivedProducts
        }
        return manager.receivedProducts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.barcode.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var totalToOrder: Int {
        manager.receivedProducts.reduce(0) { $0 + $1.orderQuantity }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if manager.receivedProducts.isEmpty {
                    EmptyStateView(isOnline: manager.isOnline)
                } else {
                    StockReceiverProductListView(
                        products: filteredProducts,
                        searchText: $searchText,
                        totalToOrder: totalToOrder,
                        onExport: { showExportSheet = true }
                    )
                }
            }
            .navigationTitle("Stock Baixo")
            .toolbar {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.isOnline ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(manager.isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.isOnline ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(manager.isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showExportSheet) {
                ExportOptionsSheet(products: manager.receivedProducts)
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let isOnline: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isOnline ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                .font(.system(size: 64))
                .foregroundStyle(isOnline ? .green : .secondary)
            
            Text(isOnline ? "Aguardando Dados" : "Desconectado")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(isOnline
                 ? "A app está online. Envia dados de stock baixo desde o Mac ou iPad."
                 : "A app não está a anunciar presença na rede.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if isOnline {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Dispositivo visível na rede local")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Pronto para receber dados")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}

// MARK: - Lista de Produtos

struct StockReceiverProductListView: View {
    let products: [ReceivedProduct]
    @Binding var searchText: String
    let totalToOrder: Int
    let onExport: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Barra de pesquisa
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Pesquisar...", text: $searchText)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding()
            
            // Resumo
            HStack(spacing: 16) {
                StockReceiverStatCard(
                    icon: "cube.box.fill",
                    title: "Produtos",
                    value: "\(products.count)",
                    color: .orange
                )
                
                StockReceiverStatCard(
                    icon: "cart.fill",
                    title: "A Encomendar",
                    value: "\(totalToOrder)",
                    color: .blue
                )
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
            // Lista
            List {
                ForEach(products) { product in
                    StockReceiverProductRowView(product: product)
                }
            }
            .listStyle(.plain)
            
            // Footer
            VStack(spacing: 12) {
                Divider()
                
                Button {
                    onExport()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Exportar Lista de Encomenda")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemCyan))
        }
    }
}

struct StockReceiverStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StockReceiverProductRowView: View {
    let product: ReceivedProduct
    
    var body: some View {
        HStack(spacing: 12) {
            // Ícone de stock
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(product.stockLevel.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "cube.fill")
                    .foregroundStyle(product.stockLevel.color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                
                HStack(spacing: 6) {
                    Image(systemName: "barcode")
                        .font(.caption2)
                    Text(product.barcode)
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Stock:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(product.currentStock)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(product.stockLevel.color)
                }
                
                if product.orderQuantity > 0 {
                    HStack(spacing: 4) {
                        Text("Enc:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(product.orderQuantity)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Export Sheet

struct ExportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let products: [ReceivedProduct]
    
    var csvContent: String {
        var csv = "barcode,name,stock_actual,qty_encomenda\n"
        for p in products {
            let safeName = p.name.contains(",") ? "\"\(p.name)\"" : p.name
            csv += "\(p.barcode),\(safeName),\(p.currentStock),\(p.orderQuantity)\n"
        }
        return csv
    }
    
    var csvURL: URL {
        let filename = "encomenda_\(formattedDate()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csvContent.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ShareLink(
                        item: csvURL,
                        subject: Text("Lista de Encomenda"),
                        message: Text("Stock Baixo - \(formattedDate())")
                    ) {
                        Label("Partilhar CSV", systemImage: "square.and.arrow.up")
                    }
                    
                    #if canImport(UIKit)
                    Button {
                        UIPasteboard.general.string = csvContent
                        dismiss()
                    } label: {
                        Label("Copiar para Clipboard", systemImage: "doc.on.clipboard")
                    }
                    #else
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csvContent, forType: .string)
                        dismiss()
                    } label: {
                        Label("Copiar para Clipboard", systemImage: "doc.on.clipboard")
                    }
                    #endif
                } header: {
                    Text("Exportar")
                }
                
                Section {
                    Text("\(products.count) produtos")
                    Text("Total a encomendar: \(products.reduce(0) { $0 + $1.orderQuantity })")
                } header: {
                    Text("Resumo")
                }
            }
            .navigationTitle("Opções de Exportação")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
