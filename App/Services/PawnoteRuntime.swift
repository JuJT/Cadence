import Foundation
import JavaScriptCore
import Security

enum PawnoteRuntimeError: Error, LocalizedError, Equatable {
    case unavailable, busy, invalidPayload, invalidSchoolHost, invalidRequest
    case timedOut, javascriptFailure, responseTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Le moteur PRONOTE n’est pas disponible. Relancez la connexion."
        case .busy: return "Une opération PRONOTE est déjà en cours."
        case .invalidPayload, .invalidRequest: return "La demande PRONOTE n’est pas valide."
        case .invalidSchoolHost: return "Choisissez une adresse HTTPS publique valide pour votre établissement."
        case .timedOut: return "PRONOTE n’a pas répondu dans le délai prévu."
        case .javascriptFailure: return "Le moteur PRONOTE n’a pas pu terminer cette opération."
        case .responseTooLarge: return "La réponse PRONOTE dépasse la taille prise en charge."
        }
    }
}

/// No JSContext/JSValue escapes this object's serial queue. The unchecked
/// conformance covers that confinement and the small explicitly locked gates.
final class PawnoteRuntime: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cadence.study.pawnote", qos: .userInitiated)
    private let gate = PawnoteRuntimeGate()
    private let resources = PawnoteJSResources()
    private let transport: PawnoteHTTPTransport
    private let onCredential: @Sendable (Data) -> Bool
    private let testSource: String?
    private let commandTimeout: TimeInterval
    // Queue-confined state. Network completion closures carry only strings/Data.
    private var generation = UUID()
    private var fetches = Set<String>()
    private var timers: [String: DispatchSourceTimer] = [:]

    init(onCredential: @escaping @Sendable (Data) -> Bool) {
        self.onCredential = onCredential
        transport = PawnoteHTTPTransport()
        testSource = nil
        commandTimeout = 180
    }

    #if CADENZA_RUNTIME_HARNESS
    init(testScript: String, protocolClasses: [AnyClass] = [], commandTimeout: TimeInterval = 180,
         onCredential: @escaping @Sendable (Data) -> Bool) {
        self.onCredential = onCredential
        transport = PawnoteHTTPTransport(protocolClasses: protocolClasses)
        testSource = testScript
        self.commandTimeout = min(180, max(0.02, commandTimeout))
    }
    #endif

    deinit {
        gate.revoke()?.finish(.failure(CancellationError()))
        transport.invalidate()
        let resources = resources
        let timers = Array(timers.values)
        queue.async {
            timers.forEach { $0.cancel() }
            resources.reset()
        }
    }

    /// Identical concurrent calls share one command. A different command fails
    /// promptly instead of retaining an unbounded queue of credential payloads.
    func call(_ command: String, payload: Data, schoolHost: String? = nil) async throws -> Data {
        guard !command.isEmpty, command.utf8.count <= 64,
              command.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0) }),
              payload.count <= 8 * 1024 * 1024, String(data: payload, encoding: .utf8) != nil,
              (try? JSONSerialization.jsonObject(with: payload, options: [.fragmentsAllowed])) != nil else {
            throw PawnoteRuntimeError.invalidPayload
        }
        let policy = try PawnoteURLPolicy(command: command, schoolHost: schoolHost)
        let waiter = PawnoteRuntimeWaiter()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                do {
                    let (operation, isNew) = try gate.admit(command: command, payload: payload, policy: policy, waiter: waiter)
                    if isNew {
                        installDeadline(operation)
                        queue.async { [weak self, operation] in self?.begin(operation) }
                    }
                } catch { waiter.finish(.failure(error)) }
            }
        } onCancel: { [weak self] in
            waiter.finish(.failure(CancellationError()))
            self?.removeCancelledWaiter(waiter.id)
        }
    }

    /// Permanent invalidation: callers must create a new runtime for a new
    /// account. Network/credential permission is revoked before queued cleanup.
    func invalidate() async {
        let operation = gate.revoke()
        operation?.finish(.failure(CancellationError()))
        transport.invalidate()
        queue.async { [weak self] in
            guard let self else { return }
            self.clearAsyncResources()
            self.generation = UUID()
            self.resources.reset()
        }
    }

    private func installDeadline(_ operation: PawnoteRuntimeOperation) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + commandTimeout)
        timer.setEventHandler { [weak self, weak operation] in
            guard let self, let operation, operation.finish(.failure(PawnoteRuntimeError.timedOut)) else { return }
            // The continuation deadline does not depend on JavaScript yielding.
            // Public JSC has no force-preemption API: the engine stays busy until
            // its queue can clean up, and every native bridge rejects this lease.
            self.transport.cancel(operationID: operation.id)
            self.queue.async { [weak self, operation] in self?.clean(operation, reset: true) }
        }
        timer.resume()
        operation.installDeadline(timer)
    }

    private func removeCancelledWaiter(_ id: UUID) {
        guard let operation = gate.current, operation.removeWaiter(id),
              operation.finish(.failure(CancellationError())) else { return }
        transport.cancel(operationID: operation.id)
        queue.async { [weak self, operation] in self?.clean(operation, reset: true) }
    }

    private func begin(_ operation: PawnoteRuntimeOperation) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard gate.isCurrent(operation), operation.isLive else { clean(operation, reset: true); return }
        do {
            try prepareContext()
            guard let context = resources.context,
                  let function = context.objectForKeyedSubscript("__cadenzaCommand"),
                  !function.isUndefined, !function.isNull,
                  let payload = String(data: operation.payload, encoding: .utf8) else {
                throw PawnoteRuntimeError.unavailable
            }
            _ = function.call(withArguments: [operation.id.uuidString, operation.command, payload])
        } catch { fail(operation, error: error) }
    }

    private static let bundledSource: Result<String, PawnoteRuntimeError> = {
        guard let url = Bundle.main.url(forResource: "pawnote.bundle", withExtension: "js", subdirectory: "Pronote")
                ?? Bundle.main.url(forResource: "pawnote.bundle", withExtension: "js"),
              let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024,
              let source = String(data: data, encoding: .utf8) else { return .failure(.unavailable) }
        return .success(source)
    }()

    private func prepareContext() throws {
        guard resources.context == nil else { return }
        let source = try testSource ?? Self.bundledSource.get()
        guard let vm = JSVirtualMachine(), let context = JSContext(virtualMachine: vm) else { throw PawnoteRuntimeError.unavailable }
        resources.vm = vm
        resources.context = context
        let epoch = generation
        context.exceptionHandler = { [weak self] _, _ in
            guard let self, self.generation == epoch, let operation = self.gate.current else { return }
            self.fail(operation, error: PawnoteRuntimeError.javascriptFailure)
        }
        // Foundation collections and blocks are bridged using documented JSC
        // conversion. No native object retains a JSValue, avoiding a VM cycle.
        let bridge = JSValue(newObjectIn: context)!
        let fetch: @convention(block) (String, String) -> Void = { [weak self] id, options in
            self?.fetch(id: id, options: options, epoch: epoch)
        }
        let random: @convention(block) (Int) -> NSArray? = { [weak self] count in
            self?.secureRandom(count: count, epoch: epoch)
        }
        let credential: @convention(block) (String) -> Bool = { [weak self] value in
            guard let self, let operation = self.liveOperation(epoch), value.utf8.count <= 1024 * 1024,
                  let data = value.data(using: .utf8), operation.isLive else { return false }
            // Synchronous by design: the Keychain callback must finish before
            // JavaScript is allowed to issue its next authentication request.
            return self.onCredential(data) && operation.isLive && !self.gate.isRevoked
        }
        let complete: @convention(block) (String, String) -> Void = { [weak self] id, value in
            guard let self, let operation = self.liveOperation(epoch), operation.id.uuidString == id else { return }
            guard value.utf8.count <= 16 * 1024 * 1024, let data = value.data(using: .utf8) else {
                self.fail(operation, error: PawnoteRuntimeError.responseTooLarge); return
            }
            // The command envelope belongs to the JS/service contract. It is
            // returned byte-for-byte as UTF-8; this bridge never decodes it.
            if operation.finish(.success(data)) { self.clean(operation, reset: false) }
        }
        let setTimer: @convention(block) (String, Double) -> Void = { [weak self] id, delay in
            self?.setTimer(id: id, delayMS: delay, epoch: epoch)
        }
        let clearTimer: @convention(block) (String) -> Void = { [weak self] id in
            guard let self, self.generation == epoch else { return }
            self.timers.removeValue(forKey: id)?.cancel()
        }
        for (name, value) in [("fetch", fetch as Any), ("secureRandom", random as Any),
                              ("credential", credential as Any), ("complete", complete as Any),
                              ("setTimer", setTimer as Any), ("clearTimer", clearTimer as Any)] {
            bridge.setObject(value, forKeyedSubscript: name as NSString)
        }
        context.setObject(bridge, forKeyedSubscript: "__cadenzaNative" as NSString)
        _ = context.evaluateScript(source)
        guard resources.context === context, context.exception == nil,
              context.evaluateScript("typeof __cadenzaCommand === 'function' && typeof __cadenzaFetchReply === 'function' && typeof __cadenzaTimerFire === 'function'")?.toBool() == true else {
            throw PawnoteRuntimeError.unavailable
        }
    }

    private func liveOperation(_ epoch: UUID) -> PawnoteRuntimeOperation? {
        guard generation == epoch, !gate.isRevoked, let operation = gate.current, operation.isLive else { return nil }
        return operation
    }

    private func secureRandom(count: Int, epoch: UUID) -> NSArray? {
        guard liveOperation(epoch) != nil, (0...65536).contains(count) else {
            throwJavaScript("secure_random_unavailable"); return nil
        }
        if count == 0 { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throwJavaScript("secure_random_unavailable"); return nil }
        return bytes.map { NSNumber(value: $0) } as NSArray
    }

    private func throwJavaScript(_ code: String) {
        if let context = JSContext.current() { context.exception = JSValue(newErrorFromMessage: code, in: context) }
    }

    private func fetch(id: String, options: String, epoch: UUID) {
        guard let operation = liveOperation(epoch) else { return }
        guard !id.isEmpty, id.utf8.count <= 128, !fetches.contains(id), fetches.count < 16 else {
            fail(operation, error: PawnoteRuntimeError.invalidRequest); return
        }
        fetches.insert(id)
        do {
            let request = try operation.policy.request(optionsJSON: options)
            transport.start(request: request.request, followRedirects: request.followRedirects,
                            policy: operation.policy, operationID: operation.id) { [weak self, weak operation] reply in
                guard let self, let operation else { return }
                self.queue.async { [weak self, operation] in self?.replyFetch(id, reply: reply, operation: operation, epoch: epoch) }
            }
        } catch {
            queue.async { [weak self, operation] in
                self?.replyFetch(id, reply: Data("{\"error\":\"request_not_allowed\"}".utf8), operation: operation, epoch: epoch)
            }
        }
    }

    private func replyFetch(_ id: String, reply: Data, operation: PawnoteRuntimeOperation, epoch: UUID) {
        guard liveOperation(epoch) === operation, fetches.remove(id) != nil,
              let value = String(data: reply, encoding: .utf8) else { return }
        _ = resources.context?.objectForKeyedSubscript("__cadenzaFetchReply")?.call(withArguments: [id, value])
    }

    private func setTimer(id: String, delayMS: Double, epoch: UUID) {
        guard let operation = liveOperation(epoch) else { return }
        guard !id.isEmpty, id.utf8.count <= 128, delayMS.isFinite,
              timers[id] != nil || timers.count < 128 else {
            fail(operation, error: PawnoteRuntimeError.invalidRequest); return
        }
        timers.removeValue(forKey: id)?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + min(60000, max(0, delayMS)) / 1000)
        timer.setEventHandler { [weak self, weak operation] in
            guard let self, let operation, self.liveOperation(epoch) === operation else { return }
            self.timers.removeValue(forKey: id)?.cancel()
            _ = self.resources.context?.objectForKeyedSubscript("__cadenzaTimerFire")?.call(withArguments: [id])
        }
        timers[id] = timer
        timer.resume()
    }

    private func fail(_ operation: PawnoteRuntimeOperation, error: Error) {
        if operation.finish(.failure(error)) { clean(operation, reset: true) }
    }

    private func clearAsyncResources(notifyJavaScript: Bool = false) {
        if notifyJavaScript, let clear = resources.context?.objectForKeyedSubscript("clearTimeout"),
           !clear.isUndefined, !clear.isNull {
            // Normal completion keeps the context. Drop its platform.js Map
            // callbacks too, rather than only cancelling their native sources.
            // The native clearTimer bridge may mutate timers during this call.
            for id in Array(timers.keys) { _ = clear.call(withArguments: [id]) }
        }
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        fetches.removeAll()
    }

    private func clean(_ operation: PawnoteRuntimeOperation, reset: Bool) {
        guard gate.isCurrent(operation) else { return }
        clearAsyncResources(notifyJavaScript: !reset)
        transport.cancel(operationID: operation.id)
        if reset || resources.context?.exception != nil {
            generation = UUID()
            resources.reset()
            transport.clearCookies()
        }
        gate.release(operation)
    }
}

