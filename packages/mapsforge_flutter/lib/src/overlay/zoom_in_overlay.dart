import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/util/mapsforge_stream_builder.dart';

/// Listens to double-tap events on the map and zooms in with a smooth
/// Google-Maps-style animation: the scale eases 1→2 while the center glides
/// toward the tapped point, ending pixel-identical to the committed zoom.
class ZoomInOverlay extends StatefulWidget {
  final MapModel mapModel;
  final TapEventListener tapEventListener;

  const ZoomInOverlay({
    super.key,
    required this.mapModel,
    this.tapEventListener = TapEventListener.doubleTap,
  });

  @override
  State<ZoomInOverlay> createState() => _ZoomInOverlayState();
}

class _ZoomInOverlayState extends State<ZoomInOverlay>
    with SingleTickerProviderStateMixin {
  late final ZoomAnimator _animator =
      ZoomAnimator(mapModel: widget.mapModel, vsync: this);

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MapsforgeStreamBuilder(
      stream: widget.tapEventListener.getStream(widget.mapModel),
      builder: (BuildContext context, TapEvent? event) {
        if (event == null) return const SizedBox();

        final lastPosition = widget.mapModel.lastPosition!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Glide the center halfway toward the tapped location (the classic
          // double-tap behaviour). A second tap mid-animation commits the
          // running zoom instantly and chains from there.
          _animator.animateZoomIn(
            (event.latitude - lastPosition.latitude) / 2 +
                lastPosition.latitude,
            (event.longitude - lastPosition.longitude) / 2 +
                lastPosition.longitude,
          );
        });
        return const SizedBox();
      },
    );
  }
}
