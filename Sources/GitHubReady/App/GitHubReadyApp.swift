import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusIconSize: CGFloat = 30
    private var statusItem: NSStatusItem?
    private let statusPopover = NSPopover()
    private var statusObservation: AnyCancellable?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureStatusItem()
        Task { await AppStore.shared.refresh() }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: statusIconSize)
        item.button?.target = self
        item.button?.action = #selector(toggleStatusPopover)
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        statusItem = item

        statusPopover.behavior = .transient
        statusPopover.animates = true
        statusPopover.contentSize = NSSize(width: 400, height: 448)
        statusPopover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(store: AppStore.shared)
        )
        installPopoverDismissalMonitors()

        statusObservation = AppStore.shared.$snapshot
            .map(\.visualState)
            .removeDuplicates()
            .sink { [weak self] visualState in
                self?.updateStatusItem(for: visualState)
            }
    }

    private func installPopoverDismissalMonitors() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.statusPopover.isShown else { return event }
            guard !self.isInsidePopover(event), !self.isOnStatusButton(event) else { return event }
            self.statusPopover.performClose(nil)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.statusPopover.isShown, !self.isOnStatusButton(event) else { return }
            Task { @MainActor [weak self] in
                self?.statusPopover.performClose(nil)
            }
        }
    }

    private func isInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = statusPopover.contentViewController?.view.window else { return false }
        return popoverWindow.frame.contains(screenLocation(for: event))
    }

    private func isOnStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        return window.convertToScreen(button.frame).contains(screenLocation(for: event))
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }

    private func updateStatusItem(for visualState: MenuVisualState) {
        guard let button = statusItem?.button else { return }
        button.image = brandStatusImage()
        button.toolTip = "GitHub Ready: \(visualState.title)"
    }

    private func brandStatusImage() -> NSImage {
        if let iconURL = Bundle.main.url(forResource: "GitHubReadyStatusIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: statusIconSize, height: statusIconSize)
            icon.isTemplate = false
            return icon
        }

        return fallbackStatusImage()
    }

    private func fallbackStatusImage() -> NSImage {
        let size = NSSize(width: statusIconSize, height: statusIconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 1.55
            let nodeRadius: CGFloat = 3.0
            let sourceTop = CGPoint(x: 5.2, y: 14.5)
            let sourceBottom = CGPoint(x: 5.2, y: 5.2)
            let readyNode = CGPoint(x: 14.7, y: 7.9)

            NSColor.white.setStroke()
            let branch = NSBezierPath()
            branch.move(to: sourceTop)
            branch.line(to: CGPoint(x: sourceTop.x, y: sourceBottom.y))
            branch.line(to: CGPoint(x: 12.0, y: sourceBottom.y))
            branch.curve(
                to: readyNode,
                controlPoint1: CGPoint(x: 14.0, y: sourceBottom.y),
                controlPoint2: CGPoint(x: 14.7, y: 6.2)
            )
            branch.lineWidth = lineWidth
            branch.lineCapStyle = .round
            branch.lineJoinStyle = .round
            branch.stroke()

            for point in [sourceTop, sourceBottom] {
                let circle = NSBezierPath(
                    ovalIn: CGRect(
                        x: point.x - nodeRadius,
                        y: point.y - nodeRadius,
                        width: nodeRadius * 2,
                        height: nodeRadius * 2
                    )
                )
                circle.lineWidth = lineWidth
                circle.stroke()
            }

            NSColor.white.setFill()
            NSBezierPath(
                ovalIn: CGRect(
                    x: readyNode.x - nodeRadius,
                    y: readyNode.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
            ).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func toggleStatusPopover() {
        guard let button = statusItem?.button else { return }
        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@main
struct GitHubReadyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup("GitHub Ready", id: "main") {
            MainWindowView(store: store)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)

        Window("GitHub Ready Details", id: "details") {
            DetailStatusView(store: store)
        }
        .defaultSize(width: 620, height: 560)
    }
}
