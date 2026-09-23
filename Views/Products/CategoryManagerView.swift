import SwiftUI

// MARK: - Gestão de categorias
//
// O chip de categoria (`CategoryChipView`) vive em `Utils/AppTheme.swift` —
// é partilhado por esta vista, pela lista de produtos, pela grelha de vendas
// e pelo formulário de produto.
//
// A ordem das linhas é a ordem real das categorias em toda a app: arrastar
// grava `sort_order` na base de dados (`CategoryViewModel.move(from:to:)`).

struct CategoryManagerView: View {
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var productViewModel: ProductViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showForm = false
    @State private var categoryToEdit: Category? = nil
    @State private var categoryToDelete: Category? = nil
    @State private var showDeleteAlert = false
    /// Passa a `true` no primeiro `onAppear` — dá a animação de entrada da janela.
    @State private var appeared = false

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    private var openAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .background(AppTheme.accent.opacity(0.04))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .blur(radius: appeared ? 0 : 6)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 460, idealHeight: 560)
        #endif
        // Duas sheets separadas: `item:` garante que a categoria a editar não fica
        // desactualizada no momento da apresentação.
        .sheet(isPresented: $showForm) {
            CategoryFormView(mode: .create)
                .environmentObject(categoryViewModel)
        }
        .sheet(item: $categoryToEdit) { category in
            CategoryFormView(mode: .edit(category))
                .environmentObject(categoryViewModel)
        }
        .alert("Apagar categoria?", isPresented: $showDeleteAlert, presenting: categoryToDelete) { category in
            Button("Apagar", role: .destructive) { delete(category) }
            Button("Cancelar", role: .cancel) {}
        } message: { category in
            Text("Os \(categoryViewModel.productCount(inCategory: category.id)) produtos desta categoria ficam sem categoria.")
        }
        .onAppear {
            categoryViewModel.loadCategories()
            withAnimation(openAnimation) { appeared = true }
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "tag.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Categorias")
                    .font(.title2.weight(.bold))
                Text(categoryViewModel.categories.isEmpty
                     ? "Nenhuma categoria criada"
                     : "\(categoryViewModel.categories.count) categoria(s) · arrasta para reordenar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            #if os(iOS)
            EditButton()
                .buttonStyle(.glass)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Fundo opaco: nada da lista pode ler-se por baixo do cabeçalho.
        .background(.regularMaterial)
        .zIndex(1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        if categoryViewModel.categories.isEmpty {
            AppEmptyStateView(
                icon: "tag",
                title: "Sem categorias",
                subtitle: "Cria a primeira categoria com o botão «Nova categoria»."
            )
            .frame(maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            // Sem `GlassEffectContainer` à volta da lista: o container desenha o vidro
            // das linhas numa camada partilhada que não é recortada pelo scroll — era
            // o que fazia as linhas passarem por cima do cabeçalho e do rodapé.
            List {
                ForEach(categoryViewModel.categories) { category in
                    row(for: category)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    withAnimation(animation) {
                        _ = categoryViewModel.move(from: source, to: destination)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .clipped()
            .animation(animation, value: categoryViewModel.categories)
        }
    }

    // MARK: - Linha

    private func row(for category: Category) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.body.weight(.semibold))
                Text("\(categoryViewModel.productCount(inCategory: category.id)) produto(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            // Botão em vez de `onTapGesture` na linha inteira: um gesto de toque
            // sobre toda a linha consumia o arrasto e a reordenação deixava de
            // funcionar em macOS. Agora arrasta-se a linha e edita-se no lápis.
            Button { edit(category) } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Editar \(category.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityHint("Arraste para mudar a ordem.")
        .contextMenu {
            Button { edit(category) } label: { Label("Editar", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete(category) } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { confirmDelete(category) } label: {
                Label("Apagar", systemImage: "trash")
            }
            Button { edit(category) } label: { Label("Editar", systemImage: "pencil") }
                .tint(AppTheme.accent)
        }
        #endif
    }

    // MARK: - Rodapé

    private var footer: some View {
        VStack(spacing: 10) {
            if !categoryViewModel.errorMessage.isEmpty {
                Label(categoryViewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ExpiryStatus.expired.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Button("Fechar") { dismiss() }
                    .buttonStyle(.glass)

                Spacer(minLength: 0)

                Button {
                    showForm = true
                } label: {
                    Label("Nova categoria", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .zIndex(1)
        .animation(animation, value: categoryViewModel.errorMessage)
    }

    // MARK: - Acções

    private func edit(_ category: Category) {
        categoryToEdit = category
    }

    private func confirmDelete(_ category: Category) {
        categoryToDelete = category
        showDeleteAlert = true
    }

    private func delete(_ category: Category) {
        withAnimation(animation) {
            _ = categoryViewModel.delete(id: category.id)
        }
        // Os produtos afectados ficaram sem categoria — recarregar para a lista reflectir.
        productViewModel.loadProducts()
    }
}
