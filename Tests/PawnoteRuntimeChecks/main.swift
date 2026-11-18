import Foundation

private let schoolHost = "fixture.index-education.net"
private let empty = Data("{}".utf8)

private enum CheckError: Error { case failed(String) }
private func check(_ accepted: @autoclosure () -> Bool, _ label: String) throws {
    if !accepted() { throw CheckError.failed(label) }
}
private func object(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CheckError.failed("response dictionary") }
    return value
}
private func encoded(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var credentials = 0
    private var calledOnMain = false
    func record() -> Bool {
        lock.lock(); defer { lock.unlock() }
        credentials += 1; calledOnMain = calledOnMain || Thread.isMainThread
        return true
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return credentials }
    var onMain: Bool { lock.lock(); defer { lock.unlock() }; return calledOnMain }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0
    private static var safeDirectoryRequests = true
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static var directoryRequestsAreSafe: Bool { lock.lock(); defer { lock.unlock() }; return safeDirectoryRequests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        guard let url = request.url else { return }
        var headers = ["Content-Type": "text/plain; charset=utf-8", "X-Fixture": "ready"]
        let body: Data
        switch url.path {
        case "/swie/geoloc.php":
            let content = String(data: requestBody(), encoding: .utf8) ?? ""
            let safe = url.host == "www.index-education.com" && request.httpMethod == "POST" &&
                request.value(forHTTPHeaderField: "Cookie") == nil && request.value(forHTTPHeaderField: "Authorization") == nil &&
                content.contains("geoLoc")
            Self.lock.lock(); Self.safeDirectoryRequests = Self.safeDirectoryRequests && safe; Self.lock.unlock()
            headers["Content-Type"] = "application/json"
            body = Data(#"[{"nomEtab":"Fixture Far","url":"https://far.example.org/pronote/","lat":"2","long":"2","cp":"00000"},{"nomEtab":"Fixture Nearby","url":"https://near.example.org/pronote/","lat":"0.01","long":"0.01","cp":"00000"}]"#.utf8)
        case "/set-cookie":
            headers["Set-Cookie"] = "fixture_cookie=private; Path=/; Secure"
            body = Data("set".utf8)
        case "/read-cookie": body = Data((request.value(forHTTPHeaderField: "Cookie") ?? "").utf8)
        case "/agent": body = Data((request.value(forHTTPHeaderField: "User-Agent") ?? "").utf8)
        case "/large":
            headers["Content-Length"] = String(8 * 1024 * 1024 + 1)
            body = Data()
        case "/large-stream": body = Data(repeating: 65, count: 8 * 1024 * 1024 + 1)
        default: body = Data("fixture-response".utf8)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            for offset in stride(from: 0, to: body.count, by: 128 * 1024) {
                client?.urlProtocol(self, didLoad: body.subdata(in: offset..<min(offset + 128 * 1024, body.count)))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private func requestBody() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), bytes = [UInt8](repeating: 0, count: 1024)
        while result.count < 8192 {
            let read = stream.read(&bytes, maxLength: min(bytes.count, 8192 - result.count))
            if read <= 0 { break }
            result.append(contentsOf: bytes.prefix(read))
        }
        return result
    }
}

private let script = #"""
let invocationCount = 0;
const fetchOwners = Object.create(null), timerOwners = Object.create(null);
globalThis.__cadenzaCommand = function(id, command, json) {
  const value = JSON.parse(json); invocationCount++;
  if (command === 'opaque') { __cadenzaNative.complete(id, 'opaque-envelope'); return; }
  if (command === 'echo') { __cadenzaNative.complete(id, JSON.stringify({counter:invocationCount})); return; }
  if (command === 'promise') { Promise.resolve(42).then(value=>__cadenzaNative.complete(id, JSON.stringify({value}))); return; }
  if (command === 'random') {
    const bytes = __cadenzaNative.secureRandom(value.count || 64);
    __cadenzaNative.complete(id, JSON.stringify({count:bytes.length,array:Array.isArray(bytes),
      bytes:bytes.every(n=>Number.isInteger(n)&&n>=0&&n<=255),varied:new Set(bytes).size>1})); return;
  }
  if (command === 'credential') {
    __cadenzaNative.complete(id, JSON.stringify({saved:__cadenzaNative.credential('{"token":"fixture-only"}')})); return;
  }
  if (command === 'persistThenFetch') {
    if (!__cadenzaNative.credential('{"token":"fixture-only"}')) {
      __cadenzaNative.complete(id, '{"blocked":true}'); return;
    }
  }
  if (command === 'fetch' || command === 'persistThenFetch') {
    const fetchID = 'fetch-'+id; fetchOwners[fetchID] = id;
    __cadenzaNative.fetch(fetchID, JSON.stringify(value)); return;
  }
  if (command === 'delay') {
    const timerID = 'timer-'+id; timerOwners[timerID] = {id:id,counter:invocationCount};
    __cadenzaNative.setTimer(timerID, value.delay || 60); return;
  }
  if (command === 'clearTimer') {
    const cancelled = 'cancel-'+id, timerID = 'timer-'+id;
    timerOwners[cancelled] = {id:id,counter:-1};
    __cadenzaNative.setTimer(cancelled, 1); globalThis.clearTimeout(cancelled);
    timerOwners[timerID] = {id:id,counter:1}; __cadenzaNative.setTimer(timerID, 20); return;
  }
  if (command === 'leaveTimer') {
    const timerID = 'left-'+id; timerOwners[timerID] = {id:id,counter:-1};
    __cadenzaNative.setTimer(timerID,60000); __cadenzaNative.complete(id,'{}'); return;
  }
  if (command === 'timerCount') { __cadenzaNative.complete(id,JSON.stringify({count:Object.keys(timerOwners).length})); return; }
  if (command === 'never') { __cadenzaNative.credential('{"started":true}'); return; }
  if (command === 'spin') {
    const until = Date.now()+800; while (Date.now()<until) {}
    __cadenzaNative.credential('{"late":true}'); __cadenzaNative.complete(id, 'late'); return;
  }
  throw new Error('fixture-script-error');
};
globalThis.__cadenzaFetchReply = function(id, json) {
  const owner = fetchOwners[id]; delete fetchOwners[id];
  if (owner) __cadenzaNative.complete(owner, json);
};
globalThis.__cadenzaTimerFire = function(id) {
  const owner = timerOwners[id]; delete timerOwners[id];
  if (owner) __cadenzaNative.complete(owner.id, JSON.stringify({counter:owner.counter}));
};
globalThis.clearTimeout = function(id) { delete timerOwners[String(id)]; __cadenzaNative.clearTimer(String(id)); };
"""#

@main
private struct PawnoteRuntimeChecks {
    static func main() async throws {
        try policies()
        try await bridgeAndTimers()
        try await networkAndCookies()
        try await coalescingAndCancellation()
        try await watchdog()
        if let path = CommandLine.arguments.dropFirst().first {
            try await actualBundleBoot(path)
            print("Pawnote actual browser bundle checks passed: native crypto/URL primitives, Promise command envelope and mock directory ordering, no real network or credentials.")
        } else {
            print("Pawnote actual bundle boot skipped: no browser bundle was supplied to this standalone run.")
        }
        print("Pawnote runtime checks passed: URL/redirect policy, opaque envelope, secure random, private cookies, HTTP caps, synchronous credentials, timers, bounded coalescing, cancellation and off-queue watchdog.")
    }

    private static func policies() throws {
        let school = try PawnoteURLPolicy(command: "login", schoolHost: schoolHost.uppercased())
        try check(school.allowedURL("https://" + schoolHost + "/pronote/") != nil, "exact HTTPS school")
        for value in ["http://" + schoolHost, "https://other.index-education.net/", "https://user:secret@" + schoolHost,
                      "https://@" + schoolHost, "https://" + schoolHost + ":8443/", "https://127.0.0.1/", "https://[::1]/", "https://school.local/"] {
            try check(school.allowedURL(value) == nil, "forbidden URL")
        }
        for value in ["localhost", "127.0.0.1", "[::1]", "school.local", "school.internal", "https://" + schoolHost, "user@" + schoolHost] {
            try check(PawnoteURLPolicy.canonicalHost(value) == nil, "invalid selected host")
        }
        let directory = try PawnoteURLPolicy(command: "discover", schoolHost: nil)
        try check(directory.allowedURL("https://www.index-education.com/swie/geoloc.php") != nil, "directory endpoint")
        try check(directory.allowedURL("https://www.index-education.com/other") == nil, "other directory paths refused")
        let discoveryPost = try directory.request(optionsJSON: "{\"url\":\"https://www.index-education.com/swie/geoloc.php\",\"method\":\"POST\",\"content\":\"fixture-location\"}")
        try check(discoveryPost.request.httpMethod == "POST", "directory POST supported")
        try check(directory.allowedURL("https://" + schoolHost) == nil, "discovery must not fetch a school")
        try check(!directory.allowsRedirect(to: URL(string: "https://www.index-education.com/swie/geoloc.php")!, originalHost: "index-education.com"), "redirect host cannot change within directory allowlist")
        try check(school.allowsRedirect(to: URL(string: "https://" + schoolHost + "/next")!, originalHost: schoolHost), "same HTTPS host redirect")
        try check(!school.allowsRedirect(to: URL(string: "http://" + schoolHost + "/next")!, originalHost: schoolHost), "redirect downgrade")
    }

    private static func bridgeAndTimers() async throws {
        let probe = Probe()
        let runtime = PawnoteRuntime(testScript: script, commandTimeout: 5, onCredential: { _ in probe.record() })
        let raw = try await runtime.call("opaque", payload: empty, schoolHost: schoolHost)
        try check(raw == Data("opaque-envelope".utf8), "opaque command envelope returned unchanged")
        let random = try object(await runtime.call("random", payload: empty, schoolHost: schoolHost))
        try check(random["count"] as? Int == 64 && random["array"] as? Bool == true && random["bytes"] as? Bool == true && random["varied"] as? Bool == true, "secure byte array")
        let promise = try object(await runtime.call("promise", payload: empty, schoolHost: schoolHost))
        try check(promise["value"] as? Int == 42, "JavaScript promise microtask completes")
        let saved = try object(await runtime.call("credential", payload: empty, schoolHost: schoolHost))
        try check(saved["saved"] as? Bool == true && probe.count == 1 && !probe.onMain, "credential synchronous off main")
        let timer = try object(await runtime.call("clearTimer", payload: empty, schoolHost: schoolHost))
        try check(timer["counter"] as? Int == 1, "cancelled timer cannot complete command")
        _ = try await runtime.call("leaveTimer", payload: empty, schoolHost: schoolHost)
        let timerCount = try object(await runtime.call("timerCount", payload: empty, schoolHost: schoolHost))
        try check(timerCount["count"] as? Int == 0, "normal completion drops retained JavaScript timer callbacks")
        do {
            _ = try await runtime.call("random", payload: encoded(["count": 65537]), schoolHost: schoolHost)
            throw CheckError.failed("oversized random rejected")
        } catch let error as PawnoteRuntimeError { try check(error == .javascriptFailure, "random bound reported safely") }
        await runtime.invalidate()
        do {
            _ = try await runtime.call("echo", payload: empty, schoolHost: schoolHost)
            throw CheckError.failed("invalidated runtime cannot reconnect")
        } catch let error as PawnoteRuntimeError { try check(error == .unavailable, "revoked runtime") }
    }

    private static func networkAndCookies() async throws {
        let probe = Probe()
        let runtime = PawnoteRuntime(testScript: script, protocolClasses: [FixtureURLProtocol.self], commandTimeout: 5, onCredential: { _ in probe.record() })
        func fetch(_ path: String) async throws -> [String: Any] {
            try object(await runtime.call("fetch", payload: encoded(["url": "https://" + schoolHost + path]), schoolHost: schoolHost))
        }
        let response = try await fetch("/agent")
        try check(response["status"] as? Int == 200 && response["content"] as? String == PawnoteURLPolicy.userAgent, "Papillon mobile user agent")
        try check((response["headers"] as? [String: String])?["x-fixture"] == "ready", "lowercase response headers")
        _ = try await fetch("/set-cookie")
        let cookie = try await fetch("/read-cookie")
        try check((cookie["content"] as? String)?.contains("fixture_cookie=private") == true, "private memory cookie roundtrip")
        let other = PawnoteRuntime(testScript: script, protocolClasses: [FixtureURLProtocol.self], commandTimeout: 5, onCredential: { _ in true })
        let noCookie = try object(await other.call("fetch", payload: encoded(["url": "https://" + schoolHost + "/read-cookie"]), schoolHost: schoolHost))
        try check(noCookie["content"] as? String == "", "cookies isolated between runtimes")
        for path in ["/large", "/large-stream"] {
            let value = try await fetch(path)
            try check(value["error"] as? String == "response_too_large", "announced and streamed HTTP response caps")
        }
        let before = FixtureURLProtocol.requestCount
        let refused = try object(await runtime.call("fetch", payload: encoded(["url": "https://other.index-education.net/"]), schoolHost: schoolHost))
        try check(refused["error"] as? String == "request_not_allowed" && FixtureURLProtocol.requestCount == before, "wrong host never starts a request")
        let denied = PawnoteRuntime(testScript: script, protocolClasses: [FixtureURLProtocol.self], commandTimeout: 5, onCredential: { _ in false })
        let blocked = try object(await denied.call("persistThenFetch", payload: encoded(["url": "https://" + schoolHost + "/"]), schoolHost: schoolHost))
        try check(blocked["blocked"] as? Bool == true && FixtureURLProtocol.requestCount == before, "failed persistence blocks next step")
        await runtime.invalidate(); await other.invalidate(); await denied.invalidate()
    }

    private static func coalescingAndCancellation() async throws {
        let runtime = PawnoteRuntime(testScript: script, commandTimeout: 5, onCredential: { _ in true })
        let payload = try encoded(["delay": 80])
        async let first = runtime.call("delay", payload: payload, schoolHost: schoolHost)
        async let second = runtime.call("delay", payload: payload, schoolHost: schoolHost)
        let (a, b) = try await (first, second)
        let value = try object(a)
        try check(a == b && value["counter"] as? Int == 1, "identical calls share one JS invocation")
        let probe = Probe()
        let blocked = PawnoteRuntime(testScript: script, commandTimeout: 5, onCredential: { _ in probe.record() })
        let pending = Task { try await blocked.call("never", payload: empty, schoolHost: schoolHost) }
        for _ in 0..<200 {
            if probe.count > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try check(probe.count == 1, "pending command started")
        do {
            _ = try await blocked.call("echo", payload: empty, schoolHost: schoolHost)
            throw CheckError.failed("different command must not be queued")
        } catch let error as PawnoteRuntimeError { try check(error == .busy, "bounded command admission") }
        pending.cancel()
        do { _ = try await pending.value; throw CheckError.failed("cancelled waiter") }
        catch is CancellationError {}
        await runtime.invalidate(); await blocked.invalidate()
    }

    private static func watchdog() async throws {
        let probe = Probe()
        let runtime = PawnoteRuntime(testScript: script, commandTimeout: 0.05, onCredential: { _ in probe.record() })
        let started = Date()
        do {
            _ = try await runtime.call("spin", payload: empty, schoolHost: schoolHost)
            throw CheckError.failed("watchdog did not expire")
        } catch let error as PawnoteRuntimeError { try check(error == .timedOut, "watchdog timeout") }
        try check(Date().timeIntervalSince(started) < 0.7, "continuation timeout does not wait for JS queue")
        try await Task.sleep(for: .milliseconds(900))
        try check(probe.count == 0, "late credential callback ignored after timeout")
        let value = try await runtime.call("opaque", payload: empty, schoolHost: schoolHost)
        try check(value == Data("opaque-envelope".utf8), "runtime recovers in a fresh context")
        await runtime.invalidate()
    }

    private static func actualBundleBoot(_ path: String) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let source = String(data: data, encoding: .utf8) else { throw CheckError.failed("browser bundle UTF8") }
        // Only adds a harness diagnostic command around the real module entry;
        // Pawnote, Forge and platform.js themselves are not substituted.
        let diagnostic = #"""
        ;const realCommand = globalThis.__cadenzaCommand;
        globalThis.__cadenzaCommand = (id,command,payload) => {
          if(command !== '__harnessPlatform') return realCommand(id,command,payload);
          const bytes = crypto.getRandomValues(new Uint8Array(32));
          const url = new URL('https://fixture.index-education.net/pronote/mobile.eleve.html?existing=x');
          url.searchParams.set('probe','un caractère');
          __cadenzaNative.complete(id,JSON.stringify({count:bytes.length,bytes:[...bytes].every(x=>x>=0&&x<=255),
            varied:new Set(bytes).size>1,host:url.hostname,path:url.pathname,value:url.searchParams.get('probe'),href:url.href}));
        };
        """#
        let runtime = PawnoteRuntime(testScript: source + diagnostic, protocolClasses: [FixtureURLProtocol.self], commandTimeout: 10, onCredential: { _ in false })
        let before = FixtureURLProtocol.requestCount
        let envelope = try object(await runtime.call("logout", payload: empty, schoolHost: schoolHost))
        try check(envelope["ok"] as? Bool == true && envelope["result"] as? [String: Any] != nil, "actual bundle command envelope")
        try check(FixtureURLProtocol.requestCount == before, "actual bundle boot must not contact a school")
        let primitives = try object(await runtime.call("__harnessPlatform", payload: empty, schoolHost: schoolHost))
        try check(primitives["count"] as? Int == 32 && primitives["bytes"] as? Bool == true && primitives["varied"] as? Bool == true, "actual platform secureRandom")
        try check(primitives["host"] as? String == schoolHost && primitives["path"] as? String == "/pronote/mobile.eleve.html" && primitives["value"] as? String == "un caractère", "actual platform URL and SearchParams")
        let directory = try object(await runtime.call("discover", payload: encoded(["latitude": 0, "longitude": 0])))
        let schools = (directory["result"] as? [[String: Any]]) ?? []
        try check(directory["ok"] as? Bool == true && schools.count == 2 && schools.first?["name"] as? String == "Fixture Nearby", "real Pawnote directory mapping and distance order")
        try check(FixtureURLProtocol.requestCount == before + 1 && FixtureURLProtocol.directoryRequestsAreSafe, "directory POST stays on allowed endpoint without cookies/auth")
        await runtime.invalidate()
    }
}
