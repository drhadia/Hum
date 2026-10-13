import AppKit
import SwiftUI

/// Renders the popover offscreen so the layout can be checked without opening the menu bar.
@MainActor
enum SnapshotRenderer {
    static func write(to path: String) {
        let model = AppModel()
        model.refresh()
        if CommandLine.arguments.contains("--demo") { model.applyDemo() }
        let renderer = ImageRenderer(content: PopoverView(model: model, previewAppeared: true).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension SnapshotRenderer {
    /// Dev aid: `Hum --open` clicks the menu-bar item from inside the process, retrying until
    /// the popover window exists, and logs its frame.
    static func openPopover(attempt: Int = 0) {
        func findButton(_ view: NSView) -> NSStatusBarButton? {
            if let b = view as? NSStatusBarButton { return b }
            for sub in view.subviews { if let b = findButton(sub) { return b } }
            return nil
        }
        if let w = NSApp.windows.first(where: { $0.className.contains("MenuBarExtraWindow") && $0.isVisible }) {
            NSLog("POPOVER frame=\(w.frame)")
            return
        }
        guard attempt < 8 else { NSLog("POPOVER not opened"); return }
        for window in NSApp.windows {
            guard let content = window.contentView, findButton(content) != nil else { continue }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: 15, y: 17), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
            break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { openPopover(attempt: attempt + 1) }
    }
}

extension SnapshotRenderer {
    /// Dev aid: `Hum --window [--demo]` shows the popover content in a normal window so it
    /// can be screen-recorded. Logs the window's frame in top-left screen coordinates.
    static func showWindow() {
        let model = AppModel()
        if CommandLine.arguments.contains("--demo") { model.applyDemo() }
        model.popoverVisible = true
        let host = NSHostingView(rootView: PopoverView(model: model))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 300, y: 300))
        if CommandLine.arguments.contains("--poke") {
            // Dev aid: change a setting from the code at fixed times, so the redraw can be captured.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { model.volumeCap = 0.6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) { model.volumeCap = 0.8 }
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        let f = window.frame
        let screenH = NSScreen.main?.frame.height ?? 1080
        let contentH = host.frame.height
        NSLog("WINDOW x=\(Int(f.minX)) y=\(Int(screenH - f.maxY + (f.height - contentH))) w=\(Int(host.frame.width)) h=\(Int(contentH))")
        // keep the window and model alive
        objc_setAssociatedObject(window, "model", model, .OBJC_ASSOCIATION_RETAIN)
        windows.append(window)
    }

    nonisolated(unsafe) static var windows: [NSWindow] = []
}
