import Foundation
import Testing
@testable import POSApp

@Suite("Filtro de data do Dashboard")
struct AdminDateFilterTests {

    private static let calendar = Calendar.current

    private static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f.date(from: iso)!
    }

    private static func sale(_ id: Int, _ iso: String, total: Double = 100) -> Sale {
        Sale(id: id, userId: 1, clientName: "", clientNIF: "", items: [],
             total: total, date: date(iso), status: .completed)
    }

    private static var sample: [Sale] {
        [
            sale(1, "2026-08-16 10:00"),
            sale(2, "2026-08-02 09:00"),
            sale(3, "2026-07-30 18:00"),
            sale(4, "2025-08-16 11:00")
        ]
    }

    // MARK: - Filtro

    @Test("Sem filtro devolve o histórico todo")
    func emptyFilter() {
        let out = AdminViewModel.apply(.init(), to: Self.sample, calendar: Self.calendar)
        #expect(out.count == 4)
    }

    @Test("Só ano apanha as vendas desse ano")
    func byYear() {
        let out = AdminViewModel.apply(.init(year: 2026), to: Self.sample, calendar: Self.calendar)
        #expect(out.map(\.id).sorted() == [1, 2, 3])
    }

    @Test("Ano e mês estreitam ao mês desse ano")
    func byYearAndMonth() {
        let out = AdminViewModel.apply(.init(year: 2026, month: 8), to: Self.sample, calendar: Self.calendar)
        #expect(out.map(\.id).sorted() == [1, 2])
    }

    @Test("Ano, mês e dia apanham só esse dia")
    func byDay() {
        let out = AdminViewModel.apply(.init(year: 2026, month: 8, day: 16),
                                       to: Self.sample, calendar: Self.calendar)
        #expect(out.map(\.id) == [1])
    }

    @Test("O mesmo mês de outro ano fica de fora")
    func yearIsolatesSameMonth() {
        let out = AdminViewModel.apply(.init(year: 2025, month: 8), to: Self.sample, calendar: Self.calendar)
        #expect(out.map(\.id) == [4])
    }

    // MARK: - Série

    @Test("Granularidade acompanha o período escolhido")
    func seriesGranularity() {
        let vm = AdminViewModel()
        #expect(vm.seriesUnit(for: .today) == .hour)
        #expect(vm.seriesUnit(for: .month) == .day)
        #expect(vm.seriesUnit(for: .year) == .month)
        #expect(vm.seriesUnit(for: .all) == .month)

        vm.filter = .init(year: 2026, month: 8)
        #expect(vm.seriesUnit(for: .all) == .day)
        vm.filter.day = 16
        #expect(vm.seriesUnit(for: .all) == .hour)
    }

    @Test("Mês filtrado dá um ponto por dia, com os dias sem vendas a zero")
    func seriesFillsEmptyBuckets() {
        let vm = AdminViewModel()
        vm.sales = Self.sample
        vm.filter = .init(year: 2026, month: 8)

        let series = vm.revenueSeries(in: .all)
        #expect(series.unit == .day)
        #expect(series.points.count == 31)
        #expect(series.total == 200)
        #expect(series.points.filter { $0.revenue > 0 }.count == 2)
    }

    @Test("Ano filtrado dá doze meses")
    func seriesYearHasTwelveMonths() {
        let vm = AdminViewModel()
        vm.sales = Self.sample
        vm.filter = .init(year: 2026)

        let series = vm.revenueSeries(in: .all)
        #expect(series.unit == .month)
        #expect(series.points.count == 12)
        #expect(series.total == 300)
    }

    @Test("Sem vendas no intervalo a série lê-se como vazia")
    func seriesEmpty() {
        let vm = AdminViewModel()
        vm.sales = Self.sample
        vm.filter = .init(year: 2026, month: 2)

        #expect(vm.revenueSeries(in: .all).isEmpty)
    }

    @Test("Anos disponíveis vêm do mais recente para o mais antigo")
    func years() {
        let vm = AdminViewModel()
        vm.sales = Self.sample
        #expect(vm.availableYears == [2026, 2025])
    }

    @Test("Dias do mês respeitam o calendário (Fevereiro de 2024 tem 29)")
    func daysInMonth() {
        let vm = AdminViewModel()
        vm.filter = .init(year: 2024, month: 2)
        #expect(vm.daysInSelectedMonth.count == 29)
        vm.filter = .init(year: 2026, month: 2)
        #expect(vm.daysInSelectedMonth.count == 28)
        vm.filter = .init(year: 2026)
        #expect(vm.daysInSelectedMonth.isEmpty)
    }
}
