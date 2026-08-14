#if canImport(AppKit)
import AppKit
import Foundation

struct CodexAppLocator {
    static func runningApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == "com.openai.codex"
        }
    }

    static func applicationURL() -> URL? {
        if let running = runningApplication(), let url = running.bundleURL { return url }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { return url }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            home.appendingPathComponent("Applications/Codex.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/ChatGPT.app"),
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return found }
        return nil
    }
}

final class CodexController {
    enum RestartError: LocalizedError {
        case appNotFound
        case couldNotQuit
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotFound: return "Codex.app was not found."
            case .couldNotQuit: return "Codex could not be closed automatically."
            case .launchFailed(let message): return "Codex could not be launched: \(message)"
            }
        }
    }

    func restartWithDebugging(port: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let appURL = CodexAppLocator.applicationURL() else {
            completion(.failure(RestartError.appNotFound)); return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let running = CodexAppLocator.runningApplication() {
                _ = running.terminate()
                let deadline = Date().addingTimeInterval(14)
                while !running.isTerminated && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
                if !running.isTerminated {
                    DispatchQueue.main.async { completion(.failure(RestartError.couldNotQuit)) }
                    return
                }
            }

            Thread.sleep(forTimeInterval: 0.4)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [
                "-na", appURL.path, "--args",
                "--remote-debugging-port=\(port)",
                "--remote-debugging-address=127.0.0.1"
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw RestartError.launchFailed("open exited with status \(process.terminationStatus)")
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func activateCodex() {
        if let running = CodexAppLocator.runningApplication() {
            running.activate(options: [.activateIgnoringOtherApps])
        } else if let url = CodexAppLocator.applicationURL() {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
    }
}
#endif
