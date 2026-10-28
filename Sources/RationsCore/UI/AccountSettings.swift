import SwiftUI

/// The Accounts tab: the accounts in display order on the left (drag to
/// reorder, + to add), the selected one's settings on the right.
struct AccountsSettings: View {
    let store: AccountStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.monitors) { AccountListRow(monitor: $0).tag($0.id) }
                        .onMove(perform: move)
                }
                .listStyle(.sidebar)
                Divider()
                HStack {
                    AddAccountMenu(store: store, style: .compact) { selection = $0.id }
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            if let monitor = store.monitors.first(where: { $0.id == selection }) {
                AccountDetail(monitor: monitor, store: store)
                    // Fresh field state per account.
                    .id(monitor.id)
            } else {
                VStack(spacing: 8) {
                    Text(store.monitors.isEmpty ? "No accounts yet" : "Select an account")
                        .foregroundStyle(.secondary)
                    if store.monitors.isEmpty {
                        AddAccountMenu(store: store) { selection = $0.id }.fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: settingsPaneSize.width, height: settingsPaneSize.height)
        .onAppear { if selection == nil { selection = store.monitors.first?.id } }
        .onChange(of: store.monitors.map(\.id)) { _, ids in
            if let current = selection, !ids.contains(current) { selection = ids.first }
        }
    }

    /// List moves are expressed as an insertion index; the store moves by offset.
    private func move(from source: IndexSet, to destination: Int) {
        guard let index = source.first else { return }
        let offset = destination > index ? destination - index - 1 : destination - index
        store.move(id: store.monitors[index].id, by: offset)
    }
}

private struct AccountListRow: View {
    let monitor: AccountMonitor

    var body: some View {
        HStack(spacing: 8) {
            AccountLabel(account: monitor.account)
                .frame(minWidth: 26)
                .padding(.vertical, 3).padding(.horizontal, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.account.name.isEmpty ? monitor.provider.name : monitor.account.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Circle().fill(statusColor).frame(width: 7, height: 7).help(statusHelp)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let identity = monitor.identity
        if monitor.account.name.isEmpty { return identity.isEmpty ? "Not signed in" : identity }
        return identity.isEmpty ? monitor.provider.name : "\(monitor.provider.name) · \(identity)"
    }

    private var statusColor: Color {
        switch monitor.status {
        case .error: .red
        case .signingIn: .orange
        case .signedOut: .secondary.opacity(0.5)
        case .idle, .refreshing: monitor.isSignedIn ? .green : .secondary.opacity(0.5)
        }
    }

    private var statusHelp: String {
        switch monitor.status {
        case .error(let message): message
        case .signingIn: "Signing in"
        case .signedOut: "Not signed in"
        case .idle, .refreshing: monitor.isSignedIn ? "Signed in" : "Not signed in"
        }
    }
}

/// One account's settings: sign-in, how it is labelled, how its menu bar
/// entry looks, and which limits it shows. Edits go straight to the store,
/// which normalises and persists.
private struct AccountDetail: View {
    let monitor: AccountMonitor
    let store: AccountStore
    @State private var tag: String
    @State private var name: String
    @State private var confirmingRemoval = false
    @FocusState private var tagFocused: Bool

    init(monitor: AccountMonitor, store: AccountStore) {
        self.monitor = monitor
        self.store = store
        _tag = State(initialValue: monitor.account.tag)
        _name = State(initialValue: monitor.account.name)
    }

    var body: some View {
        Form {
            signInSection
            Section("Label") {
                // The placeholder shows the fallback used when the field is left empty.
                TextField("Tag", text: $tag, prompt: Text(monitor.provider.tag))
                    .focused($tagFocused)
                    // Grapheme clusters, so one emoji is one tag character.
                    .onChange(of: tag) { _, new in
                        tag = String(new.prefix(3))
                        commit()
                    }
                    // The store falls back to the provider letter on empty.
                    .onChange(of: tagFocused) { _, focused in if !focused { tag = monitor.account.tag } }
                    .help("Menu bar tag, up to 3 characters (emoji count as one)")
                LabeledContent("Icon") { iconMenu }
                TextField("Name", text: $name, prompt: Text("Optional, e.g. Office"))
                    .onChange(of: name) { _, _ in commit() }
            }
            Section {
                Toggle(isOn: customised) {
                    Text("Customise menu bar")
                    Text("Off follows the Menu Bar tab.")
                }
            } header: {
                Text("Menu bar")
            }
            if monitor.account.menuBar != nil {
                MenuBarOptionToggles(
                    bars: option(\.bars), percent: option(\.percent),
                    session: option(\.session), weekly: option(\.weekly),
                    sessionCountdown: option(\.sessionCountdown), weeklyCountdown: option(\.weeklyCountdown),
                    provider: monitor.provider,
                    pinned: monitor.account.gauges != nil
                )
            }
            GaugeSettings(monitor: monitor, store: store)
            Section {
                LabeledContent {
                    Button("Remove Account…", role: .destructive) { confirmingRemoval = true }
                } label: {
                    Text("Remove account")
                    Text("Signs out and deletes its tokens from the keychain.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove this \(monitor.provider.name) account?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { store.remove(id: monitor.id) }
        } message: {
            Text("Its tokens are deleted from the keychain.")
        }
    }

    @ViewBuilder private var signInSection: some View {
        Section {
            HStack(spacing: 10) {
                AccountLabel(account: monitor.account, height: 22).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.provider.name).font(.headline)
                    Text(monitor.isSignedIn ? (monitor.identity.isEmpty ? "Signed in" : monitor.identity) : "Not signed in")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if monitor.isSignedIn {
                    Button("Sign Out") { monitor.signOut() }
                } else if monitor.pendingSignIn == nil {
                    SignInButton(monitor: monitor, store: store)
                }
            }
            if let pending = monitor.pendingSignIn {
                SignInPending(monitor: monitor, pending: pending)
            }
            if case .error(let message) = monitor.status {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// An image in place of the tag; the tag stays as the fallback and for
    /// the settings list itself.
    private var iconMenu: some View {
        Menu {
            Button(monitor.account.icon == nil ? "Choose Image…" : "Change Image…") {
                if let data = AccountIcon.pick() { setIcon(data) }
            }
            if monitor.account.icon != nil {
                Button("Remove Image") { setIcon(nil) }
            }
        } label: {
            if let data = monitor.account.icon, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: AccountIcon.pointHeight)
            } else {
                Text("None")
            }
        }
        .fixedSize()
        .help("Menu bar icon, shown instead of the tag")
    }

    private var resolved: MenuBarOptions { monitor.account.menuBar ?? MenuBarOptions.global() }

    /// Turning the override on freezes today's globals; off follows them again.
    private var customised: Binding<Bool> {
        Binding(
            get: { monitor.account.menuBar != nil },
            set: { on in
                var account = monitor.account
                account.menuBar = on ? MenuBarOptions.global() : nil
                store.update(account)
            }
        )
    }

    private func option(_ keyPath: WritableKeyPath<MenuBarOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { resolved[keyPath: keyPath] },
            set: { value in
                var account = monitor.account
                var options = resolved
                options[keyPath: keyPath] = value
                account.menuBar = options
                store.update(account)
            }
        )
    }

    private func setIcon(_ data: Data?) {
        var account = monitor.account
        account.icon = data
        store.update(account)
    }

    private func commit() {
        var account = monitor.account
        account.tag = tag
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(account)
    }
}

/// Automatic (one gauge with the provider's headline limits) or custom: gauges
/// pinned to limits picked from what the account reports, and spacers, in
/// order. The first gauge keeps the account's label; the rest have their own.
private struct GaugeSettings: View {
    let monitor: AccountMonitor
    let store: AccountStore

    private var items: [Gauge] { monitor.account.gauges ?? [] }
    private var firstGauge: UUID? { items.first { $0.kind == .pinned }?.id }

    var body: some View {
        Section {
            Picker("Limits shown", selection: custom) {
                Text("Automatic").tag(false)
                Text("Custom").tag(true)
            }
            if monitor.account.gauges != nil {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .center, spacing: 8) {
                        switch item.kind {
                        case .spacer:
                            SpacerRow(item: item, onChange: { replace(index, with: $0) })
                        case .pinned:
                            GaugeRow(gauge: item, inherited: item.id == firstGauge, account: monitor.account,
                                     choices: choices, onChange: { replace(index, with: $0) })
                        }
                        itemMenu(index, item: item)
                    }
                }
                HStack {
                    Spacer()
                    Menu("Add") {
                        Button("Gauge") { append(Gauge(tag: Gauge.nextTag(for: monitor.account))) }
                        Button("Spacer") { append(.newSpacer) }
                    }
                    .fixedSize()
                }
            }
        } header: {
            Text("Gauges")
        } footer: {
            Text(footer).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: String {
        guard monitor.account.gauges != nil else {
            return "Automatic shows the provider's main limits, usually the 5-hour session and the weekly cap. "
                + "Custom lets you choose them, add more gauges, e.g. for a model group or a single model, "
                + "and spacers between them."
        }
        var text = "Each gauge is a menu bar entry with up to two limits, short-term first. The first uses the "
            + "account's tag or icon from Label; the others, and spacers, have their own: a tag (empty uses "
            + "the account's, or for a spacer leaves a gap) or an icon."
        if monitor.snapshot == nil {
            text += " Sign in and wait for the first update to choose from this account's limits."
        }
        return text
    }

    /// The last gauge stays: a list of only spacers would have nothing to show.
    private func itemMenu(_ index: Int, item: Gauge) -> some View {
        let lastGauge = item.kind == .pinned && items.filter { $0.kind == .pinned }.count == 1
        return Menu {
            Button("Move Up") { update { $0 = Gauge.moved($0, at: index, by: -1) } }.disabled(index == 0)
            Button("Move Down") { update { $0 = Gauge.moved($0, at: index, by: 1) } }.disabled(index == items.count - 1)
            Divider()
            Button("Remove", role: .destructive) { update { $0.remove(at: index) } }.disabled(lastGauge)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move or remove")
    }

    /// The limits the account reports now, plus any pinned one that has gone
    /// missing, so a pick is never silently dropped from the menu.
    private var choices: [(id: String, label: String)] {
        let reported = (monitor.snapshot?.windows ?? []).map { ($0.id, $0.label) }
        let known = Set(reported.map(\.0))
        let missing = items.flatMap(\.windows).filter { !known.contains($0) }
        // Before the first update everything is missing, which says nothing.
        let suffix = monitor.snapshot == nil ? "" : " (not reported)"
        return reported + Array(Set(missing)).sorted().map { ($0, "\($0)\(suffix)") }
    }

    private func append(_ item: Gauge) {
        update { $0.append(item) }
    }

    private func replace(_ index: Int, with item: Gauge) {
        update { if $0.indices.contains(index) { $0[index] = item } }
    }

    /// Custom starts from today's automatic limits; Automatic forgets the list.
    private var custom: Binding<Bool> {
        Binding(
            get: { monitor.account.gauges != nil },
            set: { on in
                var account = monitor.account
                let options = MenuBarOptions.resolve(for: account, global: .global())
                account.gauges = on ? Gauge.initial(for: monitor.snapshot, options: options) : nil
                store.update(account)
            }
        )
    }

    private func update(_ change: (inout [Gauge]) -> Void) {
        var list = items
        change(&list)
        var account = monitor.account
        account.gauges = list
        store.update(account)
    }
}

/// A gauge's label (inherited for the first) and its limit pickers.
private struct GaugeRow: View {
    let gauge: Gauge
    let inherited: Bool
    let account: Account
    let choices: [(id: String, label: String)]
    let onChange: (Gauge) -> Void

    var body: some View {
        if inherited {
            InheritedLabel()
        } else {
            LabelEditor(text: gauge.tag, image: gauge.image, prompt: account.tag,
                        help: "Tag for this gauge, up to 3 characters; empty uses the account's",
                        imageMessage: "Choose an icon for this gauge") { text, image in
                var changed = gauge
                changed.tag = text
                changed.image = image
                onChange(changed)
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<Gauge.maxWindows, id: \.self) { slot in
                Picker(slot == 0 ? "First limit" : "Second limit", selection: window(slot)) {
                    Text(slot == 0 ? "Choose a limit" : "None").tag("")
                    ForEach(choices, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                // A second limit only once there is a first.
                .disabled(slot > 0 && gauge.windows.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Slot `slot` of the gauge's windows; "" means none. Clearing the first
    /// moves the second up, so the list never has a gap.
    private func window(_ slot: Int) -> Binding<String> {
        Binding(
            get: { gauge.windows.indices.contains(slot) ? gauge.windows[slot] : "" },
            set: { id in
                var windows = gauge.windows
                if id.isEmpty {
                    if windows.indices.contains(slot) { windows.remove(at: slot) }
                } else if windows.indices.contains(slot) {
                    windows[slot] = id
                } else {
                    windows.append(id)
                }
                var changed = gauge
                changed.windows = Array(windows.prefix(Gauge.maxWindows))
                onChange(changed)
            }
        )
    }
}

/// A spacer's look: text (| by default, empty for a plain gap) or an image.
private struct SpacerRow: View {
    let item: Gauge
    let onChange: (Gauge) -> Void

    var body: some View {
        let spacer = item.spacer ?? Gauge.Spacer()
        LabelEditor(text: spacer.text, image: spacer.image, prompt: "gap",
                    help: "Up to 3 characters, | by default; empty leaves a plain gap",
                    imageMessage: "Choose an icon for this menu bar spacer") { text, image in
            var changed = item
            changed.spacer = Gauge.Spacer(text: text, image: image)
            onChange(changed)
        }
        Text("Spacer").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where the label editor would be, for the first gauge, whose label is the
/// account's own. Sized by a hidden editor so the rows line up.
private struct InheritedLabel: View {
    var body: some View {
        HStack(spacing: 8) {
            LabelEditor(text: "", image: nil, prompt: "", help: "", imageMessage: "") { _, _ in }
        }
        .hidden()
        .overlay {
            Text("Inherited")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        }
        .help("The first gauge uses the account's tag or icon, set under Label above")
    }
}

/// The box at the start of a gauge or spacer row, which is itself the editor:
/// a tag field, or the icon as a button that picks another. The switch next
/// to it changes which; choosing Icon asks for one straight away, and
/// cancelling stays on the tag. Tags are capped at 3 grapheme clusters.
private struct LabelEditor: View {
    let text: String
    let image: Data?
    let prompt: String
    let help: String
    let imageMessage: String
    let onChange: (_ text: String, _ image: Data?) -> Void
    @State private var draft: String

    static let boxSize = CGSize(width: 44, height: 22)

    init(text: String, image: Data?, prompt: String, help: String, imageMessage: String,
         onChange: @escaping (_ text: String, _ image: Data?) -> Void) {
        self.text = text
        self.image = image
        self.prompt = prompt
        self.help = help
        self.imageMessage = imageMessage
        self.onChange = onChange
        _draft = State(initialValue: text)
    }

    var body: some View {
        Group {
            if let image, let picture = NSImage(data: image) {
                Button(action: pick) {
                    Image(nsImage: picture).resizable().scaledToFit()
                        .frame(height: AccountIcon.pointHeight)
                        .frame(width: Self.boxSize.width, height: Self.boxSize.height)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Click to choose another icon")
            } else {
                TextField("Label", text: $draft, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.boxSize.width)
                    .onChange(of: draft) { _, new in
                        draft = String(new.prefix(3))
                        if draft != text { onChange(draft, nil) }
                    }
                    .help(help)
            }
        }
        Picker("Label kind", selection: usesImage) {
            Text("Tag").tag(false)
            Text("Icon").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var usesImage: Binding<Bool> {
        Binding(
            get: { image != nil },
            set: { on in if on { pick() } else { onChange(draft, nil) } }
        )
    }

    private func pick() {
        if let data = AccountIcon.pick(message: imageMessage) { onChange(draft, data) }
    }
}
