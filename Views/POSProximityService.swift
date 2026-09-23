import Foundation
import Network
import CryptoKit
internal import Combine

// MARK: - Diagnóstico (nunca em RELEASE, nunca com conteúdo transferido)

@inline(__always)
private func proxLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

// MARK: - Limites e validação do payload (Docs/security/SECURITY.md §5.3)

/// Regras aplicadas a tudo o que chega da rede local. Um peer é hostil por
/// omissão: o cabeçalho de 4 bytes anuncia até 4 GiB e o JSON pode vir com
/// qualquer coisa lá dentro.
enum ProximityPayload {
    /// Máximo aceite por transferência (S7).
    static let maxBytes = 10 * 1024 * 1024
    /// Tempo máximo de uma transferência (S7).
    static let timeout: TimeInterval = 30
    /// Máximo de produtos num envelope.
    static let maxProducts = 10_000

    struct Row: Equatable {
        let barcode: String
        let name: String
        let stock: Int
        let orderQty: Int
    }

    /// `true` se o tamanho anunciado no cabeçalho pode ser aceite.
    /// Verificado **antes** de reservar memória.
    static func isAcceptableSize(_ announced: UInt32) -> Bool {
        announced > 0 && Int(announced) <= maxBytes
    }

    /// Valida o envelope JSON recebido. Devolve `nil` se estiver malformado;
    /// linhas individuais fora de gama são descartadas.
    static func validatedRows(from data: Data) -> [Row]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return validatedRows(from: json)
    }

    static func validatedRows(from json: [String: Any]) -> [Row]? {
        guard let raw = json["products"] as? [[String: Any]], raw.count <= maxProducts else {
            return nil
        }

        var rows: [Row] = []
        for item in raw {
            guard let barcode = item["barcode"] as? String, barcode.count <= 64,
                  let name = item["name"] as? String, !name.isEmpty, name.count <= 200,
                  let stock = item["stock"] as? Int, (0...1_000_000).contains(stock),
                  let orderQty = item["orderQty"] as? Int, (0...1_000_000).contains(orderQty)
            else { continue }

            rows.append(Row(barcode: barcode, name: name, stock: stock, orderQty: orderQty))
        }
        return rows
    }

    /// Código de emparelhamento de 6 dígitos.
    static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// Parâmetros TCP+TLS com PSK derivada do código de emparelhamento (S5).
    /// Sem o mesmo código dos dois lados o handshake falha — não há sessão.
    static func parameters(code: String) -> NWParameters {
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
}

// MARK: - Serviço de Descoberta e Comunicação Local

/// Permite que a app iOS/iPadOS sinalize presença na rede local
/// e que a app macOS detecte dispositivos iOS prontos para receber dados
class POSProximityService: ObservableObject {

    static let shared = POSProximityService()

    @Published var availableDevices: [POSDevice] = []
    @Published var isAdvertising = false
    @Published var isDiscovering = false
    @Published var isWaitingForList = false

    /// Código de emparelhamento desta sessão. Quem recebe mostra-o no ecrã;
    /// quem envia escreve-o antes de ligar. É dele que sai a chave TLS (S5).
    @Published var pairingCode: String = ""
    /// Dispositivo a aguardar autorização do utilizador. Enquanto não for
    /// `nil`, a UI mostra "Aceitar / Recusar" — nunca se aceita sozinho (S5).
    @Published var pendingPeerName: String?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var currentDeviceName: String?
    private var currentConnection: NWConnection?
    private var pendingConnection: NWConnection?
    private var timeoutWork: DispatchWorkItem?

    /// Uma ligação de cada vez (S7).
    private var isBusy: Bool { currentConnection != nil || pendingConnection != nil }

    private let serviceType = "_posapp._tcp"
    private let serviceDomain = "local"

    // MARK: - Iniciar Anúncio (iOS/iPadOS - "Estou online")

    /// A app iOS chama isto ao abrir para sinalizar que está pronta
    /// - Parameters:
    ///   - deviceName: Nome do dispositivo
    ///   - waitingForList: Indica se está à espera de receber lista de stock
    func startAdvertising(deviceName: String, waitingForList: Bool = true) {
        guard !isAdvertising else { return }

        pairingCode = ProximityPayload.makePairingCode()
        let params = ProximityPayload.parameters(code: pairingCode)
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: .any)

