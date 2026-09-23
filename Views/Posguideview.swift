import SwiftUI

// MARK: - Botão Guia (reutilizável)

struct POSGuideButton: View {
    /// Perfil de quem abre o guia. Por omissão, o mínimo (Caixa) — o guia nunca
    /// mostra por engano o que o utilizador não tem na app.
    var isAdmin: Bool = false
    @State private var showGuide = false

    var body: some View {
        Button {
            #if os(macOS)
            POSGuideWindowController.shared.open(isAdmin: isAdmin)
            #else
            showGuide = true
            #endif
        } label: {
            Label("Guia", systemImage: "questionmark.circle")
        }
        .help("Abrir guia de utilização")
        #if os(iOS)
        .sheet(isPresented: $showGuide) {
            POSGuideView(isAdmin: isAdmin)
        }
        #endif
    }
}

// MARK: - macOS: Controlador de janela separada

#if os(macOS)
final class POSGuideWindowController: NSObject {
    static let shared = POSGuideWindowController()
    private var window: NSWindow?
    /// Perfil com que a janela aberta foi construída — se mudar (logout/login
    /// com outro perfil), a janela é refeita em vez de reutilizada.
    private var openedAsAdmin: Bool?

    /// `isAdmin` decide os capítulos: o Caixa só vê o que existe na app dele.
    func open(isAdmin: Bool) {
        if let existing = window, existing.isVisible, openedAsAdmin == isAdmin {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()
        openedAsAdmin = isAdmin
        let content = NSHostingView(rootView: POSGuideView(isAdmin: isAdmin))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Guia do POS"
        win.contentView = content
        win.minSize = NSSize(width: 720, height: 500)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }
}
#endif

// MARK: - Vista principal do Guia

struct POSGuideView: View {
    /// Perfil de quem está autenticado. O Caixa só vê os capítulos do que tem
    /// na app; o guia não é sítio para descrever ecrãs a que não chega.
    var isAdmin: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: POSGuideChapter? = .overview
    @State private var search = ""

    var currentChapter: POSGuideChapter { selected ?? .overview }

    /// Capítulos por grupo, já filtrados pelo perfil e pela pesquisa.
    private var groups: [(group: POSGuideGroup, chapters: [POSGuideChapter])] {
        POSGuideGroup.allCases.compactMap { group in
            let chapters = group.chapters.filter { (isAdmin || !$0.isAdminOnly) && $0.matches(search) }
            return chapters.isEmpty ? nil : (group, chapters)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            GuideSearchField(text: $search)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List(selection: $selected) {
                ForEach(groups, id: \.group) { entry in
                    Section {
                        ForEach(entry.chapters) { chapter in
                            HStack(spacing: 10) {
                                Image(systemName: chapter.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(chapter.color)
                                    .frame(width: 24, height: 24)
                                    .background(chapter.color.opacity(0.14), in: .rect(cornerRadius: 7))
                                Text(chapter.title)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.vertical, 2)
                            .tag(chapter)
                        }
                    } header: {
                        Text(entry.group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.7)
                    }
                }

                if groups.isEmpty {
                    Text("Sem capítulos para “\(search)”.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: search)
        }
        .navigationTitle("Guia POS")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    // MARK: - Detalhe

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                currentChapter.content(isAdmin: isAdmin)

                Spacer(minLength: 40)
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.22),
            value: currentChapter
        )
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button("Fechar") { dismiss() }
            }
            #else
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fechar") { dismiss() }
            }
            #endif
        }
    }

    /// Cabeçalho do capítulo: um único plano de vidro sobre o gradiente da cor
    /// do capítulo (nunca vidro sobre vidro).
    private var hero: some View {
        HStack(spacing: 16) {
            Image(systemName: currentChapter.icon)
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(currentChapter.color.gradient, in: .rect(cornerRadius: 14))
                .shadow(color: currentChapter.color.opacity(0.3), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(currentChapter.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(currentChapter.subtitle(isAdmin: isAdmin))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [currentChapter.color.opacity(0.26), currentChapter.color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Campo de pesquisa do Guia

struct GuideSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Procurar capítulo…", text: $text)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar pesquisa")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 9))
    }
}

// MARK: - Grupos da sidebar

enum POSGuideGroup: String, CaseIterable, Identifiable, Hashable {
    case start, daily, management, extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:      return "COMEÇAR"
        case .daily:      return "OPERAÇÃO DIÁRIA"
        case .management: return "GESTÃO"
        case .extras:     return "EXTRAS"
        }
    }

    var chapters: [POSGuideChapter] {
        switch self {
        case .start:      return [.overview, .shortcuts]
        case .daily:      return [.sales, .payments, .dayClose]
        case .management: return [.products, .batches, .reports, .settings]
        case .extras:     return [.proximity]
        }
    }
}

// MARK: - Capítulos

