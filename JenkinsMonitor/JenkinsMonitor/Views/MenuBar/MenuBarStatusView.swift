import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var viewModel: MonitoringViewModel
    var openMainWindow: () -> Void

    var body: some View {
        let _ = MenuBarJobStatusAligner.install()

        Button("主窗口") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Button("刷新") {
            Task { await viewModel.refreshAll(force: true) }
        }

        Divider()

        if !viewModel.hasConfiguredServer {
            Text("尚未配置实例")
        } else if visibleGroups.isEmpty {
            Text("暂无任务数据")
        } else {
            ForEach(visibleGroups) { group in
                Section(group.server.name) {
                    sectionContent(for: group)
                }
            }
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func sectionContent(for group: InstanceJobGroup) -> some View {
        if let message = group.errorMessage, group.jobs.isEmpty {
            Text(message)
        } else if group.isLoading && group.jobs.isEmpty {
            Text("正在加载…")
        } else if group.jobs.isEmpty {
            Text("暂无任务")
        } else {
            ForEach(group.jobs) { item in
                Button {
                    viewModel.selectJob(item)
                    openMainWindow()
                } label: {
                    Text(jobMenuTitle(for: item))
                }
            }
        }
    }

    /// 名称和带颜色的状态用制表符拼在一起，供 AppKit 自定义菜单项解析。
    private func jobMenuTitle(for item: MonitoredJob) -> AttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let status = item.job.displayStatus
        let result = NSMutableAttributedString(
            string: item.job.name,
            attributes: [.font: font]
        )
        result.append(NSAttributedString(string: "\t", attributes: [.font: font]))
        result.append(
            NSAttributedString(
                string: status.displayName,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor(status.tintColor)
                ]
            )
        )
        return AttributedString(result)
    }

    private var visibleGroups: [InstanceJobGroup] {
        viewModel.instanceJobGroups.filter { group in
            !group.jobs.isEmpty || group.errorMessage != nil || group.isLoading
        }
    }
}

/// SwiftUI 不会保留制表位。菜单即将显示时，把任务项换成自定义视图：
/// 左侧完整任务名，右侧状态与系统快捷键同一列对齐。
enum MenuBarJobStatusAligner {
    private static var installed = false
    private static var isApplying = false
    private static var observers: [NSObjectProtocol] = []
    private static var delegateProxies: [ObjectIdentifier: MenuDelegateProxy] = [:]

    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSMenu.didAddItemNotification,
            NSMenu.didChangeItemNotification,
            NSMenu.didBeginTrackingNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let menu = notification.object as? NSMenu else { return }
                attachDelegate(to: menu)
                apply(to: menu)
            }
            observers.append(token)
        }
    }

    static func apply(to menu: NSMenu) {
        guard !isApplying else { return }
        guard isOurMenu(menu) else { return }
        isApplying = true
        defer { isApplying = false }

        let contentWidth = rowWidth(in: menu)
        guard contentWidth > 0 else { return }

        // 先清掉旧的最小宽度，再按内容设置，避免菜单越撑越宽。
        menu.minimumWidth = 0
        menu.minimumWidth = contentWidth + MenuBarSideTextItemView.menuLeadingAllowance

        let width = max(contentWidth, menu.size.width - MenuBarSideTextItemView.menuLeadingAllowance)
        for item in menu.items {
            guard shouldCustomize(item), let content = content(for: item) else { continue }
            // 每次都换新视图，避免菜单沿用之前算窄了的尺寸。
            item.view = MenuBarSideTextItemView(content: content, width: width)
        }
        expandViews(in: menu)
    }

    static func expandViews(in menu: NSMenu) {
        guard isOurMenu(menu) else { return }
        let menuWidth = menu.size.width
        guard menuWidth > 0 else { return }
        for item in menu.items {
            guard let view = item.view as? MenuBarSideTextItemView else { continue }
            let originX = max(0, view.frame.minX)
            view.updateWidth(max(view.desiredWidth, menuWidth - originX))
        }
    }

    private static func attachDelegate(to menu: NSMenu) {
        guard isOurMenu(menu) else { return }
        if menu.delegate is MenuDelegateProxy { return }
        let proxy = MenuDelegateProxy(original: menu.delegate)
        delegateProxies[ObjectIdentifier(menu)] = proxy
        menu.delegate = proxy
    }

    private static func isOurMenu(_ menu: NSMenu) -> Bool {
        menu.items.contains { item in
            let title = itemTitle(item)
            return title == "主窗口" || title == "退出" || title.contains("\t")
        }
    }

    private static func shouldCustomize(_ item: NSMenuItem) -> Bool {
        !item.isSeparatorItem && !item.isHidden && itemTitle(item).contains("\t")
    }

    private static func itemTitle(_ item: NSMenuItem) -> String {
        item.attributedTitle?.string ?? item.title
    }

    private static func rowWidth(in menu: NSMenu) -> CGFloat {
        var maxWidth: CGFloat = 0
        for item in menu.items {
            guard shouldCustomize(item), let content = content(for: item) else { continue }
            maxWidth = max(maxWidth, MenuBarSideTextItemView.preferredWidth(for: content))
        }
        return maxWidth
    }

    private static func content(for item: NSMenuItem) -> MenuBarSideTextItemView.Content? {
        let source = item.attributedTitle ?? NSAttributedString(string: item.title)
        let raw = source.string
        if let tab = raw.firstIndex(of: "\t") {
            let name = String(raw[..<tab])
            let status = String(raw[raw.index(after: tab)...])
            var color: NSColor?
            let nsRaw = raw as NSString
            let tabRange = nsRaw.range(of: "\t")
            if tabRange.location != NSNotFound {
                let location = tabRange.location + tabRange.length
                if location < nsRaw.length {
                    color = source.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
                }
            }
            return .init(leading: name, trailing: status, trailingColor: color, trailingIsShortcut: false)
        }

        return nil
    }
}

