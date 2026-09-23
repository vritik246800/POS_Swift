import Foundation
import CoreGraphics
import AppKit
import PDFKit

// MARK: - Formato do talão

/// Formato de papel para imprimir uma factura.
/// `thermal80` é o rolo térmico de 80 mm (talão contínuo, sem altura fixa);
/// `a4` é a folha normal, paginada.
enum ReceiptFormat: String, CaseIterable, Identifiable {
    case thermal80
    case a4

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thermal80: return "Talão 80 mm"
        case .a4:        return "Folha A4"
        }
    }

    var detail: String {
        switch self {
        case .thermal80: return "Impressora térmica de balcão"
        case .a4:        return "Impressora normal, 210 × 297 mm"
        }
    }

    var icon: String {
        switch self {
        case .thermal80: return "printer.fill"
        case .a4:        return "doc.plaintext.fill"
        }
    }

    /// Largura da página em pontos (1 pt = 1/72"). 80 mm = 226.77 pt.
    var pageWidth: CGFloat {
        switch self {
        case .thermal80: return 226.77
        case .a4:        return 595
        }
    }

    /// Altura fixa da página. O talão de 80 mm é contínuo — cresce com o conteúdo.
    var fixedPageHeight: CGFloat? {
        switch self {
        case .thermal80: return nil
        case .a4:        return 842
        }
    }

    var margin: CGFloat {
        switch self {
        case .thermal80: return 10
        case .a4:        return 48
        }
    }

    /// Escala tipográfica — o talão usa corpo mais pequeno que a folha A4.
    var bodySize: CGFloat {
        switch self {
        case .thermal80: return 8.5
        case .a4:        return 11
        }
    }
}

// MARK: - Serviço de impressão de facturas

/// Gera o PDF de uma factura no formato escolhido e entrega-o ao painel de
/// impressão do sistema (onde o utilizador escolhe a impressora).
///
/// Só desenha e imprime — a leitura de vendas/pagamentos é de quem chama.
/// Os ficheiros ficam sempre dentro da directoria da app (nunca caminhos à mão).
final class ReceiptPrintService {

    // MARK: Directoria dos talões

    private func receiptsDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("POSApp_Talões", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - PDF do talão

    /// Desenha as facturas no formato pedido e devolve o ficheiro gerado.
    /// Devolve `nil` (sem escrever nada) se não houver vendas.
    func makeReceiptPDF(sales: [Sale], payments: [Payment] = [], format: ReceiptFormat) -> URL? {
        guard !sales.isEmpty else { return nil }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd_HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let name = "talao_\(sales[0].id)_\(format.rawValue)_\(stamp.string(from: Date())).pdf"
        let url = receiptsDirectory().appendingPathComponent(name)

        let rows = buildRows(sales: sales, payments: payments, format: format)
        return render(rows: rows, format: format, to: url) ? url : nil
    }

    // MARK: - Impressão

    /// Abre o painel de impressão do sistema (escolha de impressora, cópias, etc.).
    /// Devolve `false` se o PDF não abrir ou se o utilizador cancelar.
    @discardableResult
    @MainActor
    func printPDF(at url: URL, format: ReceiptFormat) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }

        let height = format.fixedPageHeight
            ?? document.page(at: 0)?.bounds(for: .mediaBox).height
            ?? 842