enum POSGuideChapter: String, CaseIterable, Identifiable, Hashable {
    case overview, sales, payments, dayClose, products, batches, reports, settings, shortcuts, proximity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:  return "Visão Geral"
        case .sales:     return "Vendas"
        case .payments:  return "Pagamentos"
        case .dayClose:  return "Fecho de Caixa"
        case .products:  return "Produtos"
        case .batches:   return "Lotes e Validades"
        case .reports:   return "Relatórios"
        case .settings:  return "Definições"
        case .shortcuts: return "Atalhos"
        case .proximity: return "Partilha iOS"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:  return "Como funciona o sistema POS"
        case .sales:     return "Processar vendas e gerir o carrinho"
        case .payments:  return "Métodos de pagamento e pagamentos mistos"
        case .dayClose:  return "Fecho do dia, do mês, do ano e exportação"
        case .products:  return "Catálogo, categorias, preços e stock baixo"
        case .batches:   return "Lotes, FIFO, validades e cálculo de perdas"
        case .reports:   return "Diário, mensal, anual e histórico pesquisável"
        case .settings:  return "Utilizadores em wizard, perfis e subscrição"
        case .shortcuts: return "Atalhos de teclado para trabalhar mais rápido"
        case .proximity: return "Enviar stock baixo para app iOS por proximidade"
        }
    }

    var icon: String {
        switch self {
        case .overview:  return "square.grid.2x2"
        case .sales:     return "cart"
        case .payments:  return "creditcard.and.123"
        case .dayClose:  return "lock.circle"
        case .products:  return "cube.box"
        case .batches:   return "calendar.badge.exclamationmark"
        case .reports:   return "chart.bar"
        case .settings:  return "gearshape"
        case .shortcuts: return "keyboard"
        case .proximity: return "iphone.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .overview:  return .blue
        case .sales:     return .green
        case .payments:  return .cyan
        case .dayClose:  return .indigo
        case .products:  return .orange
        case .batches:   return .red
        case .reports:   return .purple
        case .settings:  return .gray
        case .shortcuts: return .pink
        case .proximity: return .mint
        }
    }

    /// Palavras-chave extra para a pesquisa da sidebar.
    var keywords: String {
        switch self {
        case .overview:  return "início arquitectura fluxo"
        case .sales:     return "carrinho cliente nif recibo scanner código de barras"
        case .payments:  return "numerário cartão transferência mpesa emola troco"
        case .dayClose:  return "fecho dia mês ano sessão excel pdf histórico"
        case .products:  return "catálogo categorias preço iva margem stock baixo encomenda csv"
        case .batches:   return "lote fifo validade expirado perda risco alerta"
        case .reports:   return "relatório diário mensal anual histórico pesquisa exportar"
        case .settings:  return "utilizadores wizard admin caixa password subscrição trial"
        case .shortcuts: return "teclado comandos"
        case .proximity: return "bonjour rede local iphone ipad enviar"
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q)
            || subtitle.lowercased().contains(q)
            || keywords.contains(q)
    }

    /// Capítulos de ecrãs que só o Admin tem. O Caixa não os vê no guia.
    var isAdminOnly: Bool {
        switch self {
        case .products, .batches, .reports, .settings, .proximity: return true
        case .overview, .sales, .payments, .dayClose, .shortcuts:  return false
        }
    }

    /// Subtítulo do capítulo tal como o perfil o vê.
    func subtitle(isAdmin: Bool) -> String {
        switch self {
        case .dayClose where !isAdmin:  return "Fechar a tua caixa no fim do turno"
        case .overview where !isAdmin:  return "Como funciona o teu dia de trabalho"
        default:                        return subtitle
        }
    }

    @ViewBuilder
    func content(isAdmin: Bool) -> some View {
        switch self {
        case .overview:  POSOverviewChapter(isAdmin: isAdmin)
        case .sales:     POSSalesChapter()
        case .payments:  POSPaymentsChapter()
        case .dayClose:  POSDayCloseChapter(isAdmin: isAdmin)
        case .products:  POSProductsChapter()
        case .batches:   POSBatchesChapter()
        case .reports:   POSReportsChapter()
        case .settings:  POSSettingsChapter()
        case .shortcuts: POSShortcutsChapter(isAdmin: isAdmin)
        case .proximity: POSProximityChapter()
        }
    }
}

// MARK: - Capítulo: Visão Geral

struct POSOverviewChapter: View {
    /// O Caixa só vê os blocos dos ecrãs que tem: Vendas, Pagamentos e a sua caixa.
    var isAdmin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O **Sales POS** é um sistema de ponto de venda desenhado para ser rápido, simples e completo — funciona em Mac e iPad com a mesma base de dados local.")

            POSFlowDiagram()

            POSInfoBlock(icon: "cart.fill", color: .green,
                title: "Vendas",
                bodyText: "Processa vendas, adiciona produtos ao carrinho, preenche dados do cliente e finaliza com pagamento. O recibo é gerado automaticamente e o stock é descontado por lote (FIFO).")

            POSInfoBlock(icon: "creditcard.and.123", color: .cyan,
                title: "Pagamentos",
                bodyText: "Aceita Numerário, Cartão, Transferência Bancária, M-Pesa e e-Mola. Permite combinar vários métodos na mesma venda.")

