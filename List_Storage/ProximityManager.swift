//
//  ProximityManager.swift
//  POS_Sale_list
//
//  Sistema de descoberta e transferência de arquivos por proximidade
//  Usa Network framework (Bonjour) para compatibilidade com o app Mac
//
//  Segurança (Docs/security/SECURITY.md §5.3):
//  - TLS com PSK derivada de um código de emparelhamento de 6 dígitos (S5)
//  - Confirmação explícita do utilizador antes de aceitar a ligação (S5)
//  - Payload limitado a 10 MB, timeout de 30 s, uma ligação de cada vez (S7)
//  - Diagnósticos só em DEBUG e nunca com conteúdo de transferências (S12)
//

import Foundation
import Network
import CryptoKit
import Combine
import UIKit

enum ProximityTransferState: Equatable {
    case idle
    case discovering
    case connected
    case receiving
    case completed
    case failed(Error)

    static func == (lhs: ProximityTransferState, rhs: ProximityTransferState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.discovering, .discovering),
             (.connected, .connected),
             (.receiving, .receiving),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Diagnóstico (nunca em RELEASE, nunca com conteúdo transferido)

@inline(__always)
private func proxLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

class ProximityManager: NSObject, ObservableObject {
    // MARK: - Limites de transferência
    /// Máximo aceite por transferência. O cabeçalho de 4 bytes permite anunciar
    /// 4 GiB — sem este limite um peer esgota a RAM só com um número.
    static let maxPayloadBytes = 10 * 1024 * 1024
    /// Tempo máximo de uma transferência antes de a ligação ser cancelada.
    static let transferTimeout: TimeInterval = 30

    // MARK: - Published Properties
    @Published var state: ProximityTransferState = .idle
    @Published var discoveredPeers: [String] = []  // Agora são nomes de dispositivos
    @Published var receivedFileURL: URL?
    @Published var transferProgress: Double = 0.0
    @Published var isAdvertising = false
    /// Código de emparelhamento de 6 dígitos a mostrar no ecrã de recepção.
    /// Quem envia tem de escrever o mesmo código — é dele que sai a chave TLS.
    @Published var pairingCode: String = ""
    /// Nome do dispositivo que está à espera de autorização. Enquanto não for
    /// `nil`, a UI deve mostrar "Aceitar / Recusar". Nunca aceitar sozinho.
    @Published var pendingPeerName: String?

    // MARK: - Network Framework
    private let serviceType = "_posapp._tcp"
    private let serviceDomain = "local"
    private var listener: NWListener?
    private var currentConnection: NWConnection?
    private var pendingConnection: NWConnection?
    private var timeoutWork: DispatchWorkItem?
    private var deviceName: String

    /// Uma ligação de cada vez: já há transferência activa ou pedido por decidir.
    private var isBusy: Bool { currentConnection != nil || pendingConnection != nil }

    // MARK: - Initialization
    override init() {
        self.deviceName = UIDevice.current.name
        super.init()
    }

    // MARK: - Public Methods

