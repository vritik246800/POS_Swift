import Foundation
import CoreGraphics
import CoreText
import AppKit

class ReportService {

    // MARK: - Diretório permanente de relatórios
    private func reportsDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("POSApp_Relatorios", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Sanitização do nome de ficheiro
    /// Reduz um texto livre (ex.: nome de cliente) a um componente de nome de
    /// ficheiro seguro: só alfanuméricos e `_`, no máximo 40 caracteres.
    /// Impede travessia de diretorias (`../../evil`) e caracteres de controlo.
    static func sanitizedFileComponent(_ value: String) -> String {
        let safe = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .prefix(40)
        return safe.isEmpty ? "anonimo" : String(safe)
    }

    // MARK: - EXPORT CSV (genérico)
    private func buildCSV(sales: [Sale]) -> String {
        let cur = currentCurrencySymbol
        // BOM UTF-8 à cabeça — sem ele o Excel perde os acentos.
        var csv = csvBOM
        csv += "ID Venda,Data,Hora,Cliente,NIF,Produto,Quantidade,"
        csv += "Preço Unit. (\(cur)),Subtotal (\(cur)),Total Venda (\(cur))\n"
        for sale in sales {
            let dateStr = sale.date.formatted(date: .abbreviated, time: .omitted)
            let timeStr = sale.date.formatted(date: .omitted, time: .shortened)
            for item in sale.items {
                csv += "\(sale.id),"
                csv += csvField(dateStr) + ","
                csv += csvField(timeStr) + ","
                csv += csvField(sale.clientName.isEmpty ? "—" : sale.clientName) + ","
                csv += csvField(sale.clientNIF.isEmpty ? "—" : sale.clientNIF) + ","
                csv += csvField(item.productName) + ","
                csv += "\(item.quantity),"
                // Números crus (ponto decimal, sem moeda) — assim o Excel soma
                // a coluna em vez de a ler como texto.
                csv += csvNumber(item.unitPrice) + ","
                csv += csvNumber(item.subtotal) + ","
                csv += csvNumber(sale.total) + "\n"
            }
            csv += ",,,,,,,,,\n"
        }
        let total = sales.reduce(0.0) { $0 + $1.total }
        let totalItems = sales.flatMap(\.items).reduce(0) { $0 + $1.quantity }
        csv += "TOTAL,,,,,,\(totalItems),,," + csvNumber(total) + "\n"
        return csv
    }

    // MARK: - EXPORT DIÁRIO CSV
    func exportDailyCSV(sales: [Sale], date: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_diario_\(dateStr).csv")
        let csv = buildCSV(sales: sales)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        saveReportRecord(type: .daily, period: dateStr, filePath: url.path)
        return url
    }

    // MARK: - EXPORT MENSAL CSV
    @discardableResult
    func exportMonthlyCSV(sales: [Sale], date: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_mensal_\(monthStr).csv")
        let csv = buildCSV(sales: sales)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        saveReportRecord(type: .monthly, period: monthStr, filePath: url.path)
        return url
    }

    // MARK: - EXPORT ANUAL CSV
    @discardableResult
    func exportAnnualCSV(sales: [Sale], date: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let yearStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_anual_\(yearStr).csv")
        let csv = buildCSV(sales: sales)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        saveReportRecord(type: .annual, period: yearStr, filePath: url.path)
        return url
    }

    // MARK: - EXPORT CSV de grupo
    func exportGroupCSV(sales: [Sale]) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = formatter.string(from: Date())
        let client = ReportService.sanitizedFileComponent(sales.first?.clientName ?? "")
        let url = reportsDirectory().appendingPathComponent("venda_\(client)_\(stamp).csv")
        let csv = buildCSV(sales: sales)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - EXPORT DIÁRIO PDF
    func exportDailyPDF(sales: [Sale], date: Date) async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_diario_\(dateStr).pdf")
        let success = renderPDF(
            title: "Relatório Diário — \(dateStr)",
            sales: sales,
            period: dateStr,
            to: url
        )
        if success { saveReportRecord(type: .daily, period: dateStr, filePath: url.path) }
        return success ? url : nil
    }