            if isAdmin {
                POSInfoBlock(icon: "lock.circle.fill", color: .indigo,
                    title: "Fecho de Caixa",
                    bodyText: "Fecho do dia, do mês e do ano, com resumo por método de pagamento e exportação em Excel ou PDF. Suporta várias sessões no mesmo dia.")

                POSInfoBlock(icon: "cube.box.fill", color: .orange,
                    title: "Produtos e Categorias",
                    bodyText: "Cria o catálogo, organiza por categorias com cor e ícone, define preço base, margem, IVA e stock. O preço final é calculado automaticamente.")

                POSInfoBlock(icon: "calendar.badge.exclamationmark", color: .red,
                    title: "Lotes e Validades",
                    bodyText: "Cada entrada de stock é um lote com data de validade. No arranque, a app mostra os lotes fora de prazo ou em risco e calcula a perda real.")

                POSInfoBlock(icon: "chart.bar.fill", color: .purple,
                    title: "Relatórios",
                    bodyText: "Diário, mensal e anual, com cards de total, número de vendas, itens e produto mais vendido. O histórico guarda os ficheiros exportados e é pesquisável por dia, mês ou ano.")

                POSNote("O acesso a certas funcionalidades depende do perfil: o Administrador tem acesso total; o Caixa processa vendas e fecha a sua própria caixa.")
            } else {
                POSInfoBlock(icon: "lock.circle.fill", color: .indigo,
                    title: "Fecho de Caixa",
                    bodyText: "No fim do turno fechas a **tua** caixa: o ecrã mostra as tuas vendas do dia, o total e o valor por método de pagamento.")

                POSNote("Como Caixa tens **Vendas** e **Fecho de Caixa**. Catálogo, lotes, relatórios e definições são do Administrador — por isso não aparecem aqui.")
            }
        }
    }
}

struct POSFlowDiagram: View {
    var body: some View {
        HStack(spacing: 0) {
            POSDiagramBox(icon: "person.fill",        label: "Login",      color: .blue)
            POSArrow()
            POSDiagramBox(icon: "cart.fill",           label: "Venda",      color: .green)
            POSArrow()
            POSDiagramBox(icon: "creditcard.and.123",  label: "Pagamento",  color: .cyan)
            POSArrow()
            POSDiagramBox(icon: "doc.text.fill",       label: "Recibo",     color: .teal)
            POSArrow()
            POSDiagramBox(icon: "lock.circle.fill",    label: "Fecho",      color: .indigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

struct POSDiagramBox: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

struct POSArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Capítulo: Vendas

struct POSSalesChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O ecrã de vendas divide-se em dois painéis: o **catálogo de produtos** à esquerda e o **carrinho** à direita. O fluxo é: adicionar produtos → dados do cliente → pagar → recibo.")

            POSStepSection(title: "Iniciar uma Venda", color: .green, steps: [
                "Vai ao separador **Vendas** na barra de navegação.",
                "Usa a barra de pesquisa no topo para encontrar o produto por nome ou código de barras.",
                "Filtra por **categoria** nos chips coloridos por baixo da pesquisa.",
                "Ajusta a **quantidade** com o Stepper junto ao produto antes de adicionar.",
                "Clica no botão **+** (verde) para adicionar ao carrinho.",
            ])

            POSStepSection(title: "Dados do Cliente (opcional)", color: .teal, steps: [
                "No topo do carrinho, preenche **Nome do Cliente** e **NIF** — ambos opcionais.",
                "Estes dados aparecem no recibo e ficam associados à venda no histórico.",
                "Nos relatórios, as vendas do mesmo cliente aparecem agrupadas no mesmo card.",
                "Vendas sem preenchimento ficam registadas como anónimas.",
            ])

            POSStepSection(title: "Finalizar e Pagar", color: .cyan, steps: [
                "Quando o carrinho estiver completo, clica no botão **\"Pagar\"**.",
                "Abre-se a janela de pagamento — selecciona o método e introduz o valor.",
                "Após confirmar, o recibo é gerado automaticamente.",
                "O stock é descontado do **lote mais antigo primeiro** (FIFO).",
            ])

            POSInfoBlock(icon: "arrow.uturn.backward.circle.fill", color: .red,
                title: "Limpar ou Remover Itens",
                bodyText: "Usa o botão \"Limpar\" para esvaziar o carrinho completo (pede confirmação), ou o ícone de lixo em cada item para remover individualmente.")

            POSStepSection(title: "Usar o Scanner de Código de Barras", color: .red, steps: [
                "Na barra de pesquisa das **Vendas**, toca no ícone **camera.viewfinder** à direita.",
                "Aponta a câmara para o código de barras do produto.",
                "Se o código corresponder a um produto registado, é adicionado automaticamente ao carrinho com quantidade 1.",
                "Se não houver correspondência exacta, o campo de pesquisa é preenchido com o código lido e a lista filtra os resultados parciais.",
            ])

            POSNote("Leitores externos USB ou Bluetooth também funcionam — basta ter o cursor no campo de pesquisa antes de ler o código.")

            POSWarning("Uma venda finalizada não pode ser editada. Se houve erro, o registo fica no histórico como referência mas não é possível reverter o stock automaticamente.")
        }
    }
}

// MARK: - Capítulo: Pagamentos

struct POSPaymentsChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O sistema suporta **5 métodos de pagamento** e permite combiná-los livremente na mesma venda. A janela de pagamento abre ao clicar em **\"Pagar\"** no carrinho.")

            POSPaymentMethodsGrid()

            POSStepSection(title: "Pagamento Simples", color: .green, steps: [
                "Clica em **\"Pagar\"** no carrinho.",
                "Selecciona o método desejado (ex: Numerário).",
                "O campo de valor preenche automaticamente com o total em falta.",
                "Clica **\"Adicionar\"** e depois **\"Confirmar Venda\"**.",
            ])

            POSStepSection(title: "Pagamento Misto (vários métodos)", color: .cyan, steps: [
                "Clica em **\"Pagar\"** no carrinho.",
                "Selecciona o primeiro método e introduz o valor parcial.",
                "Clica **\"Adicionar\"** — o restante é calculado automaticamente.",
                "Selecciona o segundo método — o campo preenche com o valor em falta.",
                "Repete até o total estar coberto.",
                "O botão **\"Confirmar Venda\"** fica activo assim que o valor pago ≥ total.",
            ])

            POSInfoBlock(icon: "phone.fill", color: .red,
                title: "M-Pesa",
                bodyText: "Ao seleccionar M-Pesa, é obrigatório introduzir a referência / número de transacção. A venda não pode ser confirmada sem este campo preenchido.")

            POSInfoBlock(icon: "phone.badge.waveform.fill", color: .orange,
                title: "e-Mola",
                bodyText: "Igual ao M-Pesa — a referência da transacção é obrigatória. Guarda sempre o comprovativo do cliente.")

            POSInfoBlock(icon: "banknote", color: .green,
                title: "Troco Automático",
                bodyText: "Se o valor pago em Numerário for superior ao total, o sistema calcula e mostra o troco a devolver ao cliente.")

            POSNote("Podes remover um pagamento adicionado por engano clicando no ✕ à direita de cada linha antes de confirmar.")

            POSWarning("Todos os pagamentos ficam registados na base de dados associados à venda. O fecho de caixa usa estes dados para calcular os totais por método de pagamento.")
        }
    }
}

