import Cocoa

class OptionKeyMonitor {
    var onDoubleTap: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastKeyDownTime: Date?
    private var isHolding = false
    private var holdTimer: Timer?
    private var isEnabled = false

    func start() {
        guard !isEnabled else { return }
        isEnabled = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        holdTimer?.invalidate()
        holdTimer = nil
        isEnabled = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Right Option key = keyCode 61
        let rightOptionPressed = event.modifierFlags.contains(.option) && event.keyCode == 61

        if rightOptionPressed {
            handleKeyDown()
        } else if isHolding || lastKeyDownTime != nil {
            handleKeyUp()
        }
    }

    private func handleKeyDown() {
        let now = Date()

        if let lastDown = lastKeyDownTime, now.timeIntervalSince(lastDown) < 0.3 {
            // Double tap detected
            holdTimer?.invalidate()
            holdTimer = nil
            lastKeyDownTime = nil
            isHolding = false
            onDoubleTap?()
            return
        }

        lastKeyDownTime = now

        // Start a timer; if key is still held after 300ms, it is push-to-talk
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isHolding = true
            self.onHoldStart?()
        }
    }

    private func handleKeyUp() {
        holdTimer?.invalidate()
        holdTimer = nil

        if isHolding {
            // Was push-to-talk, release stops recording
            isHolding = false
            lastKeyDownTime = nil
            onHoldEnd?()
        } else {
            // Quick tap, not a hold. Keep lastKeyDownTime for double-tap detection,
            // then clear it after the double-tap window expires.
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.lastKeyDownTime = nil
            }
        }
    }

    deinit {
        stop()
    }
}
