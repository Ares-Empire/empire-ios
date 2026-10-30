import Foundation
import Testing
@testable import Aresium

/// PayPal's own rows in phone mode (engine brief 34): a purchase in another currency and its two conversion rows, and
/// a withdrawal to the bank. Made-up rows only.
@MainActor
struct PhoneConversionTests {
    private let auth = BackendAuth(token: nil)

    private func paypal() -> ImportFile {
        ImportFile(name: "fictional-paypal-usd.csv", data: Data("""
        Datum,Name,Typ,Status,Währung,Brutto,Netto,Transaktionscode,Zugehöriger Transaktionscode,Auswirkung auf Guthaben
        03.10.2026,Fictional US Shop,Website-Zahlung,Abgeschlossen,USD,"-10,00","-10,00",FICT-USD,,Soll
        03.10.2026,,Allgemeine Währungsumrechnung,Abgeschlossen,USD,"10,00","10,00",FICT-CONV-1,FICT-USD,Haben
        03.10.2026,,Allgemeine Währungsumrechnung,Abgeschlossen,EUR,"-9,20","-9,20",FICT-CONV-2,FICT-USD,Soll
        05.10.2026,,Von Nutzer eingeleitete Abbuchung,Abgeschlossen,EUR,"-50,00","-50,00",FICT-WITHDRAWAL,,Soll
        """.utf8))
    }

    /// The conversion rows and the withdrawal are own transfers, so only the purchase waits as Not sorted, counted at
    /// its euro cost; the app passes PayPal's transaction code to the sorting (`SortingPayment.externalId`).
    @Test func conversionRowsAndWithdrawalsNeverWaitOrCount() async throws {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries"])
        _ = try await phone.importFiles([paypal()], auth: auth)
        let payments = try await phone.ledger.payments()
        #expect(payments.count == 4)
        let structural = payments.filter { $0.categorySource == .structural }.map(\.externalId).sorted()
        #expect(structural == ["FICT-CONV-1", "FICT-CONV-2", "FICT-WITHDRAWAL"])
        #expect(phone.summary.unsorted == 1)
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(abs(dashboard.total.expense - 9.20) < 0.000001)
        #expect(abs(dashboard.total.income) < 0.000001)
    }

    /// PayPal's own rows have no Name: they are not named after anyone (the reader leaves the counterparty empty), so
    /// a correction of one never carries over to another.
    @Test func paypalsOwnRowsHaveNoCounterparty() async throws {
        let phone = try await PhoneCountingTests.backend()
        _ = try await phone.importFiles([paypal()], auth: auth)
        let own = try await phone.ledger.payments().filter { $0.externalId != "FICT-USD" }
        #expect(own.allSatisfy { ($0.counterparty ?? "").isEmpty })
    }
}
