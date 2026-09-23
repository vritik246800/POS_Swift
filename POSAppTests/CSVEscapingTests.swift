import Foundation
import Testing
@testable import POSApp

// MARK: - S8 — Escaping de CSV e injeção de fórmula

@Suite("CSV Escaping")
struct CSVEscapingTests {

    @Test("Valor simples passa intacto")
    func plainValue() {
        #expect(csvField("Arroz") == "Arroz")
        #expect(csvField("") == "")
    }

    @Test("Vírgula obriga a aspas")
    func comma() {
        #expect(csvField("Arroz, 1kg") == "\"Arroz, 1kg\"")
    }

    @Test("Ponto e vírgula obriga a aspas (separador em locale PT)")
    func semicolon() {
        #expect(csvField("Arroz; 1kg") == "\"Arroz; 1kg\"")
    }

    @Test("Aspas são duplicadas e o campo é envolvido")
    func quotes() {
        #expect(csvField("Sumo \"Fresh\"") == "\"Sumo \"\"Fresh\"\"\"")
    }

    @Test("Nova linha não parte a linha do CSV")
    func newline() {
        #expect(csvField("Linha1\nLinha2") == "\"Linha1\nLinha2\"")
        #expect(csvField("Linha1\r\nLinha2") == "\"Linha1\r\nLinha2\"")
    }

    @Test("Injeção de fórmula é neutralizada com prefixo '")
    func formulaInjection() {
        #expect(csvField("=SOMA(1;1)") == "\"'=SOMA(1;1)\"")
        #expect(csvField("+1+1") == "'+1+1")
        #expect(csvField("-1+1") == "'-1+1")
        #expect(csvField("@SUM(A1)") == "'@SUM(A1)")
    }

    @Test("Fórmula com vírgula é neutralizada e escapada")
    func formulaWithComma() {
        #expect(csvField("=HYPERLINK(\"http://x\",\"a\")")
                == "\"'=HYPERLINK(\"\"http://x\"\",\"\"a\"\")\"")
    }

    @Test("csvNumber devolve número cru, sempre com ponto decimal")
    func numericCells() {
        #expect(csvNumber(0) == "0.00")
        #expect(csvNumber(1234.5) == "1234.50")
        #expect(csvNumber(-8.126) == "-8.13")
        // Sem símbolo de moeda nem separador de milhares — senão o Excel
        // lê a célula como texto e não soma a coluna.
        for value in [0.0, 1_500.0, 99_999.99, -3.5] {
            let cell = csvNumber(value)
            #expect(!cell.contains(","))
            #expect(!cell.contains(" "))
            #expect(Double(cell) != nil)
        }
    }

    @Test("BOM UTF-8 tem exatamente um scalar")
    func bom() {
        #expect(csvBOM.unicodeScalars.count == 1)
        #expect(csvBOM.unicodeScalars.first?.value == 0xFEFF)
    }

    @Test("Nome do programa é validado antes de ser usado")
    func appNameValidation() {
        #expect(Constants.sanitizedAppName("  Mercearia Silva  ") == "Mercearia Silva")
        #expect(Constants.sanitizedAppName("") == Constants.defaultAppName)
        #expect(Constants.sanitizedAppName("   ") == Constants.defaultAppName)
        #expect(Constants.sanitizedAppName("Loja\nNova") == "Loja Nova")
        #expect(Constants.sanitizedAppName(String(repeating: "A", count: 100)).count
                == Constants.appNameMaxLength)
    }

    @Test("O resultado nunca introduz separadores fora de aspas")
    func noStraySeparators() {
        for value in ["a,b", "a;b", "a\nb", "a\"b", "=1", "-", "@", "normal"] {
            let out = csvField(value)
            let isQuoted = out.hasPrefix("\"") && out.hasSuffix("\"") && out.count > 1
            if !isQuoted {
                #expect(!out.contains(","))
                #expect(!out.contains(";"))
                #expect(!out.contains("\n"))
                #expect(!out.contains("\""))
            }
        }
    }
}
