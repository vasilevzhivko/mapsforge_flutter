import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/tile/tile_dimension.dart';
import 'package:mapsforge_flutter/src/tile/tile_set.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
import 'package:mapsforge_flutter_core/cache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/task_queue.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

/// The jobqueue for a tile. It gets informed if the size of the view changes with [setSize] and if the
/// position of the map changes [setPosition]. Based on these informations the tiles will be prepared
/// and the painter will be triggered with [notifyListeners] as soon as tiles are available.
class TileJobQueue extends ChangeNotifier {
  final MapModel mapModel;

  MapSize? _size;

  final Renderer renderer;

  // Initialised in the constructor so onEvict can close over `this` and
  // guard against disposing tiles that are still painted by the current job.
  // Byte-bounded: this layer's share of the global tile-bitmap budget.
  late final WeightedLruCache<Tile, TilePicture?> _cache;

  _CurrentJob? _currentJob;

  /// A job that has been prepared but not yet shown because we're waiting for
  /// the first tile to arrive (so we never flash a blank screen on zoom).
  _CurrentJob? _pendingJob;

  /// The previously displayed job, kept while the current one is still
  /// filling after a ZOOM change. The painter draws its tiles scaled
  /// underneath the current set so edges show stretched old-zoom imagery
  /// instead of blank flicker. Cleared once the current set is complete.
  _CurrentJob? _previousJob;

  /// Incremented on every position/size change; prefetch tasks bail out when
  /// their captured version no longer matches, so they never delay real tiles.
  int _prefetchVersion = 0;

  /// subscribe to renderChanged events which are triggered when the underlying renderdata has
  /// been changed, e.g. if a map has been added to a multimap. This should force a revalidation of the cache and
  /// a redraw of the backed view.
  late final StreamSubscription<RenderChangedEvent> _renderChangedSubscription;

  /// Parallel task queue for tile loading optimization
  late final TaskQueue _taskQueue;

  /// More concurrent workers = tiles appear faster after a zoom change.
  static const int _maxConcurrentTiles = 10;

  /// Pictures no longer owned by the cache (evicted while still displayed, or
  /// never cached at all like per-tileSet miss bitmaps). They stay alive while
  /// a current/pending tileSet references them and are disposed by
  /// [_sweepZombies] as soon as no tileSet does.
  final Set<TilePicture> _zombies = {};

  /// All live tile job queues across every map view and layer. Each cache only
  /// bounds its own share, so stacked overlays and background map views would
  /// otherwise multiply the global budget — [_enforceGlobalTileBudget] evicts
  /// across all of them.
  static final Set<TileJobQueue> _instances = {};

  /// Last time the overrun condition triggered a sweep of ALL queues.
  static DateTime _lastGlobalSweep = DateTime.fromMillisecondsSinceEpoch(0);

  TileJobQueue({required this.mapModel, required this.renderer}) {
    _cache = WeightedLruCache<Tile, TilePicture?>(
      maxWeightBytes: math.max(1 << 20, (renderer.tileCacheShare * MapsforgeSettingsMgr().tileBitmapBudgetBytes).round()),
      // Picture-backed tiles (miss placeholders) have no pixels — charge a
      // token weight so they still count as entries.
      weigher: (TilePicture? picture) => picture == null ? 64 : math.max(64, picture.imageWidth * picture.imageHeight * 4),
      onEvict: (tile, picture) {
        if (picture == null) return;
        // Do not dispose if the picture is still being painted by the
        // current, pending or previous (zoom-underlay) job — park it in the
        // zombie list instead so it gets disposed once it leaves the screen.
        final inCurrent = _currentJob?.tileSet.images[tile] == picture;
        final inPending = _pendingJob?.tileSet.images[tile] == picture;
        final inPrevious = _previousJob?.tileSet.images[tile] == picture;
        if (inCurrent || inPending || inPrevious) {
          _zombies.add(picture);
        } else {
          _disposePicture(picture);
        }
      },
    );

    _taskQueue = ParallelTaskQueue(_maxConcurrentTiles);
    _instances.add(this);

    _renderChangedSubscription = mapModel.renderChangedStream.listen((RenderChangedEvent event) {
      // simple approach, clear all
      _cache.clear();
      _prefetchVersion++;
      _taskQueue.clear();
      _pendingJob?.abort();
      _pendingJob = null;
      // The underlay was rendered with the old theme/data — drop it.
      _previousJob = null;
      _sweepZombies();
      _CurrentJob? myJob = _currentJob;
      if (myJob != null) {
        _currentJob?.abort();
        unawaited(
          _positionEvent(myJob.tileSet.mapPosition, myJob.tileDimension).catchError((error) {
            print(error);
          }),
        );
      }
    });
  }

