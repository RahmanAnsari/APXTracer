import 'package:latlong2/latlong.dart';

/// Represents a sector boundary point on a track polyline.
///
/// Sectors divide a track into segments for performance analysis.
/// Each boundary is defined by its fractional position along the
/// polyline (0.0 to 1.0) and the interpolated geographic point
/// at that position.
class SectorBoundary {
  /// The fractional position along the track polyline (0.0 to 1.0).
  final double polylineFraction;

  /// The interpolated geographic point at this boundary.
  final LatLng point;

  const SectorBoundary({
    required this.polylineFraction,
    required this.point,
  });
}
