import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Result Model
struct StockImportResult {
    let updated: Int
    let notFound: [String]
    let total: Int
}

// MARK: - CSV FileDocument (para fileExporter SwiftUI)
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var content: String

    init(content: String) { self.content = content }
    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - Low Stock View
struct LowStockView: View {
    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedIDs: Set<Int> = []

    // qty a encomendar por produto — não toca na DB, vai para o CSV
    @State private var orderQty: [Int: Int] = [:]

    // stock editado manualmente — só vai à DB quando se clica "Guardar na DB"
    @State private var editedStock: [Int: Int] = [:]

    @State private var showFileImporter = false
    @State private var importResult: StockImportResult? = nil
    @State private var showImportResult = false
    @State private var isProcessingImport = false
    
    // Proximidade e partilha
    @ObservedObject private var proximityService = POSProximityService.shared
    @State private var showDevicePicker = false
    @State private var isSendingData = false
    @State private var sendResult: (success: Bool, message: String)?
    @State private var showSendResult = false
    /// S5 — código de emparelhamento escrito pelo utilizador antes de enviar.
    @State private var pairingCodeInput: String = ""

    var filteredProducts: [Product] {
        let low = productViewModel.products.filter { $0.stock <= 10 }
        if searchText.isEmpty { return low }
        return low.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.barcode.localizedCaseInsensitiveContains(searchText)
        }
    }

    var allSelected: Bool {
        !filteredProducts.isEmpty && filteredProducts.allSatisfy { selectedIDs.contains($0.id) }
    }

    var productsToExport: [Product] {
        selectedIDs.isEmpty ? filteredProducts : filteredProducts.filter { selectedIDs.contains($0.id) }
    }
    
    // Botão "Enviar para iOS" — extraído para evitar complexidade de type-checking
    private var sendToiOSButtonLabel: some View {
        let iconView: AnyView = {
            if proximityService.isDiscovering {
                return AnyView(ProgressView().controlSize(.small))
            } else {
                return AnyView(
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 13))
                )
            }
        }()
        
        return HStack(spacing: 6) {
            iconView
            Text("Enviar para iOS")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.12))
        .foregroundStyle(.purple)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // Botão "Fechar" — extraído para evitar complexidade de type-checking
    private var closeButtonLabel: some View {
        Text("Fechar")
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // CSV como ficheiro temporário — ShareLink partilha .csv e não texto puro
    var csvFileURL: URL {
        var csv = "barcode,name,stock_actual,qty_encomenda\n"
        for p in productsToExport {
            let qty = orderQty[p.id] ?? 0
            let safeName = p.name.contains(",") ? "\"\(p.name)\"" : p.name
            csv += "\(p.barcode),\(safeName),\(p.stock),\(qty)\n"
        }
        let filename = "stock_baixo_\(formattedDate()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helper Methods
    
    @ViewBuilder
    private func productRow(for product: Product) -> some View {
        let isSelected = selectedIDs.contains(product.id)
        let orderQtyBinding = Binding<Int>(
            get: { orderQty[product.id] ?? 0 },
            set: { orderQty[product.id] = $0 }
        )
        let editedStockBinding = Binding<Int>(
            get: { editedStock[product.id] ?? product.stock },
            set: { editedStock[product.id] = $0 }
        )
        
        LowStockRowView(
            product: product,
            isSelected: isSelected,
            orderQty: orderQtyBinding,
            editedStock: editedStockBinding,
            onToggle: { toggleSelection(for: product) },
            onSaveStock: { saveStock(for: product) }
        )
    }
    
    private func toggleSelection(for product: Product) {
        if selectedIDs.contains(product.id) {
            selectedIDs.remove(product.id)
        } else {
            selectedIDs.insert(product.id)
        }
    }
    
    private func saveStock(for product: Product) {
        if let newStock = editedStock[product.id] {
            productViewModel.updateStockOnly(productId: product.id, newStock: newStock)
            editedStock.removeValue(forKey: product.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stock Baixo")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(filteredProducts.count) produto(s) com stock ≤ 10")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            // MARK: Pesquisa + Select All
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    TextField("Pesquisar produto...", text: $searchText)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        filteredProducts.forEach { selectedIDs.insert($0.id) }
                    }
                } label: {
                    Text(allSelected ? "Desmarcar todos" : "Seleccionar todos")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // MARK: Lista
            if filteredProducts.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green.opacity(0.7))
                    Text("Nenhum produto com stock baixo")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProducts) { product in
                            productRow(for: product)

                            if product.id != filteredProducts.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // MARK: Footer
            HStack(spacing: 10) {

                // Enviar directamente para dispositivo iOS por perto
                Button {
                    proximityService.startDiscovery()
                    showDevicePicker = true
                } label: {
                    sendToiOSButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(filteredProducts.isEmpty || proximityService.isDiscovering)

                // Exportar — ShareLink com ficheiro .csv (AirDrop, Mail, Ficheiros, etc.)
                ShareLink(
                    item: csvFileURL,
                    subject: Text("Lista de Encomenda"),
                    message: Text("Stock baixo — \(formattedDate())")
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                        Text(selectedIDs.isEmpty
                             ? "Partilhar lista (\(filteredProducts.count))"
                             : "Partilhar \(selectedIDs.count) seleccionados")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Importar CSV do armazém
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 6) {
                        if isProcessingImport {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 13))
                        }
                        Text("Importar CSV")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isProcessingImport)

                Spacer()

                Button { dismiss() } label: {
                    closeButtonLabel
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 700, height: 540)
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(
                devices: proximityService.availableDevices,
                isSending: $isSendingData,
                pairingCode: $pairingCodeInput,
                onSelect: { device in
                    sendToDevice(device)
                },
                onCancel: {
                    proximityService.stopDiscovery()
                    showDevicePicker = false
                }
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Resultado da Importação", isPresented: $showImportResult, presenting: importResult) { _ in
            Button("OK") { importResult = nil }
        } message: { res in
            if res.notFound.isEmpty {
                Text("✅ \(res.updated) de \(res.total) produtos actualizados com sucesso.")
            } else {
                Text("✅ \(res.updated) actualizados.\n⚠️ Não encontrados (\(res.notFound.count)):\n\(res.notFound.joined(separator: ", "))")
            }
        }
        .alert("Envio para iOS", isPresented: $showSendResult, presenting: sendResult) { _ in
            Button("OK") { sendResult = nil }
        } message: { result in
            Text(result.message)
        }
    }

    // MARK: - Enviar para dispositivo iOS
    private func sendToDevice(_ device: POSDevice) {
        isSendingData = true
        
        // Exporta JSON estruturado
        let exporter = LowStockExportService.shared
        
        guard let jsonURL = exporter.exportLowStockJSON(products: productsToExport, orderQuantities: orderQty),
              let data = try? Data(contentsOf: jsonURL) else {
            sendResult = (false, "❌ Erro ao preparar dados para envio")
            showSendResult = true
            isSendingData = false
            return
        }
        
        proximityService.sendStockData(data, to: device, code: pairingCodeInput) { success in
            DispatchQueue.main.async {
                isSendingData = false
                proximityService.stopDiscovery()
                showDevicePicker = false
                
                if success {
                    sendResult = (true, "✅ Dados enviados para \(device.name)\n\(productsToExport.count) produtos enviados")
                } else {
                    sendResult = (false, "❌ Falha ao enviar para \(device.name)")
                }
                showSendResult = true
            }
        }
    }

    // MARK: - Importar CSV
    private func handleImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isProcessingImport = true
        DispatchQueue.global(qos: .userInitiated).async {
            let parseResult = parseAndApplyCSV(url: url)
            DispatchQueue.main.async {
                isProcessingImport = false
                productViewModel.loadProducts()
                importResult = parseResult
                showImportResult = true
            }
        }
    }

    private func parseAndApplyCSV(url: URL) -> StockImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            return StockImportResult(updated: 0, notFound: ["Acesso negado ao ficheiro"], total: 0)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return StockImportResult(updated: 0, notFound: ["Erro ao ler o ficheiro"], total: 0)
        }

        let db = DatabaseManager.shared
        var lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // Ignorar cabeçalho
        if let first = lines.first, first.lowercased().contains("barcode") {
            lines.removeFirst()
        }

        var updated = 0
        var notFound: [String] = []

        for line in lines {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 2 else { continue }

            let barcode = cols[0].trimmingCharacters(in: .whitespaces)

            // 4 colunas (formato exportado): barcode,name,stock_actual,qty_encomenda
            // 2 colunas (formato simples):   barcode,stock_novo
            let isFullFormat = cols.count >= 4
            let qtyStr = isFullFormat
                ? cols[3].trimmingCharacters(in: .whitespaces)
                : cols[1].trimmingCharacters(in: .whitespaces)

            guard !barcode.isEmpty, let qty = Int(qtyStr), qty > 0 else { continue }

            if let product = db.fetchProductByBarcode(barcode) {
                // Formato completo: soma stock_actual + qty_encomenda
                // Formato simples: usa o valor directo
                let finalStock: Int
                if isFullFormat, let actualInFile = Int(cols[2].trimmingCharacters(in: .whitespaces)) {
                    finalStock = actualInFile + qty
                } else {
                    finalStock = qty
                }
                _ = db.updateStock(productId: product.id, newStock: finalStock)
                updated += 1
            } else {
                notFound.append(barcode)
            }
        }

        return StockImportResult(updated: updated, notFound: notFound, total: updated + notFound.count)
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Row de stock baixo
struct LowStockRowView: View {
    let product: Product
    let isSelected: Bool
    @Binding var orderQty: Int        // qty a encomendar → vai para CSV, não para DB
    @Binding var editedStock: Int     // stock corrigido → só vai à DB via popover
    let onToggle: () -> Void
    let onSaveStock: () -> Void

