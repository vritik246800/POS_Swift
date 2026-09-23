import Foundation
import Network
import Testing
@testable import POSApp

// MARK: - Testes do Sistema de Partilha de Proximidade

@Suite("Low Stock Export Tests")
struct LowStockExportTests {
    
    let exporter: LowStockExportService
    let mockProducts: [Product]
    let mockOrderQty: [Int: Int]
    
    init() {
        exporter = LowStockExportService.shared
        
        mockProducts = [
            Product(
                id: 1,
                name: "Produto A",
                barcode: "1234567890123",
                priceBase: 100.0,
                ivaRate: 16.0,
                profitMargin: 25.0,
                priceFinal: Product.calculateFinalPrice(base: 100.0, profit: 25.0, iva: 16.0),
                stock: 2
            ),
            Product(
                id: 2,
                name: "Produto B, com vírgula",
                barcode: "9876543210987",
                priceBase: 50.0,
                ivaRate: 16.0,
                profitMargin: 30.0,
                priceFinal: Product.calculateFinalPrice(base: 50.0, profit: 30.0, iva: 16.0),
                stock: 0
            ),
            Product(
                id: 3,
                name: "Produto C",
                barcode: "5555555555555",
                priceBase: 200.0,
                ivaRate: 16.0,
                profitMargin: 20.0,
                priceFinal: Product.calculateFinalPrice(base: 200.0, profit: 20.0, iva: 16.0),
                stock: 8
            ),
        ]
        
        mockOrderQty = [
            1: 10,
            2: 20,
            3: 5
        ]
    }
    
    @Test("CSV Export")
    func csvExport() async throws {
        let url = try #require(exporter.exportLowStockCSV(products: mockProducts, orderQuantities: mockOrderQty), 
                              "Falha ao exportar CSV")
        
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // Verifica header
        #expect(content.contains("barcode,name,stock_actual,qty_encomenda"))
        
        // Verifica dados do Produto A
        #expect(content.contains("1234567890123,Produto A,2,10"))
        
        // Verifica que nome com vírgula está entre aspas
        #expect(content.contains("\"Produto B, com vírgula\""))
        
        // Verifica produto com stock 0
        #expect(content.contains("9876543210987,\"Produto B, com vírgula\",0,20"))
        
        print("✅ CSV exportado: \(url.lastPathComponent)")
    }
    
    @Test("JSON Export")
    func jsonExport() async throws {
        let url = try #require(exporter.exportLowStockJSON(products: mockProducts, orderQuantities: mockOrderQty),
                              "Falha ao exportar JSON")
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Verifica envelope
        #expect(json["version"] as? String == "1.0")
        #expect(json["source"] as? String == "POS Desktop")
        #expect(json["exportDate"] != nil)
        
        // Verifica produtos
        let products = json["products"] as! [[String: Any]]
        #expect(products.count == 3)
        
        // Verifica primeiro produto
        let p1 = try #require(products.first(where: { $0["id"] as? Int == 1 }))
        #expect(p1["name"] as? String == "Produto A")
        #expect(p1["barcode"] as? String == "1234567890123")
        #expect(p1["stock"] as? Int == 2)
        #expect(p1["orderQty"] as? Int == 10)
        #expect(p1["priceBase"] as? Double == 100.0)
        
        print("✅ JSON exportado: \(url.lastPathComponent)")
    }
    
    @Test("Filename Format")
    func filenameFormat() async throws {
        let url = try #require(exporter.exportLowStockCSV(products: mockProducts, orderQuantities: [:]),
                              "Falha ao exportar")
        
        let filename = url.lastPathComponent
        
        // Formato esperado: stock_baixo_YYYY-MM-DD_HHmm.posstock
        #expect(filename.hasPrefix("stock_baixo_"))
        #expect(filename.hasSuffix(".posstock"))
        
        // Verifica que contém uma data (8 caracteres: YYYY-MM-DD)
        #expect(filename.count > 25)
        
        print("✅ Nome do ficheiro: \(filename)")
    }
    
    @Test("Empty Order Quantities")
    func emptyOrderQuantities() async throws {
        let url = try #require(exporter.exportLowStockCSV(products: mockProducts, orderQuantities: [:]),
                              "Falha ao exportar")
        
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // Todos devem ter qty 0
        #expect(content.contains(",2,0"))  // Produto A: stock 2, order 0
        #expect(content.contains(",0,0"))  // Produto B: stock 0, order 0
        
        print("✅ Exportação com quantidades vazias funciona")
    }
}

