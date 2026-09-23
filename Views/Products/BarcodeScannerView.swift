import SwiftUI
import AVFoundation
internal import Combine

// MARK: - Scanner SwiftUI wrapper
struct BarcodeScannerView: View {
    @Binding var scannedCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
#if canImport(UIKit)
        ZStack {
            _BarcodeCameraPreview(scannedCode: $scannedCode, dismiss: dismiss)
                .ignoresSafeArea()
            _ScannerOverlay(dismiss: dismiss)
        }
        .ignoresSafeArea()
#else
        _MacBarcodeScannerView(scannedCode: $scannedCode, dismiss: dismiss)
#endif
    }
}

// MARK: - Overlay iOS
private struct _ScannerOverlay: View {
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scanner")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Aponte para um código de barras")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Spacer()

            ZStack {
                Color.black.opacity(0.5)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 14)
                            .frame(width: 270, height: 130)
                    }
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.yellow, lineWidth: 2.5)
                    .frame(width: 270, height: 130)
                ScannerCorners().frame(width: 270, height: 130)
                ScanLine().frame(width: 250, height: 130)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
                Text("EAN-8 · EAN-13 · QR · Code128")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
            .padding(.bottom, 32)
        }
    }
}

// MARK: - macOS: tudo autónomo

#if !canImport(UIKit)
private struct _MacBarcodeScannerView: View {
    @Binding var scannedCode: String
    let dismiss: DismissAction

    @StateObject private var cameraManager = MacCameraManager()
    @State private var manualInput: String = ""
    @State private var showManual: Bool = false
    @FocusState private var manualFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraManager.hasCamera {
                _MacCameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanner")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(cameraManager.hasCamera
                             ? "Aponte para um código de barras"
                             : "Ligue o iPhone via Continuity Camera ou use entrada manual")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Spacer()

                // Viewfinder ou placeholder
                if cameraManager.hasCamera {
                    ZStack {
                        Color.black.opacity(0.5)
                            .reverseMask {
                                RoundedRectangle(cornerRadius: 14)
                                    .frame(width: 270, height: 130)
                            }
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.yellow, lineWidth: 2.5)
                            .frame(width: 270, height: 130)
                        ScannerCorners().frame(width: 270, height: 130)
                        ScanLine().frame(width: 250, height: 130)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Nenhuma câmara detectada")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Certifica-te de que o iPhone está próximo\ne na mesma conta iCloud (Continuity Camera)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Painel inferior
                VStack(spacing: 10) {

                    // Selector de câmara
                    if cameraManager.availableDevices.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(cameraManager.availableDevices, id: \.uniqueID) { device in
                                    let isSelected = cameraManager.activeDevice?.uniqueID == device.uniqueID
                                    Button { cameraManager.selectDevice(device) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: deviceIcon(device))
                                                .font(.system(size: 12))
                                            Text(device.localizedName)
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? Color.yellow.opacity(0.25) : Color.white.opacity(0.1))
                                        .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(0.8))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(isSelected ? Color.yellow.opacity(0.7) : Color.clear, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Linha: hint + botão manual
                    HStack(spacing: 10) {
                        if !showManual {
                            HStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.yellow)
                                Text("EAN-8 · EAN-13 · QR · Code128")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        if showManual {
                            HStack(spacing: 8) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                TextField("Código de barras...", text: $manualInput)
                                    .font(.system(size: 14))
                                    .focused($manualFocused)
                                    .frame(minWidth: 140)
                                    .onSubmit { commitManual() }
                                if !manualInput.isEmpty {
                                    Button { manualInput = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button { commitManual() } label: {
                                Text("OK")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.yellow)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showManual.toggle()
                                if showManual { manualFocused = true }
                                else { manualInput = "" }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showManual ? "camera.fill" : "keyboard")
                                    .font(.system(size: 13))
                                Text(showManual ? "Câmara" : "Manual")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .onAppear {
            cameraManager.onCodeScanned = { code in
                scannedCode = code
                dismiss()
            }
            cameraManager.start()
        }
        .onDisappear { cameraManager.stop() }
    }

    private func commitManual() {
        let code = manualInput.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        scannedCode = code
        dismiss()
    }

    private func deviceIcon(_ device: AVCaptureDevice) -> String {
        let n = device.localizedName.lowercased()
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad")   { return "ipad" }
        return "camera.fill"
    }
}

// MARK: - NSViewRepresentable preview

private struct _MacCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> _PreviewNSView { _PreviewNSView(session: session) }
    func updateNSView(_ nsView: _PreviewNSView, context: Context) { nsView.session = session }
}

private class _PreviewNSView: NSView {
    var session: AVCaptureSession? { didSet { previewLayer.session = session } }
    private let previewLayer = AVCaptureVideoPreviewLayer()

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        self.session = session
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session
        layer?.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); previewLayer.frame = bounds }
}

// MARK: - MacCameraManager

private class MacCameraManager: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var activeDevice: AVCaptureDevice? = nil
    @Published var hasCamera: Bool = false

