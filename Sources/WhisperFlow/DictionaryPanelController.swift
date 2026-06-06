import AppKit

private enum DS {
    static let paper = NSColor(srgbRed: 0xF7/255, green: 0xF7/255, blue: 0xF5/255, alpha: 1)
    static let forest = NSColor(srgbRed: 0x1A/255, green: 0x3C/255, blue: 0x2B/255, alpha: 1)
    static let grid = NSColor(srgbRed: 0x3A/255, green: 0x3A/255, blue: 0x38/255, alpha: 1)
    static let coral = NSColor(srgbRed: 0xFF/255, green: 0x8C/255, blue: 0x69/255, alpha: 1)
    static var hairline: NSColor { grid.withAlphaComponent(0.35) }
    static let hairlineWidth: CGFloat = 1.5
    static var ink: NSColor { grid }
    static var inkMuted: NSColor { grid.withAlphaComponent(0.7) }

    static func header(_ size: CGFloat) -> NSFont {
        NSFont(name: "Space Grotesk Bold", size: size)
            ?? NSFont(name: "SpaceGrotesk-Bold", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
    static func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "General Sans", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

private func monoLabel(_ text: String, size: CGFloat, color: NSColor = DS.inkMuted, tracking: CGFloat = 1.2) -> NSTextField {
    let f = NSTextField(labelWithString: "")
    let attrs: [NSAttributedString.Key: Any] = [
        .font: DS.mono(size),
        .foregroundColor: color,
        .kern: tracking
    ]
    f.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: attrs)
    return f
}

final class DictionaryPanelController: NSViewController {
    private let wordField = NSTextField()
    private let replacementField = NSTextField()
    private let entriesStack = NSStackView()
    private let countBadge = NSTextField(labelWithString: "")
    private var replacements: [DictionaryReplacement] = []

    override func loadView() {
        view = PaperBackgroundView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        buildUI()
        reloadReplacements()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadReplacements()
        if let window = view.window {
            window.backgroundColor = DS.paper
            window.titlebarAppearsTransparent = true
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.wordField)
        }
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Header block
        let header = buildHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(header)
        header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28).isActive = true
        header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28).isActive = true

