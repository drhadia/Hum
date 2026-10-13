import AppKit
import ApplicationServices

/// Reads what the Home app shows on screen, through the macOS Accessibility API.
/// Needs the Accessibility permission for this app, which only the user can grant.
enum HomeAX {
    static let bundleID = "com.apple.Home"

    // MARK: Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security > Accessibility.
    @discardableResult
    static func promptForTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Home app

    static var homePID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    // MARK: Attributes

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        if let s = attribute(element, name) as? String, !s.isEmpty { return s }
        if let n = attribute(element, name) as? NSNumber { return n.stringValue }
        return nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    // MARK: Dump (dev aid)

    /// A readable outline of everything the Home app exposes, so a reader can be written against it.
    static func dump(maxDepth: Int = 24, maxNodes: Int = 4000) -> String {
        guard isTrusted else { return "NOT TRUSTED: grant Accessibility to Hum in System Settings, then run again.\n" }
        guard let pid = homePID else { return "Home app is not running.\n" }
        let app = AXUIElementCreateApplication(pid)
        var out = ""
        var count = 0

        func line(_ el: AXUIElement, _ depth: Int) {
            guard count < maxNodes, depth <= maxDepth else { return }
            count += 1
            var parts: [String] = []
            if let role = string(el, kAXRoleAttribute) { parts.append(role.replacingOccurrences(of: "AX", with: "")) }
            if let sub = string(el, kAXSubroleAttribute) { parts.append("(\(sub.replacingOccurrences(of: "AX", with: "")))") }
            for (label, attr) in [("title", kAXTitleAttribute), ("value", kAXValueAttribute), ("desc", kAXDescriptionAttribute),
                                  ("help", kAXHelpAttribute), ("id", kAXIdentifierAttribute)] {
                if let s = string(el, attr) { parts.append("\(label)=\"\(s.replacingOccurrences(of: "\n", with: " "))\"") }
            }
            out += String(repeating: "  ", count: depth) + parts.joined(separator: " ") + "\n"
            for child in children(el) { line(child, depth + 1) }
        }

        let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        out += "Home app: \(windows.count) window(s)\n"
        for window in windows { line(window, 0) }
        if windows.isEmpty { line(app, 0) }
        return out
    }

    // MARK: Actions (dev aid / reader)

    /// Finds the first element whose identifier matches `matches` and returns it.
    static func find(in root: AXUIElement, maxDepth: Int = 24, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        func walk(_ el: AXUIElement, _ depth: Int) -> AXUIElement? {
            if matches(el) { return el }
            guard depth < maxDepth else { return nil }
            for child in children(el) { if let hit = walk(child, depth + 1) { return hit } }
            return nil
        }
        return walk(root, 0)
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func appElement() -> AXUIElement? { homePID.map { AXUIElementCreateApplication($0) } }

    /// Searches every window of the Home app.
    static func findInWindows(where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        guard let app = appElement() else { return nil }
        for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            if let hit = find(in: window, where: matches) { return hit }
        }
        return nil
    }

    static func windows() -> [AXUIElement] {
        guard let app = appElement() else { return [] }
        return (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Every accessibility description in the Home app's windows, e.g. "Humidity, 62%".
    static func descriptions(maxNodes: Int = 600) -> [String] {
        var out: [String] = []
        var count = 0
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard count < maxNodes, depth < 24 else { return }
            count += 1
            if let d = string(el, kAXDescriptionAttribute) { out.append(d) }
            for child in children(el) { walk(child, depth + 1) }
        }
        for window in windows() { walk(window, 0) }
        return out
    }
}
