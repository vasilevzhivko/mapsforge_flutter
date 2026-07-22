import 'dart:collection';
import 'dart:io';

import 'package:ecache/ecache.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/hgt/hgt_file.dart';

class HgtFileProvider extends HgtProvider {
  final String directoryPath;

  final int maxEntries;

  // elevation data columns per degree longitude
  final int columnsPerDegree;

  // degree per file in horizontal/vertical direction
  final int step;

  final LinkedHashMap<String, HgtFile> _cache = LinkedHashMap<String, HgtFile>();

  final ExpirationCache<String, HgtFile> _missingFiles = ExpirationCache<String, HgtFile>(expiration: const Duration(minutes: 1), capacity: 100000);

  /// Int-keyed fast path for [getForLatLon]: hillshading calls it thousands of
  /// times per tile, and building the filename string per call dominated a CPU
  /// profile. Only successfully loaded files land here (missing files keep
  /// their retry semantics via [_missingFiles]).
  final Map<int, HgtFile> _cellCache = {};

  HgtFileProvider({required this.directoryPath, this.maxEntries = 256, this.columnsPerDegree = 120, this.step = 2}) : assert(!directoryPath.endsWith("/"));

  String buildFilename({required int baseLat, required int baseLon}) {
    final latPrefix = baseLat >= 0 ? 'N' : 'S';
    final lonPrefix = baseLon >= 0 ? 'E' : 'W';
    final latAbs = baseLat.abs().toString().padLeft(2, '0');
    final lonAbs = baseLon.abs().toString().padLeft(3, '0');
    return '$latPrefix$latAbs$lonPrefix$lonAbs.hgt';
  }

  @override
  HgtFile getForLatLon(double latitude, double longitude) {
    final baseLat = (latitude / step).floor() * step;
    final baseLon = (longitude / step).floor() * step;

    final int cellKey = (baseLat + 90) * 360 + (baseLon + 180);
    final HgtFile? byCell = _cellCache[cellKey];
    if (byCell != null) {
      return byCell;
    }

    final filename = buildFilename(baseLat: baseLat, baseLon: baseLon);

    final cached = _cache[filename];
    if (cached != null) {
      if (cached.rows != 0) _cellCache[cellKey] = cached;
      return cached;
    }
    HgtFile? hgt = _missingFiles.get(filename);
    if (hgt != null) {
      return hgt;
    }

    final file = File('$directoryPath${Platform.pathSeparator}$filename');

    hgt = HgtFile.readFromFile(file, baseLat: baseLat, baseLon: baseLon, tileWidth: step, tileHeight: step, rows: columnsPerDegree * step);
    _cache[filename] = hgt;

    if (hgt.rows == 0) {
      // missing
      _missingFiles.set(filename, hgt);
    } else {
      _cellCache[cellKey] = hgt;
    }

    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
      // Rare: keep the fast path consistent with the LRU without tracking a
      // reverse mapping.
      _cellCache.clear();
    }

    return hgt;
  }
}
