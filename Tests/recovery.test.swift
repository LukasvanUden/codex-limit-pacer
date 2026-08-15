#if canImport(AppKit)
import Foundation

@main
struct RecoveryTest {
    static func main() throws {
        let chromeCandidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
        ]
        guard let chromePath = chromeCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            print("SKIP: Chrome or Chromium is required for the recovery test")
            return
        }

        let port = LocalPortPicker.pickPreferredPort()
        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-limit-pacer-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }

        func launchChrome() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: chromePath)
            process.arguments = [
                "--headless=new",
                "--no-first-run",
                "--no-default-browser-check",
                "--remote-debugging-address=127.0.0.1",
                "--remote-debugging-port=\(port)",
                "--user-data-dir=\(profile.path)",
                "about:blank",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }

        func endpointAvailable() -> Bool {
            guard let url = URL(string: "http://127.0.0.1:\(port)/json/version") else { return false }
            return (try? Data(contentsOf: url)) != nil
        }

        func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            return condition()
        }

        func evaluate(_ expression: String) throws -> Any? {
            let listURL = URL(string: "http://127.0.0.1:\(port)/json/list")!
            let targets = try JSONDecoder().decode([DebugTarget].self, from: Data(contentsOf: listURL))
            guard let target = targets.first(where: { $0.type == "page" }),
                  let rawURL = target.webSocketDebuggerUrl,
                  let webSocketURL = URL(string: rawURL) else {
                throw TestError.failed("Chrome renderer target was unavailable")
            }
            let connection = CDPConnection(targetID: target.id, title: "recovery-audit", webSocketURL: webSocketURL)
            defer { connection.close() }
            var completed = false
            var outcome: Result<Any?, Error>?
            connection.evaluate(expression) { result in
                outcome = result
                completed = true
            }
            guard wait(timeout: 6, until: { completed }), let outcome else {
                throw TestError.failed("Renderer evaluation timed out")
            }
            return try outcome.get()
        }

        let injector = """
        globalThis.__codexLimitPacerMod = {
          version: 'recovery-test',
          refresh() {},
          destroy() { delete globalThis.__codexLimitPacerMod; },
          getStatus() { return { state: 'active', usedPercent: 10, elapsedPercent: 20, delta: -10 }; }
        };
        """
        let manager = CDPManager(injectorSource: injector)
        let lock = NSLock()
        var activeCount = 0
        var restartRequired = false
        manager.onStateChanged = { state in
            lock.lock()
            defer { lock.unlock() }
            if case .active = state { activeCount += 1 }
            if state == .restartRequired { restartRequired = true }
        }

        var chrome = try launchChrome()
        defer {
            manager.stop(removeInjection: false)
            if chrome.isRunning { chrome.terminate() }
        }
        guard wait(timeout: 8, until: endpointAvailable) else {
            throw TestError.failed("Chrome debug endpoint did not start")
        }

        manager.start(port: port)
        guard wait(timeout: 10, until: {
            lock.lock(); defer { lock.unlock() }
            return activeCount >= 1
        }) else {
            throw TestError.failed("Pacer did not connect to the first renderer")
        }

        _ = try evaluate("delete globalThis.__codexLimitPacerMod; true")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        guard try evaluate("Boolean(globalThis.__codexLimitPacerMod)") as? Bool == true else {
            throw TestError.failed("Pacer did not restore a missing renderer injection")
        }

        chrome.terminate()
        chrome.waitUntilExit()
        guard wait(timeout: 15, until: {
            lock.lock(); defer { lock.unlock() }
            return restartRequired
        }) else {
            throw TestError.failed("Pacer did not detect the lost debug endpoint")
        }

        chrome = try launchChrome()
        guard wait(timeout: 8, until: endpointAvailable) else {
            throw TestError.failed("Chrome debug endpoint did not restart")
        }
        guard wait(timeout: 12, until: {
            lock.lock(); defer { lock.unlock() }
            return activeCount >= 2
        }) else {
            throw TestError.failed("Pacer did not reconnect after the renderer restart")
        }

        print("PASS: restored a missing injection, detected endpoint loss, and reconnected automatically")
    }

    enum TestError: Error {
        case failed(String)
    }
}
#endif
