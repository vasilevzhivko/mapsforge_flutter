import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/cache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

Future<TilePicture> _tinyTile() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = const ui.Color(0xFF336699));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(8, 8);
  picture.dispose();
  return TilePicture.fromBitmap(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stableHash is deterministic and input-sensitive', () {
    expect(DiskTileCache.stableHash('abc'), DiskTileCache.stableHash('abc'));
    expect(DiskTileCache.stableHash('abc'), isNot(DiskTileCache.stableHash('abd')));
    expect(DiskTileCache.stableHash(''), isNotEmpty);
  });

  testWidgets('write/read roundtrip, zoom gating and version invalidation', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Directory root = await Directory.systemTemp.createTemp('disk_tile_cache_test');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final DiskTileCache cache = DiskTileCache();
      await cache.init(directory: root, version: 'v1', maxZoom: 14);
      expect(cache.enabled, isTrue);

      const String key = 'renderer-key';
      final Tile tile = Tile(1, 2, 12, 0);

      expect(await cache.read(key, tile), isNull);
      await cache.write(key, tile, await _tinyTile());
      final TilePicture? hit = await cache.read(key, tile);
      expect(hit, isNotNull);
      expect(hit!.imageWidth, 8);
      hit.dispose();

      // Different renderer key = different entry.
      expect(await cache.read('other-key', tile), isNull);

      // Above maxZoom: neither written nor read.
      final Tile deep = Tile(1, 2, 15, 0);
      await cache.write(key, deep, await _tinyTile());
      expect(await cache.read(key, deep), isNull);

      // A new version starts a fresh namespace (old tiles not visible).
      await cache.init(directory: root, version: 'v2', maxZoom: 14);
      expect(await cache.read(key, tile), isNull);
    });
  });

  testWidgets('trim deletes oldest entries down to the budget', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Directory root = await Directory.systemTemp.createTemp('disk_tile_cache_trim');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final DiskTileCache cache = DiskTileCache();
      // Tiny budget: a handful of ~100-byte PNGs exceed it.
      await cache.init(directory: root, version: 'trim', budgetBytes: 400, maxZoom: 14);

      for (int i = 0; i < 8; i++) {
        final Tile tile = Tile(i, 0, 10, 0);
        await cache.write('k', tile, await _tinyTile());
        // Distinct mtimes so LRU ordering is well-defined.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await cache.trimNow();
      expect(cache.approximateBytes, lessThanOrEqualTo(400));
      // The newest entry survives, the oldest is gone.
      expect(await cache.read('k', Tile(0, 0, 10, 0)), isNull);
      final TilePicture? newest = await cache.read('k', Tile(7, 0, 10, 0));
      expect(newest, isNotNull);
      newest!.dispose();
    });
  });
}