  /// Disposes [picture] and updates the live-bitmap accounting.
  void _disposePicture(TilePicture picture) {
    TileImageStats.remove(picture.imageWidth, picture.imageHeight);
    picture.dispose();
  }

  /// Drops every cached tile bitmap across ALL live map views and layers —
  /// the memory-pressure escape hatch (`didHaveMemoryPressure`). Tiles still
  /// on screen keep displaying via the zombie mechanism and everything
  /// re-renders lazily; the only cost is extra work after the warning, far
  /// cheaper than an OOM kill.
  static void purgeAllTileCaches() {
    for (final TileJobQueue queue in _instances) {
      queue._cache.clear();
      queue._sweepZombies();
    }
  }

  /// Enforces [MapsforgeSettingsMgr.tileBitmapBudgetBytes] as a TRUE global
  /// budget across every live layer and map view: evicts LRU tiles from the
  /// heaviest cache until the summed weight fits, stopping when every cache is
  /// at its min-entries (one screenful) floor. Cross-cache eviction is safe —
  /// each queue's onEvict/zombie logic protects its displayed tiles.
  static void _enforceGlobalTileBudget() {
    int budget = MapsforgeSettingsMgr().tileBitmapBudgetBytes;
    // The effective budget can never be below what is actually ON SCREEN:
    // on a large/high-dpr viewport the per-queue one-screenful floors alone
    // can exceed a small configured budget, and enforcement would then only
    // thrash displayed tiles out of the caches into the (unfreeable,
    // still-displayed) zombie set — costing re-renders without freeing
    // anything. Give the visible working set 1.5x headroom.
    final double tileSize = MapsforgeSettingsMgr().tileSize;
    final int bytesPerTile = (tileSize * tileSize * 4).round();
    int floorBytes = 0;
    for (final TileJobQueue queue in _instances) {
      floorBytes += queue._cache.minEntries * bytesPerTile;
    }
    final int adaptive = floorBytes * 3 ~/ 2;
    if (adaptive > budget) budget = adaptive;
    // Zombies are not in any cache's weight; during heavy multi-level zoom
    // churn they can briefly dwarf the caches (observed 221MB live vs a 64MB
    // budget). When the TRUE live total runs past the budget, sweep every
    // queue first — tiles still on screen survive the sweep, so this only
    // reclaims what nothing references anymore. Throttled: enforcement runs
    // on EVERY tile insert, and during churn the overrun condition is almost
    // always true — unthrottled this swept per insert.
    if (TileImageStats.megabytes * 1024 * 1024 > budget * 1.5) {
      final DateTime now = DateTime.now();
      if (now.difference(_lastGlobalSweep) >= const Duration(milliseconds: 250)) {
        _lastGlobalSweep = now;
        for (final TileJobQueue queue in _instances) {
          queue._sweepZombies();
        }
      }
    }
    int total = 0;
    for (final TileJobQueue queue in _instances) {
      total += queue._cache.totalWeight;
    }
    while (total > budget) {
      final List<TileJobQueue> byWeight = _instances.toList()..sort((a, b) => b._cache.totalWeight.compareTo(a._cache.totalWeight));
      bool evicted = false;
      for (final TileJobQueue queue in byWeight) {
        final int before = queue._cache.totalWeight;
        if (queue._cache.evictOldest()) {
          total -= before - queue._cache.totalWeight;
          evicted = true;
          break;
        }
      }
      // Every cache is at its one-screenful floor — nothing more to reclaim.
      if (!evicted) return;
    }
  }