            // TXT record com metadados
            let txtRecord = NWTXTRecord([
                "device": deviceName,
                "platform": "iOS",
                "version": "1.0",
                "ready": "true",
                "waitingForList": waitingForList ? "true" : "false"
            ])

            // Configura o serviço Bonjour no listener
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
                        self?.isWaitingForList = waitingForList
                        self?.currentDeviceName = deviceName
                        proxLog("✅ POS Proximity: a anunciar serviço")
                    case .failed(let error):
                        proxLog("❌ POS Proximity: erro ao anunciar - \(error)")
                        self?.isAdvertising = false
                        self?.isWaitingForList = false
                        self?.pairingCode = ""
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .main)

        } catch {
            proxLog("❌ Erro ao criar listener")
        }
    }

    /// Para o anúncio
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        isWaitingForList = false
        currentDeviceName = nil
        pairingCode = ""
        cancelPending()
        proxLog("🛑 POS Proximity: anúncio parado")
    }

    /// Atualiza o estado de "à espera de lista" e re-anuncia o serviço
    func updateWaitingForListState(_ waiting: Bool) {
        guard isAdvertising, let deviceName = currentDeviceName else {
            proxLog("⚠️ Não é possível atualizar estado: serviço não está a anunciar")
            return
        }

        // Para e reinicia com novo estado
        stopAdvertising()
        startAdvertising(deviceName: deviceName, waitingForList: waiting)
    }

    // MARK: - Descobrir Dispositivos (macOS/iPad - "Quem está online?")

    /// A app desktop chama isto para ver quem está pronto
    func startDiscovery() {
        guard !isDiscovering else { return }

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isDiscovering = true
                    proxLog("🔍 POS Proximity: a procurar dispositivos...")
                case .failed(let error):
                    proxLog("❌ Erro na descoberta: \(error)")
                    self?.isDiscovering = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.updateAvailableDevices(from: results)
            }
        }

        browser?.start(queue: .main)
    }

    /// Para a descoberta
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        availableDevices.removeAll()
        isDiscovering = false
        proxLog("🛑 POS Proximity: descoberta parada")
    }

    /// Retorna apenas dispositivos que estão à espera de receber lista
    var devicesWaitingForList: [POSDevice] {
        availableDevices.filter { $0.isWaitingForList }
    }

    // MARK: - Enviar Dados para Dispositivo iOS

    /// Envia ficheiro JSON estruturado via NWConnection cifrada.
    /// - Parameter code: código de emparelhamento de 6 dígitos mostrado no ecrã
    ///   do dispositivo que recebe. Sem o código certo o TLS não estabelece.
    func sendStockData(_ data: Data, to device: POSDevice, code: String? = nil, completion: @escaping (Bool) -> Void) {
        guard data.count <= ProximityPayload.maxBytes else {
            proxLog("🚫 Envio recusado: payload acima do limite")
            completion(false)
            return
        }

        let params = ProximityPayload.parameters(code: code ?? pairingCode)
        let connection = NWConnection(to: device.endpoint, using: params)
        var finished = false
        func finish(_ ok: Bool) {
            guard !finished else { return }
            finished = true
            completion(ok)
            connection.cancel()
        }

        // Timeout de 30 s por transferência (S7)
        DispatchQueue.main.asyncAfter(deadline: .now() + ProximityPayload.timeout) {
            if !finished {
                proxLog("⏱️ Envio excedeu o tempo limite")
                finish(false)
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                proxLog("✅ Ligação cifrada estabelecida")

                // Envia tamanho do payload (4 bytes) + dados
                var size = UInt32(data.count).bigEndian
                let sizeData = Data(bytes: &size, count: 4)

                connection.send(content: sizeData, completion: .contentProcessed { error in
                    if error != nil {
                        proxLog("❌ Erro ao enviar cabeçalho")
                        finish(false)
                        return
                    }

                    connection.send(content: data, completion: .contentProcessed { error in
                        if error != nil {
                            proxLog("❌ Erro ao enviar dados")
                            finish(false)
                        } else {
                            proxLog("✅ Dados enviados")
                            finish(true)
                        }
                    })
                })

            case .failed(let error):
                proxLog("❌ Ligação falhou: \(error)")
                finish(false)

            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    // MARK: - Confirmação explícita do utilizador (S5)

    /// O utilizador aceitou a ligação mostrada em `pendingPeerName`.
    func acceptPendingConnection() {
        guard let connection = pendingConnection else { return }
        pendingConnection = nil
        pendingPeerName = nil
        currentConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                proxLog("📲 Ligação aceite")
                self?.receiveData(from: connection)
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self?.closeCurrentConnection()
                }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// O utilizador recusou a ligação mostrada em `pendingPeerName`.
    func rejectPendingConnection() {
        cancelPending()
    }

    // MARK: - Helpers Internos

    private func cancelPending() {
        pendingConnection?.cancel()
        pendingConnection = nil
        pendingPeerName = nil
    }

    private func closeCurrentConnection() {
        timeoutWork?.cancel()
        timeoutWork = nil
        currentConnection?.cancel()
        currentConnection = nil
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard !self.isBusy else {
                proxLog("⚠️ Ligação recusada: já existe uma transferência")
                connection.cancel()
                return
            }

            // Só arranca depois de o utilizador confirmar (S5)
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

    private func startTimeout() {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.currentConnection != nil else { return }
            proxLog("⏱️ Transferência excedeu o tempo limite")
            self.closeCurrentConnection()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ProximityPayload.timeout, execute: work)
    }

    private func receiveData(from connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in self?.startTimeout() }

        // Primeiro recebe tamanho (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, _ in
            guard let self = self else { return }
            guard let sizeData = data, sizeData.count == 4 else {
                DispatchQueue.main.async { self.closeCurrentConnection() }
                return
            }

            let announced = sizeData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Limite verificado ANTES de reservar memória (S7)
            guard ProximityPayload.isAcceptableSize(announced) else {
                proxLog("🚫 Tamanho anunciado fora do limite")
                DispatchQueue.main.async { self.closeCurrentConnection() }
                return
            }

            let size = Int(announced)
            connection.receive(minimumIncompleteLength: size, maximumLength: size) { data, _, _, _ in
                guard let payload = data, payload.count == size,
                      let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                      ProximityPayload.validatedRows(from: json) != nil else {
                    proxLog("🚫 Payload recusado")
                    DispatchQueue.main.async { self.closeCurrentConnection() }
                    return
                }

                proxLog("📥 Transferência recebida")

                DispatchQueue.main.async {
                    self.closeCurrentConnection()
                    NotificationCenter.default.post(
                        name: .posStockDataReceived,
                        object: nil,
                        userInfo: ["data": json]
                    )
                }
            }
        }
    }

    private func updateAvailableDevices(from results: Set<NWBrowser.Result>) {
        availableDevices = results.compactMap { result -> POSDevice? in
            guard case .service(let name, _, _, _) = result.endpoint else {
                return nil
            }

            var metadata: [String: String] = [:]
            if case .bonjour(let txtRecord) = result.metadata {
                for key in ["device", "platform", "version", "ready", "waitingForList"] {
                    if let value = txtRecord[key] {
                        metadata[key] = value
                    }
                }
            }

            return POSDevice(
                name: name,
                endpoint: result.endpoint,
                metadata: metadata
            )
        }.sorted { $0.name < $1.name }

        proxLog("📱 Dispositivos encontrados: \(availableDevices.count)")
    }
}

// MARK: - Modelo de Dispositivo

struct POSDevice: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let metadata: [String: String]

    var platform: String {
        metadata["platform"] ?? "Unknown"
    }

    var isReady: Bool {
        metadata["ready"] == "true"
    }

    var isWaitingForList: Bool {
        metadata["waitingForList"] == "true"
    }

    var statusDescription: String {
        if !isReady {
            return "Offline"
        } else if isWaitingForList {
            return "A aguardar lista 📋"
        } else {
            return "Online"
        }
    }

    static func == (lhs: POSDevice, rhs: POSDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let posStockDataReceived = Notification.Name("com.posapp.stockDataReceived")
}
