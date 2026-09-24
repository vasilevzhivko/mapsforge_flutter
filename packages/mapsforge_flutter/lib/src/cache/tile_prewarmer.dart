import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/cache/disk_tile_cache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// Automatically pre-renders the low/mid-zoom tiles of a map into the
/// [DiskTileCache], so country-level browsing is instant on the FIRST visit —
/// not only on revisits.
///
/// Deliberately unobtrusive:
/// - renders ONE tile at a time, only while the app is foregrounded and the
///   map has been untouched for [idleThreshold] — the moment the user pans or
///   zooms it backs off;
/// - skips tiles already on disk (a cheap file check), which also makes it
///   resumable across sessions for free;
/// - stops itself when the disk cache is disabled, when [stop] is called, or
///   when a newer [start] supersedes it.
///
/// Sizing intuition: a whole country at z<=12 is a few thousand tiles
/// (~150MB as PNG) — minutes of one-time background work; z13+ has the worst
/// cache economics and is left to fill organically from real usage.
class TilePrewarmer {
  static final TilePrewarmer _instance = TilePrewarmer._();

  factory TilePrewarmer() => _instance;

  TilePrewarmer._();

  static final _log = Logger('TilePrewarmer');

  /// Bumped by [stop]/[start]; a running loop exits when its generation is
  /// no longer current.
  int _generation = 0;

  MapModel? _listenedModel;

  DateTime _lastMapActivity = DateTime.now();

  void _onMapActivity() => _lastMapActivity = DateTime.now();

  bool get isRunning => _listenedModel != null;

  /// Stops any running prewarm.
  void stop() {
    _generation++;
    _listenedModel?.removeListener(_onMapActivity);
    _listenedModel = null;
  }

  /// Starts (or restarts) prewarming [boundingBox] for zoom 0..[maxZoom]
  /// through [renderer]. No-op if the renderer opts out of disk caching or
  /// the cache is disabled. [initialDelay] keeps the startup burst (live
  /// tiles, sync work) uncontested.
  void start({
    required Renderer renderer,
    required MapModel mapModel,
    required BoundingBox boundingBox,
    int maxZoom = 12,
    Duration initialDelay = const Duration(seconds: 15),
    Duration idleThreshold = const Duration(seconds: 2),
  }) {
    stop();
    if (renderer.diskCacheKey == null || !DiskTileCache().enabled) return;
    final int generation = _generation;
    _listenedModel = mapModel;
    _lastMapActivity = DateTime.now();
    mapModel.addListener(_onMapActivity);
    unawaited(
      _run(generation, renderer, boundingBox, maxZoom, initialDelay, idleThreshold).catchError((Object error) {
        _log.warning('prewarm aborted: $error');
      }),
    );
  }

  Future<void> _run(int generation, Renderer renderer, BoundingBox bb, int maxZoom, Duration initialDelay, Duration idleThreshold) async {
    final String diskKey = renderer.diskCacheKey!;
    await Future<void>.delayed(initialDelay);
    int rendered = 0;
    int alreadyCached = 0;
    for (int zoom = 0; zoom <= maxZoom; zoom++) {
      final MercatorProjection projection = MercatorProjection.fromZoomlevel(zoom);
      final int xMin = projection.longitudeToTileX(bb.minLongitude);
      final int xMax = projection.longitudeToTileX(bb.maxLongitude);
      final int yMin = projection.latitudeToTileY(bb.maxLatitude);
      final int yMax = projection.latitudeToTileY(bb.minLatitude);
      for (int tileY = yMin; tileY <= yMax; tileY++) {
        for (int tileX = xMin; tileX <= xMax; tileX++) {
          if (generation != _generation) return;
          if (!DiskTileCache().enabled) {
            stop();
            return;
          }
          final Tile tile = Tile(tileX, tileY, zoom, 0);
          if (await DiskTileCache().contains(diskKey, tile)) {
            alreadyCached++;
            continue;
          }
          await _waitUntilIdle(generation, idleThreshold);
          if (generation != _generation) return;
          try {
            final JobResult result = await renderer.executeJob(JobRequest(tile));
            final picture = result.picture;
            if (picture != null) {
              picture.rasterize();
              await DiskTileCache().write(diskKey, tile, picture);
              picture.dispose();
              rendered++;
            }
          } catch (error) {
            _log.fine('prewarm render failed for $tile: $error');
          }
          // Breathe between tiles so frames and live tile work interleave.
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      _log.info('prewarm z$zoom done (rendered=$rendered alreadyCached=$alreadyCached)');
    }
    _log.info('prewarm complete up to z$maxZoom: rendered=$rendered alreadyCached=$alreadyCached');
    if (generation == _generation) stop();
  }

  /// Waits until the app is foregrounded and the map has been untouched for
  /// [idleThreshold] (or the run is superseded).
  Future<void> _waitUntilIdle(int generation, Duration idleThreshold) async {
    while (generation == _generation) {
      final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
      final bool foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
      final bool idle = DateTime.now().difference(_lastMapActivity) >= idleThreshold;
      if (foreground && idle) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