  /// Disposes every zombie picture that is no longer referenced by the
  /// current, pending or previous (underlay) tileSet.
  void _sweepZombies() {
    if (_zombies.isEmpty) return;
    // Build the referenced set ONCE: checking containsValue per zombie made
    // this O(zombies x tiles) hash-map iteration, and — being invoked from
    // the per-insert budget enforcement — it became the single largest CPU
    // consumer in device profiles (38%).
    final Set<TilePicture> referenced = <TilePicture>{};
    if (_currentJob != null) referenced.addAll(_currentJob!.tileSet.images.values);
    if (_pendingJob != null) referenced.addAll(_pendingJob!.tileSet.images.values);
    if (_previousJob != null) referenced.addAll(_previousJob!.tileSet.images.values);
    _zombies.removeWhere((picture) {
      if (referenced.contains(picture)) return false;
      _disposePicture(picture);
      return true;
    });
  }

  void setPosition(MapPosition position) {
    //print("Position change $position for renderer ${renderer.getRenderKey()} ${_currentJob?.tileSet.mapPosition == position}");
    if (_currentJob?.tileSet.mapPosition == position) {
      return;
    }
    if (_currentJob?.tileSet.mapPosition.latitude == position.latitude &&
        _currentJob?.tileSet.mapPosition.longitude == position.longitude &&
        _currentJob?.tileSet.mapPosition.zoomlevel == position.zoomlevel &&
        _currentJob?.tileSet.mapPosition.indoorLevel == position.indoorLevel) {
      // do not recalculate for rotation or scaling
      TileSet tileSet = TileSet(center: _currentJob!.tileSet.center, mapPosition: position);
      tileSet.images.addEntries(_currentJob!.tileSet.images.entries);
      _CurrentJob myJob = _CurrentJob(_currentJob!.tileDimension, tileSet);
      _currentJob = myJob;
      _emitTileSetBatched(_currentJob!.tileSet);
      return;
    }
    TileDimension tileDimension = TileHelper.calculateTiles(mapViewPosition: position, screensize: _size!);

    // Cancel any in-progress prefetch immediately so its queued tasks skip work.
    _prefetchVersion++;

    // Drop queued (not yet started) render tasks — they belong to a stale
    // position and would only waste CPU before bailing on their abort flag.
    _taskQueue.clear();

    // Abort any job that was prepared but never shown; keep the currently
    // displayed job alive so the map stays visible until first new tile arrives.
    _pendingJob?.abort();
    _pendingJob = null;
    _sweepZombies();

    unawaited(
      _positionEvent(position, tileDimension).catchError((error) {
        print(error);
      }),
    );
  }

  /// Promotes [job] from pending to current (aborting the old displayed job).
  /// No-op if the job has already been superseded by a newer pending job.
  void _promoteToCurrent(_CurrentJob job) {
    if (_pendingJob != job) return; // superseded
    final _CurrentJob? old = _currentJob;
    old?.abort();
    _currentJob = job;
    _pendingJob = null;
    // On a ZOOM change, keep an old set as a scaled underlay until the new
    // one is complete — otherwise the edges (rendered last) flicker blank.
    // On multi-level jumps or rapid chained zooms the outgoing job may itself
    // be nearly empty, so keep whichever underlay COVERS more of the new view
    // rather than blindly the latest one.
    if (job.tileSet.images.length >= job._expectedTiles) {
      _previousJob = null;
    } else if (old != null && old.tileSet.images.isNotEmpty && old.tileSet.mapPosition.zoomlevel != job.tileSet.mapPosition.zoomlevel) {
      if (_previousJob == null || _underlayScore(old, job) >= _underlayScore(_previousJob!, job)) {
        _previousJob = old;
      }
    }
    // else: keep the existing underlay (still valid for this zoom).
    // Tiles referenced only by dropped jobs can be released now.
    _sweepZombies();
  }

