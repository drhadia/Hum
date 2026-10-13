import AppKit
import ApplicationServices

/// Reads temperature and humidity from the Home app's Climate page through Accessibility.
///
/// The Home app shows both numbers, which come from the HomePod mini's sensor, and there is no public
/// way to get them any other way. Humidity only appears on the Climate page, and the Home window must be
/// visible to navigate there, but once it's showing that page it keeps exposing the numbers while hidden.
/// So: show Home briefly once to open the page, hide it again, then just read every 30 seconds.
///
/// Home averages every temperature and humidity sensor in the home. With a single HomePod mini that is
/// that sensor.
final class HomeClimateSource: ClimateSource {
    private let queue = DispatchQueue(label: "Hum.homeclimate", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var onReading: (@MainActor (ClimateReading) -> Void)?
    private var lastHumidity: Double?

    func start(_ onReading: @escaping @MainActor (ClimateReading) -> Void) {
        self.onReading = onReading
        queue.async { [self] in
            if !publish() { park(); publish() }
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in self?.publish() }
        t.resume()
        timer = t
    }

    deinit { timer?.cancel() }

    /// Re-opens the Climate page (briefly showing the Home app) and reads again.
    func refresh() {
        queue.async { [self] in
            park()
            publish()
        }
    }

    // MARK: Reading

    @discardableResult
    private func publish() -> Bool {
        guard HomeAX.isTrusted, let reading = Self.read(fallbackHumidity: lastHumidity) else { return false }
        lastHumidity = reading.humidity
        let handler = onReading
        DispatchQueue.main.async { MainActor.assumeIsolated { handler?(reading) } }
        return true
    }

    /// Temperature comes from either page; humidity only from the Climate page.
    static func read(fallbackHumidity: Double?) -> ClimateReading? {
        var temperature: Double?
        var humidity: Double?
        for d in HomeAX.descriptions() {
            if d.hasPrefix("Temperature, ") { temperature = number(d.dropFirst("Temperature, ".count)) }
            else if d.hasPrefix("Humidity, ") { humidity = number(d.dropFirst("Humidity, ".count)) }
            else if temperature == nil, d.hasPrefix("Show Climate, ") { temperature = number(d.dropFirst("Show Climate, ".count)) }
        }
        guard var t = temperature, let h = humidity ?? fallbackHumidity else { return nil }
        // Home prints just "28.5°" in the region's unit; no room is above 50 degrees Celsius.
        if t >= 50 { t = (t - 32) * 5 / 9 }
        return ClimateReading(temperatureC: t, humidity: h, date: Date())
    }

    private static func number(_ text: Substring) -> Double? {
        Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.-").inverted))
    }

    // MARK: Navigating

    private static func onClimatePage() -> Bool { HomeAX.descriptions().contains { $0.hasPrefix("Humidity, ") } }

    private static func pressBack() -> Bool {
        guard let back = HomeAX.findInWindows(where: {
            HomeAX.string($0, kAXDescriptionAttribute) == "Back" && HomeAX.string($0, kAXRoleAttribute) == "AXButton"
        }) else { return false }
        return HomeAX.press(back)
    }

    private static func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    /// Opens the Climate page and leaves the Home app hidden. Skipped while the user is using Home.
    private func park() {
        guard HomeAX.isTrusted else { return }
        var app = NSRunningApplication.runningApplications(withBundleIdentifier: HomeAX.bundleID).first
        if app == nil {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.hides = true
            config.addsToRecentItems = false
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Home.app"), configuration: config) { launched, _ in
                app = launched
                done.signal()
            }
            _ = done.wait(timeout: .now() + 8)
            Self.pause(2)
        }
        guard let app, !app.isActive else { return }   // the user is in the Home app right now; don't touch it

        let wasHidden = app.isHidden
        DispatchQueue.main.sync { _ = app.unhide() }
        defer { if wasHidden || true { DispatchQueue.main.sync { _ = app.hide() } } }

        // wait for a window, then walk back to the main page if we're deeper in the app
        for _ in 0..<10 where HomeAX.windows().isEmpty { Self.pause(0.4) }
        if Self.onClimatePage() { return }
        for _ in 0..<3 where Self.pressBack() { Self.pause(0.8) }

        guard let chip = HomeAX.findInWindows(where: {
            HomeAX.string($0, kAXIdentifierAttribute) == "Home.Status.Category.Climate" && HomeAX.string($0, kAXRoleAttribute) == "AXButton"
        }) else { return }
        _ = HomeAX.press(chip)
        for _ in 0..<8 where !Self.onClimatePage() { Self.pause(0.4) }
    }
}
