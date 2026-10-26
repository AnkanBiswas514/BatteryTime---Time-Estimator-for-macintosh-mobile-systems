import AppKit
import Combine
import SwiftUI

// A real NSStatusItem owns the click handling. This avoids relying on a
// MenuBarExtra window's activation behavior in exported LSUIElement apps.
@main
struct BatteryTimeApp: App {
    @NSApplicationDelegateAdaptor(BatteryAppDelegate.self) private var delegate

    var body: some Scene {
        // A Settings scene keeps SwiftUI's app lifecycle valid. The visible
        // preferences window is managed explicitly by the app delegate.
        Settings {
            PreferencesView()
        }
    }
}

@MainActor
final class BatteryAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = BatteryModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: BatteryPopover(model: model, openSettings: { [weak self] in
                self?.showSettings()
            })
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // Published values update after objectWillChange; defer to next main runloop.
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        updateStatusItem()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let percent = model.reading.percent
        let charging = model.reading.powerState == .charging
        let lowPower = model.lowPowerModeEnabled == true
        let color: NSColor = lowPower ? .systemYellow : (charging ? .systemGreen : .labelColor)
        let showIcon = defaults.object(forKey: "showMenuIcon") as? Bool ?? true
        button.image = showIcon ? BatteryStatusIcon.make(percent: percent, color: color, charging: charging) : nil
        button.imagePosition = .imageLeading
        // Percentage is drawn INSIDE the battery, so don't repeat it outside.
        var parts: [String] = []
        if defaults.object(forKey: "showMenuEstimate") as? Bool ?? true { parts.append(model.estimateText) }
        if defaults.object(forKey: "showMenuPower") as? Bool ?? true { parts.append(model.powerText) }
        button.title = parts.joined(separator: " · ")
        if !showIcon && parts.isEmpty { button.title = "BatteryTime" }
        button.toolTip = "BatteryTime — \(percent.map { "\($0)%" } ?? "Unknown") · \(model.reading.powerState.rawValue)"
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: controller)
            window.title = "BatteryTime Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 500))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private enum BatteryStatusIcon {
    // Non-template NSImage preserves yellow/green instead of being recolored
    // monochrome by the system menu bar.
    static func make(percent: Int?, color: NSColor, charging: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 39, height: 18), flipped: false) { bounds in
            let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 34, height: 14), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.4
            color.setStroke()
            outline.stroke()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 35.5, y: 6, width: 2.5, height: 6), xRadius: 1, yRadius: 1).fill()
            if let percent {
                let fraction = CGFloat(max(0, min(100, percent))) / 100
                let fill = NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: max(0, 30 * fraction), height: 10), xRadius: 1.5, yRadius: 1.5)
                color.withAlphaComponent(0.30).setFill()
                fill.fill()
            }
            let label = percent.map(String.init) ?? "–"
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: 18 - size.width / 2, y: 9 - size.height / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
    }
}
