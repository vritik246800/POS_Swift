# Sales POS — Sales_Project

Sistema de ponto de venda (POS) nativo para **macOS + iOS**, escrito em **SwiftUI + AppKit**, com base de dados **SQLite3 nativa** (sem dependências externas). Interface em **Português (PT)**.

| | |
|---|---|
| **Plataformas** | macOS 26+ · iOS 26+ |
| **Linguagem** | Swift 5.9 · SwiftUI (+ AppKit onde necessário) |
| **Base de dados** | SQLite3 nativo (`libsqlite3`) |
| **Dependências externas** | Nenhuma |
| **Moeda** | MT (vendas) · € (relatórios/faturas) |
| **Design** | Liquid Glass (`.glassEffect()`, `GlassEffectContainer`) |

---

## Funcionalidades

- **Produtos** — CRUD num wizard de 2 passos (identificação → preços, stock e lote), com preço base, margem de lucro e IVA calculados automaticamente; código de barras com scanner; alertas de stock baixo. Em edição, os lotes do produto são geridos no próprio formulário.
- **Categorias** — CRUD completo na base de dados, com ícone SF Symbol e cor próprios; **ordem definida pelo utilizador arrastando as linhas** no gestor de categorias (gravada em `sort_order`); filtro por categoria em Produtos e Vendas.
- **Lotes e validade** — stock organizado por lotes (`Batches`) com data de validade e preço base; consumo **FIFO** na venda; faixas de validade em `ExpiryStatus` (expirado · dias · 1 · 2 · 3 meses). **Stock expirado não se vende**: só os lotes dentro do prazo contam para a venda e para o consumo FIFO.
- **Alertas de validade** — sheet no arranque e badge permanente na sidebar; a lista de produtos mostra badge do lote com problema de validade. O detalhe ("Perda real", "Em risco", "Stock baixo", com lotes, quantidades e valor por produto) vive em **Administração › Validade**.
- **Administração** — separador só de Admin, entre Fecho de Caixa e Definições: **Dashboard** de estatísticas da loja (receita, ticket médio, artigos vendidos, valor em stock, risco e perda, gráfico da receita em Swift Charts, métodos de pagamento, top de produtos e receita por categoria). O **período** manda em tudo o que está abaixo dos indicadores: **Hoje**, **Mês** e **Ano** são sempre do ano actual, e **Total** abre um filtro de **Ano · Mês · Dia** (mês só com ano escolhido, dia só com mês, dias reais de cada mês). A granularidade do gráfico segue o período — por hora num dia, por dia num mês, por mês num ano ou no histórico todo. O ecrã abre com o período no cabeçalho (dito uma só vez) e os seis indicadores numa **grelha de colunas iguais** (três, duas ou uma, conforme a largura — sem buracos na última linha) com a **receita em destaque**, com o **painel de gráfico** na coluna principal — um seletor troca entre **Receita** (evolução no tempo) e **Vendas por caixa** (barras com o valor e o nº de vendas de cada utilizador no período, de quem vendeu mais para quem vendeu menos) e o top de produtos, as categorias e os métodos de pagamento na coluna lateral — em ecrã estreito empilha tudo, **Validade**, **Parados**, e os históricos de **Fechos** e de **Relatórios**. Em **Validade**, "Em risco" está ordenado pelo prazo mais curto e diz quantos dias faltam; tocar num lote (em risco ou expirado) corrige a **quantidade e a data de validade**, e tocar num produto de "Stock baixo" **repõe o stock** sem sair do ecrã. As duas folhas de edição são em Liquid Glass tingido pelo estado (dias exactos até expirar, passo −/+ grande, delta face ao valor actual) e os indicadores de **Parados** levam a cor do próprio ícone no vidro.
- **Produtos parados** — produtos com stock sem venda há mais de 3/6/9/12 meses (nunca vendidos incluídos), com o capital imobilizado e a promoção à mão. No arranque, o Admin é alertado uma vez por dia.
- **Promoções** — um produto a aproximar-se do prazo mostra a acção "Promoção", e qualquer produto abre o **menu de contexto** (botão direito em macOS, toque longo em iOS) com promoção, edição e remoção; a app abre um painel que **desce de cima** para aplicar um desconto de 0 a 90% (só Admin, registado no `AuditLog`). O preço com promoção é o praticado na venda e aparece riscado sobre o preço antigo em Produtos e Vendas.
- **Vendas** — grelha de cards grandes (ícone da categoria, preço, badges de stock e validade, stepper), filtro simplificado em dois botões grandes de vidro (**Todos** / **Filtrar** — "Filtrar" revela as categorias lado a lado com animação), carrinho com **stepper −/+ por linha** (valida o stock dos lotes e remove a linha a zero), dados de cliente, múltiplos métodos de pagamento (dinheiro / cartão), produtos com todo o stock expirado bloqueados no carrinho, fatura em PDF e **impressão do talão em 80 mm ou A4** com escolha de impressora. Toda a venda corre numa transação SQL.
- **Fecho de caixa** — fecho do dia, do mês e do ano, com resumo por método de pagamento em cartões **Liquid Glass** (valores com contagem animada) à esquerda e gráfico de barras verticais que **cresce ao entrar na aba** ao lado: no dia as **Notas** ficam por baixo do gráfico, no mês e no ano o gráfico estica até ao fundo dos cartões. Exportação CSV/PDF (CSV com BOM UTF-8 e valores numéricos somáveis; PDF com cabeçalho de tabela repetido e páginas numeradas). Só o fecho diário fica registado (`DayCloses`) e o histórico passou para Administração. A secção **Caixas** mostra o fecho por utilizador (`CashierCloses`): o Admin vê todas as caixas do dia e fecha ou reabre as que faltarem; o perfil Caixa vê e fecha só a sua — e, se a caixa já tiver sido fechada (por ele ou pelo Admin), continua a poder **actualizar o seu fecho** para incluir vendas posteriores.
- **Relatórios** — diários, mensais e anuais, com totais e **top 50 de produtos mais vendidos** ao lado, gráficos de barras verticais que crescem ao entrar na aba (facturação, nº de vendas e itens vendidos), valores dos painéis com contagem animada, pesquisa, facturas em cards quadrados (com **reimpressão** em 80 mm/A4) e exportação CSV/PDF; revelar no Finder (macOS) ou partilhar (iOS). As secções trocam num picker segmentado, por isso só o botão "Exportar" da secção activa aparece na toolbar.
- **Histórico de relatórios** — painel de pesquisa à esquerda (**Tudo, Dia, Mês ou Ano**) e lista à direita; apagar remove o ficheiro **e** o registo em `Reports`.
- **Utilizadores** — dois perfis: Admin e Caixa. O perfil Caixa não tem Produtos, Relatórios, Administração nem Definições — vê Vendas e o fecho da sua própria caixa (barreira aplicada na camada de dados, não só na UI). Criação/edição num **wizard de 4 passos** (dados → segurança → função → revisão) com validação por passo e indicador de força da password. O primeiro arranque pede a criação do Admin (nunca há password fixa em código); passwords em PBKDF2.
- **Definições** — sessão, subscrição e, lado a lado quando há largura, **Utilizadores** e **Aplicação** (empilham em ecrã estreito).
- **Ecrã de login** — painel dividido em ecrã largo (marca à esquerda, cartão de vidro à direita) e coluna única em ecrã estreito ou iOS; fundo `MeshGradient` com deriva lenta e **um só plano de Liquid Glass** (o cartão). A app abre com entrada escalonada, a recusa abana o ecrã inteiro com clarão vermelho e devolve o foco à password, e o login aceite troca para o painel com animação. Entrada validada no ViewModel antes de tocar na base de dados (campos vazios, comprimento e caracteres de controlo). Respeita `Reduce Motion`.
- **Nome do programa** — editável em Definições → Aplicação; o nome escolhido aparece no login, no título da janela, nos talões, nas facturas e no cabeçalho dos relatórios e fechos, sem reiniciar a app.
- **Guia integrado** — janela própria (macOS) ou sheet (iPad) com capítulos agrupados e pesquisáveis, **filtrados pelo perfil**: o Admin vê tudo (visão geral, vendas, pagamentos, fecho, produtos, lotes e validades, relatórios, definições, atalhos e partilha iOS); o Caixa vê só o que tem na app — visão geral, vendas, pagamentos, fecho da sua caixa e atalhos.
- **Subscrição** — StoreKit 2: paywall, período de teste (data no Keychain) e cancelamento.
- **Partilha por proximidade** — transferência de stock entre dispositivos via Bonjour (framework `Network`), com **TLS-PSK** derivada de um código de emparelhamento de 6 dígitos e confirmação explícita do utilizador.

