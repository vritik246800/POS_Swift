import Foundation

struct DayClose: Identifiable {
    let id: Int
    let date: String
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
}