  /// How much of [job]'s viewport the tiles of [prev], scaled to [job]'s
  /// zoom, can cover (0..1). Zoomed-in underlays are magnified and can cover
  /// everything; zoomed-out ones shrink quadratically per level.
  static double _underlayScore(_CurrentJob prev, _CurrentJob job) {
    final int dz = job.tileSet.mapPosition.zoomlevel - prev.tileSet.mapPosition.zoomlevel;
    final double f = dz >= 0 ? (1 << dz).toDouble() : 1.0 / (1 << -dz);
    final double area = f >= 1 ? 1 : f * f;
    final double fill = prev._expectedTiles > 0 ? prev.tileSet.images.length / prev._expectedTiles : 0;
    return area * (fill > 1 ? 1 : fill);
  }

  /// Drops the zoom-underlay once [job] (the current job) is fully rendered,
  /// and sweeps zombies unconditionally at that point — completion is the
  /// last position-independent moment to reclaim churn leftovers; without it
  /// the final burst of evicted-while-displayed tiles sat unswept until the
  /// NEXT gesture.
  void _releaseUnderlayIfComplete(_CurrentJob job) {
    if (_currentJob != job) return;
    if (job.tileSet.images.length < job._expectedTiles) return;
    _previousJob = null;
    _sweepZombies();
  }

  @override
  void dispose() {
    super.dispose();
    _instances.remove(this);
    _renderChangedSubscription.cancel();
    _taskQueue.cancel();
    _currentJob?.abort();
    _pendingJob?.abort();
    // Drop the tileSets first so the cache's onEvict sees no references and
    // disposes every cached picture; everything not cache-owned is a zombie.
    _currentJob = null;
    _pendingJob = null;
    _previousJob = null;
    _cache.dispose();
    for (final TilePicture picture in _zombies) {
      _disposePicture(picture);
    }
    _zombies.clear();
  }

  TileSet? get tileSet => _currentJob?.tileSet;

  /// Old-zoom tiles to paint (scaled) underneath [tileSet] while it is still
  /// filling after a zoom change, or null when the current set is complete.
  TileSet? get previousTileSet => _previousJob?.tileSet;

  /// Sets the current size of the mapview so that we know which and how many tiles we need for the whole view
  void setSize(double width, double height) {
    if (_size == null || _size!.width != width || _size!.height != height) {
      _size = MapSize(width: width, height: height);
      // Never evict below one screenful of tiles plus a 1-tile ring — a byte
      // budget smaller than the viewport would otherwise thrash visible tiles.
      final double tileSize = MapsforgeSettingsMgr().tileSize;
      _cache.minEntries = ((width / tileSize).ceil() + 2) * ((height / tileSize).ceil() + 2);
      _prefetchVersion++;
      _taskQueue.clear();
      MapPosition? position = _currentJob?.tileSet.mapPosition;
      if (position != null) {
        TileDimension tileDimension = TileHelper.calculateTiles(mapViewPosition: position, screensize: _size!);
        _currentJob?.abort();
        unawaited(
          _positionEvent(position, tileDimension).catchError((error) {
            print(error);
          }),
        );
      }
      return;
    }
    _size = MapSize(width: width, height: height);
  }

  MapSize? getSize() => _size;