private final class PawnoteJSResources: @unchecked Sendable {
    var vm: JSVirtualMachine?
    var context: JSContext?
    func reset() { context?.exceptionHandler = nil; context = nil; vm = nil }
}

private final class PawnoteRuntimeWaiter: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    var isFinished: Bool { lock.pawnoteLocked { result != nil } }
    func install(_ continuation: CheckedContinuation<Data, Error>) {
        let completed = lock.pawnoteLocked { () -> Result<Data, Error>? in
            if let result { return result }
            self.continuation = continuation; return nil
        }
        if let completed { continuation.resume(with: completed) }
    }
    func finish(_ result: Result<Data, Error>) {
        let pending = lock.pawnoteLocked { () -> CheckedContinuation<Data, Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            let pending = continuation; continuation = nil; return pending
        }
        pending?.resume(with: result)
    }
}

private final class PawnoteRuntimeOperation: @unchecked Sendable {
    let id = UUID()
    let command: String
    let payload: Data
    let policy: PawnoteURLPolicy
    private let lock = NSLock()
    private var finished = false
    private var waiters: [UUID: PawnoteRuntimeWaiter] = [:]
    private var deadline: DispatchSourceTimer?
    init(command: String, payload: Data, policy: PawnoteURLPolicy) {
        self.command = command; self.payload = payload; self.policy = policy
    }
    var isLive: Bool { lock.pawnoteLocked { !finished } }
    func add(_ waiter: PawnoteRuntimeWaiter) throws {
        try lock.pawnoteLocked {
            guard !waiter.isFinished else { throw CancellationError() }
            guard !finished, waiters.count < 8 else { throw PawnoteRuntimeError.busy }
            waiters[waiter.id] = waiter
        }
    }
    func removeWaiter(_ id: UUID) -> Bool {
        lock.pawnoteLocked { waiters.removeValue(forKey: id) != nil && waiters.isEmpty && !finished }
    }
    func installDeadline(_ timer: DispatchSourceTimer) {
        let cancel = lock.pawnoteLocked { () -> Bool in
            if finished { return true }
            deadline = timer; return false
        }
        if cancel { timer.cancel() }
    }
    @discardableResult func finish(_ result: Result<Data, Error>) -> Bool {
        let values = lock.pawnoteLocked { () -> ([PawnoteRuntimeWaiter], DispatchSourceTimer?)? in
            guard !finished else { return nil }
            finished = true
            let result = (Array(waiters.values), deadline)
            waiters.removeAll(); deadline = nil
            return result
        }
        guard let values else { return false }
        values.1?.cancel()
        values.0.forEach { $0.finish(result) }
        return true
    }
}

