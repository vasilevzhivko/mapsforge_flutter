import 'dart:async';
import 'dart:collection';

/// A byte-budgeted LRU cache.
///
/// Unlike an entry-count LRU, eviction is driven by the summed weight of the
/// stored values (as reported by [weigher], typically bytes), so a few huge
/// values cannot silently blow the memory budget. Values heavier than
/// [maxEntryWeightBytes] are never cached at all — one oversized value must
/// not evict a whole working set.
///
/// Not thread-safe; intended for single-isolate use.
class WeightedLruCache<K, V> {
  /// Total weight budget for all cached values.
  final int maxWeightBytes;

  /// Values weighing more than this are returned/ignored without caching.
  /// Defaults to a quarter of [maxWeightBytes].
  final int maxEntryWeightBytes;

  /// Never evict below this many entries, regardless of weight. Guards
  /// against thrashing when the budget is smaller than one working set
  /// (e.g. the tiles visible on screen). Mutable so callers can adjust it
  /// when the viewport size becomes known. Regardless of this value, at
  /// least one entry is always kept so a just-inserted value can never be
  /// evicted by its own insertion.
  int minEntries;

  /// Returns the weight of a value in bytes.
  final int Function(V value) weigher;

  /// Called for every value that leaves the cache (eviction, [clear],
  /// [dispose] or replacement by [set]).
  final void Function(K key, V value)? onEvict;

  final LinkedHashMap<K, V> _entries = LinkedHashMap();

  /// In-flight producers so concurrent [getOrProduce] calls for the same key
  /// share one future. Weight is only accounted once the value is stored.
  final Map<K, Future<V>> _producing = {};

  int _totalWeight = 0;

  WeightedLruCache({required this.maxWeightBytes, required this.weigher, int? maxEntryWeightBytes, this.minEntries = 0, this.onEvict})
    : assert(maxWeightBytes > 0),
      maxEntryWeightBytes = maxEntryWeightBytes ?? maxWeightBytes ~/ 4;

  int get length => _entries.length;

  int get totalWeight => _totalWeight;

  bool containsKey(K key) => _entries.containsKey(key);

  /// Returns the cached value for [key] and marks it most-recently-used, or
  /// null if absent.
  V? get(K key) {
    if (!_entries.containsKey(key)) return null;
    final V value = _entries.remove(key) as V;
    _entries[key] = value; // re-insert -> most recently used
    return value;
  }

  /// Stores [value] under [key]. A value heavier than [maxEntryWeightBytes]
  /// is not stored (and [onEvict] is not called for it — the caller keeps
  /// ownership; check [containsKey] afterwards if ownership matters).
  void set(K key, V value) {
    remove(key, evict: true);
    final int weight = weigher(value);
    if (weight > maxEntryWeightBytes) return;
    _entries[key] = value;
    _totalWeight += weight;
    _evictWhileOverBudget();
  }

  /// Removes and returns the value for [key]. With [evict] the [onEvict]
  /// callback fires for it (ownership stays with the cache); without, the
  /// caller takes ownership.
  V? remove(K key, {bool evict = false}) {
    if (!_entries.containsKey(key)) return null;
    final V value = _entries.remove(key) as V;
    _totalWeight -= weigher(value);
    if (evict) onEvict?.call(key, value);
    return value;
  }

  /// Returns the value for [key], producing (and caching) it if absent.
  /// Concurrent calls for the same key share a single [produce] invocation.
  /// A produced null (for nullable V) is returned but never cached.
  Future<V> getOrProduce(K key, Future<V> Function(K key) produce) {
    final V? existing = get(key);
    if (existing != null) return Future.value(existing);
    final Future<V>? inFlight = _producing[key];
    if (inFlight != null) return inFlight;
    final Future<V> future = () async {
      try {
        final V value = await produce(key);
        if (value != null) set(key, value);
        return value;
      } finally {
        unawaited(_producing.remove(key));
      }
    }();
    _producing[key] = future;
    return future;
  }

  /// Evicts the least-recently-used entry, respecting the [minEntries] floor.
  /// Returns true if an entry was evicted. Used by coordinators that enforce
  /// a budget ACROSS several caches.
  bool evictOldest() {
    final int floor = minEntries > 1 ? minEntries : 1;
    if (_entries.length <= floor) return false;
    remove(_entries.keys.first, evict: true);
    return true;
  }

  /// Evicts everything (firing [onEvict] per entry). In-flight producers are
  /// unaffected; their results will be cached on completion.
  void clear() {
    for (final MapEntry<K, V> entry in _entries.entries.toList()) {
      onEvict?.call(entry.key, entry.value);
    }
    _entries.clear();
    _totalWeight = 0;
  }

  void dispose() {
    clear();
  }

  void _evictWhileOverBudget() {
    // The floor of 1 guarantees the most recently inserted entry survives its
    // own insertion — callers may hold a borrowed reference to it.
    final int floor = minEntries > 1 ? minEntries : 1;
    while (_totalWeight > maxWeightBytes && _entries.length > floor) {
      final K oldest = _entries.keys.first;
      remove(oldest, evict: true);
    }
  }

  @override
  String toString() {
    return 'WeightedLruCache{entries: ${_entries.length}, weight: $_totalWeight/$maxWeightBytes}';
  }
}
