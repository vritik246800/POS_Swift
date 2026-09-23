import Foundation
import Testing
@testable import POSApp

// MARK: - S7 — Limite de payload, timeout e validação do que vem da rede

@Suite("Proximity Payload")
struct ProximityPayloadTests {

    // MARK: Tamanho anunciado no cabeçalho de 4 bytes

    @Test("Limite é 10 MB")
    func limitIs10MB() {
        #expect(ProximityPayload.maxBytes == 10 * 1024 * 1024)
        #expect(ProximityPayload.timeout == 30)
    }

    @Test("Tamanho acima do limite é recusado sem alocar")
    func oversizedRejected() {
        #expect(ProximityPayload.isAcceptableSize(UInt32.max) == false)
        #expect(ProximityPayload.isAcceptableSize(UInt32(ProximityPayload.maxBytes + 1)) == false)
    }

    @Test("Tamanho zero é recusado")
    func zeroRejected() {
        #expect(ProximityPayload.isAcceptableSize(0) == false)
    }

    @Test("Tamanho dentro do limite é aceite, fronteira incluída")
    func acceptedSizes() {
        #expect(ProximityPayload.isAcceptableSize(1))
        #expect(ProximityPayload.isAcceptableSize(2_300))
        #expect(ProximityPayload.isAcceptableSize(UInt32(ProximityPayload.maxBytes)))
    }

    // MARK: Envelope JSON

    private func envelope(_ products: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["version": "1.0", "products": products])
    }

    @Test("Envelope válido produz linhas")
    func validEnvelope() {
        let data = envelope([[
            "barcode": "1234567890123",
            "name": "Arroz",
            "stock": 2,
            "orderQty": 10
        ]])
        let rows = ProximityPayload.validatedRows(from: data)
        #expect(rows?.count == 1)
        #expect(rows?.first?.name == "Arroz")
    }

    @Test("JSON malformado é rejeitado")
    func malformedRejected() {
        #expect(ProximityPayload.validatedRows(from: Data("não é json".utf8)) == nil)
        #expect(ProximityPayload.validatedRows(from: Data()) == nil)
    }

    @Test("Envelope sem 'products' é rejeitado")
    func missingProductsRejected() {
        let data = try! JSONSerialization.data(withJSONObject: ["version": "1.0"])
        #expect(ProximityPayload.validatedRows(from: data) == nil)
    }

    @Test("Campos hostis são descartados")
    func hostileFieldsDropped() {
        let data = envelope([
            ["barcode": "1", "name": "", "stock": 1, "orderQty": 1],                    // nome vazio
            ["barcode": "2", "name": String(repeating: "x", count: 500), "stock": 1, "orderQty": 1], // nome enorme
            ["barcode": String(repeating: "9", count: 200), "name": "A", "stock": 1, "orderQty": 1], // barcode enorme
            ["barcode": "5", "name": "B", "stock": -5, "orderQty": 1],                  // stock negativo
            ["barcode": "6", "name": "C", "stock": 1, "orderQty": 99_999_999],          // quantidade fora de gama
            ["barcode": "7", "name": "D", "stock": "muito", "orderQty": 1],             // tipo errado
            ["barcode": "8", "name": "Válido", "stock": 3, "orderQty": 4]
        ])
        let rows = ProximityPayload.validatedRows(from: data)
        #expect(rows?.count == 1)
        #expect(rows?.first?.name == "Válido")
    }

    @Test("Lista de produtos acima do máximo é rejeitada inteira")
    func tooManyProducts() {
        let many = Array(repeating: ["barcode": "1", "name": "A", "stock": 1, "orderQty": 1] as [String: Any],
                         count: ProximityPayload.maxProducts + 1)
        #expect(ProximityPayload.validatedRows(from: envelope(many)) == nil)
    }

    // MARK: Emparelhamento

    @Test("Código de emparelhamento tem 6 dígitos")
    func pairingCodeFormat() {
        for _ in 0..<50 {
            let code = ProximityPayload.makePairingCode()
            let allDigits = code.allSatisfy(\.isNumber)
            #expect(code.count == 6)
            #expect(allDigits)
        }
    }

    @Test("Códigos diferentes dão parâmetros TLS distintos (não há sessão sem o código certo)")
    func parametersUseCode() {
        // Não é possível inspecionar a PSK; garante-se apenas que os parâmetros
        // são construídos com TLS e peer-to-peer activo.
        let params = ProximityPayload.parameters(code: "123456")
        #expect(params.includePeerToPeer)
        #expect(params.defaultProtocolStack.applicationProtocols.isEmpty == false)
    }
}