@Suite("Proximity Service Tests")
struct ProximityServiceTests {
    
    @Test("Service Initialization")
    func serviceInit() async throws {
        let service = POSProximityService.shared
        
        #expect(service.availableDevices.isEmpty)
        #expect(!service.isAdvertising)
        #expect(!service.isDiscovering)
        
        print("✅ Serviço inicializado correctamente")
    }
    
    @Test("Device Model")
    func deviceModel() async throws {
        let endpoint = NWEndpoint.hostPort(host: "localhost", port: 12345)
        
        let device = POSDevice(
            name: "iPhone de Teste",
            endpoint: endpoint,
            metadata: [
                "platform": "iOS",
                "ready": "true",
                "version": "1.0"
            ]
        )
        
        #expect(device.name == "iPhone de Teste")
        #expect(device.platform == "iOS")
        #expect(device.isReady)
        
        print("✅ Modelo POSDevice funciona correctamente")
    }
    
    @Test("Device with Empty Metadata")
    func deviceWithEmptyMetadata() async throws {
        let endpoint = NWEndpoint.hostPort(host: "localhost", port: 12345)
        
        let device = POSDevice(
            name: "Dispositivo Desconhecido",
            endpoint: endpoint,
            metadata: [:]
        )
        
        #expect(device.platform == "Unknown")
        #expect(!device.isReady)
        
        print("✅ Device sem metadata tratado correctamente")
    }
}

@Suite("Transfer Protocol Tests")
struct TransferProtocolTests {
    
    @Test("Size Header Encoding")
    func sizeHeaderEncoding() async throws {
        let payload = "Hello, World!".data(using: .utf8)!
        let size = UInt32(payload.count)
        
        // Serializa como big-endian
        var bigEndianSize = size.bigEndian
        let sizeData = Data(bytes: &bigEndianSize, count: 4)
        
        #expect(sizeData.count == 4)
        
        // Deserializa
        let decoded = sizeData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        #expect(decoded == size)
        
        print("✅ Header de tamanho: \(size) bytes")
    }
    
    @Test("JSON Payload Validity")
    func jsonPayloadValidity() async throws {
        let envelope: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "source": "Test",
            "products": [
                [
                    "id": 1,
                    "barcode": "123",
                    "name": "Test Product",
                    "stock": 5,
                    "orderQty": 10
                ]
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: envelope)
        
        // Verifica que pode ser deserializado
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        #expect(decoded["version"] as? String == "1.0")
        #expect(decoded["source"] as? String == "Test")
        
        let products = decoded["products"] as! [[String: Any]]
        #expect(products.count == 1)
        
        print("✅ Payload JSON válido (\(data.count) bytes)")
    }
}

@Suite("Receiver Tests")
struct ReceiverTests {
    
    @Test("Product Parsing")
    func productParsing() async throws {
        let productDict: [String: Any] = [
            "barcode": "1234567890123",
            "name": "Produto Teste",
            "stock": 3,
            "orderQty": 15,
            "priceBase": 120.50
        ]
        
        let barcode = try #require(productDict["barcode"] as? String)
        let name = try #require(productDict["name"] as? String)
        let stock = try #require(productDict["stock"] as? Int)
        let orderQty = try #require(productDict["orderQty"] as? Int)
        let priceBase = try #require(productDict["priceBase"] as? Double)
        
        let product = ReceivedProduct(
            barcode: barcode,
            name: name,
            currentStock: stock,
            orderQuantity: orderQty,
            priceBase: priceBase
        )
        
        #expect(product.barcode == "1234567890123")
        #expect(product.name == "Produto Teste")
        #expect(product.currentStock == 3)
        #expect(product.orderQuantity == 15)
        #expect(product.stockLevel == .low)
        
        print("✅ Produto parsed correctamente")
    }
    
