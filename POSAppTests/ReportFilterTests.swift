import Foundation
import PDFKit
import Testing
@testable import POSApp

@Suite("Filtro do histórico de relatórios")
struct ReportFilterTests {

    private func report(_ id: Int, _ type: ReportType, _ period: String) -> Report {
        Report(id: id, type: type, period: period, filePath: "/tmp/r\(id)", createdAt: Date())
    }

    private var sample: [Report] {
        [
            report(1, .daily,   "2026-08-15"),
            report(2, .daily,   "2026-08-02"),
            report(3, .daily,   "2026-07-30"),
            report(4, .monthly, "2026-08"),
            report(5, .monthly, "2025-12"),
            report(6, .annual,  "2026"),
            report(7, .annual,  "2025")
        ]
    }

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    @Test("Âmbito 'Tudo' devolve tudo")
    func scopeAll() {
        let out = ReportViewModel.filterReports(sample, scope: .all, date: date("2026-08-15"), type: nil)
        #expect(out.count == 7)
    }

    @Test("Âmbito Dia apanha só o dia exacto")
    func scopeDay() {
        let out = ReportViewModel.filterReports(sample, scope: .day, date: date("2026-08-15"), type: nil)
        #expect(out.map(\.id) == [1])
    }

    @Test("Âmbito Mês apanha diários do mês e o mensal")
    func scopeMonth() {
        let out = ReportViewModel.filterReports(sample, scope: .month, date: date("2026-08-15"), type: nil)
        #expect(out.map(\.id).sorted() == [1, 2, 4])
    }

    @Test("Âmbito Ano apanha tudo do ano")
    func scopeYear() {
        let out = ReportViewModel.filterReports(sample, scope: .year, date: date("2026-03-01"), type: nil)
        #expect(out.map(\.id).sorted() == [1, 2, 3, 4, 6])
    }

    @Test("Tipo e âmbito combinam-se")
    func scopeAndType() {
        let out = ReportViewModel.filterReports(sample, scope: .year, date: date("2026-01-01"), type: .daily)
        #expect(out.map(\.id).sorted() == [1, 2, 3])
    }

    @Test("Sem correspondência devolve vazio")
    func noMatch() {
        let out = ReportViewModel.filterReports(sample, scope: .day, date: date("2024-01-01"), type: nil)
        #expect(out.isEmpty)
    }
}

// MARK: - Helpers partilhados de venda

/// Constrói uma venda com itens `(nome, quantidade, preço unitário)`.
func makeSale(id: Int, date: Date = Date(), items: [(String, Int, Double)]) -> Sale {
    let saleItems = items.enumerated().map { index, item in
        SaleItem(
            id: id * 100 + index,
            saleId: id,
            productId: index + 1,
            productName: item.0,
            quantity: item.1,
            unitPrice: item.2,
            subtotal: Double(item.1) * item.2
        )
    }
    return Sale(
        id: id,
        userId: 1,
        clientName: "",
        clientNIF: "",
        items: saleItems,
        total: saleItems.reduce(0) { $0 + $1.subtotal },
        date: date,
        status: .completed
    )
}

// MARK: - Top de produtos vendidos

@Suite("Top de produtos vendidos")
struct TopProductsTests {

    private var sales: [Sale] {
        [
            makeSale(id: 1, items: [("Café", 3, 10), ("Pão", 1, 5)]),
            makeSale(id: 2, items: [("Café", 2, 10), ("Leite", 7, 2)]),
            makeSale(id: 3, items: [("Pão", 4, 5)])
        ]
    }

    @Test("Soma quantidades e valores do mesmo produto")
    func aggregates() {
        let top = ReportViewModel().topProducts(for: sales)
        let cafe = top.first { $0.name == "Café" }
        #expect(cafe?.quantity == 5)
        #expect(cafe?.total == 50)
    }

    @Test("Ordena por quantidade decrescente")
    func ordering() {
        let top = ReportViewModel().topProducts(for: sales)
        #expect(top.map(\.name) == ["Leite", "Café", "Pão"])
    }

