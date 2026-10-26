import AppKit
import Combine
import SwiftUI

@MainActor
final class TokenPeekAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: 122)
    private let popover = NSPopover()
    private var modelObserver: AnyCancellable?
    private weak var statusTextField: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        model.start()
        updateStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.image = nil
        button.imagePosition = .noImage
        button.title = ""
        button.setAccessibilityLabel("TokenPeek")
        button.toolTip = "查看 Codex 配额与 Poe 积分"

        let glass = PassthroughVisualEffectView(frame: button.bounds.insetBy(dx: 1, dy: 1))
        glass.autoresizingMask = [.width, .height]
        glass.material = .headerView
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .aqua)
        glass.wantsLayer = true
        glass.layer?.backgroundColor = NSColor(calibratedWhite: 0.86, alpha: 0.18).cgColor
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        glass.layer?.borderWidth = 0.5
        glass.layer?.cornerRadius = 8.5
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        button.addSubview(glass)

        let textField = PassthroughTextField(labelWithString: "")
        textField.frame = button.bounds.insetBy(dx: 7, dy: 0)
        textField.appearance = NSAppearance(named: .aqua)
        textField.autoresizingMask = [.width, .height]
        textField.alignment = .center
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        textField.drawsBackground = false
        button.addSubview(textField)
        statusTextField = textField
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 368, height: 490)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(model)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        statusTextField?.attributedStringValue = StatusTitleRenderer.title(
            codex: model.menuBarCodex,
            poe: model.menuBarPoe,
            degraded: model.hasDegradedData
        )
        button.setAccessibilityTitle("Codex 剩余 \(model.menuBarCodex)，Poe 积分 \(model.menuBarPoe)")
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override var allowsVibrancy: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let text = attributedStringValue
        guard text.length > 0 else { return }
        let measured = text.boundingRect(
            with: NSSize(width: bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = ceil(measured.height)
        let target = NSRect(
            x: 0,
            y: floor((bounds.height - height) / 2) + 0.5,
            width: bounds.width,
            height: height
        )
        text.draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

@main
struct TokenPeekApp: App {
    @NSApplicationDelegateAdaptor(TokenPeekAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

private enum StatusTitleRenderer {
    static func title(codex: String, poe: String, degraded: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1),
            .baselineOffset: 0
        ]
        let codexAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
            .foregroundColor: NSColor(red: 0.06, green: 0.46, blue: 0.38, alpha: 1)
        ]
        let poeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(red: 0.43, green: 0.30, blue: 0.76, alpha: 1)
        ]
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(red: 0.73, green: 0.76, blue: 0.81, alpha: 1)
        ]

        result.append(NSAttributedString(string: "C", attributes: codexAttributes))
        result.append(NSAttributedString(string: " \(codex) ", attributes: valueAttributes))
        result.append(NSAttributedString(string: "│", attributes: separatorAttributes))
        result.append(NSAttributedString(string: " ✳", attributes: poeAttributes))
        result.append(NSAttributedString(string: " \(poe)", attributes: valueAttributes))
        if degraded {
            result.append(NSAttributedString(string: "  ●", attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                .foregroundColor: NSColor.systemOrange,
                .baselineOffset: 1
            ]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
