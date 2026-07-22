import 'dart:async';

import 'package:mapsforge_flutter_core/cache.dart';
import 'package:test/test.dart';

void main() {
  group('WeightedLruCache', () {
    test('accounts weight and evicts least-recently-used first', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 100, onEvict: (k, v) => evicted.add(k));

      cache.set('a', 40);
      cache.set('b', 40);
      expect(cache.totalWeight, 80);

      cache.set('c', 40); // over budget -> evict 'a' (oldest)
      expect(evicted, ['a']);
      expect(cache.get('a'), isNull);
      expect(cache.totalWeight, 80);
    });

    test('get marks entry most-recently-used', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 100, onEvict: (k, v) => evicted.add(k));

      cache.set('a', 40);
      cache.set('b', 40);
      expect(cache.get('a'), 40); // 'a' becomes MRU
      cache.set('c', 40); // evicts 'b', not 'a'
      expect(evicted, ['b']);
      expect(cache.get('a'), 40);
    });

    test('oversized values are returned but never cached', () async {
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 50);

      cache.set('huge', 60);
      expect(cache.containsKey('huge'), isFalse);
      expect(cache.totalWeight, 0);

      final int produced = await cache.getOrProduce('huge2', (_) async => 80);
      expect(produced, 80);
      expect(cache.containsKey('huge2'), isFalse);
    });

    test('one oversized insert cannot flush the working set', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 25, onEvict: (k, v) => evicted.add(k));

      cache.set('a', 20);
      cache.set('b', 20);
      cache.set('big', 90); // above maxEntryWeightBytes -> skipped
      expect(evicted, isEmpty);
      expect(cache.length, 2);
    });

    test('replacement via set evicts the old value', () {
      final List<int> evictedValues = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 100, onEvict: (k, v) => evictedValues.add(v));

      cache.set('a', 30);
      cache.set('a', 50);
      expect(evictedValues, [30]);
      expect(cache.totalWeight, 50);
      expect(cache.get('a'), 50);
    });

    test('minEntries floor prevents eviction below one working set', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, maxEntryWeightBytes: 100, onEvict: (k, v) => evicted.add(k));
      cache.minEntries = 3;

      cache.set('a', 60);
      cache.set('b', 60);
      cache.set('c', 60); // 180 > 100, but only 3 entries -> no eviction
      expect(evicted, isEmpty);
      expect(cache.length, 3);

      cache.set('d', 60); // 4 entries -> evict down to the floor of 3
      expect(evicted, ['a']);
      expect(cache.length, 3);
    });

    test('a just-inserted entry survives its own insertion even when alone and over budget', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 10, weigher: (v) => v, maxEntryWeightBytes: 100, onEvict: (k, v) => evicted.add(k));

      cache.set('only', 50); // over budget but never evicts itself
      expect(evicted, isEmpty);
      expect(cache.get('only'), 50);
    });

    test('concurrent getOrProduce shares one producer invocation', () async {
      int produceCalls = 0;
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v);
      final Completer<int> gate = Completer();

      final Future<int> first = cache.getOrProduce('k', (_) async {
        produceCalls++;
        return gate.future;
      });
      final Future<int> second = cache.getOrProduce('k', (_) async {
        produceCalls++;
        return -1;
      });

      gate.complete(7);
      expect(await first, 7);
      expect(await second, 7);
      expect(produceCalls, 1);
      expect(cache.get('k'), 7);
    });

    test('failed producer does not poison the key', () async {
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v);

      await expectLater(cache.getOrProduce('k', (_) async => throw StateError('boom')), throwsStateError);
      expect(await cache.getOrProduce('k', (_) async => 5), 5);
    });

    test('clear evicts everything with callbacks', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, onEvict: (k, v) => evicted.add(k));

      cache.set('a', 10);
      cache.set('b', 10);
      cache.clear();
      expect(evicted, unorderedEquals(['a', 'b']));
      expect(cache.length, 0);
      expect(cache.totalWeight, 0);
    });

    test('remove without evict transfers ownership silently', () {
      final List<String> evicted = [];
      final cache = WeightedLruCache<String, int>(maxWeightBytes: 100, weigher: (v) => v, onEvict: (k, v) => evicted.add(k));

      cache.set('a', 10);
      expect(cache.remove('a'), 10);
      expect(evicted, isEmpty);
      expect(cache.totalWeight, 0);
    });
  });
}