    @Test("Respeita o limite pedido")
    func limit() {
        let top = ReportViewModel().topProducts(for: sales, limit: 2)
        #expect(top.count == 2)
    }

    @Test("topProduct devolve o primeiro do ranking")
    func single() {
        #expect(ReportViewModel().topProduct(for: sales) == "Leite")
    }

    @Test("Sem vendas devolve vazio e traço")
    func empty() {
        #expect(ReportViewModel().topProducts(for: []).isEmpty)
        #expect(ReportViewModel().topProduct(for: []) == "—")
    }

    @Test("Série de itens vendidos por dia soma as quantidades")
    func itemsPerDay() {
        let day = Calendar.current.startOfDay(for: Date())
        let series = ReportViewModel().itemsByDay(for: [
            makeSale(id: 1, date: day, items: [("Café", 3, 10)]),
            makeSale(id: 2, date: day, items: [("Pão", 2, 5)])
        ])
        #expect(series.count == 1)
        #expect(series[0].items == 5)
    }
}

// MARK: - Risco de validade por produto

@Suite("Risco de validade por produto")
struct ProductRiskTests {

    private func batch(_ id: Int, product: Int, quantity: Int, price: Double, daysFromNow: Int?) -> Batch {
        let expiry = daysFromNow.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())! }
        return Batch(id: id, productId: product, quantity: quantity,
                     priceBase: price, expiryDate: expiry, receivedAt: Date())
    }

    private func product(_ id: Int, _ name: String) -> Product {
        Product(id: id, name: name, barcode: "\(id)", priceBase: 1, ivaRate: 16,
                profitMargin: 20, priceFinal: 1.4, stock: 0)
    }

    @Test("Em risco só leva lotes por expirar, com totais por produto")
    func entries() {
        let vm = BatchViewModel()
        vm.batches = [
            batch(1, product: 1, quantity: 2, price: 100, daysFromNow: 5),    // em risco
            batch(2, product: 1, quantity: 1, price: 100, daysFromNow: -3),   // expirado
            batch(3, product: 2, quantity: 4, price: 10, daysFromNow: 40),    // em risco
            batch(4, product: 3, quantity: 9, price: 50, daysFromNow: 400),   // seguro
            batch(5, product: 4, quantity: 9, price: 50, daysFromNow: nil)    // não expira
        ]
        let entries = vm.riskEntries(products: [product(1, "Café"), product(2, "Pão")])

        #expect(entries.map(\.productId) == [1, 2])
        #expect(entries[0].totalQuantity == 2)
        #expect(entries[0].totalValue == 200)
        #expect(entries[0].worstStatus == .days)
        #expect(entries[1].totalValue == 40)
        #expect(vm.riskEntriesTotal(products: []) == 240)
        #expect(vm.riskEntriesTotal(products: []) == vm.riskValue)
    }

    @Test("Lote expirado só aparece na perda real, nunca em risco")
    func expiredOnlyInLoss() {
        let vm = BatchViewModel()
        vm.batches = [
            batch(1, product: 1, quantity: 3, price: 100, daysFromNow: -1),   // expirado
            batch(2, product: 1, quantity: 2, price: 100, daysFromNow: 5)     // em risco
        ]
        let loss = vm.lossEntries(products: [product(1, "Café")])
        let risk = vm.riskEntries(products: [product(1, "Café")])

        #expect(loss.map(\.totalQuantity) == [3])
        #expect(loss[0].totalValue == 300)
        #expect(loss[0].totalValue == vm.realLoss)
        #expect(risk.map(\.totalQuantity) == [2])
        #expect(risk[0].worstStatus != .expired)
    }

    @Test("Produto sem lotes em alerta não tem estado")
    func noStatus() {
        let vm = BatchViewModel()
        vm.batches = [batch(1, product: 7, quantity: 1, price: 5, daysFromNow: 400)]
        #expect(vm.worstStatus(productId: 7) == nil)
    }

    @Test("Estado do produto é o do lote mais grave")
    func worst() {
        let vm = BatchViewModel()
        vm.batches = [
            batch(1, product: 7, quantity: 1, price: 5, daysFromNow: 70),
            batch(2, product: 7, quantity: 1, price: 5, daysFromNow: 2)
        ]
        #expect(vm.worstStatus(productId: 7) == .days)
    }
}

