import AppKit

@MainActor
final class CallbackTextField: NSTextField, NSTextFieldDelegate {
    var onChange: ((String) -> Void)?

    convenience init(value: String, placeholder: String = "", onChange: @escaping (String) -> Void) {
        self.init(frame: .zero)
        stringValue = value
        placeholderString = placeholder
        self.onChange = onChange
        delegate = self
    }

    func controlTextDidChange(_ obj: Notification) {
        onChange?(stringValue)
    }
}

@MainActor
final class CallbackTextView: NSTextView, NSTextViewDelegate {
    var onChange: ((String) -> Void)?

    func textDidChange(_ notification: Notification) {
        onChange?(string)
    }
}

@MainActor
final class CallbackButton: NSButton {
    var handler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(invoke)
    }

    @objc private func invoke() { handler?() }
}

@MainActor
final class CallbackPopUpButton: NSPopUpButton {
    var handler: ((Int) -> Void)?

    convenience init(items: [String], selectedIndex: Int, handler: @escaping (Int) -> Void) {
        self.init(frame: .zero, pullsDown: false)
        addItems(withTitles: items)
        selectItem(at: max(0, min(selectedIndex, max(items.count - 1, 0))))
        self.handler = handler
        target = self
        action = #selector(invoke)
    }

    @objc private func invoke() { handler?(indexOfSelectedItem) }
}

@MainActor
func makeCheckbox(title: String, value: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
    let button = CallbackButton(title: title) {}
    button.setButtonType(.switch)
    button.state = value ? .on : .off
    button.handler = { [weak button] in onChange(button?.state == .on) }
    return button
}

@MainActor
func makeHeader(_ title: String, detail: String? = nil) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    let views: [NSView]
    if let detail {
        let subtitle = NSTextField(wrappingLabelWithString: detail)
        subtitle.textColor = .secondaryLabelColor
        views = [label, subtitle]
    } else {
        views = [label]
    }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    return stack
}

@MainActor
func makeSection(_ title: String, rows: [NSView]) -> NSView {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .secondaryLabelColor

    let rowsStack = NSStackView(views: rows)
    rowsStack.orientation = .vertical
    rowsStack.alignment = .leading
    rowsStack.spacing = 10
    rowsStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
    rowsStack.wantsLayer = true
    rowsStack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    rowsStack.layer?.cornerRadius = 9

    let section = NSStackView(views: [titleLabel, rowsStack])
    section.orientation = .vertical
    section.alignment = .leading
    section.spacing = 6
    rowsStack.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
    return section
}

@MainActor
func makeFormRow(_ label: String, control: NSView, help: String? = nil) -> NSView {
    let labelView = NSTextField(labelWithString: label)
    labelView.alignment = .right
    labelView.textColor = .labelColor
    labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true
    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    if let help { control.toolTip = help }
    let row = NSStackView(views: [labelView, control])
    row.orientation = .horizontal
    row.alignment = .firstBaseline
    row.spacing = 12
    control.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
    return row
}

@MainActor
func makeMultilineEditor(
    text: String,
    height: CGFloat = 100,
    onChange: @escaping (String) -> Void
) -> NSScrollView {
    let textView = CallbackTextView()
    textView.string = text
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.onChange = onChange
    textView.delegate = textView

    let scroll = NSScrollView()
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    return scroll
}

@MainActor
func makeFormScrollView(stack: NSStackView) -> NSScrollView {
    let document = NSView()
    document.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
        stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
        stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -24),
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
    ])

    let scroll = NSScrollView()
    scroll.documentView = document
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = .windowBackgroundColor
    document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    return scroll
}

func nonemptyLines(_ text: String) -> [String] {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func pingUrlsText(_ urls: [PingUrl]) -> String {
    urls.map { "\($0.host)|\($0.port)|\($0.path)" }.joined(separator: "\n")
}

func parsePingUrls(_ text: String) -> [PingUrl] {
    nonemptyLines(text).compactMap { line in
        let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let port = Int(parts[1]), !parts[0].isEmpty else { return nil }
        return PingUrl(host: parts[0], port: port, path: parts[2].isEmpty ? "/" : parts[2])
    }
}

@MainActor
func promptText(window: NSWindow?, title: String, message: String, value: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: value)
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = field
    let result = alert.runModal()
    guard result == .alertFirstButtonReturn else { return nil }
    return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
}
