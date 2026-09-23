import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Serviço de Exportação de Stock Baixo

class LowStockExportService {
    
    static let shared = LowStockExportService()
    
    private func reportsDir() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("POSApp_LowStock", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    
    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
    
    // MARK: - Exportar CSV com formato especial para partilha
    func exportLowStockCSV(products: [Product], orderQuantities: [Int: Int]) -> URL? {
        let filename = "stock_baixo_\(formattedDate()).posstock"
        let url = reportsDir().appendingPathComponent(filename)
        
        var csv = "# POS Stock Export - \(Date().formatted())\n"
        csv += "# Format: barcode,name,stock_actual,qty_encomenda,price_base\n"
        csv += "barcode,name,stock_actual,qty_encomenda,price_base\n"
        
        for product in products {
            let qty = orderQuantities[product.id] ?? 0
            csv += "\(csvField(product.barcode)),\(csvField(product.name)),\(product.stock),\(qty),\(product.priceBase)\n"
        }
        
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // MARK: - Exportar JSON estruturado (para comunicação directa iOS ↔ macOS)
    func exportLowStockJSON(products: [Product], orderQuantities: [Int: Int]) -> URL? {
        let filename = "stock_baixo_\(formattedDate()).posstock.json"
        let url = reportsDir().appendingPathComponent(filename)
        
        let items = products.map { product -> [String: Any] in
            return [
                "id": product.id,
                "barcode": product.barcode,
                "name": product.name,
                "stock": product.stock,
                "orderQty": orderQuantities[product.id] ?? 0,
                "priceBase": product.priceBase,
                "ivaRate": product.ivaRate,
                "profitMargin": product.profitMargin
            ]
        }
        
        let envelope: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "source": "POS Desktop",
            "products": items
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: .prettyPrinted) else {
            return nil
        }
        
        try? data.write(to: url)
        return url
    }
}

// MARK: - Extensão de ficheiro customizada (.posstock)

extension UTType {
    static let posStock = UTType(exportedAs: "com.posapp.stock-export")
}

// MARK: - FileDocument para .posstock

struct POSStockFile: FileDocument {
    static var readableContentTypes: [UTType] { [.posStock, .commaSeparatedText, .json] }
    
    var content: String
    var format: ExportFormat
    
    enum ExportFormat {
        case csv, json
    }
    
    init(content: String, format: ExportFormat = .csv) {
        self.content = content
        self.format = format
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            content = text
            format = text.hasPrefix("{") ? .json : .csv
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
