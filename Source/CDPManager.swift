#if canImport(AppKit)
import Foundation

struct DebugTarget: Decodable {
    let id: String
    let type: String
    let title: String?
    let url: String?
    let webSocketDebuggerUrl: String?
}

struct LimitPacerRendererStatus {
    let state: String
    let usedPercent: Double?
    let elapsedPercent: Double?
    let delta: Double?

    init?(dictionary: JSONDictionary) {
        guard let state = dictionary["state"] as? String else { return nil }
        self.state = state
        usedPercent = dictionary["usedPercent"] as? Double ?? (dictionary["usedPercent"] as? Int).map(Double.init)
        elapsedPercent = dictionary["elapsedPercent"] as? Double ?? (dictionary["elapsedPercent"] as? Int).map(Double.init)
        delta = dictionary["delta"] as? Double ?? (dictionary["delta"] as? Int).map(Double.init)
    }
}

final class CDPManager {
    enum ConnectionState: Equatable {
        case stopped
        case connecting
        case active(String)
        case waitingForMenu
        case unavailable(String)
    }

    var onStateChanged: ((ConnectionState) -> Void)?
    private let queue = DispatchQueue(label: "studio.morje.codexlimitpacer.cdp.manager", qos: .userInitiated)
    private let session: URLSession
    private var timer: DispatchSourceTimer?
    private var connections: [String: CDPConnection] = [:]
    private var port: Int?
    private var injectorSource = ""
    private var pollingTargets = false
    private var targetFailureCount = 0
    private var lastState: ConnectionState = .stopped

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        session = URLSession(configuration: configuration)
        if let url = Bundle.main.url(forResource: "injector", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            injectorSource = source
        }
    }

    static func probe(port: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/version") else { completion(false); return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: configuration)
        session.dataTask(with: url) { data, response, _ in
            let okay = data != nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(okay) }
            session.invalidateAndCancel()
        }.resume()
    }

    func start(port: Int) {
        stop(removeInjection: false)
        self.port = port
        updateState(.connecting)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.5)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func stop(removeInjection: Bool = true) {
        timer?.cancel(); timer = nil
        let current = connections.values
        connections.removeAll()
        if removeInjection {
            current.forEach { connection in
                connection.evaluate("globalThis.__codexLimitPacerMod?.destroy?.();") { _ in connection.close() }
            }
        } else {
            current.forEach { $0.close() }
        }
        port = nil
        updateState(.stopped)
    }

    private func tick() {
        guard !pollingTargets, let port else { return }
        pollingTargets = true
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/list") else {
            pollingTargets = false; return
        }
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                self.pollingTargets = false
                guard error == nil,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let data,
                      let targets = try? JSONDecoder().decode([DebugTarget].self, from: data) else {
                    self.targetFailureCount += 1
                    if self.targetFailureCount >= 4 {
                        self.updateState(.unavailable("Codex is not running with menu access"))
                    }
                    return
                }
                self.targetFailureCount = 0
                self.syncTargets(targets)
                self.pollStatuses()
            }
        }.resume()
    }

    private func syncTargets(_ targets: [DebugTarget]) {
        let usable = targets.filter { target in
            (target.type == "page" || target.type == "webview") && target.webSocketDebuggerUrl != nil
        }
        let currentIDs = Set(usable.map(\.id))
        let staleIDs = connections.keys.filter { !currentIDs.contains($0) }
        for id in staleIDs {
            connections.removeValue(forKey: id)?.close()
        }

        for target in usable where connections[target.id] == nil {
            guard let rawURL = target.webSocketDebuggerUrl, let url = URL(string: rawURL) else { continue }
            let connection = CDPConnection(targetID: target.id, title: target.title ?? "Renderer", webSocketURL: url)
            connections[target.id] = connection
            inject(into: connection)
        }

        if connections.isEmpty { updateState(.connecting) }
    }

    private func inject(into connection: CDPConnection) {
        guard !injectorSource.isEmpty else {
            updateState(.unavailable("The injector resource is missing")); return
        }
        connection.send(method: "Runtime.enable")
        connection.send(method: "Page.enable")
        connection.send(method: "Page.addScriptToEvaluateOnNewDocument", params: ["source": injectorSource])
        connection.evaluate(injectorSource) { [weak self, weak connection] _ in
            guard let self, let connection else { return }
            self.queue.async { self.pollStatus(connection) }
        }
    }

    private func pollStatuses() {
        guard !connections.isEmpty else { return }
        connections.values.forEach { pollStatus($0) }
    }

    private func pollStatus(_ connection: CDPConnection) {
        connection.evaluate("globalThis.__codexLimitPacerMod?.getStatus?.() ?? null") { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard case .success(let value) = result,
                      let dictionary = value as? JSONDictionary,
                      let status = LimitPacerRendererStatus(dictionary: dictionary) else { return }
                self.handle(status)
            }
        }
    }

    private func handle(_ status: LimitPacerRendererStatus) {
        switch status.state {
        case "active":
            let used = Int((status.usedPercent ?? 0).rounded())
            let elapsed = Int((status.elapsedPercent ?? 0).rounded())
            let delta = Int((status.delta ?? 0).rounded())
            let pace: String
            if abs(delta) <= 4 { pace = "on pace" }
            else if delta > 0 { pace = "\(abs(delta)) pp fast" }
            else { pace = "\(abs(delta)) pp below" }
            updateState(.active("\(used)% used · \(elapsed)% week · \(pace)"))
        case "loading-usage":
            updateState(.active("Reading weekly usage…"))
        case "usage-unavailable":
            updateState(.unavailable("Could not read weekly Codex usage"))
        default:
            if case .active = lastState { return }
            updateState(.waitingForMenu)
        }
    }

    private func updateState(_ state: ConnectionState) {
        guard state != lastState else { return }
        lastState = state
        DispatchQueue.main.async { [weak self] in self?.onStateChanged?(state) }
    }
}
#endif
