import Foundation
import JavaScriptCore

/// Why the engine could not answer.
nonisolated enum EngineError: LocalizedError, Equatable {
    /// The bundle is not in the app (a build without `Engine/aresium-engine.js`).
    case missingBundle
    /// A bank file the readers refused, with the engine's code (`empty`, `noTable`, `headerMismatch`, `camt`, `mt940`,
    /// `zip`, `unknown`); `ImportWording` words it for the person.
    case bankFile(code: String, message: String)
    /// Any other JavaScript exception, with its message.
    case javascript(String)
    /// The engine answered something the app cannot read.
    case invalidAnswer(String)

    var errorDescription: String? {
        switch self {
        case .missingBundle: String(localized: "Aresium's engine is missing from the app.")
        case let .bankFile(code, _): ImportWording.bankFileProblem(code)
        case .javascript, .invalidAnswer: String(localized: "Aresium's engine could not do this.")
        }
    }
}

/// The shared engine (aresium/src/engine: the server's own TypeScript, bundled by `npm run engine` and copied into the
/// app by `scripts/aresium-engine.sh`), run in JavaScriptCore. One actor owns one `JSContext` with the bundle loaded,
/// so calls never overlap. Every call crosses the bridge as JSON: Swift values are encoded, parsed in JavaScript, the
/// engine's function runs, and its answer comes back as JSON and is decoded (bank-file bytes go across as a
/// `Uint8Array`). A JavaScript exception becomes an `EngineError`; the engine's bank-file errors keep their `code`.
actor AresiumEngine {
    private let context: JSContext
    private var cachedCatalog: CategoryCatalog?

    /// The bundle shipped in the app (`Engine/aresium-engine.js`, copied flat into the app's resources).
    nonisolated static func bundledScriptURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "aresium-engine", withExtension: "js")
    }

    /// The engine from the app's own bundle.
    static func bundled(in bundle: Bundle = .main) throws -> AresiumEngine {
        guard let url = bundledScriptURL(in: bundle) else { throw EngineError.missingBundle }
        return try AresiumEngine(script: String(contentsOf: url, encoding: .utf8))
    }

    /// Phone mode creates the VM away from the UI run loop as well as calling it off main. JavaScriptCore schedules
    /// incremental sweep timers on the run loop where its context is created; creating it on main brings GC back
    /// there after a sort, even though the engine call itself runs on this actor.
    @concurrent
    nonisolated static func bundledForPhone(in bundle: Bundle = .main) async throws -> AresiumEngine {
        try PickerTiming.measure("engine.initialize") { try bundled(in: bundle) }
    }

    init(script: String) throws {
        guard let context = JSContext() else { throw EngineError.javascript("JavaScriptCore could not start") }
        context.name = "Aresium engine"
        self.context = context
        try Self.evaluate(script, in: context)
        guard context.objectForKeyedSubscript("AresiumEngine")?.isObject == true else {
            throw EngineError.invalidAnswer("The bundle did not define AresiumEngine")
        }
        try Self.evaluate(Self.bridge, in: context)
    }

    /// Opening an old store is synchronous, before the ledger can be read. Use the engine's own no-side rule,
    /// including its receipt, cash and currency counting, in a temporary VM used only for this migration.
    nonisolated static func legacyCategoryKinds(
        input: (CategoryCatalog) throws -> DashboardSourceInput
    ) throws -> [String: String] {
        guard let url = bundledScriptURL(), let context = JSContext() else { throw EngineError.missingBundle }
        try evaluate(String(contentsOf: url, encoding: .utf8), in: context)
        try evaluate(bridge, in: context)
        guard let catalogJSON = context.objectForKeyedSubscript("__aresiumCall")?
            .call(withArguments: ["catalog", "{}"])?.toString() else { throw EngineError.invalidAnswer("catalog") }
        let catalog = try JSONDecoder().decode(Envelope<CategoryCatalog>.self, from: Data(catalogJSON.utf8))
        guard let catalog = catalog.ok else { throw EngineError.invalidAnswer("catalog") }
        let source = try input(catalog)
        let json = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
        let call = context.evaluateScript("(json) => JSON.stringify(AresiumEngine.buildDashboardSource(JSON.parse(json)).categories)")
        guard let result = call?.call(withArguments: [json])?.toString(), context.exception == nil else {
            throw EngineError.invalidAnswer("legacy category sides")
        }
        struct Kind: Decodable { let name: String; let kind: String }
        let kinds = try JSONDecoder().decode([Kind].self, from: Data(result.utf8))
        return Dictionary(kinds.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: typed calls

    /// The default categories, the built-ins and their looks (`DEFAULT_CATEGORIES`, `BUILT_IN_CATEGORIES`,
    /// `CATEGORY_LOOK`, `CUSTOM_CATEGORY_LOOK`). Read once.
    func catalog() throws -> CategoryCatalog {
        if let cachedCatalog { return cachedCatalog }
        let catalog = try call("catalog", Empty(), as: CategoryCatalog.self)
        cachedCatalog = catalog
        return catalog
    }

    /// `readBankFile`: decodes the bytes (UTF-8, Windows-1252, UTF-16), finds the format and reads it. `layouts` are the
    /// layouts the person confirmed before.
    func readBankFile(_ bytes: Data, layouts: [CsvLayout]) throws -> BankFile {
        let array = try uint8Array(bytes)
        let value = context.objectForKeyedSubscript("__aresiumReadBankFile")?.call(withArguments: [array, try json(layouts)])
        return try answer(value, as: BankFile.self)
    }

    /// The file read with one layout (`decodeBankFile`, then `readCsv`): the column check's preview.
    func read(_ bytes: Data, with layout: CsvLayout) throws -> BankFile {
        let array = try uint8Array(bytes)
        let value = context.objectForKeyedSubscript("__aresiumReadWithLayout")?.call(withArguments: [array, try json(layout)])
        return try answer(value, as: BankFile.self)
    }

    /// `readingsOfUnknownFile`: the ways an unknown CSV can be read, best first (at most 4, each with its first
    /// payments), for "Does this look right?". Empty when the file is not an unknown CSV or nothing reads it (then the
    /// person picks the columns). `layouts` are the layouts the person confirmed before.
    func readings(_ bytes: Data, layouts: [CsvLayout]) throws -> [FileReading] {
        let array = try uint8Array(bytes)
        let value = context.objectForKeyedSubscript("__aresiumReadings")?.call(withArguments: [array, try json(layouts)])
        return try answer(value, as: [FileReading].self)
    }

    /// `shareableLayout`: a confirmed layout as it may be sent to us (the format only), or why it may not.
    func shareableLayout(_ layout: CsvLayout) throws -> ShareCheck {
        try call("shareableLayout", layout, as: ShareCheck.self)
    }

    /// Whether a text a person typed (a bank's name) looks like personal data, by the engine's own rule (`looksPersonal`
    /// in readers/share.ts, the one `shareableLayout` applies to a format's words): the reason (`email`, `iban`, `date`,
    /// `amount`, `digits`), or nil. Being longer than a column's name may be (`tooLong`) does not count here.
    func personalData(in text: String) throws -> String? {
        try call("personalData", text, as: PersonalCheck.self).reason
    }

    /// `sortPayments` over all of the person's payments (the own-transfer rules look across them): one result per
    /// payment, in order. `categories` are the ids the person may be sorted into.
    func sortPayments(_ payments: [SortingPayment], categories: [String],
                      learned: [String: String]) throws -> [SortResult] {
        let input = SortInput(payments: payments, categories: categories.map { CategoryID(id: $0) }, learned: learned)
        let results = try call("sortPayments", input, as: [SortResult].self)
        guard results.count == payments.count else { throw EngineError.invalidAnswer("sortPayments: wrong count") }
        return results
    }

    /// `learn` for one correction: the rule it makes (merchant key → category id); empty when the payment names no
    /// merchant the engine would learn.
    func learn(_ payment: SortingPayment, categoryID: String) throws -> [String: String] {
        try call("learn", LearnInput(learned: [:], payment: payment, categoryId: categoryID), as: [String: String].self)
    }

    /// `merchantKey` for each payment, in order ("" when it names none).
    func merchantKeys(_ payments: [SortingPayment]) throws -> [String] {
        let keys = try call("merchantKeys", payments, as: [String].self)
        guard keys.count == payments.count else { throw EngineError.invalidAnswer("merchantKeys: wrong count") }
        return keys
    }

    /// Full merchant keys plus line-only keys and card-statement checks, in one name-job bridge call.
    func nameKeys(_ payments: [SortingPayment], lines: [SortingPayment]) throws -> NameKeys {
        let answer = try call("nameKeys", NameKeyInput(payments: payments, lines: lines), as: NameKeys.self)
        guard answer.keys.count == payments.count, answer.lineKeys.count == lines.count,
              answer.cardLines.count == lines.count else { throw EngineError.invalidAnswer("nameKeys: wrong count") }
        return answer
    }

    /// `shopIdentities` for each merchant key, in the same order and length.
    func shopIdentities(_ keys: [String]) throws -> [String] {
        try PickerTiming.measure("names.identities") {
            assert(!Thread.isMainThread)
            let identities = try call("shopIdentities", keys, as: [String].self)
            guard identities.count == keys.count else { throw EngineError.invalidAnswer("shopIdentities: wrong count") }
            return identities
        }
    }

    /// The dashboard from stored payments: `buildDashboardSource`, then `buildDashboard`, in one call. The same
    /// `Dashboard` the server sends.
    func dashboard(_ input: DashboardSourceInput) throws -> Dashboard {
        let dashboard = try call("dashboard", input, as: Dashboard.self)
        guard dashboard.version == 2 else { throw DashboardError.unsupportedVersion }
        return dashboard
    }

    /// `readReceipt`: what Vision read on a receipt (`ReceiptCapture`, the JSON the engine takes) → shop, date, total,
    /// currency, card or cash, the rows, and which of them it is sure of.
    func readReceipt(_ capture: ReceiptCapture) throws -> ReceiptReading {
        try call("readReceipt", capture, as: ReceiptReading.self)
    }

    /// `matchReceipt`: the bank payment a card receipt belongs to, exactly one (`exact`), or the ones to ask about.
    /// `taken`: payments the person's other receipts are joined to, and the ones they said are not this one.
    func matchReceipt(_ receipt: MatchReceipt, payments: [MatchPayment], taken: [String]) throws -> ReceiptMatch {
        try call("matchReceipt", MatchInput(receipt: receipt, payments: payments, taken: taken), as: ReceiptMatch.self)
    }

    /// The engine's own version (`version` in index.ts).
    func version() throws -> String { try call("version", Empty(), as: String.self) }

    // MARK: the bridge

    /// Every call goes through these functions, which turn the engine's answer, or its exception, into one JSON text.
    private static let bridge = """
    (function () {
      const E = globalThis.AresiumEngine;
      const wrap = (run) => {
        try {
          const value = run();
          return JSON.stringify({ ok: value === undefined ? null : value });
        } catch (e) {
          return JSON.stringify({ error: {
            name: String((e && e.name) || "Error"),
            code: e && typeof e.code === "string" ? e.code : null,
            message: String((e && e.message) || e),
          } });
        }
      };
      const calls = {
        catalog: () => ({ defaults: E.DEFAULT_CATEGORIES, builtIns: E.BUILT_IN_CATEGORIES,
                          looks: E.CATEGORY_LOOK, custom: E.CUSTOM_CATEGORY_LOOK }),
        dashboard: (input) => E.buildDashboard(E.buildDashboardSource(input)),
        sortPayments: (input) => E.sortPayments(input.payments, { categories: input.categories, learned: input.learned }),
        learn: (input) => E.learn(input.learned, input.payment, input.categoryId),
        merchantKeys: (payments) => payments.map((payment) => E.merchantKey(payment)),
        nameKeys: (input) => ({
          keys: input.payments.map((payment) => E.merchantKey(payment)),
          lineKeys: input.lines.map((payment) => E.merchantKey(payment)),
          cardLines: input.lines.map((payment) => E.cardMerchant(payment.counterparty) !== null),
        }),
        shopIdentities: (keys) => E.shopIdentities(keys),
        shareableLayout: (layout) => E.shareableLayout(layout),
        readReceipt: (capture) => E.readReceipt(capture),
        matchReceipt: (input) => E.matchReceipt(input.receipt, input.payments, input.taken),
        // The engine exports no `looksPersonal` of its own: a layout whose one column is named `text` runs exactly that
        // check. A layout it calls invalid would hide every answer, so that is an error here.
        personalData: (text) => {
          const answer = E.shareableLayout({ version: 1, separator: ";", header: [text], dateFormat: "DD.MM.YYYY",
                                             numberFormat: "de", columns: { date: 0, amount: 0 } });
          if (answer.ok || answer.reason === "tooLong") return { reason: null };
          if (answer.reason === "invalid") throw new Error("personalData: the check's layout is invalid");
          return { reason: answer.reason };
        },
        version: () => E.version,
      };
      globalThis.__aresiumCall = (name, json) => wrap(() => {
        if (!Object.prototype.hasOwnProperty.call(calls, name)) throw new Error("Unknown engine call: " + name);
        return calls[name](JSON.parse(json));
      });
      globalThis.__aresiumReadBankFile = (bytes, layouts) => wrap(() => E.readBankFile(bytes, JSON.parse(layouts)));
      globalThis.__aresiumReadWithLayout = (bytes, layout) => wrap(() => E.readCsv(E.decodeBankFile(bytes), JSON.parse(layout)));
      globalThis.__aresiumReadings = (bytes, layouts) => wrap(() => E.readingsOfUnknownFile(bytes, JSON.parse(layouts)));
    })();
    """

    private func call<Input: Encodable, Output: Decodable>(_ name: String, _ input: Input,
                                                          as type: Output.Type) throws -> Output {
        let value = context.objectForKeyedSubscript("__aresiumCall")?.call(withArguments: [name, try json(input)])
        return try answer(value, as: type)
    }

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func answer<Output: Decodable>(_ value: JSValue?, as type: Output.Type) throws -> Output {
        if let exception = context.exception {
            context.exception = nil
            throw EngineError.javascript(exception.toString() ?? "Unknown JavaScript exception")
        }
        guard let value, value.isString, let text = value.toString() else {
            throw EngineError.invalidAnswer("The engine gave no answer")
        }
        let envelope: Envelope<Output>
        do { envelope = try JSONDecoder().decode(Envelope<Output>.self, from: Data(text.utf8)) }
        catch { throw EngineError.invalidAnswer(String(describing: error)) }
        if let failure = envelope.error {
            if let code = failure.code, failure.name == "BankFileError" {
                throw EngineError.bankFile(code: code, message: failure.message)
            }
            throw EngineError.javascript(failure.message)
        }
        guard let ok = envelope.ok else { throw EngineError.invalidAnswer("The engine answered null") }
        return ok
    }

    /// A `Uint8Array` over a copy of the bytes, freed by JavaScriptCore when the array goes.
    private func uint8Array(_ bytes: Data) throws -> JSValue {
        let count = bytes.count
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 16)
        bytes.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: count)
        var exception: JSValueRef?
        let array = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef, kJSTypedArrayTypeUint8Array, buffer,
                                                          count, { bytes, _ in bytes?.deallocate() }, nil, &exception)
        guard let array, exception == nil else {
            if array == nil { buffer.deallocate() }
            throw EngineError.javascript("The file's bytes could not be handed to the engine")
        }
        return JSValue(jsValueRef: array, in: context)
    }

    private static func evaluate(_ script: String, in context: JSContext) throws {
        context.exception = nil
        context.evaluateScript(script)
        if let exception = context.exception {
            context.exception = nil
            throw EngineError.javascript(exception.toString() ?? "Unknown JavaScript exception")
        }
    }

    private nonisolated struct Envelope<Value: Decodable>: Decodable {
        let ok: Value?
        let error: Failure?
    }

    private nonisolated struct Failure: Decodable {
        let name: String
        let code: String?
        let message: String
    }

    private nonisolated struct Empty: Encodable {}
    private nonisolated struct PersonalCheck: Decodable { let reason: String? }
    private nonisolated struct CategoryID: Encodable { let id: String }
    private nonisolated struct SortInput: Encodable {
        let payments: [SortingPayment]
        let categories: [CategoryID]
        let learned: [String: String]
    }
    private nonisolated struct MatchInput: Encodable {
        let receipt: MatchReceipt
        let payments: [MatchPayment]
        let taken: [String]
    }
    private nonisolated struct LearnInput: Encodable {
        let learned: [String: String]
        let payment: SortingPayment
        let categoryId: String
    }
}
