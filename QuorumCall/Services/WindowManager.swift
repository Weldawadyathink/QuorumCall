import AppKit
import ApplicationServices
import CoreGraphics

// Private API: gets the CGWindowID for an AXUIElement without Screen Recording permission.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct FocusedWindowSnapshot {
    let bundleID: String
    let appName: String
    let windowTitle: String
    let cgWindowID: UInt32?
}

@Observable
final class WindowManager {
    private(set) var lastFrontmostSnapshot: FocusedWindowSnapshot?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func activeAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastFrontmostSnapshot = snapshot(for: app)
    }

    private func snapshot(for app: NSRunningApplication) -> FocusedWindowSnapshot {
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? bundleID

        guard AXIsProcessTrusted() else {
            return FocusedWindowSnapshot(bundleID: bundleID, appName: appName, windowTitle: "", cgWindowID: nil)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)

        var title = ""
        var windowID: UInt32? = nil
        if err == .success, let axWindow = windowRef {
            let axWin = axWindow as! AXUIElement
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
            title = (titleRef as? String) ?? ""
            windowID = cgWindowID(for: axWin)
        }

        return FocusedWindowSnapshot(bundleID: bundleID, appName: appName, windowTitle: title, cgWindowID: windowID)
    }

    func activate(quorum: Quorum) {
        guard !quorum.windows.isEmpty else { return }
        guard AXIsProcessTrusted() else { return }

        // Activate all unique apps first
        let uniqueBundleIDs = Set(quorum.windows.map { $0.appBundleID })
        for bundleID in uniqueBundleIDs {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID })?
                .activate()
        }

        // Raise individual windows (last one ends up frontmost)
        for window in quorum.windows {
            raiseWindow(matching: window)
        }
    }

    private func raiseWindow(matching record: QuorumWindow) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == record.appBundleID
        }) else { return }

        app.activate()

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        // Try CGWindowID match first — stable across title changes
        if let storedID = record.cgWindowID,
           let axWin = axWindows.first(where: { cgWindowID(for: $0) == storedID }) {
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            return
        }

        // Fall back to fuzzy title matching
        let best = axWindows
            .compactMap { axWin -> (AXUIElement, Int)? in
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                guard let title = titleRef as? String else { return nil }
                return (axWin, titleMatchScore(candidate: title, target: record.windowTitle))
            }
            .max(by: { $0.1 < $1.1 })

        if let (win, _) = best {
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            // Refresh stored CGWindowID so future activations use the stable path
            record.cgWindowID = cgWindowID(for: win)
        }
    }

    private func cgWindowID(for element: AXUIElement) -> UInt32? {
        var windowID = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &windowID) == .success else { return nil }
        return windowID
    }

    private func titleMatchScore(candidate: String, target: String) -> Int {
        guard !target.isEmpty else { return 0 }
        if candidate == target { return 3 }
        if candidate.contains(target) || target.contains(candidate) { return 2 }
        return longestCommonSubstringLength(candidate, target) > 4 ? 1 : 0
    }

    private func longestCommonSubstringLength(_ a: String, _ b: String) -> Int {
        let aArr = Array(a), bArr = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: bArr.count + 1), count: aArr.count + 1)
        var maxLen = 0
        for i in 1...aArr.count {
            for j in 1...bArr.count {
                if aArr[i-1] == bArr[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                    maxLen = max(maxLen, dp[i][j])
                }
            }
        }
        return maxLen
    }
}
