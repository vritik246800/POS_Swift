import Foundation
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
typealias UIColor = NSColor
typealias UIFont = NSFont

private var _pushedContexts: [NSGraphicsContext] = []
private func UIGraphicsPushContext(_ ctx: CGContext) {
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    _pushedContexts.append(NSGraphicsContext.current ?? NSGraphicsContext(cgContext: ctx, flipped: false))
    NSGraphicsContext.current = nsCtx
}
private func UIGraphicsPopContext() {
    NSGraphicsContext.current = _pushedContexts.popLast()
}
#endif

// MARK: - Serviço de exportação para Fecho de Caixa

class CloseExportService {

    private func fmt(_ value: Double) -> String {
        formatCurrency(value)
    }

    private func reportsDir() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("POSApp_Fechos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Export Excel (CSV compatível com Excel)
    func exportExcel(title: String, sales: [Sale], payments: [Payment], period: String) -> URL? {
        let url = reportsDir().appendingPathComponent("fecho_\(period).csv")

        // BOM primeiro: sem ele o Excel perde os acentos do Português.
        var csv = csvBOM + csvField(title) + "\n\n"

        // Resumo por método
        csv += "RESUMO POR MÉTODO DE PAGAMENTO\n"
        csv += "Método,Total (\(currentCurrencySymbol))\n"

        let methods: [PaymentMethod] = [.cash, .card, .bankTransfer, .mpesa, .emola]
        var totals: [PaymentMethod: Double] = [:]
        for p in payments {
            totals[p.method, default: 0] += p.amount
        }
        for method in methods {
            csv += csvField(method.label) + ",\(csvNumber(totals[method] ?? 0))\n"
        }
        let grandTotal = payments.reduce(0.0) { $0 + $1.amount }
        csv += "TOTAL,\(csvNumber(grandTotal))\n\n"

        // Detalhe de vendas
        csv += "DETALHE DE VENDAS\n"
        csv += "ID,Data,Hora,Cliente,NIF,Produtos,Nº Itens,Total Venda (\(currentCurrencySymbol)),Métodos de Pagamento\n"

        // Agrupa payments por saleId
        var paymentsBySale: [Int: [Payment]] = [:]
        for p in payments {
            paymentsBySale[p.saleId, default: []].append(p)
        }

        for sale in sales {
            let dateStr = sale.date.formatted(date: .abbreviated, time: .omitted)
            let timeStr = sale.date.formatted(date: .omitted, time: .shortened)
            let client = sale.clientName.isEmpty ? "Anónimo" : sale.clientName
            let nif = sale.clientNIF.isEmpty ? "—" : sale.clientNIF
            let products = sale.items.map { "\($0.productName) x\($0.quantity)" }.joined(separator: "; ")
            let numItems = sale.items.reduce(0) { $0 + $1.quantity }
            let salePayments = paymentsBySale[sale.id] ?? []
            let payStr = salePayments.map { "\($0.method.label): \(fmt($0.amount))" }.joined(separator: " | ")

            // Todos os campos de texto passam por `csvField` — um cliente
            // chamado "Silva, Lda" partia a linha em duas colunas.
            csv += "\(sale.id),"
            csv += csvField(dateStr) + "," + csvField(timeStr) + ","
            csv += csvField(client) + "," + csvField(nif) + ","
            csv += csvField(products) + ",\(numItems),"
            csv += csvNumber(sale.total) + "," + csvField(payStr) + "\n"
        }

        csv += "\nTotal de Vendas:,\(sales.count)\n"
        csv += "Total Faturado (\(currentCurrencySymbol)):,\(csvNumber(grandTotal))\n"
        csv += "\n" + csvField("Gerado por \(Constants.appName) em \(Date().formatted())") + "\n"

        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Export PDF (CoreGraphics, sem UIKit)
    func exportPDF(title: String, sales: [Sale], payments: [Payment], period: String, type: String) async -> URL? {
        let url = reportsDir().appendingPathComponent("fecho_\(type)_\(period).pdf")

        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let margin: CGFloat = 40
        let cW = pageW - margin * 2

        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        let blue = UIColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        let lightGray = UIColor(white: 0.96, alpha: 1)
        let darkGray = UIColor(white: 0.3, alpha: 1)

        func attr(_ text: String, font: UIFont, color: UIColor = .black, align: NSTextAlignment = .left) -> NSAttributedString {
            let p = NSMutableParagraphStyle(); p.alignment = align
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
        }

        func draw(_ s: NSAttributedString, in r: CGRect) {
            UIGraphicsPushContext(ctx)
            s.draw(in: r)
            UIGraphicsPopContext()
        }

        func fillRect(_ r: CGRect, _ c: UIColor) {
            ctx.setFillColor(c.cgColor); ctx.fill(r)
        }

        func hline(y: CGFloat) {
            ctx.setStrokeColor(UIColor.lightGray.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: pageW - margin, y: y))
            ctx.strokePath()
        }

        var y: CGFloat = pageH - margin

        // Rodapé igual em todas as páginas: origem + numeração.
        var pageNumber = 0
        func startPage() {
            pageNumber += 1
            ctx.beginPDFPage(nil)
            y = pageH - margin
        }
        func finishPage() {
            draw(attr("Gerado por \(Constants.appName) em \(Date().formatted())",
                      font: UIFont.systemFont(ofSize: 8), color: .gray),
                 in: CGRect(x: margin, y: margin - 14, width: cW * 0.7, height: 12))
            draw(attr("Página \(pageNumber)", font: UIFont.systemFont(ofSize: 8), color: .gray, align: .right),
                 in: CGRect(x: margin + cW * 0.7, y: margin - 14, width: cW * 0.3, height: 12))
            ctx.endPDFPage()
        }

        startPage()

        // Título
        draw(attr(Constants.appName, font: UIFont.boldSystemFont(ofSize: 18), color: blue),
             in: CGRect(x: margin, y: y - 24, width: cW, height: 24))
        y -= 30
        draw(attr(title, font: UIFont.boldSystemFont(ofSize: 13), color: darkGray),
             in: CGRect(x: margin, y: y - 18, width: cW, height: 18))
        y -= 24
        hline(y: y); y -= 16

        // Resumo por método
        let methods: [PaymentMethod] = [.cash, .card, .bankTransfer, .mpesa, .emola]
        var totals: [PaymentMethod: Double] = [:]
        for p in payments { totals[p.method, default: 0] += p.amount }
        let grandTotal = payments.reduce(0.0) { $0 + $1.amount }

        draw(attr("Resumo por Método de Pagamento", font: UIFont.boldSystemFont(ofSize: 12)),
             in: CGRect(x: margin, y: y - 16, width: cW, height: 16))
        y -= 22

        let cardW = (cW - 32) / 3
        let cardH: CGFloat = 56
        var col = 0
        for method in methods {
            let amt = totals[method] ?? 0
            guard amt > 0 else { continue }
            let cx = margin + CGFloat(col % 3) * (cardW + 16)
            if col % 3 == 0 && col > 0 { y -= cardH + 10 }
            let cr = CGRect(x: cx, y: y - cardH, width: cardW, height: cardH)
            fillRect(cr, lightGray)
            draw(attr(method.label, font: UIFont.systemFont(ofSize: 9), color: darkGray),
                 in: CGRect(x: cx + 6, y: y - 18, width: cardW - 12, height: 14))
            draw(attr(fmt(amt), font: UIFont.boldSystemFont(ofSize: 13)),
                 in: CGRect(x: cx + 6, y: y - cardH + 8, width: cardW - 12, height: 18))
            col += 1
        }
        y -= cardH + 16

        // Total
        fillRect(CGRect(x: margin, y: y - 24, width: cW, height: 24),
                 UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1))
        draw(attr("TOTAL GERAL", font: UIFont.boldSystemFont(ofSize: 11)),
             in: CGRect(x: margin + 8, y: y - 20, width: cW / 2, height: 16))
        draw(attr(fmt(grandTotal), font: UIFont.boldSystemFont(ofSize: 14), color: blue, align: .right),
             in: CGRect(x: margin + cW / 2, y: y - 20, width: cW / 2 - 8, height: 16))
        y -= 34

        // Nº vendas
        draw(attr("Total de Vendas: \(sales.count)", font: UIFont.systemFont(ofSize: 10), color: darkGray),
             in: CGRect(x: margin, y: y - 14, width: cW, height: 14))
        y -= 22

        hline(y: y); y -= 16

        // Tabela de vendas
        draw(attr("Detalhe de Vendas", font: UIFont.boldSystemFont(ofSize: 12)),
             in: CGRect(x: margin, y: y - 16, width: cW, height: 16))
        y -= 22

        // Cabeçalho tabela
        let cols: [(String, CGFloat)] = [("Venda", 0.08), ("Data", 0.14), ("Cliente", 0.22), ("Total", 0.14), ("Métodos", 0.42)]
        func colX(_ i: Int) -> CGFloat { margin + cols.prefix(i).reduce(0) { $0 + $1.1 * cW } }
        func colW(_ i: Int) -> CGFloat { cols[i].1 * cW }

        fillRect(CGRect(x: margin, y: y - 18, width: cW, height: 18), blue)
        for (i, c) in cols.enumerated() {
            draw(attr(c.0, font: UIFont.boldSystemFont(ofSize: 9), color: .white),
                 in: CGRect(x: colX(i) + 2, y: y - 15, width: colW(i) - 4, height: 13))
        }
        y -= 18

        var payBySale: [Int: [Payment]] = [:]
        for p in payments { payBySale[p.saleId, default: []].append(p) }

        for (rowIdx, sale) in sales.enumerated() {
            if y - 20 < margin + 20 {
                finishPage()
                startPage()
                // Repete o cabeçalho da tabela na página nova — sem ele as
                // colunas ficam sem legenda a partir da segunda página.
                fillRect(CGRect(x: margin, y: y - 18, width: cW, height: 18), blue)
                for (i, c) in cols.enumerated() {
                    draw(attr(c.0, font: UIFont.boldSystemFont(ofSize: 9), color: .white),
                         in: CGRect(x: colX(i) + 2, y: y - 15, width: colW(i) - 4, height: 13))
                }
                y -= 18
            }
            let bg = rowIdx % 2 == 1 ? UIColor(white: 0.97, alpha: 1) : .white
            fillRect(CGRect(x: margin, y: y - 18, width: cW, height: 18), bg)
            let salePayments = payBySale[sale.id] ?? []
            let payStr = salePayments.map { "\($0.method.label): \(fmt($0.amount))" }.joined(separator: ", ")
            let vals = [
                "#\(sale.id)",
                sale.date.formatted(date: .numeric, time: .omitted),
                sale.clientName.isEmpty ? "Anónimo" : sale.clientName,
                fmt(sale.total),
                payStr
            ]
            let bodyFont = UIFont.systemFont(ofSize: 8)
            for (i, v) in vals.enumerated() {
                draw(attr(v, font: bodyFont),
                     in: CGRect(x: colX(i) + 2, y: y - 15, width: colW(i) - 4, height: 13))
            }
            hline(y: y - 18)
            y -= 18
        }

        finishPage()
        ctx.closePDF()

        return url
    }
}
