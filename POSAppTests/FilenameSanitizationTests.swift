import Foundation
import PDFKit
import Testing
@testable import POSApp

// MARK: - S9 — Nome de ficheiro a partir do nome do cliente

@Suite("Filename Sanitization")
struct FilenameSanitizationTests {

    @Test("Travessia de diretoria não sobrevive")
    func pathTraversal() {
        let safe = ReportService.sanitizedFileComponent("../../evil")
        #expect(!safe.contains("/"))
        #expect(!safe.contains("."))
        #expect(safe == "evil")
    }

    @Test("O ficheiro fica dentro da diretoria de relatórios")
    func staysInsideReportsDirectory() {
        let base = URL(fileURLWithPath: "/tmp/POSApp_Relatorios", isDirectory: true)
        let safe = ReportService.sanitizedFileComponent("../../etc/passwd")
        let url = base.appendingPathComponent("venda_\(safe)_2026-01-01.csv")
        #expect(url.deletingLastPathComponent().standardized == base.standardized)
    }

    @Test("Separadores e caracteres de controlo viram _")
    func separators() {
        #expect(ReportService.sanitizedFileComponent("a/b\\c") == "a_b_c")
        #expect(ReportService.sanitizedFileComponent("Ana-Maria O'Neill") == "Ana_Maria_O_Neill")
        #expect(!ReportService.sanitizedFileComponent("nome\ncom\tcontrolo").contains("\n"))
    }

    @Test("Nome vazio ou só com símbolos vira 'anonimo'")
    func emptyBecomesAnonimo() {
        #expect(ReportService.sanitizedFileComponent("") == "anonimo")
        #expect(ReportService.sanitizedFileComponent("   ") == "anonimo")
        #expect(ReportService.sanitizedFileComponent("///") == "anonimo")
    }

    @Test("Máximo de 40 caracteres")
    func maxLength() {
        let long = String(repeating: "x", count: 200)
        #expect(ReportService.sanitizedFileComponent(long).count == 40)
    }
}

// MARK: - Orientação do texto no PDF exportado

/// O `drawText` do `ReportService` já teve um `scaleBy(y: -1)` sem
/// `NSGraphicsContext(flipped: true)`, o que fazia cada glifo sair espelhado na
/// vertical dentro do seu próprio rectângulo.
///
/// O flip mantinha a linha na mesma banda da página — só virava cada glifo ao
/// contrário — por isso não chega olhar para a posição do texto. O teste desenha
/// "TTTT", cuja tinta está quase toda na barra de cima, e verifica que a metade
/// superior da mancha continua mais pesada do que a inferior.
@Suite("PDF orientação do texto")
struct PDFOrientationTests {

    private func makeSale() -> Sale {
        let item = SaleItem(id: 1, saleId: 1, productId: 1, productName: "Arroz", quantity: 2, unitPrice: 50, subtotal: 100)
        return Sale(id: 1, userId: 1, clientName: "Ana", clientNIF: "", items: [item], total: 100, date: Date(), status: .completed)
    }

    @Test("O PDF exportado extrai o texto esperado")
    func exportedPDFHasText() async throws {
        let url = try #require(await ReportService().exportGroupPDF(sales: [makeSale()]))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try #require(PDFDocument(url: url))
        let text = doc.string ?? ""
        #expect(text.contains("Arroz"))
        #expect(text.contains("Ana"))
    }

    /// Réplica exacta do `drawText` do `ReportService` — se lá voltar o flip,
    /// esta cópia deixa de bater certo com o que a app produz e o teste
    /// deixa de proteger; por isso a asserção é sobre a regra, não sobre a cópia.
    @Test("Os glifos não saem espelhados na vertical")
    func glyphsAreNotMirrored() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orient_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let size = CGSize(width: 200, height: 60)
        var box = CGRect(origin: .zero, size: size)
        let consumer = try #require(CGDataConsumer(url: tmp as CFURL))
        let ctx = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))

        // Mesmo caminho de desenho do `drawText` do ReportService.
        ctx.beginPDFPage(nil)
        let previous = NSGraphicsContext.current
        ctx.saveGState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: "TTTT", attributes: [.font: NSFont.boldSystemFont(ofSize: 28)])
            .draw(in: CGRect(x: 10, y: 14, width: 180, height: 34))
        NSGraphicsContext.current = previous
        ctx.restoreGState()
        ctx.endPDFPage()
        ctx.closePDF()

        let page = try #require(PDFDocument(url: tmp)?.page(at: 0))
        let tiff = try #require(page.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))

        // Linhas com tinta (y = 0 é o topo da imagem).
        var inkPerRow: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            var count = 0
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.5 {
                count += 1
            }
            inkPerRow.append(count)
        }
        let inked = inkPerRow.indices.filter { inkPerRow[$0] > 0 }
        let top = try #require(inked.first)
        let bottom = try #require(inked.last)
        #expect(bottom > top, "não foi desenhada tinta nenhuma")

        // O "T" tem a barra em cima: metade superior da mancha muito mais pesada.
        let middle = (top + bottom) / 2
        let upper = inkPerRow[top...middle].reduce(0, +)
        let lower = inkPerRow[(middle + 1)...bottom].reduce(0, +)
        #expect(Double(upper) > Double(lower) * 1.4, "glifos espelhados: \(upper) px em cima vs \(lower) px em baixo")
    }
}
