import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = StockViewModel()

    @State private var showImporter = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showProximityReceiver = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.products.isEmpty {
                    emptyState
                } else {
                    productList
                }
            }
            .navigationTitle("Stock Manager")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .searchable(text: $vm.searchText, prompt: "Nome ou código de barras")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { vm.importCSV(from: url) }
                case .failure(let error):
                    vm.errorMessage = error.localizedDescription
                    vm.showError = true
                }
            }
            .alert("Erro", isPresented: $vm.showError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(vm.errorMessage ?? "Erro desconhecido")
            })
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showProximityReceiver) {
                ProximityReceiverView { url in
                    vm.importCSV(from: url)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Nenhum CSV importado")
                .font(.title3.weight(.semibold))
            Text("Importa um ficheiro CSV para começar")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { showImporter = true }) {
                Label("Importar CSV", systemImage: "square.and.arrow.down")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    private var productList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                summaryBar
                filterPicker.padding(.horizontal, 16)

                ForEach(vm.filteredProducts) { product in
                    ProductRow(
                        product: product,
                        onCycleStatus: { vm.cycleStatus(for: product) },
                        onUpdateStock: { stock, enc in
                            vm.updateStock(for: product, stockActual: stock, qtyEncomenda: enc)
                        }
                    )
                    .padding(.horizontal, 16)
                }

                if vm.filteredProducts.isEmpty {
                    Text("Nenhum produto encontrado")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var summaryBar: some View {
        HStack(spacing: 0) {
            SummaryTile(label: "Total",      value: "\(vm.products.count)",  color: .primary)
            Divider().frame(height: 30)
            SummaryTile(label: "Red Flag",   value: "\(vm.redFlagCount)",    color: vm.redFlagCount > 0 ? .red : .secondary)
            Divider().frame(height: 30)
            SummaryTile(label: "Confirmado", value: "\(vm.confirmedCount)",  color: vm.confirmedCount > 0 ? .green : .secondary)
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private var filterPicker: some View {
        Picker("Filtro", selection: $vm.filterStatus) {
            Text("Todos").tag(StockStatus?.none)
            Label("Red Flag", systemImage: "flag.fill").tag(StockStatus?.some(.redFlag))
            Label("Confirmado", systemImage: "checkmark.seal.fill").tag(StockStatus?.some(.confirmed))
            Label("Sem estado", systemImage: "flag").tag(StockStatus?.some(.none))
        }
        .pickerStyle(.segmented)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("Importar CSV do Sistema", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    showProximityReceiver = true
                } label: {
                    Label("Receber de Dispositivo Próximo", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                
                if !vm.products.isEmpty {
                    Divider()
                    Button { export(data: vm.csvDataAll(), name: "stock_export.csv") } label: {
                        Label("Exportar Todos", systemImage: "square.and.arrow.up")
                    }
                    Button { export(data: vm.csvDataRedFlags(), name: "stock_redflags.csv") } label: {
                        Label("Exportar Red Flags (\(vm.redFlagCount))", systemImage: "flag.fill")
                    }
                    .disabled(vm.redFlagCount == 0)
                    Button { export(data: vm.csvDataConfirmed(), name: "stock_confirmados.csv") } label: {
                        Label("Exportar Confirmados (\(vm.confirmedCount))", systemImage: "checkmark.seal.fill")
                    }
                    .disabled(vm.confirmedCount == 0)
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18))
            }
        }
    }

    private func export(data: Data, name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        shareItems = [url]
        showShareSheet = true
    }
}

struct SummaryTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
