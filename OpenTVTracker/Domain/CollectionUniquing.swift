import Foundation

/// Crash-safe dictionary construction for library IDs that may be duplicated by import or merge bugs.
enum CollectionUniquing {
    /// Builds a dictionary, keeping the last value when keys collide.
    static func dictionary<Key: Hashable, Value>(
        keepingLast pairs: some Sequence<(Key, Value)>
    ) -> [Key: Value] {
        Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    /// Builds a dictionary, keeping the first value when keys collide.
    static func dictionary<Key: Hashable, Value>(
        keepingFirst pairs: some Sequence<(Key, Value)>
    ) -> [Key: Value] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// Stable first-wins dedupe by key while preserving encounter order.
    static func uniqued<Element, Key: Hashable>(
        _ values: [Element],
        by key: (Element) -> Key
    ) -> [Element] {
        var seen = Set<Key>()
        return values.filter { seen.insert(key($0)).inserted }
    }
}

extension Sequence {
    /// Dictionary keyed by the given property; last write wins on collision.
    func keyedByKeepingLast<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        CollectionUniquing.dictionary(keepingLast: map { ($0[keyPath: keyPath], $0) })
    }

    /// Dictionary keyed by the given property; first write wins on collision.
    func keyedByKeepingFirst<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        CollectionUniquing.dictionary(keepingFirst: map { ($0[keyPath: keyPath], $0) })
    }
}
