#if canImport(AppKit)
import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let cdpManager = CDPManager()
    private let codex = CodexController()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var currentState: CDPManager.ConnectionState = .stopped
    private var promptIsVisible = false
    private lazy var menuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureManager()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(codexDidLaunch),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        connectOrOfferRestart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        cdpManager.stop(removeInjection: true)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = menuBarImage
            button.toolTip = "Codex Limit Pacer"
        }
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func configureManager() {
        cdpManager.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.currentState = state
            self.rebuildMenu()
            if state == .restartRequired, CodexAppLocator.runningApplication() != nil {
                self.presentRestartExplanation()
            }
        }
    }

    private func connectOrOfferRestart() {
        cdpManager.start(port: AppPreferences.debugPort)
    }

    private func presentRestartExplanation() {
        guard !promptIsVisible else { return }
        promptIsVisible = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Restart Codex to place Limit Pacer inside the menu"
        alert.informativeText = "A real element between Usage and Show pet requires Codex to start with local menu access. Running Codex work will be interrupted, so restart only when it is safe."
        alert.addButton(withTitle: "Restart Codex now")
        alert.addButton(withTitle: "Later")
        let result = alert.runModal()
        promptIsVisible = false
        if result == .alertFirstButtonReturn { restartCodex(showConfirmation: false) }
    }

    private func restartCodex(showConfirmation: Bool) {
        if showConfirmation, CodexAppLocator.runningApplication() != nil {
            NSApp.activate(ignoringOtherApps: true)
            let warning = NSAlert()
            warning.alertStyle = .warning
            warning.messageText = "Restart Codex now?"
            warning.informativeText = "Any currently running Codex task may be interrupted."
            warning.addButton(withTitle: "Restart")
            warning.addButton(withTitle: "Cancel")
            guard warning.runModal() == .alertFirstButtonReturn else { return }
        }

        currentState = .connecting
        rebuildMenu()
        cdpManager.stop(removeInjection: true)
        let port = AppPreferences.debugPort
        codex.restartWithDebugging(port: port) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.currentState = .connecting
                self.rebuildMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    self.cdpManager.start(port: port)
                }
            case .failure(let error):
                self.currentState = .unavailable(error.localizedDescription)
                self.rebuildMenu()
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Codex Limit Pacer could not start"
        alert.informativeText = message
        alert.runModal()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        guard menu != nil else { return }
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())
        let restart = NSMenuItem(title: "Restart Codex with menu access…", action: #selector(restartAction), keyEquivalent: "r")
        restart.target = self
        menu.addItem(restart)

        let open = NSMenuItem(title: "Open Codex", action: #selector(openCodexAction), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let launch = NSMenuItem(title: "Open Limit Pacer at Login", action: #selector(toggleLoginAction), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(launch)

        let about = NSMenuItem(title: "About Codex Limit Pacer…", action: #selector(aboutAction), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let uninstall = NSMenuItem(title: "Uninstall Limit Pacer…", action: #selector(uninstallAction), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        let quit = NSMenuItem(title: "Quit Limit Pacer", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private var statusText: String {
        switch currentState {
        case .stopped: return "Limit Pacer stopped"
        case .connecting: return "Connecting to Codex…"
        case .active(let detail): return "Active · \(detail)"
        case .waitingForMenu: return "Connected · open the account menu"
        case .restartRequired: return "Restart Codex once to restore menu access"
        case .unavailable(let detail): return detail
        }
    }

    @objc private func codexDidLaunch(_ notification: Notification) {
        guard currentState == .restartRequired,
              let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier == "com.openai.codex" else { return }
        presentRestartExplanation()
    }

    @objc private func restartAction() { restartCodex(showConfirmation: true) }
    @objc private func openCodexAction() { codex.activateCodex() }
    @objc private func toggleLoginAction() {
        _ = LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
        rebuildMenu()
    }

    @objc private func aboutAction() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Codex Limit Pacer"
        alert.informativeText = "Version \(version)\nBuilt by Lukas van Uden\n\nIndependent, unofficial, and not affiliated with OpenAI."
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "X")
        alert.addButton(withTitle: "LinkedIn")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://x.com/LukasvanUden")!)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://www.linkedin.com/in/lukas-van-uden/")!)
        default:
            break
        }
    }

    @objc private func quitAction() { NSApp.terminate(nil) }

    @objc private func uninstallAction() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Codex Limit Pacer?"
        alert.informativeText = "This removes the helper, its login item, and the injected menu elements. Codex itself is not changed."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cdpManager.stop(removeInjection: true)
        _ = LoginItemManager.setEnabled(false)
        let appPath = Bundle.main.bundlePath
        let preferencesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(limitPacerBundleIdentifier).plist").path
        let script = """
        sleep 1
        /bin/rm -rf \(shellQuote(appPath))
        /bin/rm -f \(shellQuote(preferencesPath))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        NSApp.terminate(nil)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