final class MenuDelegateProxy: NSObject, NSMenuDelegate {
    weak var original: NSMenuDelegate?

    init(original: NSMenuDelegate?) {
        self.original = original
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        original?.menuNeedsUpdate?(menu)
        MenuBarJobStatusAligner.apply(to: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        MenuBarJobStatusAligner.apply(to: menu)
        original?.menuWillOpen?(menu)
        MenuBarJobStatusAligner.expandViews(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        original?.menuDidClose?(menu)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        original?.menu?(menu, willHighlight: item)
    }

    override func responds(to aSelector: Selector) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector) -> Any? {
        if let original, original.responds(to: aSelector) {
            return original
        }
        return nil
    }
}

final class MenuBarSideTextItemView: NSView {
    struct Content {
        var leading: String
        var trailing: String?
        var trailingColor: NSColor?
        var trailingIsShortcut: Bool
    }

    static let rowHeight: CGFloat = 22
    static let trailingGap: CGFloat = 16
    static let horizontalInset: CGFloat = 14
    // 与系统快捷键右缘大致对齐，并避开菜单圆角。
    static let rightInset: CGFloat = 14
    // 系统菜单给每一项留的左缩进，用来把 minimumWidth 补足到窗口宽度。
    static let menuLeadingAllowance: CGFloat = 20

    static func textWidth(_ string: String) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        return ceil((string as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    static func preferredWidth(for content: Content) -> CGFloat {
        let leading = textWidth(content.leading)
        let contentWidth: CGFloat
        if let trailing = content.trailing, !trailing.isEmpty {
            contentWidth = leading + trailingGap + textWidth(trailing)
        } else {
            contentWidth = leading
        }
        return ceil(contentWidth + horizontalInset + rightInset)
    }

    private let leadingLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private let font = NSFont.menuFont(ofSize: 0)
    private var content: Content
    private(set) var desiredWidth: CGFloat

    init(content: Content, width: CGFloat) {
        self.content = content
        self.desiredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        autoresizingMask = [.width]
        clipsToBounds = true
        setupLabels()
        apply(content: content, width: width)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWidthToMenuWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        syncWidthToMenuWindow()
    }

    func updateWidth(_ width: CGFloat) {
        let width = max(width, desiredWidth)
        guard abs(frame.width - width) > 0.5 || abs(desiredWidth - width) > 0.5 else { return }
        apply(content: content, width: width)
    }

    private func syncWidthToMenuWindow() {
        guard let contentView = window?.contentView else { return }
        let xInWindow = convert(.zero, to: contentView).x
        let available = contentView.bounds.width - xInWindow
        if available > 0 {
            updateWidth(available)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var allowsVibrancy: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: desiredWidth, height: Self.rowHeight)
    }

    override var fittingSize: NSSize {
        intrinsicContentSize
    }

    func apply(content: Content, width: CGFloat) {
        self.content = content
        self.desiredWidth = width
        leadingLabel.stringValue = content.leading
        trailingLabel.stringValue = content.trailing ?? ""
        trailingLabel.isHidden = (content.trailing ?? "").isEmpty
        applyColors(highlighted: enclosingMenuItem?.isHighlighted ?? false)
        setFrameSize(NSSize(width: width, height: Self.rowHeight))
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let trailingWidth: CGFloat = {
            guard !trailingLabel.isHidden, !trailingLabel.stringValue.isEmpty else { return 0 }
            return Self.textWidth(trailingLabel.stringValue)
        }()
        let gap: CGFloat = trailingWidth == 0 ? 0 : Self.trailingGap
        leadingLabel.frame = NSRect(
            x: Self.horizontalInset,
            y: 0,
            width: max(0, bounds.width - Self.horizontalInset - Self.rightInset - trailingWidth - gap),
            height: bounds.height
        )
        if trailingWidth > 0 {
            trailingLabel.frame = NSRect(
                x: bounds.width - Self.rightInset - trailingWidth,
                y: 0,
                width: trailingWidth,
                height: bounds.height
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        applyColors(highlighted: highlighted)
        super.draw(dirtyRect)
    }

    private func setupLabels() {
        for label in [leadingLabel, trailingLabel] {
            label.font = font
            label.isEditable = false
            label.isBordered = false
            label.isBezeled = false
            label.drawsBackground = false
            label.refusesFirstResponder = true
            addSubview(label)
        }
        leadingLabel.cell?.lineBreakMode = .byTruncatingTail
        trailingLabel.cell?.lineBreakMode = .byClipping
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingLabel.alignment = .right
    }

    private func applyColors(highlighted: Bool) {
        if highlighted {
            leadingLabel.textColor = .selectedMenuItemTextColor
            trailingLabel.textColor = .selectedMenuItemTextColor
        } else {
            leadingLabel.textColor = .controlTextColor
            if content.trailingIsShortcut {
                trailingLabel.textColor = .secondaryLabelColor
            } else {
                trailingLabel.textColor = content.trailingColor ?? .controlTextColor
            }
        }
    }
}
