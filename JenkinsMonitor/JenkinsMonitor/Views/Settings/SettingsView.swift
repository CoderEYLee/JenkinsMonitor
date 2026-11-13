import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: MonitoringViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var route: EditorRoute?
    @State private var pendingAction: PendingInstanceAction?
    @State private var intervalText: String = ""
    @State private var intervalError: String?
    @State private var isEditingOrder = false
    @State private var draftServers: [ServerConfiguration] = []
    @State private var draggingID: UUID?
    @State private var dragLocation: CGPoint?
    @State private var dragGrabOffset: CGSize = .zero
    @State private var dragRowWidth: CGFloat = 0
    @State private var dragRowHeight: CGFloat = 0
    @State private var insertionIndex: Int?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero
    @State private var lastAutoScrollAt: Date = .distantPast

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    if viewModel.servers.isEmpty {
                        Text("尚未添加实例")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedServers) { server in
                            instanceRow(server)
                                .id(server.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("所有实例")
                        Spacer(minLength: 8)
                        if displayedServers.count > 1 {
                            Button(isEditingOrder ? "保存" : "编辑") {
                                if isEditingOrder {
                                    saveInstanceOrder()
                                } else {
                                    beginEditingOrder()
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    if isEditingOrder {
                        Text("拖动整行调整顺序，点击保存后生效")
                    }
                }

                Section {
                    Button {
                        viewModel.clearError()
                        route = .add
                    } label: {
                        Label("添加实例", systemImage: "plus")
                    }
                }

                if let message = viewModel.errorMessage, route == nil {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let notice = viewModel.instanceActionNotice, route == nil, viewModel.errorMessage == nil {
                    Section {
                        Label(notice, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("刷新") {
                    HStack(spacing: 8) {
                        Text("自动刷新间隔")
                        Spacer(minLength: 12)
                        TextField(
                            "",
                            text: $intervalText,
                            prompt: Text(intervalRangePrompt)
                        )
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .frame(width: 108)
                            .onChange(of: intervalText) { _, _ in
                                intervalError = nil
                            }
                            .onSubmit(saveRefreshInterval)
                        Text("秒")
                            .foregroundStyle(.secondary)
                        Button("保存") {
                            saveRefreshInterval()
                        }
                        .disabled(!canSaveRefreshInterval)
                    }
                    if let intervalError {
                        Text(intervalError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersionText)
                }
            }
            .formStyle(.grouped)
            .toolbar(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Text("设置")
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 8)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .background(.background)
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .add:
                    ServerEditorView(viewModel: viewModel, mode: .add, route: $route)
                case .edit(let id):
                    if let server = viewModel.servers.first(where: { $0.id == id }) {
                        ServerEditorView(viewModel: viewModel, mode: .edit(server), route: $route)
                    } else {
                        ContentUnavailableView("实例不存在", systemImage: "server.rack")
                    }
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SettingsViewportKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(SettingsViewportKey.self) { viewportFrame = $0 }
            .onChange(of: dragLocation) { _, location in
                autoScrollInstances(proxy: proxy, location: location)
            }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .overlay {
            liftedInstanceOverlay
        }
        .onAppear {
            intervalText = "\(Int(viewModel.refreshIntervalSeconds))"
            intervalError = nil
        }
        .onChange(of: viewModel.servers.count) { _, count in
            if count < 2 {
                isEditingOrder = false
                draftServers = []
                resetReorderDrag()
            }
        }
        .onDisappear {
            // 关闭设置且未点保存时，丢弃未写入的顺序。
            isEditingOrder = false
            draftServers = []
            resetReorderDrag()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingAction {
                Button(pending.action.title, role: pending.action.isDestructive ? .destructive : nil) {
                    let item = pending
                    pendingAction = nil
                    Task {
                        await viewModel.performInstanceAction(item.action, on: item.server)
                    }
                }
                Button("取消", role: .cancel) {
                    pendingAction = nil
                }
            }
        } message: {
            if let pending = pendingAction {
                Text(pending.action.confirmationMessage)
            }
        }
    }

    private var confirmationTitle: String {
        guard let pending = pendingAction else { return "确认操作？" }
        return "确认对「\(pending.server.name)」\(pending.action.title)？"
    }

    private var displayedServers: [ServerConfiguration] {
        isEditingOrder ? draftServers : viewModel.servers
    }

    private func beginEditingOrder() {
        draftServers = viewModel.servers
        withAnimation(.snappy) {
            isEditingOrder = true
        }
    }

    private func saveInstanceOrder() {
        if draftServers.map(\.id) != viewModel.servers.map(\.id) {
            viewModel.saveServerOrder(draftServers)
        }
        withAnimation(.snappy) {
            isEditingOrder = false
        }
        draftServers = []
        resetReorderDrag()
    }

    @ViewBuilder
    private func instanceRow(_ server: ServerConfiguration) -> some View {
        // 用 ZStack 量位置：offset 只移动视觉内容，占位尺寸保持不动，才能算出插入空隙。
        let row = ZStack {
            instanceRowContent(server)
                .opacity(draggingID == server.id ? 0 : 1)
                .offset(y: insertionOffset(for: server.id))
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: insertionIndex)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: InstanceRowFrameKey.self,
                    value: [server.id: geo.frame(in: .global)]
                )
            }
        }
        .onPreferenceChange(InstanceRowFrameKey.self) { values in
            rowFrames.merge(values, uniquingKeysWith: { $1 })
        }

        if isEditingOrder {
            row.gesture(reorderGesture(for: server))
        } else {
            row
        }
    }

    private func instanceRowContent(_ server: ServerConfiguration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if isEditingOrder {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("调整顺序")
            }

            instanceSummary(server)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !isEditingOrder {
                if viewModel.instanceActionInProgressID == server.id {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("编辑") {
                    viewModel.clearError()
                    route = .edit(server.id)
                }

                Menu("操作") {
                    ForEach(viewModel.availableInstanceActions(for: server)) { action in
                        Button(action.title, role: action.isDestructive ? .destructive : nil) {
                            viewModel.clearError()
                            pendingAction = PendingInstanceAction(server: server, action: action)
                        }
                    }
                }
                .disabled(viewModel.instanceActionInProgressID != nil)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func instanceSummary(_ server: ServerConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(server.name)
                .font(.body.weight(.medium))
            Text(verbatim: server.baseURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !server.username.isEmpty {
                Text("用户名：\(server.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = viewModel.instanceStatusText(for: server) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(instanceStatusColor(for: server))
            }
        }
    }

    private var liftedInstanceOverlay: some View {
        GeometryReader { geo in
            if isEditingOrder,
               let draggingID,
               let server = draftServers.first(where: { $0.id == draggingID }),
               let location = dragLocation {
                let origin = geo.frame(in: .global).origin
                instanceRowContent(server)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: max(dragRowWidth, 240), alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                    .scaleEffect(1.02)
                    .position(
                        x: location.x - origin.x - dragGrabOffset.width + dragRowWidth / 2,
                        y: location.y - origin.y - dragGrabOffset.height + dragRowHeight / 2
                    )
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private func reorderGesture(for server: ServerConfiguration) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                handleReorderChanged(server: server, value: value)
            }
            .onEnded { _ in
                handleReorderEnded()
            }
    }

    private func handleReorderChanged(server: ServerConfiguration, value: DragGesture.Value) {
        if draggingID == nil {
            draggingID = server.id
            let frame = rowFrames[server.id] ?? .zero
            dragGrabOffset = CGSize(
                width: value.startLocation.x - frame.minX,
                height: value.startLocation.y - frame.minY
            )
            dragRowWidth = frame.width
            dragRowHeight = max(frame.height, 1)
            insertionIndex = draftServers.firstIndex(where: { $0.id == server.id })
        }
        guard draggingID == server.id else { return }
        dragLocation = value.location
        insertionIndex = targetInsertionIndex(atGlobalY: value.location.y)
    }

    private func handleReorderEnded() {
        if let draggingID,
           let insertion = insertionIndex,
           let from = draftServers.firstIndex(where: { $0.id == draggingID }),
           from != insertion {
            draftServers.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: from < insertion ? insertion + 1 : insertion
            )
        }
        resetReorderDrag()
    }

    private func resetReorderDrag() {
        draggingID = nil
        dragLocation = nil
        insertionIndex = nil
        dragGrabOffset = .zero
        lastAutoScrollAt = .distantPast
    }

    private func targetInsertionIndex(atGlobalY y: CGFloat) -> Int {
        let ids = draftServers.map(\.id)
        guard !ids.isEmpty else { return 0 }
        for (index, id) in ids.enumerated() {
            guard let frame = rowFrames[id] else { continue }
            if y < frame.midY {
                return index
            }
        }
        return ids.count - 1
    }

    private func insertionOffset(for id: UUID) -> CGFloat {
        guard draggingID != nil,
              let start = draftServers.firstIndex(where: { $0.id == draggingID }),
              let insertion = insertionIndex,
              id != draggingID,
              let current = draftServers.firstIndex(where: { $0.id == id }) else { return 0 }
        let stride = rowStride
        if start < insertion, current > start, current <= insertion {
            return -stride
        }
        if start > insertion, current >= insertion, current < start {
            return stride
        }
        return 0
    }

    private var rowStride: CGFloat {
        let frames = draftServers.compactMap { rowFrames[$0.id] }.sorted { $0.minY < $1.minY }
        if frames.count >= 2 {
            return frames[1].minY - frames[0].minY
        }
        return max(dragRowHeight, 1)
    }

    private func autoScrollInstances(proxy: ScrollViewProxy, location: CGPoint?) {
        guard isEditingOrder, draggingID != nil, let location, !draftServers.isEmpty else { return }
        let edge: CGFloat = 44
        let now = Date()
        guard now.timeIntervalSince(lastAutoScrollAt) > 0.16 else { return }
        let insertion = insertionIndex ?? 0
        if location.y < viewportFrame.minY + edge, insertion > 0 {
            lastAutoScrollAt = now
            withAnimation(.easeInOut(duration: 0.16)) {
                proxy.scrollTo(draftServers[insertion - 1].id, anchor: .top)
            }
        } else if location.y > viewportFrame.maxY - edge, insertion < draftServers.count - 1 {
            lastAutoScrollAt = now
            withAnimation(.easeInOut(duration: 0.16)) {
                proxy.scrollTo(draftServers[insertion + 1].id, anchor: .bottom)
            }
        }
    }

    private func instanceStatusColor(for server: ServerConfiguration) -> Color {
        if viewModel.instanceActionInProgressID == server.id
            || viewModel.restartingServerIDs.contains(server.id) {
            return .secondary
        }
        if viewModel.serverInfoByID[server.id]?.quietingDown == true {
            return .orange
        }
        if viewModel.instanceErrors[server.id] != nil {
            return .red
        }
        return .secondary
    }

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != short {
            return "\(short)（\(build)）"
        }
        return short
    }

    private var intervalRangePrompt: String {
        "\(Int(ServerSettingsStore.minRefreshInterval))~\(Int(ServerSettingsStore.maxRefreshInterval))"
    }

    private var parsedRefreshInterval: Int? {
        let trimmed = intervalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return nil }
        return value
    }

    private var canSaveRefreshInterval: Bool {
        guard let value = parsedRefreshInterval else { return false }
        let min = Int(ServerSettingsStore.minRefreshInterval)
        let max = Int(ServerSettingsStore.maxRefreshInterval)
        guard (min...max).contains(value) else { return false }
        return TimeInterval(value) != viewModel.refreshIntervalSeconds
    }

    private func saveRefreshInterval() {
        let min = Int(ServerSettingsStore.minRefreshInterval)
        let max = Int(ServerSettingsStore.maxRefreshInterval)
        guard let value = parsedRefreshInterval else {
            intervalError = "请输入整数秒数。"
            return
        }
        guard (min...max).contains(value) else {
            intervalError = "间隔需在 \(min) 到 \(max) 秒之间。"
            return
        }
        intervalError = nil
        viewModel.saveRefreshInterval(TimeInterval(value))
        intervalText = "\(value)"
    }
}

private struct PendingInstanceAction: Identifiable {
    let id = UUID()
    let server: ServerConfiguration
    let action: JenkinsInstanceAction
}

private enum EditorRoute: Hashable, Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let id):
            return id.uuidString
        }
    }
}

private struct ServerEditorView: View {
    enum Mode {
        case add
        case edit(ServerConfiguration)

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }

        var title: String {
            isEditing ? "编辑实例" : "添加实例"
        }

        var submitTitle: String {
            isEditing ? "保存" : "添加并连接"
        }
    }

    @Bindable var viewModel: MonitoringViewModel
    let mode: Mode
    @Binding var route: EditorRoute?

    @State private var name: String = ""
    @State private var baseURLString: String = ""
    @State private var username: String = ""
    @State private var userPassword: String = ""
    @State private var localError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                TextField("显示名称", text: $name, prompt: Text("Jenkins1"))
                    .multilineTextAlignment(.trailing)
                TextField(
                    "实例地址",
                    text: $baseURLString,
                    prompt: Text(verbatim: "默认 http://127.0.0.1:8080/")
                )
                .multilineTextAlignment(.trailing)
                TextField("用户名", text: $username, prompt: Text("Jenkins 用户名"))
                    .multilineTextAlignment(.trailing)
                SecureField(
                    "密码",
                    text: $userPassword,
                    prompt: Text(mode.isEditing ? "留空则保留原密码" : "Jenkins 用户名对应的密码")
                )
                .multilineTextAlignment(.trailing)
            }

            if let message = localError ?? viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(mode.title)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .confirmationDialog("确认删除该实例？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if case .edit(let server) = mode {
                    viewModel.deleteServer(server)
                    route = nil
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear(perform: populate)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if mode.isEditing {
                Button("删除此实例", role: .destructive) {
                    showDeleteConfirm = true
                }
                .foregroundStyle(.red)
                .tint(.red)
            }
            Spacer()
            Button("取消") {
                route = nil
            }
            .keyboardShortcut(.cancelAction)
            Button {
                Task { await save() }
            } label: {
                if viewModel.isSavingServer {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(mode.submitTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit || viewModel.isSavingServer)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var canSubmit: Bool {
        let hasBasics = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedURL != nil
        if mode.isEditing {
            return hasBasics
        }
        return hasBasics && !userPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func populate() {
        if case .edit(let server) = mode {
            name = server.name
            baseURLString = server.baseURL.absoluteString
            username = server.username
            userPassword = ""
        }
        localError = nil
    }

    private func save() async {
        localError = nil
        viewModel.clearError()
        guard let url = normalizedURL else {
            localError = "请输入有效的实例地址。"
            return
        }

        let token = userPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingID: UUID? = {
            if case .edit(let server) = mode { return server.id }
            return nil
        }()
        let configuration = ServerConfiguration(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: url,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            userPassword: token.isEmpty ? nil : token
        )
        let makeActive = !mode.isEditing
            || viewModel.activeServer?.id == configuration.id
            || viewModel.servers.isEmpty
        let ok = await viewModel.saveServer(configuration, makeActive: makeActive)
        if ok {
            route = nil
        } else {
            localError = viewModel.errorMessage
        }
    }
}

private struct InstanceRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SettingsViewportKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    SettingsView(viewModel: MonitoringViewModel(environment: .preview))
}
