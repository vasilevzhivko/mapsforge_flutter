import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/src/map_model.dart';
import 'package:mapsforge_flutter/src/map_position.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// An online renderer whose request is torn down by the OS (app backgrounded
/// mid-download).
class _AbortingRenderer extends Renderer {
  int calls = 0;

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) {
    calls++;
    return Future.error(const SocketException('Software caused connection abort'));
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async => JobResult.unsupported();

  @override
  String getRenderKey() => 'aborting';

  @override
  bool supportLabels() => false;
}

void main() {
  // hikerbgapp #826 #825: a failed tile render must not escape the
  // fire-and-forget task queue into the root zone ("GLOBAL ZONE ERROR").
  test('a failing tile render does not escape to the zone', () async {
    final List<Object> zoneErrors = [];
    final renderer = _AbortingRenderer();
    final model = MapModel(renderer: renderer);
    late TileJobQueue queue;
    await runZonedGuarded(() async {
      queue = TileJobQueue(mapModel: model, renderer: renderer);
      queue.setSize(512, 512);
      queue.setPosition(MapPosition(42.7, 23.3, 12));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }, (error, stack) => zoneErrors.add(error));
    expect(renderer.calls, greaterThan(0), reason: 'the renderer must have been asked for tiles');
    expect(zoneErrors, isEmpty);
    queue.dispose();
  });
}