    @State private var showStockEditor = false

    private var hasStockChanges: Bool { editedStock != product.stock }

    private var stockColor: Color {
        if product.stock == 0 { return .red }
        if product.stock <= 3 { return .orange }
        return .yellow
    }

    var body: some View {
        HStack(spacing: 12) {

            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            // Ícone
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(stockColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "cube.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(stockColor.opacity(0.8))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !product.barcode.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "barcode")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text(product.barcode)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .monospacedDigit()
                    }
                }
            }

            Spacer()

            HStack(spacing: 10) {

                // Stock actual — clica para abrir popover de edição (guarda na DB)
                Button { showStockEditor.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 10))
                            .foregroundStyle(stockColor)
                        Text("stock: \(product.stock)")
                            .font(.system(size: 11))
                            .foregroundStyle(stockColor)
                            .monospacedDigit()
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(stockColor.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stockColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showStockEditor, arrowEdge: .bottom) {
                    StockEditorPopover(
                        productName: product.name,
                        editedStock: $editedStock,
                        hasChanges: hasStockChanges,
                        onSave: { onSaveStock(); showStockEditor = false },
                        onCancel: { editedStock = product.stock; showStockEditor = false }
                    )
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 20)

                // Qty encomenda — controla o valor que vai para o CSV
                HStack(spacing: 4) {
                    Text("enc:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Button {
                        if orderQty > 0 { orderQty -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(orderQty > 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(orderQty == 0)

                    Text("\(orderQty)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(orderQty > 0 ? .blue : .primary)
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .center)

                    Button { orderQty += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.04) : Color.clear)
    }
}

// MARK: - Popover edição de stock (guarda na DB)
struct StockEditorPopover: View {
    let productName: String
    @Binding var editedStock: Int
    let hasChanges: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Corrigir stock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(productName)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    if editedStock > 0 { editedStock -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(editedStock > 0 ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(editedStock == 0)

                Text("\(editedStock)")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .center)

                Button {
                    editedStock += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onSave) {
                    Text("Guardar na DB")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(hasChanges ? Color.blue : Color.secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!hasChanges)
            }
        }
        .padding(16)
        .frame(width: 210)
    }
}
// MARK: - Sheet de selecção de dispositivo iOS

struct DevicePickerSheet: View {
    let devices: [POSDevice]
    @Binding var isSending: Bool
    /// S5 — código de 6 dígitos mostrado no dispositivo que recebe.
    @Binding var pairingCode: String
    let onSelect: (POSDevice) -> Void
    let onCancel: () -> Void