  Future<void> _positionEvent(MapPosition position, TileDimension tileDimension) async {
    final session = PerformanceProfiler().startSession(category: "TileJobQueue");
    TileSet tileSet = TileSet(center: position.getCenter(), mapPosition: position);
    _CurrentJob myJob = _CurrentJob(tileDimension, tileSet);
    // Register as pending — do NOT replace _currentJob yet.
    // Old tiles stay visible until we have something to show at the new position.
    _pendingJob = myJob;

    // Capture the prefetch version at the moment this job starts so prefetch
    // tasks can tell if they've been superseded by a newer position event.
    final int myPrefetchVersion = _prefetchVersion;

    List<Tile> tiles = _createTiles(mapPosition: position, tileDimension: tileDimension);
    myJob._expectedTiles = tiles.length;
    List<Tile> missingTiles = [];

    // Tiles currently on screen — carry them forward so the layer never shows
    // FEWER tiles than it already does. A Tile key includes the zoom level, so
    // this only reuses same-zoom tiles (a pan): their content is identical, so
    // the reused picture is correct and we don't even re-render it. On a zoom
    // change no old key matches, so nothing is carried (correct). Without this,
    // promoting a partially-cached new set dropped the visible tiles and a
    // transparent overlay (hillshade) flickered on every small move.
    final Map<Tile, TilePicture> displayed = _currentJob?.tileSet.images ?? const {};

    // retrieve all available tiles from cache
    for (Tile tile in tiles) {
      try {
        TilePicture? picture = _cache.get(tile);
        if (picture != null) {
          tileSet.images[tile] = picture;
        } else if (displayed.containsKey(tile)) {
          // Still-valid on-screen tile the cache has evicted — keep showing it.
          tileSet.images[tile] = displayed[tile]!;
        } else {
          missingTiles.add(tile);
        }
      } catch (error) {
        // previous tile generation not yet done or another error occured, check in the second pass
        if (displayed.containsKey(tile)) {
          tileSet.images[tile] = displayed[tile]!;
        } else {
          missingTiles.add(tile);
        }
      }
    }
    if (myJob._abort) return;
    final bool zoomChanged = _currentJob != null && _currentJob!.tileSet.mapPosition.zoomlevel != position.zoomlevel;
    if (tileSet.images.isNotEmpty || zoomChanged) {
      // Show immediately when we have cached tiles — or on a ZOOM change even
      // with an empty set: waiting for the first tile would draw the old-zoom
      // tileSet against the new position's transform (a visible snap-back
      // flash); promoting now lets the painter draw the old tiles as a
      // correctly scaled underlay instead while the new tiles arrive.
      _promoteToCurrent(myJob);
      _releaseUnderlayIfComplete(myJob);
      _emitTileSetBatched(tileSet);
    }
    // Same-zoom with nothing to show (e.g. theme change cleared the cache):
    // old job keeps displaying until _producePicture promotes us.

    for (Tile tile in missingTiles) {
      unawaited(_taskQueue.add(() => _producePicture(myJob, tileSet, tile)));
    }
    unawaited(
      _taskQueue.add(() async {
        myJob._done = true;
        // Once all visible tiles for this zoom level are ready, speculatively
        // render zoom±1 tiles so the next zoom is instant from cache. Skipped
        // for renderers that opt out (e.g. a lightweight overlay with a small
        // cache — prefetched off-zoom tiles would evict the visible ones and
        // make the layer flicker while panning).
        if (renderer.prefetchAdjacentZooms &&
            !myJob._abort &&
            _currentJob == myJob) {
          unawaited(_prefetchAdjacentZooms(position, tileDimension, myPrefetchVersion));
        }
      }),
    );
    session.complete();
  }