        let attributes = NSPrintInfo.shared.dictionary() as? [NSPrintInfo.AttributeKey: Any] ?? [:]
        let info = NSPrintInfo(dictionary: attributes)
        info.paperSize = NSSize(width: format.pageWidth, height: height)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        guard let operation = document.printOperation(
            for: info,
            scalingMode: .pageScaleDownToFit,
            autoRotate: false
        ) else { return false }

        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
    }

    // MARK: - Conteúdo do talão

    /// Uma linha desenhável, já com a altura que ocupa.
    private struct Row {
        enum Kind {
            case text(NSAttributedString)
            /// Etiqueta à esquerda, valor à direita, na mesma linha.
            case pair(NSAttributedString, NSAttributedString)
            case rule
            case gap
        }
        let kind: Kind
        let height: CGFloat
    }

    private func buildRows(sales: [Sale], payments: [Payment], format: ReceiptFormat) -> [Row] {
        let width = format.pageWidth - format.margin * 2
        let body = format.bodySize
        var rows: [Row] = []

        func attr(_ text: String, size: CGFloat, bold: Bool = false,
                  align: NSTextAlignment = .left, color: NSColor = .black) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = align
            paragraph.lineBreakMode = .byWordWrapping
            return NSAttributedString(string: text, attributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        /// Altura real do texto com quebra de linha na largura disponível.
        func height(_ string: NSAttributedString, in available: CGFloat) -> CGFloat {
            ceil(string.boundingRect(
                with: CGSize(width: available, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height) + 2
        }

        func text(_ string: NSAttributedString) {
            rows.append(Row(kind: .text(string), height: height(string, in: width)))
        }

        func pair(_ left: NSAttributedString, _ right: NSAttributedString) {
            let h = max(height(left, in: width * 0.62), height(right, in: width * 0.38))
            rows.append(Row(kind: .pair(left, right), height: h))
        }

        func rule() { rows.append(Row(kind: .rule, height: 6)) }
        func gap(_ h: CGFloat = 8) { rows.append(Row(kind: .gap, height: h)) }

        // Cabeçalho
        text(attr(Constants.appName, size: body + 5, bold: true, align: .center))
        gap(4)

        for (index, sale) in sales.enumerated() {
            if index > 0 { gap(12); rule() }

            text(attr("FACTURA #\(sale.id)", size: body + 1, bold: true, align: .center))
            text(attr(sale.date.formatted(date: .abbreviated, time: .shortened),
                      size: body - 0.5, align: .center, color: .darkGray))

            if !sale.clientName.isEmpty {
                text(attr("Cliente: \(sale.clientName)", size: body))
            }
            if !sale.clientNIF.isEmpty {
                text(attr("NIF: \(sale.clientNIF)", size: body))
            }

            rule()

            for item in sale.items {
                text(attr(item.productName, size: body, bold: true))
                pair(
                    attr("\(item.quantity) × \(formatMT(item.unitPrice))", size: body - 0.5, color: .darkGray),
                    attr(formatMT(item.subtotal), size: body, align: .right)
                )
            }

            rule()
            pair(
                attr("TOTAL", size: body + 3, bold: true),
                attr(formatMT(sale.total), size: body + 3, bold: true, align: .right)
            )

            // Os pagamentos vêm sempre da base de dados, já com `saleId` —
            // filtrar por venda evita repeti-los quando se imprime um grupo.
            let salePayments = payments.filter { $0.saleId == sale.id }
            if !salePayments.isEmpty {
                gap(4)
                text(attr("Pagamento", size: body - 0.5, bold: true, color: .darkGray))
                for payment in salePayments {
                    pair(
                        attr(payment.method.label, size: body - 0.5),
                        attr(formatMT(payment.amount), size: body - 0.5, align: .right)
                    )
                    if !payment.reference.isEmpty {
                        text(attr("Ref: \(payment.reference)", size: body - 1.5, color: .darkGray))
                    }
                }
            }
        }

        // Total do grupo — só faz sentido com mais do que uma factura
        if sales.count > 1 {
            rule()
            let total = sales.reduce(0.0) { $0 + $1.total }
            pair(
                attr("TOTAL GERAL", size: body + 3, bold: true),
                attr(formatMT(total), size: body + 3, bold: true, align: .right)
            )
        }

        gap(10)
        text(attr("Obrigado pela preferência.", size: body - 0.5, align: .center, color: .darkGray))
        text(attr("\(Constants.appName) · \(Date().formatted(date: .numeric, time: .shortened))",
                  size: body - 2, align: .center, color: .gray))

        return rows
    }

    // MARK: - Desenho

    private func render(rows: [Row], format: ReceiptFormat, to url: URL) -> Bool {
        let width = format.pageWidth
        let margin = format.margin
        let contentWidth = width - margin * 2
        let contentHeight = rows.reduce(0) { $0 + $1.height }

        // A4 tem altura fixa e pagina; o talão é uma página única do tamanho do conteúdo.
        let pageHeight = format.fixedPageHeight ?? (contentHeight + margin * 2)
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: pageHeight)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return false
        }

        // O contexto PDF já tem o Y a crescer para cima — desenha-se sem flip,
        // tal como em `ReportService.renderPDF`.
        func draw(_ string: NSAttributedString, in rect: CGRect) {
            let previous = NSGraphicsContext.current
            ctx.saveGState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            string.draw(in: rect)
            NSGraphicsContext.current = previous
            ctx.restoreGState()
        }

        ctx.beginPDFPage(nil)
        var y = pageHeight - margin

        for row in rows {
            // Só o A4 pagina; o talão contínuo cabe sempre na sua página única.
            if format.fixedPageHeight != nil, y - row.height < margin {
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                y = pageHeight - margin
            }

            let top = y - row.height

            switch row.kind {
            case .text(let string):
                draw(string, in: CGRect(x: margin, y: top, width: contentWidth, height: row.height))

            case .pair(let left, let right):
                let leftWidth = contentWidth * 0.62
                draw(left, in: CGRect(x: margin, y: top, width: leftWidth, height: row.height))
                draw(right, in: CGRect(x: margin + leftWidth, y: top,
                                       width: contentWidth - leftWidth, height: row.height))

            case .rule:
                ctx.setStrokeColor(NSColor.lightGray.cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: margin, y: top + row.height / 2))
                ctx.addLine(to: CGPoint(x: width - margin, y: top + row.height / 2))
                ctx.strokePath()

            case .gap:
                break
            }

            y -= row.height
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return true
    }
}