private final class PawnoteRuntimeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: PawnoteRuntimeOperation?
    private var revoked = false
    var current: PawnoteRuntimeOperation? { lock.pawnoteLocked { operation } }
    var isRevoked: Bool { lock.pawnoteLocked { revoked } }
    func isCurrent(_ candidate: PawnoteRuntimeOperation) -> Bool { lock.pawnoteLocked { operation === candidate } }
    func admit(command: String, payload: Data, policy: PawnoteURLPolicy, waiter: PawnoteRuntimeWaiter) throws -> (PawnoteRuntimeOperation, Bool) {
        try lock.pawnoteLocked {
            guard !revoked else { throw PawnoteRuntimeError.unavailable }
            if let operation {
                guard operation.command == command, operation.payload == payload, operation.policy == policy else { throw PawnoteRuntimeError.busy }
                try operation.add(waiter); return (operation, false)
            }
            let operation = PawnoteRuntimeOperation(command: command, payload: payload, policy: policy)
            try operation.add(waiter)
            self.operation = operation
            return (operation, true)
        }
    }
    func release(_ candidate: PawnoteRuntimeOperation) { lock.pawnoteLocked { if operation === candidate { operation = nil } } }
    func revoke() -> PawnoteRuntimeOperation? { lock.pawnoteLocked { revoked = true; return operation } }
}

