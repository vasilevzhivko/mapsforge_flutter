import 'dart:async';

import 'package:ecache/ecache.dart';
import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/tile/tile_dimension.dart';
import 'package:mapsforge_flutter/src/tile/tile_set.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
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
  late final LruCache<Tile, TilePicture?> _cache;

  _CurrentJob? _currentJob;

  /// A job that has been prepared but not yet shown because we're waiting for
  /// the first tile to arrive (so we never flash a blank screen on zoom).
  _CurrentJob? _pendingJob;

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

  TileJobQueue({required this.mapModel, required this.renderer}) {
    _cache = LruCache<Tile, TilePicture?>(
      onEvict: (tile, picture) {
        if (picture == null) return;
        // Do not dispose if the picture is still being painted by the
        // current or pending job — that would crash the painter.
        final inCurrent = _currentJob?.tileSet.images[tile] == picture;
        final inPending = _pendingJob?.tileSet.images[tile] == picture;
        if (!inCurrent && !inPending) {
          picture.dispose();
        }
      },
      capacity: 800,
      name: "TileJobQueue",
    );

    _taskQueue = ParallelTaskQueue(_maxConcurrentTiles);

    _renderChangedSubscription = mapModel.renderChangedStream.listen((RenderChangedEvent event) {
      // simple approach, clear all
      _cache.clear();
      _prefetchVersion++;
      _pendingJob?.abort();
      _pendingJob = null;
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

    // Abort any job that was prepared but never shown; keep the currently
    // displayed job alive so the map stays visible until first new tile arrives.
    _pendingJob?.abort();
    _pendingJob = null;

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
    _currentJob?.abort();
    _currentJob = job;
    _pendingJob = null;
  }

  @override
  void dispose() {
    super.dispose();
    _currentJob?.abort();
    _renderChangedSubscription.cancel();
    _taskQueue.cancel();
    _pendingJob?.abort();
    _pendingJob = null;
    _cache.dispose();
  }

  TileSet? get tileSet => _currentJob?.tileSet;

  /// Sets the current size of the mapview so that we know which and how many tiles we need for the whole view
  void setSize(double width, double height) {
    if (_size == null || _size!.width != width || _size!.height != height) {
      _size = MapSize(width: width, height: height);
      _prefetchVersion++;
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
    List<Tile> missingTiles = [];

    // retrieve all available tiles from cache
    for (Tile tile in tiles) {
      try {
        TilePicture? picture = _cache.get(tile);
        if (picture != null) {
          tileSet.images[tile] = picture;
        } else {
          missingTiles.add(tile);
        }
      } catch (error) {
        // previous tile generation not yet done or another error occured, check in the second pass
        missingTiles.add(tile);
      }
    }
    if (myJob._abort) return;
    if (tileSet.images.isNotEmpty) {
      // Have cached tiles — show immediately, replacing old display.
      _promoteToCurrent(myJob);
      _emitTileSetBatched(tileSet);
    }
    // If no cached tiles: old job keeps displaying until _producePicture promotes us.

    for (Tile tile in missingTiles) {
      unawaited(_taskQueue.add(() => _producePicture(myJob, tileSet, tile)));
    }
    unawaited(
      _taskQueue.add(() async {
        myJob._done = true;
        // Once all visible tiles for this zoom level are ready, speculatively
        // render zoom±1 tiles so the next zoom is instant from cache.
        if (!myJob._abort && _currentJob == myJob) {
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
          return renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap();
        }
        // make sure the picture is converted to an image because rendering (vector) pictures is usually slower than drawing images
        result.picture!.convertPictureToImage();
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
      tileSet.images[tile] = picture;
      //print("Added picture for tile $tile for renderer ${renderer.getRenderKey()}");
    } else {
      tileSet.images[tile] =
          await (renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap());
    }
    // If this job was waiting (pending), promote it now that we have a tile —
    // this is the moment the blank screen would appear; instead we show the
    // first tile immediately and let the rest fill in.
    if (_pendingJob == myJob) {
      _promoteToCurrent(myJob);
    }
    // Only emit if this is now the current displayed job.
    if (_currentJob == myJob) {
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
      await _cache.getOrProduce(tile, (Tile t) async {
        if (_prefetchVersion != version) return null;
        try {
          final JobResult result = await renderer.executeJob(JobRequest(t));
          if (result.picture == null) {
            return renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap();
          }
          result.picture!.convertPictureToImage();
          return result.picture!;
        } catch (e, st) {
          print(e);
          print(st);
          return renderer.transparentOnMiss ? ImageHelper().createTransparentBitmap() : ImageHelper().createNoDataBitmap();
        }
      });
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

  bool _done = false;

  bool _abort = false;

  _CurrentJob(this.tileDimension, this.tileSet);

  void abort() => _abort = true;
}
