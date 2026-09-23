import Foundation

/// Conjunto fixo de SF Symbols oferecidos ao escolher o ícone de uma categoria.
/// Não é um browser de todos os SF Symbols — é uma grelha curta e previsível.
enum CategoryIcons {

    /// Ícone usado quando nada foi escolhido (igual ao DEFAULT da coluna `icon`).
    static let fallback = "cube.box.fill"

    static let all: [String] = [
        // Alimentação
        "carrot.fill",
        "fork.knife",
        "birthday.cake.fill",
        "fish.fill",
        "leaf.fill",
        "basket.fill",
        "takeoutbag.and.cup.and.straw.fill",

        // Bebidas
        "cup.and.saucer.fill",
        "mug.fill",
        "wineglass.fill",
        "drop.fill",

        // Limpeza e higiene
        "bubbles.and.sparkles.fill",
        "sparkles",
        "hands.and.sparkles.fill",
        "shower.fill",
        "trash.fill",

        // Ferramentas e casa
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "screwdriver.fill",
        "paintbrush.fill",
        "gearshape.fill",
        "bolt.fill",
        "house.fill",
        "lightbulb.fill",

        // Papelaria
        "pencil.and.ruler.fill",
        "book.fill",
        "newspaper.fill",
        "paperclip",
        "scissors",

        // Saúde
        "pills.fill",
        "cross.case.fill",
        "bandage.fill",

        // Geral
        "tshirt.fill",
        "pawprint.fill",
        "gift.fill",
        "bag.fill",
        "cart.fill",
        "shippingbox.fill",
        "cube.box.fill",
        "tag.fill"
    ]
}