// MARK: - Impressão de talões

@Suite("Impressão de facturas")
struct ReceiptPrintTests {

    @Test("Larguras de página dos formatos")
    func widths() {
        #expect(abs(ReceiptFormat.thermal80.pageWidth - 226.77) < 0.01)
        #expect(ReceiptFormat.a4.pageWidth == 595)
        #expect(ReceiptFormat.thermal80.fixedPageHeight == nil)   // talão contínuo
        #expect(ReceiptFormat.a4.fixedPageHeight == 842)
    }

    @Test("Sem vendas não gera ficheiro")
    func empty() {
        #expect(ReceiptPrintService().makeReceiptPDF(sales: [], format: .a4) == nil)
        #expect(ReceiptPrintService().makeReceiptPDF(sales: [], format: .thermal80) == nil)
    }

    @Test("Gera PDF não vazio nos dois formatos", arguments: [ReceiptFormat.thermal80, .a4])
    func generates(format: ReceiptFormat) throws {
        let sale = makeSale(id: 42, items: [("Café", 2, 12.5), ("Pão de forma grande", 1, 80)])
        let url = try #require(ReceiptPrintService().makeReceiptPDF(
            sales: [sale],
            payments: [Payment(id: 1, saleId: 42, method: .cash, amount: sale.total, reference: "")],
            format: format
        ))
        defer { try? FileManager.default.removeItem(at: url) }

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 0)
        #expect(url.pathExtension == "pdf")
    }
}


// MARK: - Layout do PDF de relatórios

@Suite("Layout do PDF de relatórios")
struct ReportPDFLayoutTests {

    /// Pares de caracteres que ocupam praticamente o mesmo sítio na página.
    /// Foi assim que passou despercebido o título da app impresso por cima do
    /// cabeçalho da venda: o texto saía todo, mas sobreposto.
    /// ponytail: varrimento O(n²); chega para uma página de teste.
    private func overlappingPairs(in page: PDFPage) -> [(String, String)] {
        var boxes: [(rect: CGRect, char: String)] = []
        let text = page.string ?? ""
        let chars = Array(text)
        for index in 0..<page.numberOfCharacters {
            let rect = page.characterBounds(at: index)
            guard rect.width > 0.5, rect.height > 0.5 else { continue }
            let char = index < chars.count ? String(chars[index]) : ""
            guard !char.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            boxes.append((rect, char))
        }

        var found: [(String, String)] = []
        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                let intersection = boxes[i].rect.intersection(boxes[j].rect)
                guard !intersection.isNull else { continue }
                let smallest = min(boxes[i].rect.width * boxes[i].rect.height,
                                   boxes[j].rect.width * boxes[j].rect.height)
                guard smallest > 0 else { continue }
                let area = intersection.width * intersection.height
                if area / smallest > 0.5 {
                    found.append((boxes[i].char, boxes[j].char))
                }
            }
        }
        return found
    }

    @Test("Cabeçalho e tabela não se sobrepõem")
    func noOverlap() async throws {
        let sale = makeSale(id: 35, items: [("Maria cim 200g", 1, 20.11)])
        let url = try #require(await ReportService().exportGroupPDF(sales: [sale]))
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))

        let overlaps = overlappingPairs(in: page)
        #expect(overlaps.isEmpty, "Caracteres sobrepostos: \(overlaps.prefix(5))")

        // O conteúdo continua todo lá: título, cabeçalho da venda e item.
        let text = page.string ?? ""
        #expect(text.contains("Venda #35"))
        #expect(text.contains("Maria cim 200g"))
        #expect(text.contains("Página 1"))
    }
}