struct POSPaymentMethodsGrid: View {
    let methods: [(String, String, Color)] = [
        ("banknote",                "Numerário",        .green),
        ("creditcard",              "Cartão",           .blue),
        ("building.columns",        "Transf. Bancária", .purple),
        ("phone.fill",              "M-Pesa",           .red),
        ("phone.badge.waveform.fill","e-Mola",          .orange),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Métodos de Pagamento Disponíveis")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(methods, id: \.1) { method in
                    HStack(spacing: 10) {
                        Image(systemName: method.0)
                            .font(.title3)
                            .foregroundStyle(method.2)
                            .frame(width: 36, height: 36)
                            .background(method.2.opacity(0.12), in: .rect(cornerRadius: 8))
                        Text(method.1)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(method.2.opacity(0.06), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(method.2.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }
}

// MARK: - Capítulo: Fecho de Caixa

struct POSDayCloseChapter: View {
    var isAdmin: Bool = false

    var body: some View {
        if isAdmin { adminBody } else { cashierBody }
    }

    /// O que o Caixa tem: a secção **Caixas** com a sua própria caixa.
    private var cashierBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("No separador **Fecho de Caixa** vês a **tua** caixa do dia: número de vendas, total e o valor recebido por cada método de pagamento.")

            POSStepSection(title: "Fechar a tua caixa", color: .indigo, steps: [
                "Abre o separador **Fecho de Caixa**.",
                "Confirma a data no canto superior direito — por omissão é hoje.",
                "Confere **Vendas**, **Total** e os valores por método no teu cartão.",
                "Se quiseres, escreve algo no campo **Notas do fecho**.",
                "Clica em **\"Fechar a minha caixa\"**.",
                "O cartão passa a **Fechada**, com a hora do fecho.",
            ])

            POSStepSection(title: "Vendeste depois de fechar?", color: .orange, steps: [
                "O botão passa a **\"Actualizar o meu fecho\"**.",
                "Ao actualizar, o fecho fica com **todas** as vendas do dia.",
                "O registo é actualizado, não duplicado.",
            ])

            POSNote("Só o Administrador reabre uma caixa fechada e faz o fecho da loja (dia, mês e ano). O teu fecho é o da tua caixa.")

            POSWarning("Faz o fecho antes de terminar o turno. Se saíres com vendas por fechar, a app avisa no arranque seguinte.")
        }
    }

    private var adminBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O **Fecho de Caixa** está no separador **\"Fecho\"** e tem quatro secções: **Dia**, **Mês**, **Ano** e **Histórico**. Cada uma resume as vendas por método de pagamento e exporta em Excel ou PDF.")

            POSWarning("Se terminares o dia com vendas e sem fecho feito, o sistema mostra um alerta automático ao abrir a aplicação. Faz sempre o fecho antes de terminar a sessão.")

            POSInfoBlock(icon: "lock.circle.fill", color: .indigo,
                title: "Fecho do Dia",
                bodyText: "Resume as vendas de um dia, agrupadas por método de pagamento, e permite adicionar notas. É o único fecho que fica registado na base de dados e aparece no Histórico.")

            POSInfoBlock(icon: "lock.rectangle.stack.fill", color: .purple,
                title: "Fecho do Mês",
                bodyText: "Agrega todas as vendas do mês seleccionado, com total por método e gráfico animado de distribuição. Serve para conferência e exportação — não substitui os fechos diários.")

