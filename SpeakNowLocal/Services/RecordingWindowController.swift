import AppKit
import SwiftUI

class RecordingWindowController {
    static let shared = RecordingWindowController()
    private var window: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    private let windowWidth: CGFloat = 120
    private let windowHeight: CGFloat = 180
    private let collapsedWidth: CGFloat = 40
    private var isCollapsed = false

    func show(appState: AppState) {
        if let existing = window, existing.isVisible {
            existing.orderFront(nil)
            return
        }

        let contentView = RecordingFloaterView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: AnyView(contentView))

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Position: bottom-right of main screen, slightly inset
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - windowWidth - 20
            let y = screenFrame.minY + 100
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
        self.hostingView = hostingView
        self.isCollapsed = false
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }

    func collapse() {
        guard let window = window, !isCollapsed else { return }
        isCollapsed = true
        let frame = window.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(
                NSRect(x: frame.maxX - collapsedWidth, y: frame.origin.y, width: collapsedWidth, height: 60),
                display: true
            )
        }
    }

    func expand() {
        guard let window = window, isCollapsed else { return }
        isCollapsed = false
        let frame = window.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(
                NSRect(x: frame.origin.x - (windowWidth - collapsedWidth), y: frame.origin.y, width: windowWidth, height: windowHeight),
                display: true
            )
        }
    }

    func toggleCollapse() {
        if isCollapsed { expand() } else { collapse() }
    }
}
