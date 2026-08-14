#if canImport(AppKit)
import AppKit
import Foundation
import Darwin

let limitPacerBundleIdentifier = "studio.morje.codexusagepace"

enum PreferenceKeys {
    static let debugPort = "debugPortV3"
}

enum AppPreferences {
    static var debugPort: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: PreferenceKeys.debugPort)
            if (40000...59999).contains(stored) { return stored }
            let selected = LocalPortPicker.pickPreferredPort()
            UserDefaults.standard.set(selected, forKey: PreferenceKeys.debugPort)
            return selected
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKeys.debugPort) }
    }

}

enum LocalPortPicker {
    static func pickPreferredPort() -> Int {
        for _ in 0..<80 {
            let candidate = Int.random(in: 43100...58900)
            if isFree(candidate) { return candidate }
        }
        return 49273
    }

    private static func isFree(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

enum LoginItemManager {
    static let label = limitPacerBundleIdentifier

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: launchAgentURL.path) }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard let executable = Bundle.main.executablePath else { return false }
            do {
                try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let plist: [String: Any] = [
                    "Label": label,
                    "ProgramArguments": [executable],
                    "RunAtLoad": true,
                    "KeepAlive": false,
                    "LimitLoadToSessionType": "Aqua",
                    "ProcessType": "Interactive"
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: launchAgentURL, options: .atomic)
                return true
            } catch { return false }
        }

        bootOutIfLoaded()
        do {
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
            return true
        } catch { return false }
    }

    static func bootOutIfLoaded() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", launchAgentURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
#endif
