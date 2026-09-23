import Foundation

// MARK: - Escaping de CSV (fonte única)

/// Escapa um valor para uma célula CSV.
///
/// - Duplica aspas e envolve o campo em aspas quando contém `"`, `,`, `;`,
///   `\n` ou `\r` — senão o campo parte a linha ou a coluna.
/// - Neutraliza injeção de fórmula (Excel / Numbers / LibreOffice) prefixando
///   `'` quando o valor começa por `=`, `+`, `-` ou `@`.
///
/// Todos os exportadores CSV do projeto usam esta função. Não escrever outra.
/// BOM UTF-8 — sem ele o Excel abre o CSV em Latin-1 e parte os acentos.
/// Todo o CSV exportado começa por esta string.
let csvBOM = "\u{FEFF}"

/// Valor monetário/numérico para célula CSV: número cru com ponto decimal e
/// 2 casas, sem símbolo de moeda nem separador de milhares — assim o Excel
/// soma a coluna em vez de a tratar como texto. A moeda vai no cabeçalho.
func csvNumber(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func csvField(_ value: String) -> String {
    var field = value

    if let first = field.first, "=+-@".contains(first) {
        field = "'" + field
    }

    // Comparação por scalar: em Swift, "\r\n" é um único Character, logo
    // `contains(where:)` sobre Characters deixava passar CRLF sem aspas.
    let mustQuote: Set<Unicode.Scalar> = ["\"", ",", ";", "\n", "\r"]
    if field.unicodeScalars.contains(where: { mustQuote.contains($0) }) {
        field = "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    return field
}