    /// Verificar se temos permissões necessárias
    func checkPermissions() async -> Bool {
        // Tentar criar um listener temporário para verificar permissões
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        do {
            let testListener = try NWListener(using: params, on: .any)

            return await withCheckedContinuation { continuation in
                testListener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        testListener.cancel()
                        continuation.resume(returning: true)
                    case .failed:
                        testListener.cancel()
                        continuation.resume(returning: false)
                    default:
                        break
                    }
                }
                testListener.start(queue: .main)
            }
        } catch {
            proxLog("❌ Erro ao verificar permissões")
            return false
        }
    }

    /// Começar a anunciar disponibilidade para receber arquivos.
    /// Gera um código de emparelhamento novo em cada sessão.
    func startAdvertising() {
        guard listener == nil else { return }

        pairingCode = Self.makePairingCode()

        // TLS com PSK: sem o código certo não há sessão (S5)
        let params = Self.pskParameters(code: pairingCode)
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: .any)

            // TXT record com metadados (compatível com o app Mac)
            let txtRecord = NWTXTRecord([
                "device": deviceName,
                "platform": "iOS",
                "version": "1.0",
                "ready": "true",
                "waitingForList": "true"
            ])

            // Configura o serviço Bonjour
            listener?.service = NWListener.Service(
                name: deviceName,
                type: serviceType,
                domain: serviceDomain,
                txtRecord: txtRecord
            )

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        self?.state = .discovering
                        proxLog("📡 A anunciar dispositivo")

                    case .failed(let error):
                        proxLog("❌ Erro ao anunciar: \(error)")
                        self?.state = .failed(error)
                        self?.isAdvertising = false

                    case .waiting:
                        proxLog("⏳ Listener em espera")

                    case .cancelled:
                        proxLog("🛑 Listener cancelado")

                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .main)

        } catch {
            proxLog("❌ Erro ao criar listener")
            state = .failed(error)
        }
    }

    /// Parar de anunciar
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        pairingCode = ""
        state = .idle

        proxLog("🛑 Parou de anunciar")
    }

    /// Limpar arquivo recebido
    func clearReceivedFile() {
        receivedFileURL = nil
        transferProgress = 0.0
        state = .idle
    }

    /// Desconectar sessão
    func disconnect() {
        cancelTimeout()
        currentConnection?.cancel()
        currentConnection = nil
        pendingConnection?.cancel()
        pendingConnection = nil
        pendingPeerName = nil
        stopAdvertising()
        discoveredPeers.removeAll()
        state = .idle
    }

    // MARK: - Confirmação explícita do utilizador (S5)

    /// O utilizador aceitou o dispositivo mostrado em `pendingPeerName`.
    func acceptPendingConnection() {
        guard let connection = pendingConnection else { return }
        pendingConnection = nil
        pendingPeerName = nil
        currentConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    proxLog("✅ Ligação cifrada estabelecida")
                    self?.state = .connected
                    self?.receiveData(from: connection)

                case .failed(let error):
                    proxLog("❌ Ligação falhou: \(error)")
                    self?.finishTransfer(with: error)

                case .cancelled:
                    proxLog("🛑 Ligação cancelada")
                    self?.currentConnection = nil
                    self?.cancelTimeout()

                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    /// O utilizador recusou o dispositivo mostrado em `pendingPeerName`.
    func rejectPendingConnection() {
        pendingConnection?.cancel()
        pendingConnection = nil
        pendingPeerName = nil
        state = isAdvertising ? .discovering : .idle
    }

    deinit {
        timeoutWork?.cancel()
        currentConnection?.cancel()
        pendingConnection?.cancel()
        listener?.cancel()
    }

    // MARK: - Private Methods

    /// Código de emparelhamento de 6 dígitos, gerado com o RNG do sistema.
    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// Parâmetros TCP+TLS com PSK derivada do código de emparelhamento.
    private static func pskParameters(code: String) -> NWParameters {
        let digest = SHA256.hash(data: Data("POSApp-pairing-v1:\(code)".utf8))
        let keyData = Data(digest).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("POSApp".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            keyData as __DispatchData,
            identity as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t.AES_128_GCM_SHA256
        )

        let params = NWParameters(tls: tls)
        params.includePeerToPeer = true
        return params
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Uma ligação de cada vez (S7)
            guard !self.isBusy else {
                proxLog("⚠️ Ligação recusada: já existe uma transferência")
                connection.cancel()
                return
            }

            // A ligação só arranca depois de o utilizador aceitar (S5)
            self.pendingConnection = connection
            self.pendingPeerName = Self.describe(connection.endpoint)
            proxLog("📲 Pedido de ligação a aguardar confirmação")
        }
    }

    private static func describe(_ endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint { return name }
        if case .hostPort(let host, _) = endpoint { return "\(host)" }
        return "Dispositivo desconhecido"
    }

    // MARK: - Timeout de transferência (S7)

    private func startTimeout() {
        cancelTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.currentConnection != nil else { return }
            proxLog("⏱️ Transferência excedeu o tempo limite")
            self.finishTransfer(with: Self.error("A transferência demorou demasiado tempo."))
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transferTimeout, execute: work)
    }

    private func cancelTimeout() {
        timeoutWork?.cancel()
        timeoutWork = nil
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "ProximityManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Fecha a ligação e publica o erro. Só o MainActor mexe no estado.
    private func finishTransfer(with error: Error) {
        cancelTimeout()
        currentConnection?.cancel()
        currentConnection = nil
        state = .failed(error)
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.finishTransfer(with: Self.error(message))
        }
    }

    private func receiveData(from connection: NWConnection) {
        state = .receiving
        transferProgress = 0.0
        startTimeout()

        // Primeiro recebe tamanho (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if error != nil {
                self.fail("Falha ao receber o cabeçalho da transferência.")
                return
            }

            guard let sizeData = data, sizeData.count == 4 else {
                self.fail("Cabeçalho da transferência inválido.")
                return
            }

            let totalSize = Int(sizeData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })

            // Limite verificado ANTES de reservar memória (S7)
            guard totalSize > 0, totalSize <= Self.maxPayloadBytes else {
                proxLog("🚫 Tamanho anunciado fora do limite")
                self.fail("Transferência recusada: excede o limite de 10 MB.")
                return
            }

            proxLog("📥 A receber transferência")
            self.receivePayload(from: connection, totalSize: totalSize)
        }
    }

    private func receivePayload(from connection: NWConnection, totalSize: Int) {
        var receivedData = Data()
        receivedData.reserveCapacity(totalSize)

        func receiveChunk() {
            let chunkSize = min(65536, totalSize - receivedData.count) // 64KB chunks
            guard chunkSize > 0 else {
                self.processReceivedData(receivedData)
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }

                if error != nil {
                    self.fail("Falha ao receber os dados.")
                    return
                }

                if let data = data {
                    receivedData.append(data)

                    // Um peer que envie mais do que anunciou é hostil
                    guard receivedData.count <= totalSize else {
                        self.fail("Transferência recusada: dados a mais.")
                        return
                    }

                    let progress = Double(receivedData.count) / Double(totalSize)
                    DispatchQueue.main.async {
                        self.transferProgress = progress
                    }
                }

                if receivedData.count >= totalSize {
                    self.processReceivedData(receivedData)
                } else if isComplete {
                    self.fail("Transferência incompleta.")
                } else {
                    receiveChunk()
                }
            }
        }

        receiveChunk()
    }

    private func processReceivedData(_ data: Data) {
        proxLog("✅ Transferência recebida")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = Self.validatedProducts(from: json) else {
            fail("Os dados recebidos não são válidos.")
            return
        }

        guard let csvURL = convertToCSV(products) else {
            fail("Não foi possível guardar a lista recebida.")
            return
        }

        DispatchQueue.main.async {
            self.cancelTimeout()
            self.currentConnection?.cancel()
            self.currentConnection = nil
            self.receivedFileURL = csvURL
            self.state = .completed
            self.transferProgress = 1.0
        }
    }

    // MARK: - Validação do payload (dados de um peer são hostis por omissão)

    struct ReceivedRow {
        let barcode: String
        let name: String
        let stock: Int
        let orderQty: Int
    }

    /// Devolve as linhas válidas ou `nil` se o envelope estiver malformado.
    static func validatedProducts(from json: [String: Any]) -> [ReceivedRow]? {
        guard let raw = json["products"] as? [[String: Any]], raw.count <= 10_000 else {
            return nil
        }

        var rows: [ReceivedRow] = []
        for item in raw {
            guard let barcode = item["barcode"] as? String, barcode.count <= 64,
                  let name = item["name"] as? String, !name.isEmpty, name.count <= 200,
                  let stock = item["stock"] as? Int, (0...1_000_000).contains(stock),
                  let orderQty = item["orderQty"] as? Int, (0...1_000_000).contains(orderQty)
            else { continue }

            rows.append(ReceivedRow(barcode: barcode, name: name, stock: stock, orderQty: orderQty))
        }
        return rows
    }

    private func convertToCSV(_ products: [ReceivedRow]) -> URL? {
        var csv = "barcode,name,stock_actual,qty_encomenda\n"
        for product in products {
            csv += "\(csvField(product.barcode)),\(csvField(product.name)),\(product.stock),\(product.orderQty)\n"
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "received_stock_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = documentsPath.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            proxLog("✅ CSV guardado")
            return fileURL
        } catch {
            proxLog("❌ Erro ao guardar CSV")
            return nil
        }
    }
}