            POSInfoBlock(icon: "lock.square.stack.fill", color: .orange,
                title: "Fecho do Ano",
                bodyText: "Mesma leitura, mas do ano inteiro: escolhe o ano no menu do topo e obténs o total do ano, a distribuição por método e a exportação anual em Excel ou PDF.")

            POSInfoBlock(icon: "clock.arrow.circlepath", color: .teal,
                title: "Histórico de Fechos",
                bodyText: "Lista os fechos diários já registados com data, hora, total e número de vendas.")

            POSStepSection(title: "Como Fazer o Fecho do Dia", color: .indigo, steps: [
                "Vai ao separador **\"Fecho\"** e à secção **Dia**.",
                "Confirma que a data está correcta — por defeito é o dia de hoje.",
                "Verifica o resumo por método de pagamento.",
                "Opcionalmente, adiciona notas no campo **\"Notas\"**.",
                "Clica **\"Fazer Fecho do Dia\"** e confirma o diálogo.",
                "O fecho fica registado e o indicador verde aparece.",
            ])

            POSStepSection(title: "Nova Sessão — Fecho após Vendas Adicionais", color: .orange, steps: [
                "Se fizeres vendas depois de um fecho já efectuado, o sistema detecta automaticamente.",
                "O badge muda para laranja: **\"Existem vendas após o último fecho\"**.",
                "O botão passa a **\"Actualizar Fecho do Dia\"**.",
                "Ao actualizar, o fecho é recalculado com **todas** as vendas do dia — incluindo as novas.",
                "Não perdes dados — o registo do dia é actualizado, não duplicado.",
            ])

            POSStepSection(title: "Fecho do Ano, passo a passo", color: .orange, steps: [
                "No separador **\"Fecho\"**, escolhe a secção **Ano**.",
                "Selecciona o ano no menu ao lado do título (ano corrente e os 9 anteriores).",
                "Confere o total geral, o valor por método e o gráfico de distribuição.",
                "Exporta em **Excel** ou **PDF** e usa **\"Partilhar ficheiro exportado\"**.",
            ])

            POSStepSection(title: "Exportar em Excel", color: .green, steps: [
                "Em qualquer secção de fecho, clica no botão **\"Excel\"**.",
                "É gerado um ficheiro CSV compatível com Excel e Numbers.",
                "O ficheiro inclui o resumo por método de pagamento e o detalhe de cada venda.",
                "Clica em **\"Partilhar ficheiro exportado\"** para guardar ou enviar.",
            ])

            POSStepSection(title: "Exportar em PDF", color: .red, steps: [
                "Em qualquer secção de fecho, clica no botão **\"PDF\"**.",
                "É gerado um PDF formatado com resumo e tabela de vendas.",
                "Clica em **\"Partilhar ficheiro exportado\"** para guardar, imprimir ou enviar.",
            ])

            POSNote("Os ficheiros exportados ficam disponíveis para partilha imediata via AirDrop, email ou qualquer app do sistema.")
            POSNote("Só o Administrador pode fazer o fecho de caixa e exportar.")
        }
    }
}

// MARK: - Capítulo: Produtos

struct POSProductsChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O separador **Produtos** reúne o catálogo, o filtro por categoria, o painel de perdas por validade e o acesso ao **Stock Baixo**.")

            POSStepSection(title: "Adicionar Produto", color: .orange, steps: [
                "Vai ao separador **Produtos**.",
                "Clica no botão **\"+\"** na barra de ferramentas.",
                "Preenche: Nome, Preço Base, IVA, Margem de Lucro e Stock inicial.",
                "Escolhe a **categoria** do produto (opcional, mas recomendado).",
                "Opcionalmente, adiciona um **Código de Barras** — manualmente ou com o scanner.",
                "O stock inicial é registado como o **primeiro lote**, com data de validade opcional.",
                "Clica **\"Guardar\"** para adicionar ao catálogo.",
            ])

            POSInfoBlock(icon: "percent", color: .blue,
                title: "Cálculo Automático de Preços",
                bodyText: "O preço final é calculado em tempo real: Preço Base → aplica Margem de Lucro → aplica IVA. O formulário mostra o resumo de cada componente enquanto editas.")

            POSStepSection(title: "Categorias", color: .purple, steps: [
                "Na barra de ferramentas dos Produtos, clica em **\"Categorias\"** (ícone de etiqueta).",
                "Cria categorias com **nome, ícone e cor** — a cor é usada nos chips do catálogo e das vendas.",
                "Cada categoria mostra quantos produtos tem antes de a apagares.",
                "Ao apagar uma categoria, os produtos dela ficam **sem categoria** — não são apagados.",
                "No catálogo, os chips coloridos por cima da lista filtram por categoria.",
            ])

            POSStepSection(title: "Editar Produto", color: .blue, steps: [
                "Na lista de produtos, clica no produto a editar.",
                "Altera os campos pretendidos, incluindo categoria e código de barras.",
                "Na secção de lotes vês o stock total e cada lote com a respectiva validade.",
                "Clica **\"Guardar\"** — as alterações ficam imediatamente visíveis nas vendas.",
            ])

            POSStepSection(title: "Stock Baixo e Encomendas", color: .red, steps: [
                "Produtos com **stock ≤ 10** activam a faixa laranja no topo da lista.",
                "Clica na faixa (ou em **\"Gerir stock\"**) para abrir o painel **Stock Baixo**.",
                "Define a quantidade a encomendar por produto e corrige o stock actual quando necessário.",
                "Exporta a **lista de encomenda** ou envia-a para a app iOS por proximidade.",
                "Ao receber a mercadoria, podes **importar o CSV** para actualizar o stock em bloco.",
            ])

            POSStepSection(title: "Associar Código de Barras a um Produto", color: .red, steps: [
                "No formulário do produto, localiza o campo **\"Código de Barras\"**.",
                "Escreve o código manualmente...",
                "...ou toca no ícone **camera.viewfinder** à direita do campo para abrir o scanner.",
                "Aponta a câmara — o código é lido automaticamente e o scanner fecha.",
                "Clica **\"Guardar\"** para confirmar a associação.",
            ])

            POSInfoBlock(icon: "barcode.viewfinder", color: .red,
                title: "Formatos Suportados",
                bodyText: "EAN-8, EAN-13, UPC-E, Code 128, Code 39, QR Code, PDF417 e Interleaved 2 of 5. Leitores externos USB ou Bluetooth também funcionam — basta que escrevam o código no campo de texto.")

            POSWarning("Apagar um produto é permanente. Produtos com vendas associadas ficam no histórico mas deixam de aparecer no catálogo.")
            POSNote("Cada código de barras é único. Não é possível guardar dois produtos com o mesmo código.")
        }
    }
}

