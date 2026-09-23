import Foundation

enum CSVError: LocalizedError {
    case invalidFormat
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Formato CSV inválido. Colunas esperadas: barcode, name, stock_actual, qty_encomenda"
        case .emptyFile: return "O ficheiro está vazio."
        }
    }
}

struct CSVManager {

    static func parse(csv string: String) throws -> [Product] {
        let lines = string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { throw CSVError.emptyFile }

        let header = lines[0].lowercased()
        guard header.contains("barcode"),
              header.contains("name"),
              header.contains("stock_actual"),
              header.contains("qty_encomenda") else {
            throw CSVError.invalidFormat
        }

        let headerCols = lines[0].components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        let barcodeIdx    = headerCols.firstIndex(of: "barcode") ?? 0
        let nameIdx       = headerCols.firstIndex(of: "name") ?? 1
        let stockIdx      = headerCols.firstIndex(of: "stock_actual") ?? 2
        let qtyIdx        = headerCols.firstIndex(of: "qty_encomenda") ?? 3
        let statusIdx     = headerCols.firstIndex(of: "status")
        let legacyFlagIdx = headerCols.firstIndex(of: "red_flag")

        var products: [Product] = []

        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4 else { continue }

            let barcode      = cols[safe: barcodeIdx] ?? ""
            let name         = cols[safe: nameIdx] ?? ""
            let stockActual  = Int(cols[safe: stockIdx] ?? "0") ?? 0
            let qtyEncomenda = Int(cols[safe: qtyIdx] ?? "0") ?? 0

            let status: StockStatus
            if let si = statusIdx, let raw = cols[safe: si] {
                status = StockStatus(rawValue: raw) ?? .none
            } else if let li = legacyFlagIdx, cols[safe: li] == "1" {
                status = .redFlag
            } else {
                status = .none
            }

            products.append(Product(
                barcode: barcode,
                name: name,
                stockActual: stockActual,
                qtyEncomenda: qtyEncomenda,
                status: status
            ))
        }

        return products
    }

    static func exportAll(_ products: [Product]) -> String {
        let header = "barcode,name,stock_actual,qty_encomenda,status"
        return ([header] + products.map { $0.toCSVRow() }).joined(separator: "\n")
    }

    static func exportRedFlags(_ products: [Product]) -> String {
        let header = "barcode,name,stock_actual,qty_encomenda,status"
        return ([header] + products.filter { $0.isRedFlag }.map { $0.toCSVRow() }).joined(separator: "\n")
    }

    static func exportConfirmed(_ products: [Product]) -> String {
        let header = "barcode,name,stock_actual,qty_encomenda,status"
        return ([header] + products.filter { $0.isConfirmed }.map { $0.toCSVRow() }).joined(separator: "\n")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