    // MARK: - EXPORT MENSAL PDF
    func exportMonthlyPDF(sales: [Sale], date: Date) async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_mensal_\(monthStr).pdf")
        let success = renderPDF(
            title: "Relatório Mensal — \(monthStr)",
            sales: sales,
            period: monthStr,
            to: url
        )
        if success { saveReportRecord(type: .monthly, period: monthStr, filePath: url.path) }
        return success ? url : nil
    }

    // MARK: - EXPORT ANUAL PDF
    func exportAnnualPDF(sales: [Sale], date: Date) async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let yearStr = formatter.string(from: date)
        let url = reportsDirectory().appendingPathComponent("relatorio_anual_\(yearStr).pdf")
        let success = renderPDF(
            title: "Relatório Anual — \(yearStr)",
            sales: sales,
            period: yearStr,
            to: url
        )
        if success { saveReportRecord(type: .annual, period: yearStr, filePath: url.path) }
        return success ? url : nil
    }

    // MARK: - EXPORT PDF de grupo
    func exportGroupPDF(sales: [Sale]) async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = formatter.string(from: Date())
        let client = ReportService.sanitizedFileComponent(sales.first?.clientName ?? "")
        let url = reportsDirectory().appendingPathComponent("venda_\(client)_\(stamp).pdf")
        let periodFormatter = DateFormatter()
        periodFormatter.dateFormat = "yyyy-MM-dd"
        let period = sales.first.map { periodFormatter.string(from: $0.date) } ?? stamp
        let success = renderPDF(
            title: "Venda — \(client)",
            sales: sales,
            period: period,
            to: url
        )
        return success ? url : nil
    }

    // MARK: - Renderizar PDF com CoreGraphics (sem WKWebView)
    private func renderPDF(title: String, sales: [Sale], period: String, to url: URL) -> Bool {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            print("Erro: não foi possível criar CGContext para PDF")
            return false
        }

        // Estilos
        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let headerFont = NSFont.boldSystemFont(ofSize: 11)
        let bodyFont = NSFont.systemFont(ofSize: 10)
        let captionFont = NSFont.systemFont(ofSize: 9)
        let blue = NSColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        let lightGray = NSColor(white: 0.96, alpha: 1)
        let darkGray = NSColor(white: 0.3, alpha: 1)

        func attr(_ text: String, font: NSFont, color: NSColor = .black, align: NSTextAlignment = .left) -> NSAttributedString {
            let para = NSMutableParagraphStyle()
            para.alignment = align
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: para
            ])
        }

        func drawText(_ str: NSAttributedString, in rect: CGRect) {
            // O contexto PDF do CoreGraphics já tem origem em baixo-à-esquerda e Y
            // a crescer para cima — o mesmo que um `NSGraphicsContext(flipped: false)`.
            // Aplicar aqui um `scaleBy(y: -1)` sem declarar `flipped: true` fazia os
            // glifos saírem espelhados na vertical: desenha-se sem flip nenhum.
            let previous = NSGraphicsContext.current
            ctx.saveGState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            str.draw(in: rect)
            NSGraphicsContext.current = previous
            ctx.restoreGState()
        }

        func fillRect(_ rect: CGRect, color: NSColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        }

        func drawLine(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor = .lightGray) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()
        }

        var y: CGFloat = pageHeight - margin

        // Colunas da tabela. A antiga coluna "Total Venda" saía sempre vazia
        // (o total já vem na linha de total da venda) — foi removida.
        let cols: [(String, CGFloat)] = [
            ("Produto", 0.46),
            ("Qtd", 0.10),
            ("Preço Unit. (\(currentCurrencySymbol))", 0.22),
            ("Subtotal (\(currentCurrencySymbol))", 0.22)
        ]

        func colX(_ index: Int) -> CGFloat {
            let offset = cols.prefix(index).reduce(0) { $0 + $1.1 * contentWidth }
            return margin + offset
        }
        func colW(_ index: Int) -> CGFloat { cols[index].1 * contentWidth }

        // Rodapé igual em todas as páginas: origem à esquerda, número à direita.
        var pageNumber = 0
        // `startPage` não mexe no `y` — quem quiser voltar ao topo usa
        // `newPage()`. Repor o `y` aqui fazia a tabela reiniciar no topo e
        // escrever por cima do cabeçalho já desenhado.
        func startPage() {
            pageNumber += 1
            ctx.beginPDFPage(nil)
        }

        func finishPage() {
            let origin = attr("Gerado por \(Constants.appName) em \(Date().formatted())",
                              font: captionFont, color: .gray)
            drawText(origin, in: CGRect(x: margin, y: margin - 16, width: contentWidth * 0.7, height: 14))
            let number = attr("Página \(pageNumber)", font: captionFont, color: .gray, align: .right)
            drawText(number, in: CGRect(x: margin + contentWidth * 0.7, y: margin - 16, width: contentWidth * 0.3, height: 14))
            ctx.endPDFPage()
        }

        func newPage() {
            finishPage()
            startPage()
            y = pageHeight - margin
        }

        func ensureSpace(_ needed: CGFloat) {
            if y - needed < margin + 20 {
                newPage()
            }
        }

        // A página abre antes de qualquer desenho: no CoreGraphics nada pode
        // ser desenhado fora de um par beginPDFPage/endPDFPage.
        startPage()

        // Título da app
        drawText(attr(Constants.appName, font: titleFont, color: blue),
                 in: CGRect(x: margin, y: y - 22, width: contentWidth, height: 22))
        y -= 28

        // Subtítulo
        drawText(attr(title, font: headerFont, color: darkGray),
                 in: CGRect(x: margin, y: y - 16, width: contentWidth, height: 16))
        y -= 22

        // Linha separadora
        drawLine(x1: margin, y1: y, x2: pageWidth - margin, y2: y)
        y -= 12

        // Cards de resumo
        let total = sales.reduce(0.0) { $0 + $1.total }
        let totalItems = sales.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }
        let cardW = (contentWidth - 16) / 3
        let cardH: CGFloat = 48
        let cards: [(String, String)] = [
            ("Total", formatMT(total)),
            ("Vendas", "\(sales.count)"),
            ("Itens", "\(totalItems)")
        ]
        for (i, card) in cards.enumerated() {
            let cx = margin + CGFloat(i) * (cardW + 8)
            fillRect(CGRect(x: cx, y: y - cardH, width: cardW, height: cardH), color: lightGray)
            drawText(attr(card.0, font: captionFont, color: darkGray),
                     in: CGRect(x: cx + 8, y: y - 20, width: cardW - 16, height: 14))
            drawText(attr(card.1, font: NSFont.boldSystemFont(ofSize: 14), color: .black),
                     in: CGRect(x: cx + 8, y: y - cardH + 6, width: cardW - 16, height: 20))
        }
        y -= cardH + 16

        for sale in sales {
            ensureSpace(60)

            // Cabeçalho da venda
            let clientStr = sale.clientName.isEmpty ? "Cliente anónimo" : sale.clientName
            let dateStr = sale.date.formatted(date: .abbreviated, time: .shortened)
            let saleHeader = attr("Venda #\(sale.id)  ·  \(clientStr)  ·  \(dateStr)", font: NSFont.boldSystemFont(ofSize: 10), color: blue)
            drawText(saleHeader, in: CGRect(x: margin, y: y - 14, width: contentWidth, height: 14))
            y -= 18

            // Cabeçalho da tabela
            fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 18), color: blue)
            for (i, col) in cols.enumerated() {
                let h = attr(col.0, font: NSFont.boldSystemFont(ofSize: 9), color: .white)
                drawText(h, in: CGRect(x: colX(i) + 2, y: y - 15, width: colW(i) - 4, height: 13))
            }
            y -= 18

            // Linhas de itens
            for (rowIndex, item) in sale.items.enumerated() {
                ensureSpace(18)
                let bg = rowIndex % 2 == 1 ? NSColor(white: 0.97, alpha: 1) : NSColor.white
                fillRect(CGRect(x: margin, y: y - 16, width: contentWidth, height: 16), color: bg)

                let vals = [
                    item.productName,
                    "\(item.quantity)",
                    formatMT(item.unitPrice),
                    formatMT(item.subtotal)
                ]
                for (i, val) in vals.enumerated() {
                    drawText(attr(val, font: bodyFont), in: CGRect(x: colX(i) + 2, y: y - 14, width: colW(i) - 4, height: 13))
                }
                drawLine(x1: margin, y1: y - 16, x2: pageWidth - margin, y2: y - 16)
                y -= 16
            }

            // Linha de total da venda
            ensureSpace(18)
            fillRect(CGRect(x: margin, y: y - 16, width: contentWidth, height: 16), color: NSColor(red: 0.91, green: 0.94, blue: 1.0, alpha: 1))
            drawText(attr("Total da venda", font: NSFont.boldSystemFont(ofSize: 10)), in: CGRect(x: colX(0) + 2, y: y - 14, width: colW(0) + colW(1) + colW(2) - 4, height: 13))
            drawText(attr(formatMT(sale.total), font: NSFont.boldSystemFont(ofSize: 10), align: .right), in: CGRect(x: colX(3) + 2, y: y - 14, width: colW(3) - 4, height: 13))
            y -= 16
            y -= 12 // espaço entre vendas
        }

        finishPage()
        ctx.closePDF()

        #if DEBUG
        print("PDF gerado")
        #endif
        return true
    }

    // MARK: - Revelar / partilhar o ficheiro exportado
    #if os(macOS)
    /// Abre o Finder com o ficheiro exportado selecionado.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
    // Em iOS não há Finder: as funções `export*` já devolvem a `URL`, que a
    // View passa diretamente ao `ShareSheet` (`List_Storage/ShareSheet.swift`).

    // MARK: - Gravar registo na base de dados
    private func saveReportRecord(type: ReportType, period: String, filePath: String) {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        _ = DatabaseManager.shared.saveReport(
            type: type,
            period: period,
            filePath: filePath,
            createdAt: dateStr
        )
    }
}