// MARK: - Capítulo: Lotes e Validades

struct POSBatchesChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("Cada entrada de stock é um **lote**: quantidade, preço base e data de validade. As vendas consomem sempre o **lote mais antigo primeiro (FIFO)**, e as validades alimentam os alertas e o cálculo de perdas.")

            POSInfoBlock(icon: "arrow.down.to.line", color: .green,
                title: "FIFO — primeiro a entrar, primeiro a sair",
                bodyText: "Ao finalizar uma venda, a quantidade é retirada do lote com validade mais próxima. Se um lote não chega, o restante sai do lote seguinte.")

            POSStepSection(title: "Registar um Lote Novo", color: .orange, steps: [
                "Abre o produto no separador **Produtos**.",
                "Na secção de lotes, adiciona a **quantidade recebida**, o **preço base** desse lote e a **validade**.",
                "O stock do produto passa a ser a soma dos lotes.",
                "Lotes sem validade nunca entram nos alertas.",
            ])

            POSInfoBlock(icon: "exclamationmark.triangle.fill", color: .red,
                title: "Faixas de Validade",
                bodyText: "Expirado, dias (≤ 30), um mês, dois meses, três meses e seguro. Cada faixa tem cor e ícone próprios — a cor nunca aparece sozinha, há sempre texto ou número.")

            POSStepSection(title: "Alerta de Validade no Arranque", color: .red, steps: [
                "Ao abrir a app, se houver lotes fora de prazo ou em risco, aparece o ecrã **\"Validades\"**.",
                "Os lotes vêm agrupados por faixa, da mais grave para a menos grave.",
                "No topo vês a **perda real** (lotes já expirados) e o **valor em risco**.",
                "**\"Ver produtos\"** leva-te ao catálogo; **\"Dispensar hoje\"** esconde o alerta até ao dia seguinte.",
            ])

            POSInfoBlock(icon: "number.circle.fill", color: .orange,
                title: "Badge no separador Produtos",
                bodyText: "O número junto a \"Produtos\" conta os lotes fora de prazo ou em risco. Desaparece quando não há nada a assinalar.")

            POSNote("As perdas são calculadas com o preço base de cada lote — não com o preço de venda — para reflectirem o custo real da mercadoria.")
        }
    }
}

// MARK: - Capítulo: Relatórios

