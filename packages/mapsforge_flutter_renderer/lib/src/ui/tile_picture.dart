import 'dart:ui' as ui;

import 'package:mapsforge_flutter_core/utils.dart';

/// A container for either a `ui.Picture` (a recorded sequence of drawing
/// commands) or a `ui.Image` (raw pixel data).
///
/// This class is used to represent a rendered map tile.
///
/// Ownership contract: a TilePicture exclusively owns its underlying
/// `ui.Picture`/`ui.Image`. Accessors return borrowed references that must not
/// be disposed by the caller and must not be held across an await. Exactly one
/// owner calls [dispose] — for tiles this is the tile cache (via onEvict) or
/// the TileJobQueue's zombie sweep.
class TilePicture {
  ui.Picture? _picture;

  ui.Image? _image;

  /// Creates a [TilePicture] from a `ui.Picture`.
  TilePicture.fromPicture(this._picture) : _image = null;

  /// Creates a [TilePicture] from a `ui.Image`.
  ///
  /// The responsibility to dispose the image is transferred to this class.
  TilePicture.fromBitmap(this._image)
    : assert(_image != null, "Image must not be null"),
      assert(!_image!.debugDisposed, "Image is already disposed"),
      _picture = null;

  /// Returns the underlying `ui.Picture`, if it exists. Borrowed reference —
  /// do not dispose.
  ui.Picture? getPicture() {
    return _picture;
  }

  /// Rasterized image dimensions (0 if this still holds only a Picture), for
  /// memory accounting.
  int get imageWidth => _image?.width ?? 0;
  int get imageHeight => _image?.height ?? 0;

  /// Returns the underlying `ui.Image`, if it exists. Borrowed reference —
  /// do not dispose, do not hold across an await.
  ui.Image? getImage() {
    if (_image != null) assert(!_image!.debugDisposed, "Image is already disposed");
    return _image;
  }

  /// Rasterizes the underlying `ui.Picture` into a `ui.Image` owned by this
  /// TilePicture and releases the picture (drawing images each frame is faster
  /// than re-rendering pictures). No-op if already rasterized.
  void rasterize() {
    if (_image != null) return;
    _image = _picture!.toImageSync(MapsforgeSettingsMgr().tileSize.round(), MapsforgeSettingsMgr().tileSize.round());
    _picture!.dispose();
    _picture = null;
  }

  /// Rasterizes if needed and returns the image. Borrowed reference — do not
  /// dispose, this TilePicture still owns it. Kept for tests and tools;
  /// production code should call [rasterize] and draw via [getImage].
  ui.Image convertPictureToImage() {
    rasterize();
    return _image!;
  }

  /// Disposes the underlying `ui.Picture` and/or `ui.Image` to release their resources.
  void dispose() {
    _picture?.dispose();
    _image?.dispose();
  }
}