struct PawnoteURLPolicy: Equatable, Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 PRONOTE Mobile APP Version/2.0.11"
    let hosts: Set<String>
    let discovery: Bool
    init(command: String, schoolHost: String?) throws {
        discovery = command == "discover"
        if discovery { hosts = ["www.index-education.com", "index-education.com"] }
        else {
            guard let schoolHost, let canonical = Self.canonicalHost(schoolHost) else { throw PawnoteRuntimeError.invalidSchoolHost }
            hosts = [canonical]
        }
    }
    static func canonicalHost(_ value: String) -> String? {
        let host = value.lowercased()
        guard !host.isEmpty, host.utf8.count <= 253, !host.hasSuffix("."),
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.").contains($0) }) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
              let last = labels.last, last.contains(where: { $0.isLetter }),
              !["localhost", "local", "localdomain", "lan", "home", "internal", "intranet", "test", "invalid", "example", "onion", "arpa"].contains(String(last)) else { return nil }
        return host
    }
    func allowedURL(_ value: String) -> URL? {
        guard value.utf8.count <= 8192, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host.flatMap(Self.canonicalHost), hosts.contains(host),
              components.port == nil || components.port == 443,
              !discovery || (components.percentEncodedPath == "/swie/geoloc.php" && components.query == nil && components.fragment == nil) else { return nil }
        return components.url
    }
    func allowsRedirect(to url: URL, originalHost: String) -> Bool {
        allowedURL(url.absoluteString) != nil && url.host?.lowercased() == originalHost.lowercased()
    }
    func request(optionsJSON: String) throws -> (request: URLRequest, followRedirects: Bool) {
        guard optionsJSON.utf8.count <= 8 * 1024 * 1024,
              let data = optionsJSON.data(using: .utf8),
              let options = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawURL = options["url"] as? String, let url = allowedURL(rawURL) else { throw PawnoteRuntimeError.invalidRequest }
        let method = (options["method"] as? String ?? "GET").uppercased()
        // Public directory: the exact geolocation endpoint and POST only.
        guard ["GET", "POST", "HEAD"].contains(method), !discovery || method == "POST" else { throw PawnoteRuntimeError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        if let headers = options["headers"] {
            guard let values = headers as? [String: String], values.count <= 64 else { throw PawnoteRuntimeError.invalidRequest }
            for (key, value) in values {
                let lower = key.lowercased()
                guard !key.isEmpty, key.utf8.count <= 128, value.utf8.count <= 8192,
                      key.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").contains($0) }),
                      !value.contains("\r"), !value.contains("\n"), !value.contains("\0"),
                      !["host", "content-length", "connection", "proxy-authorization", "proxy-connection", "transfer-encoding"].contains(lower),
                      !discovery || !["cookie", "authorization"].contains(lower) else { throw PawnoteRuntimeError.invalidRequest }
                if lower != "user-agent" { request.setValue(value, forHTTPHeaderField: key) }
            }
        }
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if method == "POST", let content = options["content"] as? String ?? options["body"] as? String {
            guard content.utf8.count <= 8 * 1024 * 1024 else { throw PawnoteRuntimeError.invalidRequest }
            request.httpBody = content.data(using: .utf8)
        }
        return (request, (options["redirect"] as? String) != "manual")
    }
}