        let divider = HairlineView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(divider)
        divider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28).isActive = true
        divider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28).isActive = true
        divider.heightAnchor.constraint(equalToConstant: DS.hairlineWidth).isActive = true

        // Input block
        let inputBlock = buildInputBlock()
        inputBlock.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(inputBlock)
        inputBlock.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28).isActive = true
        inputBlock.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28).isActive = true

        // Section label
        let sectionRow = NSStackView()
        sectionRow.orientation = .horizontal
        sectionRow.alignment = .centerY
        sectionRow.spacing = 10
        sectionRow.translatesAutoresizingMaskIntoConstraints = false
        let entriesLabel = monoLabel("Entries", size: 11, color: DS.ink)
        let sectionLine = HairlineView()
        sectionRow.addArrangedSubview(entriesLabel)
        sectionRow.addArrangedSubview(sectionLine)
        sectionLine.heightAnchor.constraint(equalToConstant: DS.hairlineWidth).isActive = true
        sectionLine.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(sectionRow)
        sectionRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28).isActive = true
        sectionRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28).isActive = true

        // Entries list
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        entriesStack.orientation = .vertical
        entriesStack.alignment = .width
        entriesStack.spacing = 0
        entriesStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(entriesStack)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.contentView.drawsBackground = false
        root.addArrangedSubview(scrollView)
        scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28).isActive = true
        scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28).isActive = true

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            entriesStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            entriesStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            entriesStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            entriesStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])
    }

    private func buildHeader() -> NSView {
        let container = NSView()

        let eyebrow = monoLabel("Dictionary", size: 11, color: DS.grid.withAlphaComponent(0.7))
        eyebrow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(eyebrow)

        let title = NSTextField(labelWithString: "")
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: DS.header(36),
            .foregroundColor: DS.forest,
            .kern: -0.6,
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = 0.9
                return p
            }()
        ]
        title.attributedStringValue = NSAttributedString(string: "Replacements", attributes: titleAttrs)
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let badge = BadgeView()
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        badge.contentField = countBadge
        badge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)

        NSLayoutConstraint.activate([
            eyebrow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            eyebrow.topAnchor.constraint(equalTo: container.topAnchor),

            title.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            title.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 6),
            title.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),

            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            badge.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        return container
    }

    private func buildInputBlock() -> NSView {
        let block = BorderedBoxView()

        let header = monoLabel("Add Entry", size: 10, color: DS.grid.withAlphaComponent(0.7))
        header.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(header)

        configureField(wordField, placeholder: "WORD")
        configureField(replacementField, placeholder: "REPLACEMENT")
        wordField.target = self
        wordField.action = #selector(addReplacement)
        replacementField.target = self
        replacementField.action = #selector(addReplacement)

        let wordWrap = BorderedFieldWrap(field: wordField)
        let replacementWrap = BorderedFieldWrap(field: replacementField)

        let arrow = NSTextField(labelWithString: "")
        arrow.attributedStringValue = NSAttributedString(string: "→", attributes: [
            .font: DS.mono(15),
            .foregroundColor: DS.grid.withAlphaComponent(0.6)
        ])
        arrow.alignment = .center

        let addButton = FlatButton(title: "Add", style: .primary, target: self, action: #selector(addReplacement))

        let inputRow = NSStackView(views: [wordWrap, arrow, replacementWrap, addButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 12
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(inputRow)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 16),
            header.topAnchor.constraint(equalTo: block.topAnchor, constant: 14),

            inputRow.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -16),
            inputRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            inputRow.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -16),

            wordWrap.widthAnchor.constraint(equalToConstant: 150),
            replacementWrap.widthAnchor.constraint(equalToConstant: 170),
            arrow.widthAnchor.constraint(equalToConstant: 18),
            wordWrap.heightAnchor.constraint(equalToConstant: 32),
            replacementWrap.heightAnchor.constraint(equalToConstant: 32)
        ])

        return block
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = DS.mono(12)
        field.textColor = DS.ink
        field.translatesAutoresizingMaskIntoConstraints = false
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .font: DS.mono(11),
            .foregroundColor: DS.grid.withAlphaComponent(0.4),
            .kern: 1.0
        ]
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: placeholderAttrs)
    }

    func reloadReplacements() {
        replacements = Config.shared.dictionaryReplacements
        rebuildEntries()
    }

    @objc private func addReplacement() {
        let word = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !replacement.isEmpty else {
            NSSound.beep()
            return
        }

        let rule = DictionaryReplacement(word: word, replacement: replacement)
        if let index = replacements.firstIndex(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
            replacements[index] = rule
        } else {
            replacements.append(rule)
        }

        Config.shared.saveDictionaryReplacements(replacements)
        wordField.stringValue = ""
        replacementField.stringValue = ""
        rebuildEntries()
        view.window?.makeFirstResponder(wordField)
    }

    private func removeReplacement(at index: Int) {
        guard replacements.indices.contains(index) else { return }
        replacements.remove(at: index)
        Config.shared.saveDictionaryReplacements(replacements)
        rebuildEntries()
    }

    private func rebuildEntries() {
        entriesStack.arrangedSubviews.forEach { view in
            entriesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        updateCountBadge()

        guard !replacements.isEmpty else {
            let empty = EmptyStateView()
            entriesStack.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 96).isActive = true
            return
        }

        for (index, rule) in replacements.enumerated() {
            let row = DictionaryEntryRowView(rule: rule, isFirst: index == 0) { [weak self] in
                self?.removeReplacement(at: index)
            }
            entriesStack.addArrangedSubview(row)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }
    }

    private func updateCountBadge() {
        let count = replacements.count
        let text = count == 1 ? "1 Entry" : "\(count) Entries"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DS.mono(10),
            .foregroundColor: DS.ink,
            .kern: 1.2
        ]
        countBadge.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: attrs)
    }
}

// MARK: - Style primitives

