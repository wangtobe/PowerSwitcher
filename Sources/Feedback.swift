import AppKit

/// First SF Symbol that exists on this macOS version; names added in later releases fall back gracefully.
func symbol(_ names: [String], _ description: String, size: CGFloat? = nil) -> NSImage? {
    for name in names {
        guard var image = NSImage(systemSymbolName: name, accessibilityDescription: description) else { continue }
        if let size = size, let sized = image.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) { image = sized }
        return image
    }
    return nil
}

enum UI {
    static func label(_ text: String, size: CGFloat = NSFont.systemFontSize, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    static func paragraph(_ text: String, width: CGFloat, size: CGFloat = NSFont.systemFontSize,
                          color: NSColor = .secondaryLabelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.preferredMaxLayoutWidth = width
        field.isSelectable = false
        return field
    }

    static func stack(_ views: [NSView], spacing: CGFloat = 12, vertical: Bool = true) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }

    static func icon(_ names: [String], tint: NSColor, size: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.image = symbol(names, "", size: size)
        view.contentTintColor = tint
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    /// Icon + bold title + secondary detail, used for mode explanations and feedback.
    static func row(_ names: [String], tint: NSColor, title: String, detail: String?, width: CGFloat) -> NSStackView {
        var text: [NSView] = [label(title, weight: .semibold)]
        if let detail = detail, !detail.isEmpty { text.append(paragraph(detail, width: width - 40, size: 12)) }
        let row = stack([icon(names, tint: tint, size: 20), stack(text, spacing: 3)], spacing: 12, vertical: false)
        row.alignment = .top
        return row
    }

    @discardableResult
    static func alert(_ title: String, _ detail: String, style: NSAlert.Style = .informational,
                      buttons: [String] = [L("好", "OK")], log: String? = nil, logSize: NSSize = NSSize(width: 440, height: 160),
                      suppression: String? = nil) -> (NSApplication.ModalResponse, Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = detail
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let log = log, !log.isEmpty {
            let text = NSTextView(frame: NSRect(origin: .zero, size: logSize))
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            text.string = log
            text.isVerticallyResizable = true
            let scroll = NSScrollView(frame: text.frame)
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.documentView = text
            alert.accessoryView = scroll
        }
        if let suppression = suppression {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = suppression
        }
        let response = alert.runModal()
        return (response, alert.suppressionButton?.state == .on)
    }
}

/// Non-interactive status block shown at the top of the menu.
final class StatusCardView: NSView {
    static let width: CGFloat = 300
    private let iconView = NSImageView()
    private let titleField = UI.label("", weight: .semibold)
    private let detailField = UI.paragraph("", width: StatusCardView.width - 62, size: 12)
    private let stack = NSStackView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: StatusCardView.width, height: 52))
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 10
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(UI.stack([titleField, detailField], spacing: 2))
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(symbols: [String], tint: NSColor, title: String, detail: String) {
        iconView.image = symbol(symbols, title, size: 18)
        iconView.contentTintColor = tint
        titleField.stringValue = title
        detailField.stringValue = detail
        detailField.isHidden = detail.isEmpty
        setAccessibilityLabel(detail.isEmpty ? title : title + L("。", ".") + detail)
        let height = stack.fittingSize.height + 12
        setFrameSize(NSSize(width: StatusCardView.width, height: height))
    }
}

/// Short-lived confirmation anchored to the menu bar icon, replacing modal success alerts.
final class FeedbackPopover {
    private var popover: NSPopover?
    private var closeWork: DispatchWorkItem?

    func show(_ symbols: [String], tint: NSColor, title: String, detail: String?, from button: NSStatusBarButton?) {
        guard let button = button, button.window != nil else { return }
        dismiss()
        let row = UI.row(symbols, tint: tint, title: title, detail: detail, width: 300)
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let controller = NSViewController()
        controller.view = row
        controller.preferredContentSize = row.fittingSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (detail == nil ? 2.5 : 4.5), execute: work)
    }

    func dismiss() {
        closeWork?.cancel()
        closeWork = nil
        popover?.performClose(nil)
        popover = nil
    }
}