private final class PawnoteHTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Entry {
        let operationID: UUID
        let task: URLSessionDataTask
        let policy: PawnoteURLPolicy
        let originalHost: String
        let followRedirects: Bool
        let completion: @Sendable (Data) -> Void
        var data = Data()
        var response: HTTPURLResponse?
        var error: String?
        var redirects = 0
        init(operationID: UUID, task: URLSessionDataTask, policy: PawnoteURLPolicy, host: String,
             followRedirects: Bool, completion: @escaping @Sendable (Data) -> Void) {
            self.operationID = operationID; self.task = task; self.policy = policy
            originalHost = host; self.followRedirects = followRedirects; self.completion = completion
        }
    }
    private struct CookieKey: Hashable { let host: String; let name: String; let path: String }
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var cookies: [CookieKey: HTTPCookie] = [:]
    private var invalidated = false
    private let protocolClasses: [AnyClass]?
    private var storedSession: URLSession?
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.urlCredentialStorage = nil
        // No shared Foundation cookie store: this transport uses a bounded
        // in-memory jar scoped to the exact originating host below.
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 4
        if let protocolClasses, !protocolClasses.isEmpty { config.protocolClasses = protocolClasses }
        let callbacks = OperationQueue(); callbacks.maxConcurrentOperationCount = 1
        callbacks.name = "com.cadence.study.pawnote.http"
        return URLSession(configuration: config, delegate: self, delegateQueue: callbacks)
    }
    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses; super.init() }
    func start(request initial: URLRequest, followRedirects: Bool, policy: PawnoteURLPolicy, operationID: UUID,
               completion: @escaping @Sendable (Data) -> Void) {
        var request = initial
        let host = request.url?.host?.lowercased() ?? ""
        let jarHeader = cookieHeader(for: request.url!)
        if !policy.discovery, request.value(forHTTPHeaderField: "Cookie") == nil, !jarHeader.isEmpty { request.setValue(jarHeader, forHTTPHeaderField: "Cookie") }
        let task = lock.pawnoteLocked { () -> URLSessionDataTask? in
            guard !invalidated, entries.count < 16 else { return nil }
            let session = storedSession ?? makeSession()
            storedSession = session
            let task = session.dataTask(with: request)
            entries[task.taskIdentifier] = Entry(operationID: operationID, task: task, policy: policy, host: host,
                followRedirects: followRedirects, completion: completion)
            return task
        }
        if let task { task.resume() } else { completion(Self.replyData(["error": "request_cancelled"])) }
    }
    func cancel(operationID: UUID) {
        let tasks = lock.pawnoteLocked { () -> [URLSessionDataTask] in
            let keys = entries.filter { $0.value.operationID == operationID }.map(\.key)
            return keys.compactMap { entries.removeValue(forKey: $0)?.task }
        }
        tasks.forEach { $0.cancel() }
    }
    func clearCookies() { lock.pawnoteLocked { cookies.removeAll() } }
    func invalidate() {
        let pending = lock.pawnoteLocked { () -> ([URLSessionDataTask], URLSession?) in
            invalidated = true; cookies.removeAll()
            let tasks = entries.values.map(\.task), session = storedSession
            entries.removeAll(); storedSession = nil
            return (tasks, session)
        }
        pending.0.forEach { $0.cancel() }
        // Break URLSession's delegate-retention cycle without ever constructing
        // a session on an arbitrary cancellation thread.
        pending.1?.invalidateAndCancel()
    }
    private func cookieHeader(for url: URL) -> String {
        lock.pawnoteLocked {
            let now = Date(), host = url.host?.lowercased() ?? "", path = url.path.isEmpty ? "/" : url.path
            cookies = cookies.filter { $0.value.expiresDate.map { $0 > now } ?? true }
            let values = cookies.filter { key, _ in
                key.host == host && (path == key.path || path.hasPrefix(key.path.hasSuffix("/") ? key.path : key.path + "/"))
            }.values.sorted { $0.path.count > $1.path.count }
            var result = ""
            for cookie in values {
                let addition = (result.isEmpty ? "" : "; ") + cookie.name + "=" + cookie.value
                if result.utf8.count + addition.utf8.count <= 65536 { result += addition }
            }
            return result
        }
    }
    private func storeCookies(_ response: HTTPURLResponse) {
        guard let url = response.url, let host = url.host?.lowercased() else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in result[String(describing: item.key)] = String(describing: item.value) }
        let received = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        lock.pawnoteLocked {
            guard !invalidated else { return }
            for cookie in received where cookie.name.utf8.count + cookie.value.utf8.count <= 8192 {
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard host == domain || host.hasSuffix("." + domain) else { continue }
                let key = CookieKey(host: host, name: cookie.name, path: cookie.path)
                if cookie.expiresDate.map({ $0 <= Date() }) == true { cookies.removeValue(forKey: key) }
                else if cookies[key] != nil || cookies.count < 128 { cookies[key] = cookie }
            }
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        let headerBytes = http.allHeaderFields.reduce(0) { $0 + String(describing: $1.key).utf8.count + String(describing: $1.value).utf8.count }
        let accepted = lock.pawnoteLocked { () -> (Bool, Bool) in
            guard let entry = entries[dataTask.taskIdentifier] else { return (false, false) }
            entry.response = http
            if response.expectedContentLength > 8 * 1024 * 1024 || headerBytes > 65536 { entry.error = "response_too_large"; return (false, false) }
            return (true, !entry.policy.discovery)
        }
        if accepted.1 { storeCookies(http) }
        completionHandler(accepted.0 ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let cancel = lock.pawnoteLocked { () -> Bool in
            guard let entry = entries[dataTask.taskIdentifier] else { return true }
            guard entry.data.count + data.count <= 8 * 1024 * 1024 else { entry.error = "response_too_large"; return true }
            entry.data.append(data); return false
        }
        if cancel { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let usesPrivateJar = lock.pawnoteLocked { entries[task.taskIdentifier]?.policy.discovery == false }
        if usesPrivateJar { storeCookies(response) }
        let allowed = lock.pawnoteLocked { () -> Bool in
            guard let entry = entries[task.taskIdentifier] else { return false }
            guard entry.followRedirects else { return false }
            guard let url = request.url, entry.policy.allowsRedirect(to: url, originalHost: entry.originalHost), entry.redirects < 8 else {
                entry.error = "redirect_not_allowed"; return false
            }
            entry.redirects += 1; return true
        }
        guard allowed else { completionHandler(nil); return }
        var next = request
        next.setValue(PawnoteURLPolicy.userAgent, forHTTPHeaderField: "User-Agent")
        if usesPrivateJar, let url = next.url {
            let header = cookieHeader(for: url)
            if next.value(forHTTPHeaderField: "Cookie") == nil, !header.isEmpty { next.setValue(header, forHTTPHeaderField: "Cookie") }
        }
        completionHandler(next)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = lock.pawnoteLocked({ entries.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let code = entry.error { entry.completion(Self.replyData(["error": code])); return }
        if let error {
            let code = (error as NSError).code == NSURLErrorTimedOut ? "request_timeout" : "network_unavailable"
            entry.completion(Self.replyData(["error": code])); return
        }
        guard let response = entry.response else { entry.completion(Self.replyData(["error": "invalid_response"])); return }
        var headers: [String: String] = [:]
        var headerBytes = 0
        for (key, value) in response.allHeaderFields {
            let name = String(describing: key).lowercased(), value = String(describing: value)
            headerBytes += name.utf8.count + value.utf8.count
            guard headerBytes <= 65536 else { entry.completion(Self.replyData(["error": "response_too_large"])); return }
            headers[name] = value
        }
        let content = String(data: entry.data, encoding: .utf8) ?? String(data: entry.data, encoding: .isoLatin1) ?? ""
        entry.completion(Self.replyData(["status": response.statusCode, "content": content, "headers": headers]))
    }
    private static func replyData(_ values: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: values)) ?? Data("{\"error\":\"invalid_response\"}".utf8)
    }
}

private extension NSLock {
    func pawnoteLocked<T>(_ operation: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }; return try operation()
    }
}
