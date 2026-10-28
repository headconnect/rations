import Foundation

/// One item of a customised menu bar entry, in order: a gauge pinned to up
/// to two limits by id, short-term first by convention (e.g. Antigravity's
/// `3p-5h` and `3p-weekly`), or a spacer. The first gauge shows the account's
/// own tag or icon; later ones their own, or the account's if left empty.
struct Gauge: Codable, Identifiable, Equatable {
    static let maxWindows = 2

    enum Kind: String, Codable { case pinned, spacer }

    /// Text such as "|" (empty is a plain gap) or, if set, an image instead.
    struct Spacer: Codable, Equatable {
        static let defaultText = "|"
        var text = Spacer.defaultText
        var image: Data?
    }

    var id = UUID()
    var kind = Kind.pinned
    var tag = ""
    /// Drawn instead of the tag, like an account icon.
    var image: Data?
    var windows: [String] = []
    var spacer: Spacer?

    static var newSpacer: Gauge { Gauge(kind: .spacer, spacer: Spacer()) }

    /// What one item draws.
    struct Resolved: Identifiable {
        let id: UUID
        /// nil (and no image) draws the account's icon or tag.
        let tag: String?
        let image: Data?
        let windows: [UsageWindow]
        let pinned: Bool
        /// Set for spacers, which draw only this.
        let spacer: Spacer?
    }

    /// The account's items against its latest usage. An automatic account (no
    /// list, or one without any gauge) has one gauge with the headline windows
    /// the options select. A pinned limit the provider stopped reporting is
    /// skipped, not forgotten; a gauge with none left draws "–".
    static func resolve(_ account: Account, snapshot: UsageSnapshot?, options: MenuBarOptions) -> [Resolved] {
        guard let items = account.gauges, let first = items.first(where: { $0.kind == .pinned })?.id else {
            return [Resolved(id: account.id, tag: nil, image: nil, windows: snapshot.map { options.selectedWindows(in: $0) } ?? [],
                             pinned: false, spacer: nil)]
        }
        return items.map { item in
            switch item.kind {
            case .pinned:
                let windows = item.windows.compactMap { id in snapshot?.windows.first { $0.id == id } }
                // The first gauge is the account's own entry, so it keeps the account's label.
                let tag = item.id == first ? "" : item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                return Resolved(id: item.id, tag: tag.isEmpty ? nil : String(tag.prefix(3)),
                                image: item.id == first ? nil : item.image, windows: windows, pinned: true, spacer: nil)
            case .spacer:
                return Resolved(id: item.id, tag: nil, image: nil, windows: [], pinned: false, spacer: item.spacer ?? Spacer())
            }
        }
    }

    /// Starting point when the user customises: today's automatic headline,
    /// so switching changes nothing until a limit is picked.
    static func initial(for snapshot: UsageSnapshot?) -> [Gauge] {
        [Gauge(windows: snapshot?.headline.map(\.id) ?? [])]
    }

    /// Default tag for a further gauge: the account tag numbered (Y2, Y3).
    static func nextTag(for account: Account) -> String {
        let taken = Set((account.gauges ?? []).map(\.tag))
        return (2...99).lazy.map { "\(account.tag.prefix(2))\($0)" }.first { !taken.contains($0) } ?? account.tag
    }

    /// Display order edit: moves the item at `index` by `offset`, clamped.
    static func moved(_ items: [Gauge], at index: Int, by offset: Int) -> [Gauge] {
        guard items.indices.contains(index) else { return items }
        let target = min(max(index + offset, 0), items.count - 1)
        var moved = items
        moved.insert(moved.remove(at: index), at: target)
        return moved
    }
}

extension Gauge {
    /// Every field optional, so a list saved by another build never fails to
    /// decode; a failure there would drop the whole account list.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // Unknown kinds, such as a future one, read as a plain gauge.
        kind = (try? values.decodeIfPresent(Kind.self, forKey: .kind)) ?? .pinned
        tag = try values.decodeIfPresent(String.self, forKey: .tag) ?? ""
        image = try? values.decodeIfPresent(Data.self, forKey: .image)
        windows = try values.decodeIfPresent([String].self, forKey: .windows) ?? []
        spacer = try? values.decodeIfPresent(Spacer.self, forKey: .spacer)
    }
}

extension Gauge.Spacer {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? Self.defaultText
        image = try values.decodeIfPresent(Data.self, forKey: .image)
    }
}
