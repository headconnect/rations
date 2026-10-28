import Foundation

/// One configured account. Metadata only: the tokens live in the keychain
/// vault, keyed by `id`, so this can sit in user defaults in the clear.
struct Account: Codable, Identifiable, Equatable {
    var id = UUID()
    var provider: Provider
    /// Menu bar label, 1–3 grapheme clusters (emoji count as one).
    var tag: String
    /// Optional user label, e.g. "Office".
    var name = ""
    /// nil follows the global menu bar settings.
    var menuBar: MenuBarOptions?
    /// Optional PNG shown instead of the tag, already scaled down (see
    /// AccountIcon), so it is small enough to live next to the metadata.
    var icon: Data?
    /// A customised menu bar entry: gauges and spacers in order. nil is the
    /// automatic gauge.
    var gauges: [Gauge]?

    /// Trimmed and capped by grapheme cluster so an emoji is one character;
    /// empty falls back to the provider's letter.
    static func normalized(tag: String, provider: Provider) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.tag : String(trimmed.prefix(3))
    }

    /// The provider letter, numbered from the second account on (A, A2, A3)
    /// so the menu bar gauges stay distinguishable.
    static func defaultTag(for provider: Provider, existing: [Account]) -> String {
        let taken = Set(existing.map(\.tag))
        guard taken.contains(provider.tag) else { return provider.tag }
        return (2...99).lazy.map { "\(provider.tag)\($0)" }.first { !taken.contains($0) } ?? provider.tag
    }

    /// Display order edit: moves the account at `index` by `offset`, clamped.
    static func moved(_ accounts: [Account], at index: Int, by offset: Int) -> [Account] {
        guard accounts.indices.contains(index) else { return accounts }
        let target = min(max(index + offset, 0), accounts.count - 1)
        var moved = accounts
        moved.insert(moved.remove(at: index), at: target)
        return moved
    }
}

extension Account {
    /// The synthesized decoding, except that a malformed gauge list is read
    /// lossily (or dropped) rather than failing the account, and with it the
    /// whole account list.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        provider = try values.decode(Provider.self, forKey: .provider)
        tag = try values.decode(String.self, forKey: .tag)
        name = try values.decode(String.self, forKey: .name)
        menuBar = try values.decodeIfPresent(MenuBarOptions.self, forKey: .menuBar)
        icon = try values.decodeIfPresent(Data.self, forKey: .icon)
        gauges = (try? values.decodeIfPresent(LossyList<Gauge>.self, forKey: .gauges))?.elements
    }
}