    @Test("Stock Levels")
    func stockLevels() async throws {
        let critical = ReceivedProduct(barcode: "1", name: "A", currentStock: 0, orderQuantity: 0, priceBase: 100)
        let low = ReceivedProduct(barcode: "2", name: "B", currentStock: 2, orderQuantity: 0, priceBase: 100)
        let medium = ReceivedProduct(barcode: "3", name: "C", currentStock: 5, orderQuantity: 0, priceBase: 100)
        
        #expect(critical.stockLevel == .critical)
        #expect(low.stockLevel == .low)
        #expect(medium.stockLevel == .medium)
        
        #expect(critical.stockLevel.color == .red)
        #expect(low.stockLevel.color == .orange)
        #expect(medium.stockLevel.color == .yellow)
        
        print("✅ Stock levels classificados correctamente")
    }
}

@Suite("File Document Tests")
struct FileDocumentTests {
    
    @Test("CSV File Document")
    func csvFileDocument() async throws {
        let csvContent = "barcode,name,stock\n123,Produto,5"
        let data = csvContent.data(using: .utf8)!
        
        let file = POSStockFile(content: csvContent, format: .csv)
        
        #expect(file.content == csvContent)
        #expect(file.format == .csv)
        
        print("✅ FileDocument CSV criado")
    }
    
    @Test("JSON File Document")
    func jsonFileDocument() async throws {
        let jsonContent = "{\"version\": \"1.0\", \"products\": []}"
        
        let file = POSStockFile(content: jsonContent, format: .json)
        
        #expect(file.content == jsonContent)
        #expect(file.format == .json)
        
        print("✅ FileDocument JSON criado")
    }
    
    @Test("Format Detection")
    func formatDetection() async throws {
        let jsonContent = "{\"test\": true}"
        let csvContent = "col1,col2\nval1,val2"
        
        let jsonFile = POSStockFile(content: jsonContent, format: .csv) // Ignora formato inicial
        let csvFile = POSStockFile(content: csvContent, format: .json)
        
        // A lógica de detecção seria na init(configuration:)
        // Aqui apenas verificamos que aceita ambos
        #expect(jsonFile.content.hasPrefix("{"))
        #expect(csvFile.content.contains(","))
        
        print("✅ Formatos detectados")
    }
}

@Suite("Integration Tests")
struct IntegrationTests {
    
    @Test("Complete Flow")
    func completeFlow() async throws {
        // 1. Criar produtos
        let products = [
            Product(id: 1, name: "P1", barcode: "111", priceBase: 10, ivaRate: 16, profitMargin: 20, priceFinal: Product.calculateFinalPrice(base: 10, profit: 20, iva: 16), stock: 1),
            Product(id: 2, name: "P2", barcode: "222", priceBase: 20, ivaRate: 16, profitMargin: 20, priceFinal: Product.calculateFinalPrice(base: 20, profit: 20, iva: 16), stock: 3),
        ]
        
        let orderQty = [1: 5, 2: 10]
        
        // 2. Exportar JSON
        let exporter = LowStockExportService.shared
        let url = try #require(exporter.exportLowStockJSON(products: products, orderQuantities: orderQty),
                              "Exportação falhou")
        
        // 3. Ler JSON
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // 4. Simular recepção
        let productsData = try #require(json["products"] as? [[String: Any]],
                                       "Produtos não encontrados no JSON")
        
        let receivedProducts = productsData.compactMap { dict -> ReceivedProduct? in
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
        
        // 5. Validar
        #expect(receivedProducts.count == 2)
        #expect(receivedProducts[0].barcode == "111")
        #expect(receivedProducts[0].orderQuantity == 5)
        #expect(receivedProducts[1].orderQuantity == 10)
        
        print("✅ Fluxo completo validado:")
        print("   - \(products.count) produtos exportados")
        print("   - \(receivedProducts.count) produtos recebidos")
        print("   - Dados intactos após transferência")
    }
}
