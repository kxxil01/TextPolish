import AppKit

/// Recent Polishes: pick one of the last Polishes to see and copy what was written and what was pasted.
@MainActor
final class RecentPolishesWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
  private let store: RecentPolishes
  private let tableView = NSTableView()
  private let originalView = NSTextView()
  private let polishedView = NSTextView()
  private let emptyLabel = NSTextField(labelWithString: "No Polishes kept yet.")
  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
  }()

  init(store: RecentPolishes) {
    self.store = store
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    title = "Recent Polishes"
    isFloatingPanel = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    level = .floating
    minSize = NSSize(width: 520, height: 300)
    setupUI()
  }

  func show() {
    reload()
    center()
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }

  func reload() {
    tableView.reloadData()
    emptyLabel.isHidden = !store.entries.isEmpty
    if !store.entries.isEmpty {
      tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    showSelected()
  }

  // MARK: Table

  func numberOfRows(in _: NSTableView) -> Int {
    store.entries.count
  }

  func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
    let entry = store.entries[row]
    let cell = NSTextField(labelWithString: "")
    cell.lineBreakMode = .byTruncatingTail
    cell.attributedStringValue = Self.rowTitle(entry, date: dateFormatter.string(from: entry.date))
    return cell
  }

  func tableViewSelectionDidChange(_: Notification) {
    showSelected()
  }

  private func showSelected() {
    let entry = store.entries.indices.contains(tableView.selectedRow) ? store.entries[tableView.selectedRow] : nil
    originalView.string = entry?.original ?? ""
    polishedView.string = entry?.polished ?? ""
  }

  /// "Today 22:42 · Discord · Natural", then the start of the result.
  static func rowTitle(_ entry: RecentPolish, date: String) -> NSAttributedString {
    let result = NSMutableAttributedString(
      string: "\(date) · \(entry.appName) · \(entry.styleName)\n",
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    )
    let preview = entry.polished.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    result.append(NSAttributedString(string: preview, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    return result
  }

  // MARK: Actions

  @objc private func copyOriginal() {
    copy(originalView.string)
  }

  @objc private func copyPolished() {
    copy(polishedView.string)
  }

  @objc private func clearAll() {
    store.clear()
    reload()
  }

  private func copy(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  // MARK: Layout

  private func setupUI() {
    let container = NSView()
    contentView = container

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("polish"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 40
    tableView.dataSource = self
    tableView.delegate = self
    tableView.setAccessibilityLabel("Recent Polishes")
    let listScroll = NSScrollView()
    listScroll.documentView = tableView
    listScroll.hasVerticalScroller = true
    listScroll.borderType = .bezelBorder

    let originalBox = textBox(title: "You wrote", textView: originalView, copyTitle: "Copy Original", action: #selector(copyOriginal))
    let polishedBox = textBox(title: "Pasted", textView: polishedView, copyTitle: "Copy Result", action: #selector(copyPolished))
    let details = NSStackView(views: [originalBox, polishedBox])
    details.orientation = .vertical
    details.distribution = .fillEqually
    details.spacing = 12

    let split = NSStackView(views: [listScroll, details])
    split.spacing = 12
    split.distribution = .fill

    let clearButton = NSButton(title: "Clear All", target: self, action: #selector(clearAll))
    clearButton.bezelStyle = .rounded
    let note = NSTextField(labelWithString: "Kept on this Mac only. Turn off in Settings > Advanced to delete them.")
    note.font = .systemFont(ofSize: 11)
    note.textColor = .secondaryLabelColor
    let footer = NSStackView(views: [note, clearButton])
    footer.spacing = 8

    for view in [split, footer, emptyLabel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
    }
    emptyLabel.textColor = .secondaryLabelColor
    NSLayoutConstraint.activate([
      split.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      split.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      split.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      listScroll.widthAnchor.constraint(equalToConstant: 240),
      footer.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 12),
      footer.leadingAnchor.constraint(equalTo: split.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: split.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
      emptyLabel.centerXAnchor.constraint(equalTo: listScroll.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: listScroll.centerYAnchor),
    ])
  }

  private func textBox(title: String, textView: NSTextView, copyTitle: String, action: Selector) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    let copyButton = NSButton(title: copyTitle, target: self, action: action)
    copyButton.bezelStyle = .rounded
    copyButton.controlSize = .small
    let header = NSStackView(views: [label, NSView(), copyButton])

    textView.isEditable = false
    textView.isSelectable = true
    textView.font = .systemFont(ofSize: 13)
    textView.textContainerInset = NSSize(width: 4, height: 4)
    textView.autoresizingMask = [.width]
    textView.setAccessibilityLabel(title)
    let scroll = NSScrollView()
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder

    let box = NSStackView(views: [header, scroll])
    box.orientation = .vertical
    box.alignment = .leading
    box.spacing = 4
    header.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
    scroll.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
    return box
  }

  #if DEBUG
    var debugRowCount: Int {
      tableView.numberOfRows
    }

    var debugOriginal: String {
      originalView.string
    }

    var debugPolished: String {
      polishedView.string
    }

    func debugSelect(row: Int) {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      showSelected()
    }

    func debugClearAll() {
      clearAll()
    }
  #endif
}