  Future<void> _producePicture(_CurrentJob myJob, TileSet tileSet, Tile tile) async {
    if (myJob._abort) return;
    TilePicture? picture = await _cache.getOrProduce(tile, (Tile tile) async {
      try {
        JobResult result = await renderer.executeJob(JobRequest(tile));
        if (result.picture == null) {
          //return null;
          // print("No picture for tile $tile");
          final miss = await (renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap());
          TileImageStats.add(miss.imageWidth, miss.imageHeight);
          return miss;
        }
        // make sure the picture is converted to an image because rendering (vector) pictures is usually slower than drawing images
        result.picture!.rasterize();
        TileImageStats.add(result.picture!.imageWidth, result.picture!.imageHeight);
        return result.picture!;
      } catch (error, stacktrace) {
        // error in ecache abort() method. The completer should be checked for isComplete() before injecting an exception
        print(error);
        print(stacktrace);
        rethrow;
      }
    });
    if (myJob._abort) return;
    if (picture != null) {
      // If the cache refused ownership (oversized entry) the picture would
      // otherwise never be disposed — track it as a zombie. Idempotent for
      // pictures the cache evicted into the zombie list already.
      if (!_cache.containsKey(tile)) _zombies.add(picture);
      tileSet.images[tile] = picture;
      _enforceGlobalTileBudget();
      //print("Added picture for tile $tile for renderer ${renderer.getRenderKey()}");
    } else {
      final TilePicture miss = await (renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap());
      TileImageStats.add(miss.imageWidth, miss.imageHeight);
      // Never cache-owned — register as zombie so the sweep disposes it once
      // this tileSet leaves the screen.
      _zombies.add(miss);
      tileSet.images[tile] = miss;
    }
    // If this job was waiting (pending), promote it now that we have a tile —
    // this is the moment the blank screen would appear; instead we show the
    // first tile immediately and let the rest fill in (the previous zoom's
    // tiles stay painted underneath until we're complete).
    if (_pendingJob == myJob) {
      _promoteToCurrent(myJob);
    }
    // Only emit if this is now the current displayed job.
    if (_currentJob == myJob) {
      _releaseUnderlayIfComplete(myJob);
      _emitTileSetBatched(tileSet);
    }
  }

  /// Speculatively renders tiles for [zoomDiff] ±1 levels into the LRU cache
  /// so that zoom transitions are served instantly on the next call.
  Future<void> _prefetchAdjacentZooms(
    MapPosition position,
    TileDimension tileDimension,
    int version,
  ) async {
    for (final int zoomDiff in const [-1]) {
      if (_prefetchVersion != version) return;
      final int targetZoom = position.zoomlevel + zoomDiff;
      if (targetZoom < 1 || targetZoom > 22) continue;

      final List<Tile> tiles = _tilesForAdjacentZoom(
        baseDimension: tileDimension,
        baseZoom: position.zoomlevel,
        targetZoom: targetZoom,
        indoorLevel: position.indoorLevel,
      );

      for (final Tile tile in tiles) {
        if (_prefetchVersion != version) return;
        try {
          if (_cache.get(tile) != null) continue; // already in cache
        } catch (_) {}
        unawaited(_taskQueue.add(() => _prefetchTile(tile, version)));
      }
    }
  }

  /// Renders a single tile into the cache for prefetch purposes.
  Future<void> _prefetchTile(Tile tile, int version) async {
    if (_prefetchVersion != version) return;
    try {
      final TilePicture? produced = await _cache.getOrProduce(tile, (Tile t) async {
        if (_prefetchVersion != version) return null;
        TilePicture picture;
        try {
          final JobResult result = await renderer.executeJob(JobRequest(t));
          if (result.picture == null) {
            picture = await (renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap());
          } else {
            result.picture!.rasterize();
            picture = result.picture!;
          }
        } catch (e, st) {
          print(e);
          print(st);
          picture = await (renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap());
        }
        TileImageStats.add(picture.imageWidth, picture.imageHeight);
        return picture;
      });
      // A prefetched picture the cache refused (oversized) is referenced by
      // nothing — dispose it via the zombie sweep.
      if (produced != null && !_cache.containsKey(tile)) {
        _zombies.add(produced);
      }
      _enforceGlobalTileBudget();
    } catch (_) {}
  }