private final class PaperBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DS.paper.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class HairlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DS.hairline.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class BorderedBoxView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = DS.hairline.cgColor
        layer?.borderWidth = DS.hairlineWidth
        layer?.cornerRadius = 2
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class BorderedFieldWrap: NSView {
    init(field: NSTextField) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = DS.hairline.cgColor
        layer?.borderWidth = DS.hairlineWidth
        layer?.cornerRadius = 2

        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class BadgeView: NSView {
    var contentField: NSTextField? {
        didSet {
            subviews.forEach { $0.removeFromSuperview() }
            guard let field = contentField else { return }
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                field.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
            ])
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = DS.hairline.cgColor
        layer?.borderWidth = DS.hairlineWidth
        layer?.cornerRadius = 2
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class FlatButton: NSButton {
    enum Style { case primary, ghost, ghostCoral }

    private let style: Style
    private var hovering = false
    private var trackingArea: NSTrackingArea?
    private let titleText: String

    init(title: String, style: Style, target: AnyObject?, action: Selector?) {
        self.style = style
        self.titleText = title
        super.init(frame: .zero)
        self.target = target
        self.action = action
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        layer?.cornerRadius = 2
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        let intrinsicHeight: CGFloat = style == .primary ? 32 : 24
        let intrinsicMinWidth: CGFloat = style == .primary ? 72 : 80
        heightAnchor.constraint(equalToConstant: intrinsicHeight).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: intrinsicMinWidth).isActive = true
        applyTitle()
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        applyColors()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        applyColors()
    }

    private func applyTitle() {
        let size: CGFloat = style == .primary ? 11 : 10
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DS.mono(size, weight: .bold),
            .foregroundColor: currentForeground(),
            .kern: 1.4
        ]
        attributedTitle = NSAttributedString(string: titleText.uppercased(), attributes: attrs)
    }

    private func currentForeground() -> NSColor {
        switch style {
        case .primary:
            return hovering ? DS.forest : DS.paper
        case .ghost:
            return hovering ? DS.forest : DS.ink
        case .ghostCoral:
            return hovering ? DS.coral : DS.ink
        }
    }

    private func applyColors() {
        switch style {
        case .primary:
            layer?.backgroundColor = (hovering ? DS.paper : DS.forest).cgColor
            layer?.borderColor = DS.forest.cgColor
        case .ghost:
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = (hovering ? DS.forest : DS.hairline).cgColor
        case .ghostCoral:
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = (hovering ? DS.coral : DS.hairline).cgColor
        }
        applyTitle()
    }
}

// MARK: - Row & empty state

private final class DictionaryEntryRowView: NSView {
    private let onRemove: () -> Void
    private let isFirst: Bool

    init(rule: DictionaryReplacement, isFirst: Bool, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        self.isFirst = isFirst
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        build(rule: rule)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.sublayers?.removeAll(where: { $0.name == "hairline" })

        let w = DS.hairlineWidth
        let bottom = CALayer()
        bottom.name = "hairline"
        bottom.frame = CGRect(x: 0, y: 0, width: bounds.width, height: w)
        bottom.backgroundColor = DS.hairline.cgColor
        layer?.addSublayer(bottom)

        if isFirst {
            let top = CALayer()
            top.name = "hairline"
            top.frame = CGRect(x: 0, y: bounds.height - w, width: bounds.width, height: w)
            top.backgroundColor = DS.hairline.cgColor
            layer?.addSublayer(top)
        }
    }

    private func build(rule: DictionaryReplacement) {
        let wordLabel = NSTextField(labelWithString: "")
        wordLabel.attributedStringValue = NSAttributedString(string: rule.word, attributes: [
            .font: DS.body(15, weight: .bold),
            .foregroundColor: DS.ink
        ])
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.setContentHuggingPriority(.required, for: .horizontal)
        wordLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let arrowLabel = NSTextField(labelWithString: "")
        arrowLabel.attributedStringValue = NSAttributedString(string: "→", attributes: [
            .font: DS.mono(15, weight: .bold),
            .foregroundColor: DS.grid.withAlphaComponent(0.6)
        ])
        arrowLabel.alignment = .center
        arrowLabel.setContentHuggingPriority(.required, for: .horizontal)

        let replacementLabel = NSTextField(labelWithString: "")
        replacementLabel.attributedStringValue = NSAttributedString(string: rule.replacement, attributes: [
            .font: DS.mono(14, weight: .semibold),
            .foregroundColor: DS.forest
        ])
        replacementLabel.lineBreakMode = .byTruncatingTail
        replacementLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let removeButton = FlatButton(title: "Remove", style: .ghostCoral, target: self, action: #selector(remove))

        let leftGroup = NSStackView(views: [wordLabel, arrowLabel, replacementLabel])
        leftGroup.orientation = .horizontal
        leftGroup.alignment = .centerY
        leftGroup.spacing = 12
        leftGroup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftGroup)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            leftGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            leftGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftGroup.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -16),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            arrowLabel.widthAnchor.constraint(equalToConstant: 18),

            topAnchor.constraint(lessThanOrEqualTo: leftGroup.topAnchor, constant: -12),
            bottomAnchor.constraint(greaterThanOrEqualTo: leftGroup.bottomAnchor, constant: 12)
        ])
    }

    @objc private func remove() {
        onRemove()
    }
}

private final class EmptyStateView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = DS.hairline.cgColor
        layer?.borderWidth = DS.hairlineWidth
        layer?.cornerRadius = 2
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let label = monoLabel("No Entries Yet", size: 11, color: DS.grid.withAlphaComponent(0.55))
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
