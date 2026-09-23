import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

/// Persistent, byte-budgeted LRU store of RENDERED tile bitmaps.
///
/// A vector map re-rasterizes every tile from scratch on every app start; on
/// mid/low-end devices the dense low/mid-zoom tiles take 100-500ms each, which
/// reads as "the map is slow" even at a fluid frame rate (land-colored areas
/// crawling in behind the viewport). Since map usage is intensely repetitive
/// (the same country overview and home regions every session), persisting the
/// rendered bitmaps makes every previously-visited area appear instantly,
/// forever: a disk read + PNG decode (~2-5ms, off the UI thread) instead of a
/// full render.
///
/// Disabled until [init] is called — the library takes a plain [Directory] so
/// it needs no path_provider dependency; the app passes a folder under its OS
/// caches directory (reclaimable under storage pressure, excluded from
/// backups).
///
/// Only zoom levels <= [init]'s maxZoom are cached: low/mid zooms are the
/// expensive, few, constantly-revisited tiles (a whole country at z8-14 is a
/// few thousand), while high zooms are cheap per tile, astronomically many
/// and rarely revisited — the worst cache economics.
class DiskTileCache {
  static final DiskTileCache _instance = DiskTileCache._();

  factory DiskTileCache() => _instance;

  DiskTileCache._();

  static final _log = Logger('DiskTileCache');

  /// The active version-scoped namespace directory; null = cache disabled.
  Directory? _dir;

  int _budgetBytes = 300 << 20;

  int _maxZoom = 14;

  int _approxBytes = 0;

  int _writesSinceTrim = 0;

  bool _trimming = false;

  bool get enabled => _dir != null;

  /// Rough total of the stored bytes (exact after the init scan / a trim).
  int get approximateBytes => _approxBytes;

  /// Enables the cache.
  ///
  /// [directory] is the cache ROOT (place it under the OS caches dir).
  /// [version] must change whenever rendered pixels would change for reasons
  /// the library cannot see — map file updated, theme file changed, POI
  /// exclusions changed. Each version gets its own namespace; namespaces of
  /// other versions are deleted in the background. [budgetBytes] <= 0
  /// disables the cache.
  Future<void> init({required Directory directory, required String version, int budgetBytes = 300 << 20, int maxZoom = 14}) async {
    _budgetBytes = budgetBytes;
    _maxZoom = maxZoom;
    if (budgetBytes <= 0) {
      _dir = null;
      return;
    }
    final String namespace = 'v${stableHash(version)}';
    final Directory namespaceDir = Directory('${directory.path}${Platform.pathSeparator}$namespace');
    try {
      await namespaceDir.create(recursive: true);
    } catch (error) {
      _log.warning('disk tile cache disabled: $error');
      _dir = null;
      return;
    }
    _dir = namespaceDir;
    unawaited(_initScan(directory, namespace));
  }

  /// Deletes stale version namespaces and measures the current one.
  Future<void> _initScan(Directory root, String keep) async {
    try {
      await for (final FileSystemEntity entity in root.list()) {
        if (entity is Directory && entity.path.split(Platform.pathSeparator).last != keep) {
          unawaited(entity.delete(recursive: true).then((_) {}, onError: (_) {}));
        }
      }
      final Directory? dir = _dir;
      if (dir == null) return;
      int total = 0;
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File) total += (await entity.stat()).size;
      }
      _approxBytes = total;
      _maybeTrim();
    } catch (_) {
      // best effort — a failed scan only delays trimming
    }
  }

  File _fileFor(String rendererKey, Tile tile) =>
      File('${_dir!.path}${Platform.pathSeparator}${stableHash(rendererKey)}_${tile.zoomLevel}_${tile.tileX}_${tile.tileY}_${tile.indoorLevel}.png');

  /// Returns the cached tile as a ready [TilePicture], or null on a miss.
  /// PNG decoding runs on the engine's IO workers, not the UI thread.
  Future<TilePicture?> read(String rendererKey, Tile tile) async {
    if (_dir == null || tile.zoomLevel > _maxZoom) return null;
    final File file = _fileFor(rendererKey, tile);
    try {
      if (!await file.exists()) return null;
      final Uint8List bytes = await file.readAsBytes();
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      // LRU recency, best effort — mtime ordering drives trimming.
      unawaited(file.setLastModified(DateTime.now()).then((_) {}, onError: (_) {}));
      return TilePicture.fromBitmap(frame.image);
    } catch (error) {
      // Corrupt/truncated entry (e.g. killed mid-write): drop and re-render.
      _log.fine('dropping unreadable cached tile $file: $error');
      unawaited(file.delete().then((_) {}, onError: (_) {}));
      return null;
    }
  }

  /// Persists a rendered tile. Fire-and-forget: PNG encoding happens on the
  /// engine side and file IO is async — never on the render critical path.
  Future<void> write(String rendererKey, Tile tile, TilePicture picture) async {
    if (_dir == null || tile.zoomLevel > _maxZoom) return;
    final ui.Image? image = picture.getImage();
    if (image == null) return;
    // Clone the handle: the borrowed image can be evicted + disposed while
    // the async encode is still running.
    final ui.Image clone = image.clone();
    try {
      final ByteData? data = await clone.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final File file = _fileFor(rendererKey, tile);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      _approxBytes += data.lengthInBytes;
      if (++_writesSinceTrim >= 64) {
        _writesSinceTrim = 0;
        _maybeTrim();
      }
    } catch (error) {
      _log.fine('tile cache write failed: $error');
    } finally {
      clone.dispose();
    }
  }

  void _maybeTrim() {
    if (_trimming || _dir == null || _approxBytes <= _budgetBytes) return;
    _trimming = true;
    unawaited(trimNow().whenComplete(() => _trimming = false));
  }

  /// Deletes least-recently-used entries until 15% under budget (hysteresis,
  /// so trimming doesn't run on every write once the budget is reached).
  Future<void> trimNow() async {
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      final List<(File, FileStat)> entries = [];
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File) entries.add((entity, await entity.stat()));
      }
      int total = 0;
      for (final (_, FileStat stat) in entries) {
        total += stat.size;
      }
      _approxBytes = total;
      if (total <= _budgetBytes) return;
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      final int target = (_budgetBytes * 0.85).round();
      for (final (File file, FileStat stat) in entries) {
        if (total <= target) break;
        try {
          await file.delete();
          total -= stat.size;
        } catch (_) {}
      }
      _approxBytes = total;
    } catch (_) {
      // best effort
    }
  }

  /// Deletes every cached tile of the current version (a "clear map cache"
  /// button). The cache stays enabled.
  Future<void> clear() async {
    final Directory? dir = _dir;
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _approxBytes = 0;
    } catch (_) {}
  }

  /// Deterministic FNV-1a 64 string hash. Dart's String.hashCode is NOT
  /// guaranteed stable across sessions — a disk cache key must be. Also
  /// usable by apps to fold their own identity inputs (e.g. an exclusion
  /// list) into the [init] version.
  static String stableHash(String input) {
    int hash = 0xcbf29ce484222325;
    for (final int unit in input.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(60).toRadixString(16);
  }
}