struct POSReportsChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("Os Relatórios estão no separador **\"Relatórios\"** e dividem-se em quatro secções: **Diário**, **Mensal**, **Anual** e **Histórico**.")

            POSInfoBlock(icon: "calendar.day.timeline.left", color: .blue,
                title: "Relatório Diário",
                bodyText: "Vendas de um dia: total facturado, número de vendas, itens vendidos, produto mais vendido e a lista das vendas agrupadas por cliente.")

            POSInfoBlock(icon: "calendar", color: .purple,
                title: "Relatório Mensal",
                bodyText: "Mesma leitura, para o mês escolhido, com a distribuição por dia do mês.")

            POSInfoBlock(icon: "chart.bar.xaxis", color: .orange,
                title: "Relatório Anual",
                bodyText: "Total facturado no ano, vendas, itens e a barra **Por Mês** com o peso de cada mês face ao mês mais forte.")

            POSStepSection(title: "Pesquisar dentro de um Relatório", color: .blue, steps: [
                "No cabeçalho da lista de vendas há um campo de pesquisa por **data ou hora**.",
                "Escreve, por exemplo, `14:` para ver as vendas dessa hora.",
                "O contador de **registos** actualiza; os cards do topo mantêm o total do período.",
                "**Esc** limpa a pesquisa.",
            ])

            POSStepSection(title: "Exportar um Relatório", color: .green, steps: [
                "Usa o botão **\"Exportar\"** na barra de ferramentas da secção activa.",
                "Escolhe **CSV** (Excel/Numbers) ou **PDF**.",
                "No Mac o ficheiro é revelado no Finder; no iPad abre a folha de partilha.",
                "O ficheiro fica registado no **Histórico**.",
            ])

            POSStepSection(title: "Histórico de Relatórios", color: .teal, steps: [
                "Abre a secção **Histórico** dentro de Relatórios.",
                "Filtra por tipo: **Todos, Diários, Mensais ou Anuais**.",
                "Escolhe o âmbito da pesquisa: **Tudo, Dia, Mês ou Ano**.",
                "Selecciona a data (ou o ano) — os resultados aparecem por baixo, com o número de resultados.",
                "Um âmbito mais largo apanha o que está dentro dele: pesquisar por **Mês** mostra também os relatórios diários desse mês.",
                "Toca no ícone de partilha para enviar o ficheiro; desliza para apagar o registo e o ficheiro.",
            ])

            POSWarning("Apagar um relatório do histórico apaga o registo **e** o ficheiro em disco. Partilha ou guarda o ficheiro antes.")
            POSNote("Para o fecho de caixa e o resumo por método de pagamento, usa o separador **\"Fecho\"** — é dedicado a essa funcionalidade.")
        }
    }
}

// MARK: - Capítulo: Definições

struct POSSettingsChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("As **Definições** estão organizadas em cartões: **Sessão Actual**, **Subscrição**, **Utilizadores** (só Administrador) e **Aplicação**.")

            POSWarning("Utilizadores com perfil **Caixa** não têm acesso ao separador Definições.")

            POSInfoBlock(icon: "person.crop.circle", color: .blue,
                title: "Sessão Actual",
                bodyText: "Mostra quem está autenticado, o nome de utilizador e o perfil. Daqui terminas a sessão.")

            POSInfoBlock(icon: "creditcard.fill", color: .purple,
                title: "Subscrição",
                bodyText: "Estado da subscrição ou do trial de 15 dias, com os dias restantes e as acções de subscrever, reactivar ou cancelar.")

            POSInfoBlock(icon: "lock.shield.fill", color: .orange,
                title: "Perfis e Permissões",
                bodyText: "Administrador: acesso total — fecho de caixa, exportações, relatórios, definições e gestão de utilizadores. Caixa: processa vendas, gere produtos e consulta relatórios do dia.")

            POSStepSection(title: "Criar Utilizador — assistente em 4 passos", color: .green, steps: [
                "No cartão **Utilizadores**, clica em **\"Adicionar Utilizador\"**.",
                "**Passo 1 — Dados**: nome completo (mín. 2 caracteres) e nome de utilizador (mín. 3, sem espaços).",
                "**Passo 2 — Segurança**: password com pelo menos 6 caracteres e confirmação; a barra indica a força.",
                "**Passo 3 — Função**: escolhe **Caixa** ou **Administrador**.",
                "**Passo 4 — Revisão**: confere tudo e usa o lápis para voltar a um passo.",
                "Clica **\"Criar Utilizador\"** — o login fica activo de imediato.",
            ])

            POSStepSection(title: "Editar ou Remover Utilizador", color: .red, steps: [
                "Clica na linha do utilizador (ou no ícone de lápis) para abrir o assistente já preenchido.",
                "No passo **Segurança**, deixa a password em branco para a manter.",
                "Para remover, usa o ícone de lixo e confirma o diálogo.",
                "A tua própria conta não mostra o botão de apagar.",
            ])

            POSInfoBlock(icon: "key.fill", color: .indigo,
                title: "Passwords",
                bodyText: "As passwords são guardadas apenas em hash com salt — nunca em texto simples, nem em logs, nem em ficheiros exportados.")

            POSNote("O cartão **Aplicação** mostra a versão e o nome da base de dados, e abre a pasta onde o ficheiro está guardado.")
        }
    }
}

// MARK: - Capítulo: Atalhos

struct POSShortcutsChapter: View {
    var isAdmin: Bool = false

