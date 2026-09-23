import Foundation
import Testing
@testable import POSApp

@Suite("Faixas de validade")
struct ExpiryStatusTests {

    /// Data a `days` dias de `now`, sempre ao início do dia.
    private func date(inDays days: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now))!
    }

    @Test("Uma data por faixa")
    func oneDatePerBand() {
        let now = Date()
        #expect(ExpiryStatus.from(expiryDate: date(inDays: -5, from: now), now: now) == .expired)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 10, from: now), now: now) == .days)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 45, from: now), now: now) == .oneMonth)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 75, from: now), now: now) == .twoMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 100, from: now), now: now) == .threeMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 200, from: now), now: now) == .safe)
    }

    @Test("Fronteiras 0, 30, 31, 60, 61, 90, 91, 120, 121")
    func boundaries() {
        let now = Date()
        #expect(ExpiryStatus.from(expiryDate: date(inDays: -1, from: now), now: now) == .expired)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 0, from: now), now: now) == .days)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 30, from: now), now: now) == .days)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 31, from: now), now: now) == .oneMonth)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 60, from: now), now: now) == .oneMonth)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 61, from: now), now: now) == .twoMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 90, from: now), now: now) == .twoMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 91, from: now), now: now) == .threeMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 120, from: now), now: now) == .threeMonths)
        #expect(ExpiryStatus.from(expiryDate: date(inDays: 121, from: now), now: now) == .safe)
    }

    @Test("Sem data de validade")
    func noExpiry() {
        #expect(ExpiryStatus.from(expiryDate: nil) == .none)
        #expect(ExpiryStatus.none.isAlerting == false)
        #expect(ExpiryStatus.safe.isAlerting == false)
        #expect(ExpiryStatus.expired.isAlerting)
    }

    @Test("Gravidade ordena da faixa pior para a melhor")
    func severityOrder() {
        let ordered = ExpiryStatus.allCases.sorted { $0.severity > $1.severity }
        #expect(ordered.first == .expired)
        #expect(ExpiryStatus.days.severity > ExpiryStatus.oneMonth.severity)
        #expect(ExpiryStatus.threeMonths.severity > ExpiryStatus.safe.severity)
    }

    @Test("Valor perdido usa o preço base do lote")
    func lostValue() {
        let batch = Batch(id: 1, productId: 1, quantity: 4, priceBase: 12.5, expiryDate: nil, receivedAt: Date())
        #expect(batch.lostValue == 50.0)
    }
}
