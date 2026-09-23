import SwiftUI
import Combine
import UniformTypeIdentifiers

class StockViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var searchText = ""
    @Published var filterStatus: StockStatus? = nil

    var filteredProducts: [Product] {
        var list = products
        if let f = filterStatus { list = list.filter { $0.status == f } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.barcode.contains(searchText)
            }
        }
        return list
    }

    var redFlagCount:   Int { products.filter { $0.isRedFlag }.count }
    var confirmedCount: Int { products.filter { $0.isConfirmed }.count }

    func importCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = try CSVManager.parse(csv: content)
            products = parsed
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func cycleStatus(for product: Product) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        switch products[idx].status {
        case .none:      products[idx].status = .redFlag
        case .redFlag:   products[idx].status = .confirmed
        case .confirmed: products[idx].status = .none
        }
    }

    func updateStock(for product: Product, stockActual: Int? = nil, qtyEncomenda: Int? = nil) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        if let s = stockActual  { products[idx].stockActual  = s }
        if let q = qtyEncomenda { products[idx].qtyEncomenda = q }
    }

    func csvDataAll()       -> Data { CSVManager.exportAll(products).data(using: .utf8) ?? Data() }
    func csvDataRedFlags()  -> Data { CSVManager.exportRedFlags(products).data(using: .utf8) ?? Data() }
    func csvDataConfirmed() -> Data { CSVManager.exportConfirmed(products).data(using: .utf8) ?? Data() }
}