    private var codeIsValid: Bool {
        pairingCode.count == 6 && pairingCode.allSatisfy(\.isNumber)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dispositivos iOS por Perto")
                        .font(.system(size: 16, weight: .bold))
                    Text(devices.isEmpty ? "A procurar..." : "\(devices.count) encontrado(s)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Divider()

            // S5 — código de emparelhamento
            VStack(alignment: .leading, spacing: 4) {
                Text("Código de emparelhamento")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("6 dígitos mostrados no dispositivo iOS", text: $pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, design: .monospaced))
                    .onChange(of: pairingCode) { _, novo in
                        let filtrado = String(novo.filter(\.isNumber).prefix(6))
                        if filtrado != novo { pairingCode = filtrado }
                    }
            }
            .padding(.horizontal, 20)

            // Lista de dispositivos
            if devices.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("A procurar dispositivos iOS na rede local...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Certifica-te que a app iOS está aberta e no mesmo Wi-Fi")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(devices) { device in
                            DeviceRow(device: device, isSending: isSending || !codeIsValid) {
                                onSelect(device)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Cancelar") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isSending)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 420, height: 360)
        .background(Color(.controlBackgroundColor))
    }
}

struct DeviceRow: View {
    let device: POSDevice
    let isSending: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: device.platform == "iOS" ? "iphone" : "ipad")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(device.isReady ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(device.isReady ? "Pronto" : "Aguardando")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSending || !device.isReady)
        .opacity(device.isReady ? 1.0 : 0.5)
    }
}