---

## Estrutura do Projeto

```
Sales_Project/
├── README.md                     # Este ficheiro
├── .gitignore                    # BD, relatórios e artefactos do Xcode fora do repo
├── List-Storage-Info.plist       # NSBonjourServices (_posapp._tcp) + uso da rede local
├── Sales_Project.xcodeproj/
│
├── Sales_Project/                # Alvo principal (app)
│   ├── Sales_ProjectApp.swift    # Scene alternativa (@main comentado — o real é Views/POSAppApp.swift)
│   ├── ContentView.swift
│   └── Assets.xcassets/          # AppIcon, AccentColor
│
├── Models/                       # Structs Codable puras (sem SwiftUI)
│   ├── Product.swift
│   ├── Category.swift
│   ├── Batch.swift
│   ├── ExpiryStatus.swift        # Fonte única das faixas de validade
│   ├── Sale.swift
│   ├── SaleItem.swift
│   ├── Payment.swift
│   ├── DayClose.swift
│   ├── CashierClose.swift        # Fecho da caixa de um utilizador num dia
│   ├── Report.swift
│   └── User.swift
│
├── ViewModels/                   # Estado observável + regras de negócio
│   ├── AuthViewModel.swift
│   ├── ProductViewModel.swift
│   ├── CategoryViewModel.swift
│   ├── BatchViewModel.swift
│   ├── AdminViewModel.swift      # Dashboard, produtos parados, fecho por caixa
│   └── SaleViewModel.swift
│
├── Database/
│   └── DatabaseManager.swift     # Singleton SQLite3: schema, migrações, CRUD
│
├── Utils/
│   ├── AppTheme.swift            # Tokens de cor + componentes partilhados (CategoryChipView, AppEmptyStateView)
│   ├── CategoryIcons.swift       # Grelha de SF Symbols para escolher o ícone da categoria
│   ├── CSVField.swift            # csvField()/csvNumber()/csvBOM — CSV, definição única
│   └── Constants.swift           # appName configurável, moeda, IVA, nome da BD
│
├── Views/                        # Camada de apresentação
│   ├── MainView.swift            # Sidebar (macOS) / TabView (iOS)
│   ├── LoginView.swift           # Login + criação do primeiro Admin (painel dividido, Liquid Glass, animações)
│   ├── POSAppApp.swift           # @main real + RootView (troca animada paywall/login/painel)
│   ├── Posguideview.swift          # Guia: sidebar agrupada + pesquisa de capítulos
│   ├── Products/
│   │   ├── ProductListView.swift     # Lista + filtros + menu de contexto (promoção)
│   │   ├── ProductFormView.swift     # Wizard de 2 passos (identificação → preços/stock/lote)
│   │   ├── CategoryManagerView.swift # CRUD de categorias + reordenação por arrastar
│   │   ├── CategoryFormView.swift    # Nome + ícone + cor, com pré-visualização
│   │   ├── ExpiryAlertView.swift     # Sheet de validade no arranque
│   │   ├── LowStockView.swift
│   │   ├── BarcodeScannerView.swift
│   │   └── POSStockReceiverApp.swift
│   ├── Sales/
│   │   ├── SaleView.swift            # Grelha de cards + filtro por categoria
│   │   ├── ProductCardView.swift     # Card quadrado de produto com stepper
│   │   ├── PaymentView.swift         # Métodos, pagamento repartido, troco
│   │   ├── InvoiceView.swift         # Factura + partilhar PDF + imprimir
│   │   ├── PrintFormatSheet.swift    # Escolha 80 mm / A4 + painel de impressora
│   │   └── ReceiptPrintService.swift # Talão em PDF (80 mm/A4) e impressão
│   ├── Reports/
│   │   ├── DailyReportView.swift
│   │   ├── MonthlyReportView.swift
│   │   ├── AnnualReportView.swift    # Relatório anual + gráficos por mês
│   │   ├── ReportHistoryView.swift   # Histórico (vive em Administração)
│   │   ├── ReportComponents.swift    # Cards, top 50, gráficos verticais, export
│   │   ├── SaleReportRowView.swift   # Card de factura + detalhe + reimprimir
│   │   ├── ReportViewModel.swift
│   │   ├── ReportService.swift       # Exportação CSV/PDF
│   │   └── CloseExportService.swift
│   ├── Admin/
│   │   ├── AdminView.swift               # Contentor + componentes (KPI, painel, barras)
│   │   ├── AdminDashboardView.swift      # Estatísticas da loja (Swift Charts)
│   │   ├── AdminExpiryView.swift         # Perda real · em risco · stock baixo
│   │   ├── StaleProductsView.swift       # Produtos sem venda há 6+ meses
│   │   └── CashierCloseAdminView.swift   # Fecho por caixa (Admin e Caixa)
│   ├── DayClose/
│   │   └── DayCloseView.swift        # Caixas · fecho do dia · mês · ano
│   ├── Settings/
│   │   ├── SettingsView.swift        # Cartões de vidro: sessão, subscrição, utilizadores, app (nome do programa)
│   │   └── UserFormView.swift        # Wizard de 4 passos de utilizador
│   ├── Subscription/
│   │   ├── SubscriptionManager.swift # StoreKit 2
│   │   ├── TrialManager.swift
│   │   ├── PaywallView.swift
│   │   └── CancellationReason.swift
│   ├── POSProximityService.swift     # Network/Bonjour + TLS-PSK
│   ├── ProximityIntegrationExamples.swift
│   ├── POSProximityExamples.swift
│   ├── ReceivedProduct.swift
│   ├── LowStockExportService.swift
│   └── Info.plist.template · Info-iOS.plist.template · StoreKitConfig.storekit
│
├── List_Storage/                 # Alvo secundário: gestão de stock/lista
│   ├── POS_Sale_listApp.swift
│   ├── ContentView.swift
│   ├── Product.swift
│   ├── ProductRow.swift
│   ├── StockViewModel.swift
│   ├── ProximityManager.swift
│   ├── ProximityReceiverView.swift
│   ├── CSVManager.swift
│   ├── ShareSheet.swift
│   └── List_Storage-Bridging-Header.h
│
├── Sales_Project.xctestplan      # Testes sem paralelismo (BD é um singleton partilhado)
│
└── POSAppTests/
    ├── SQLInjectionTests.swift
    ├── PasswordHashTests.swift
    ├── AuthorizationTests.swift
    ├── TransactionTests.swift
    ├── CSVEscapingTests.swift
    ├── FilenameSanitizationTests.swift
    ├── ProximityPayloadTests.swift
    ├── ExpiryStatusTests.swift
    ├── FIFOTests.swift
    ├── ReportFilterTests.swift   # Filtro do histórico por dia/mês/ano
    ├── AdminStatsTests.swift     # Produtos parados (6 meses) + fecho por caixa
    ├── AdminDateFilterTests.swift # Filtro de data do Dashboard da Administração
    ├── AdminEditingTests.swift   # Edição de lote e reposição de stock (Administração)
    ├── CashierCloseFlowTests.swift # Caixa vê e fecha a sua própria caixa
    ├── CategoryReorderTests.swift
    └── ProximityTests.swift
```

---

## Arquitetura

**MVVM**, camadas estritamente separadas:

```
Views (SwiftUI/AppKit)  →  ViewModels (@Published / @Observable)  →  DatabaseManager (SQLite3)
                                                                          ↓
                                                                    Models (structs Codable)
```

- **Models** — structs puras, `Codable`. Nunca importam SwiftUI.
- **ViewModels** — estado observável e regras de negócio. Injetados como `@EnvironmentObject` a partir do ponto de entrada (`Views/POSAppApp.swift`).
- **DatabaseManager** — singleton. Fonte única de acesso a SQL: schema, migrações (`PRAGMA table_info`), CRUD e transações.
- **Views** — apresentação apenas. Sem SQL, sem lógica de negócio.

Base de dados em `ApplicationSupportDirectory/<dbName>`.

---

## Compilar e Correr

```bash
open Sales_Project.xcodeproj
# Escolher o esquema Sales_Project e o destino (My Mac ou simulador iOS)
```

Requer Xcode com SDKs macOS 26 / iOS 26 (necessário para as APIs Liquid Glass).