    let session = AVCaptureSession()
    var onCodeScanned: ((String) -> Void)? = nil
    private var didScan = false
    private let metaOutput = AVCaptureMetadataOutput()

    func start() {
        discoverDevices()
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        NotificationCenter.default.removeObserver(self)
    }

    func selectDevice(_ device: AVCaptureDevice) {
        didScan = false
        configure(device: device)
    }

    @objc private func devicesChanged() {
        DispatchQueue.main.async { self.discoverDevices() }
    }

    private func discoverDevices() {
        let ds = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let devices = ds.devices
        DispatchQueue.main.async {
            self.availableDevices = devices
            self.hasCamera = !devices.isEmpty
            if self.activeDevice == nil, let first = devices.first {
                self.configure(device: first)
            }
        }
    }

    private func configure(device: AVCaptureDevice) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }

            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            if !self.session.outputs.contains(self.metaOutput),
               self.session.canAddOutput(self.metaOutput) {
                self.session.addOutput(self.metaOutput)
                self.metaOutput.setMetadataObjectsDelegate(self, queue: .main)
            }
            self.metaOutput.metadataObjectTypes = [
                .ean8, .ean13, .pdf417, .qr, .code128, .code39, .upce, .interleaved2of5
            ]
            self.session.commitConfiguration()

            DispatchQueue.main.async { self.activeDevice = device }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue else { return }
        didScan = true
        session.stopRunning()
        onCodeScanned?(code)
    }
}
#endif

// MARK: - iOS camera

#if canImport(UIKit)
private struct _BarcodeCameraPreview: UIViewRepresentable {
    @Binding var scannedCode: String
    let dismiss: DismissAction

    func makeCoordinator() -> Coordinator { Coordinator(scannedCode: $scannedCode, dismiss: dismiss) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        let session = AVCaptureSession()
        context.coordinator.session = session
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return view }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return view }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .pdf417, .qr, .code128, .code39, .upce, .interleaved2of5]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.previewLayer?.frame = uiView.bounds }
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String
        let dismiss: DismissAction
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var didScan = false

        init(scannedCode: Binding<String>, dismiss: DismissAction) {
            _scannedCode = scannedCode
            self.dismiss = dismiss
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = obj.stringValue else { return }
            didScan = true
            session?.stopRunning()
            scannedCode = code
            dismiss()
        }
    }
}
#endif

// MARK: - Componentes visuais

private struct ScannerCorners: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let len: CGFloat = 22, thick: CGFloat = 3
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: len, y: 0)) }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: thick, lineCap: .round))
                Path { p in p.move(to: CGPoint(x: w-len, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: len)) }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: thick, lineCap: .round))
                Path { p in p.move(to: CGPoint(x: 0, y: h-len)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: len, y: h)) }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: thick, lineCap: .round))
                Path { p in p.move(to: CGPoint(x: w-len, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h-len)) }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: thick, lineCap: .round))
            }
        }
    }
}

private struct ScanLine: View {
    @State private var offset: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .yellow.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .offset(y: offset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        offset = geo.size.height - 4
                    }
                }
        }
    }
}

extension View {
    func reverseMask<M: View>(@ViewBuilder mask: () -> M) -> some View {
        self.mask(Rectangle().overlay(mask().blendMode(.destinationOut)).compositingGroup())
    }
}
