import Foundation

/// The day of the month in a day tile (`DayTile`): a payment's row, the Cash page's movements, the receipt check's and
/// the file check's payments. Written as the app's language writes a day alone (brief 55, Patrik: next to a summed row's
/// "3×" a bare "4" did not read as a date): German with its dot, "4.", English without, "4" (English puts no dot after
/// a day; the summed tile stays apart by its stack and its ×). Foundation writes a lone day as "4" in German too
/// (`Date.FormatStyle().day()`, checked 2026-10-31), so the dot is added here. Every tile asks this one function.
nonisolated enum DayWording {
    /// "4." / "4" for the 4th.
    static func alone(_ day: Int, language: AppLanguage = .current) -> String {
        language == .german ? "\(day)." : String(day)
    }

    /// The same for a `YYYY-MM-DD` day (a receipt's, a cash movement's); "–" when it is not one.
    static func alone(date: String, language: AppLanguage = .current) -> String {
        guard let date = ReceiptDay.date(date) else { return "–" }
        return alone(ReceiptDay.calendar.component(.day, from: date), language: language)
    }
}