  /// Returns the tiles at [targetZoom] that cover the same viewport as
  /// [baseDimension] at [baseZoom], using only the fully-visible ("min") range.
  List<Tile> _tilesForAdjacentZoom({
    required TileDimension baseDimension,
    required int baseZoom,
    required int targetZoom,
    required int indoorLevel,
  }) {
    final int diff = targetZoom - baseZoom;
    int left, right, top, bottom;

    if (diff > 0) {
      // Zooming in: each base tile splits into 2^diff children.
      final int mult = 1 << diff;
      left = baseDimension.minLeft * mult;
      right = (baseDimension.minRight + 1) * mult - 1;
      top = baseDimension.minTop * mult;
      bottom = (baseDimension.minBottom + 1) * mult - 1;
    } else {
      // Zooming out: 2^|diff| base tiles merge into one parent tile.
      final int shift = -diff;
      left = baseDimension.minLeft >> shift;
      right = baseDimension.minRight >> shift;
      top = baseDimension.minTop >> shift;
      bottom = baseDimension.minBottom >> shift;
    }

    final List<Tile> tiles = [];
    for (int tileY = top; tileY <= bottom; tileY++) {
      for (int tileX = left; tileX <= right; tileX++) {
        tiles.add(Tile(tileX, tileY, targetZoom, indoorLevel));
      }
    }
    return tiles;
  }

  /// Emit tile set with batching to reduce stream emissions
  void _emitTileSetBatched(TileSet tileSet) {
    notifyListeners();
    // _batchTileset = tileSet;
    // // Set new timer for batching
    // _batchTimer ??= Timer(const Duration(milliseconds: 16), () {
    //   // ~60fps
    //   _batchTimer = null;
    //   if (_batchTileset != null && !_tileStream.isClosed) {
    //     _tileStream.add(_batchTileset!);
    //   }
    // });
  }

  ///
  /// Get all tiles needed for a given view. The tiles are in the order where it makes most sense for
  /// the user (tile in the middle should be created first
  ///
  List<Tile> _createTiles({required MapPosition mapPosition, required TileDimension tileDimension}) {
    int zoomLevel = mapPosition.zoomlevel;
    int indoorLevel = mapPosition.indoorLevel;
    Mappoint center = mapPosition.getCenter();
    // shift the center to the left-upper corner of a tile since we will calculate the distance to the left-upper corners of each tile
    MappointRelative relative = center.offset(Mappoint(MapsforgeSettingsMgr().tileSize / 2, MapsforgeSettingsMgr().tileSize / 2));
    Map<Tile, double> tileMap = <Tile, double>{};
    for (int tileY = tileDimension.minTop; tileY <= tileDimension.minBottom; ++tileY) {
      for (int tileX = tileDimension.minLeft; tileX <= tileDimension.minRight; ++tileX) {
        Tile tile = Tile(tileX, tileY, zoomLevel, indoorLevel);
        Mappoint leftUpper = tile.getLeftUpper();
        // Replace pow() with multiplication for better performance
        double dx = leftUpper.x - relative.dx;
        double dy = leftUpper.y - relative.dy;
        tileMap[tile] = dx * dx + dy * dy;
      }
    }
    //_log.info("$tileTop, $tileBottom, sort ${tileMap.length} items");

    List<Tile> sortedKeys = tileMap.keys.toList(growable: false)..sort((k1, k2) => tileMap[k1]!.compareTo(tileMap[k2]!));

    for (int tileY = tileDimension.top; tileY <= tileDimension.bottom; ++tileY) {
      for (int tileX = tileDimension.left; tileX <= tileDimension.right; ++tileX) {
        if (tileX >= tileDimension.minLeft && tileX <= tileDimension.minRight && tileY >= tileDimension.minTop && tileY <= tileDimension.minBottom) continue;
        Tile tile = Tile(tileX, tileY, zoomLevel, indoorLevel);
        sortedKeys.add(tile);
      }
    }

    return sortedKeys;
  }
}

//////////////////////////////////////////////////////////////////////////////

class _CurrentJob {
  final TileDimension tileDimension;

  final TileSet tileSet;

  /// Total number of tiles this job will produce; used to detect completion
  /// (when the zoom-underlay of the previous job can be released).
  int _expectedTiles = 0;

  bool _done = false;

  bool _abort = false;

  _CurrentJob(this.tileDimension, this.tileSet);

  void abort() => _abort = true;
}