    /// Só os atalhos dos ecrãs que o perfil tem.
    private var groups: [(String, [(String, String)])] {
        guard isAdmin else {
            return [
                ("Navegação", [
                    ("Vendas",          "⌘ 1"),
                    ("Fecho de Caixa",  "⌘ 4"),
                ]),
                ("Vendas", [
                    ("Pesquisar produto",   "⌘ F"),
                    ("Ir para pagamento",   "⌘ ↩"),
                    ("Cancelar carrinho",   "⌘ ⌫"),
                ]),
                ("Geral", [
                    ("Abrir este Guia",     "⌘ ?"),
                    ("Logout",              "⌘ ⇧ Q"),
                ]),
            ]
        }
        return [
            ("Navegação", [
                ("Vendas",          "⌘ 1"),
                ("Produtos",        "⌘ 2"),
                ("Relatórios",      "⌘ 3"),
                ("Fecho de Caixa",  "⌘ 4"),
                ("Definições",      "⌘ 5"),
            ]),
            ("Vendas", [
                ("Pesquisar produto",   "⌘ F"),
                ("Ir para pagamento",   "⌘ ↩"),
                ("Cancelar carrinho",   "⌘ ⌫"),
            ]),
            ("Produtos", [
                ("Novo produto",        "⌘ ⇧ N"),
                ("Editar selecionado",  "⌘ E"),
                ("Apagar selecionado",  "⌘ ⌫"),
            ]),
            ("Geral", [
                ("Abrir este Guia",     "⌘ ?"),
                ("Definições",          "⌘ ,"),
                ("Logout",              "⌘ ⇧ Q"),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            POSGuideText("Atalhos disponíveis no **Mac**. No iPad usa gestos e botões no ecrã.")

            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.0.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    VStack(spacing: 0) {
                        ForEach(Array(group.1.enumerated()), id: \.0) { i, item in
                            HStack {
                                Text(item.0)
                                    .font(.callout)
                                Spacer()
                                Text(item.1)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            if i < group.1.count - 1 {
                                Divider().padding(.horizontal, 14)
                            }
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 11))
                }
            }
        }
    }
}

// MARK: - Componentes reutilizáveis

struct POSGuideText: View {
    let text: LocalizedStringKey
    init(_ text: String) { self.text = LocalizedStringKey(text) }
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct POSStepSection: View {
    let title: String
    let color: Color
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.0) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(color.gradient, in: .circle)
                        Text(LocalizedStringKey(step))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }
}

struct POSInfoBlock: View {
    let icon: String
    let color: Color
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(bodyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

struct POSWarning: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }
}

struct POSNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Capítulo: Partilha iOS via Proximidade

struct POSProximityChapter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            POSGuideText("O sistema permite **enviar a lista de stock baixo directamente para um iPhone ou iPad** na mesma rede local, sem necessidade de AirDrop, email ou cabo.")

            POSInfoBlock(icon: "iphone.radiowaves.left.and.right", color: .mint,
                title: "Como Funciona",
                bodyText: "A app iOS anuncia presença na rede local via Bonjour. O Mac ou iPad detecta automaticamente dispositivos prontos e envia os dados via conexão directa peer-to-peer.")

            POSStepSection(title: "Passo 1: Preparar o iOS", color: .green, steps: [
                "Abre a app **POS Stock Receiver** no iPhone ou iPad.",
                "A app anuncia automaticamente que está online e pronta.",
                "Verás o indicador verde **\"Online\"** no canto superior.",
                "Certifica-te que estás na **mesma rede Wi-Fi** que o Mac/iPad principal.",
            ])

            POSStepSection(title: "Passo 2: Enviar do Desktop", color: .purple, steps: [
                "No Mac ou iPad, vai a **Produtos → Stock Baixo**.",
                "Selecciona os produtos que queres enviar (ou deixa todos seleccionados).",
                "Clica no botão **\"Enviar para iOS\"**.",
                "Abre-se a janela de dispositivos detectados — aguarda alguns segundos.",
                "Selecciona o dispositivo iOS e confirma o código de emparelhamento.",
                "Os dados são enviados instantaneamente via rede local.",
            ])

            POSStepSection(title: "Passo 3: Receber no iOS", color: .blue, steps: [
                "A app iOS recebe os dados automaticamente.",
                "Feedback háptico confirma recepção.",
                "A lista de produtos aparece imediatamente no ecrã.",
                "Podes pesquisar, filtrar e consultar os produtos recebidos.",
                "Para exportar, clica em **\"Exportar Lista de Encomenda\"**.",
            ])

            POSInfoBlock(icon: "lock.shield.fill", color: .orange,
                title: "Segurança e Privacidade",
                bodyText: "A comunicação é local (peer-to-peer) — os dados nunca saem da tua rede. Usa Bonjour (mDNS) para descoberta e NWConnection para transferência via TCP.")

            POSInfoBlock(icon: "arrow.triangle.2.circlepath", color: .cyan,
                title: "Formato dos Dados",
                bodyText: "Os dados são enviados em JSON estruturado com: código de barras, nome, stock actual, quantidade a encomendar e preço base. Compatível com a importação de CSV no painel de Stock Baixo.")

            POSWarning("Os dispositivos têm de estar na mesma rede Wi-Fi ou ligados via Personal Hotspot. Não funciona através da internet ou redes diferentes.")

            POSNote("A app iOS pode exportar a lista recebida via AirDrop, email, copiar para clipboard ou partilhar com qualquer app compatível com ficheiros CSV.")

            POSStepSection(title: "Resolução de Problemas", color: .red, steps: [
                "**Dispositivo não aparece**: Verifica que ambos estão na mesma rede Wi-Fi.",
                "**Envio falha**: Fecha e abre novamente a app iOS, depois tenta outra vez.",
                "**iOS diz Offline**: Verifica permissões de rede local nas Definições do iOS.",
                "**Ligação lenta**: Aproxima os dispositivos ou melhora o sinal Wi-Fi.",
            ])
        }
    }
}

// MARK: - Preview

#Preview("Guia POS") {
    POSGuideView()
}

#Preview("Botão") {
    POSGuideButton()
        .padding()
}
