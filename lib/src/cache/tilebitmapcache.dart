import 'package:mapsforge_flutter/core.dart';

import '../graphics/tilepicture.dart';

///
/// Implementations of this class provides caches for [Tile]s.
///
abstract class TileBitmapCache {
  ///
  /// disposes the cache. It should not be used anymore after disposing.
  ///
  void dispose();

  ///
  /// Returns the requested bitmap for the given [Tile]
  ///
  TilePicture? getTileBitmapSync(Tile tile);

  Future<TilePicture?> getTileBitmapAsync(Tile tile);

  ///
  /// Adds a bitmap to the cache
  ///
  void addTileBitmap(Tile tile, TilePicture tileBitmap);

  ///
  /// Purges the whole cache. The cache can be used afterwards but will not return any items
  ///
  void purgeAll();

  ///
  /// Purges the cache whose [Tile]s intersects with the given [boundingBox]. Any bitmap which is fully or partially intersecting the
  /// given [boundingBox] will be purged.
  ///
  void purgeByBoundary(BoundingBox boundingBox);
}
