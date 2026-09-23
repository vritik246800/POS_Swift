import SwiftUI

/// Criar ou editar uma categoria: nome, ícone, cor e pré-visualização ao vivo do chip.
struct CategoryFormView: View {
    enum Mode {
        case create
        case edit(Category)
    }

    let mode: Mode

    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var nameTouched = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _icon = State(initialValue: CategoryIcons.all.first ?? CategoryIcons.fallback)
            _colorHex = State(initialValue: AppTheme.categorySwatches.first ?? "5856D6")
        case .edit(let category):
            _name = State(initialValue: category.name)
            _icon = State(initialValue: category.icon)
            _colorHex = State(initialValue: category.colorHex)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    private var previewColor: Color { Color(hex: colorHex) }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview
                    nameField
                    iconPicker
                    colorPicker

                    if !categoryViewModel.errorMessage.isEmpty {
                        Label(categoryViewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ExpiryStatus.expired.color)
                            .transition(.opacity)
                    }
                }
                .padding(16)
            }
            .animation(animation, value: categoryViewModel.errorMessage)
            .navigationTitle(isEditing ? "Editar categoria" : "Nova categoria")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.glass)
                        .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520, idealHeight: 560)
        #endif
    }

    // MARK: - Pré-visualização ao vivo

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pré-visualização")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(previewColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(previewColor)
                }
                CategoryChipView(
                    name: trimmedName.isEmpty ? "Sem nome" : trimmedName,
                    icon: icon,
                    color: previewColor,
                    isSelected: true
                )
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .animation(animation, value: colorHex)
            .animation(animation, value: icon)
        }
    }

    // MARK: - Nome

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nome")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Ex.: Bebidas", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { nameTouched = true }

            if nameTouched && !canSave {
                Label("O nome da categoria não pode estar vazio.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ExpiryStatus.expired.color)
                    .transition(.opacity)
            }
        }
        .animation(animation, value: canSave)
    }

    // MARK: - Ícone

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ícone")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(CategoryIcons.all, id: \.self) { symbol in
                    Button {
                        withAnimation(animation) { icon = symbol }
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(symbol == icon ? previewColor : Color.secondary)
                            .background(previewColor.opacity(symbol == icon ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(previewColor.opacity(symbol == icon ? 0.9 : 0), lineWidth: 1.5)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Cor

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cor")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.categorySwatches, id: \.self) { hex in
                    Button {
                        withAnimation(animation) { colorHex = hex }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                            if hex == colorHex {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cor \(hex)")
                    .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Guardar

    private func save() {
        nameTouched = true
        guard canSave else { return }

        let ok: Bool
        switch mode {
        case .create:
            ok = categoryViewModel.create(name: trimmedName, icon: icon, colorHex: colorHex)
        case .edit(let category):
            var updated = category
            updated.name = trimmedName
            updated.icon = icon
            updated.colorHex = colorHex
            ok = categoryViewModel.update(updated)
        }
        if ok { dismiss() }
    }
}
