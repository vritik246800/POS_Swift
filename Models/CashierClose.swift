import Foundation

/// Fecho da caixa de **um** utilizador num dia. O `DayClose` é o fecho da loja
/// (agregado do dia); este é o fecho individual de cada caixa.
struct CashierClose: Identifiable, Hashable {
    let id: Int
    let date: String        // yyyy-MM-dd
    let userId: Int
    let totalSales: Double
    let totalCash: Double
    let totalCard: Double
    let totalBankTransfer: Double
    let totalMpesa: Double
    let totalEmola: Double
    let numSales: Int
    let notes: String
    let closedBy: Int
    let closedAt: Date

    var grandTotal: Double {
        totalCash + totalCard + totalBankTransfer + totalMpesa + totalEmola
    }

    /// O Admin fechou a caixa de outro utilizador.
    var closedByAdmin: Bool { closedBy != userId }
}
