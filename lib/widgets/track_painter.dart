import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as geo;

/// Paints a track polyline split into three colour-coded sectors.
///
/// Optionally draws one or two position markers (e.g. a highlighted point from
/// the speed graph). Pass [markerA] / [markerB] as geographic coordinates and
/// the painter will map them onto the same canvas coordinate space as the
/// polyline, then draw a filled circle with a white stroke.
class TrackLinePainter extends CustomPainter {
  final List<geo.LatLng> points;
  final double sector1Fraction;
  final double sector2Fraction;
  final geo.LatLng? markerA;
  final geo.LatLng? markerB;
  final Color markerAColor;
  final Color markerBColor;

  static const _sectorColors = [
    Color(0xFFE53935), // S1 – red
    Color(0xFF00E5FF), // S2 – cyan
    Color(0xFFFFAB00), // S3 – amber
  ];

  const TrackLinePainter({
    required this.points,
    required this.sector1Fraction,
    required this.sector2Fraction,
    this.markerA,
    this.markerB,
    this.markerAColor = Colors.white,
    this.markerBColor = const Color(0xFFE65100),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Compute bounding box.
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    const padding = 0.1;
    final effectiveWidth = size.width * (1 - 2 * padding);
    final effectiveHeight = size.height * (1 - 2 * padding);

    double scale;
    double translateX;
    double translateY;

    if (latRange == 0 && lngRange == 0) {
      scale = 1.0;
      translateX = size.width / 2;
      translateY = size.height / 2;
    } else if (latRange == 0) {
      scale = effectiveWidth / lngRange;
      translateX = size.width * padding;
      translateY = size.height / 2;
    } else if (lngRange == 0) {
      scale = effectiveHeight / latRange;
      translateX = size.width / 2;
      translateY = size.height * padding;
    } else {
      final scaleX = effectiveWidth / lngRange;
      final scaleY = effectiveHeight / latRange;
      scale = scaleX < scaleY ? scaleX : scaleY;
      final actualWidth = lngRange * scale;
      final actualHeight = latRange * scale;
      translateX = (size.width - actualWidth) / 2;
      translateY = (size.height - actualHeight) / 2;
    }

    // Map a LatLng to canvas offset using the computed transform.
    Offset toCanvas(geo.LatLng ll) {
      final x = translateX + (ll.longitude - minLng) * scale;
      final y = translateY + (maxLat - ll.latitude) * scale;
      return Offset(x, y);
    }

    final canvasPoints = points.map(toCanvas).toList();

    // Cumulative arc-lengths for sector splitting.
    final segLengths = <double>[0.0];
    for (int i = 1; i < canvasPoints.length; i++) {
      segLengths.add(
          segLengths.last + (canvasPoints[i] - canvasPoints[i - 1]).distance);
    }
    final totalLength = segLengths.last;
    final s1End = totalLength * sector1Fraction.clamp(0.0, 1.0);
    final s2End = totalLength * sector2Fraction.clamp(0.0, 1.0);
    final boundaries = [0.0, s1End, s2End, totalLength];

    // Draw each sector.
    for (int sector = 0; sector < 3; sector++) {
      final segStart = boundaries[sector];
      final segEnd = boundaries[sector + 1];
      if (segEnd <= segStart) continue;

      final paint = Paint()
        ..color = _sectorColors[sector]
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool started = false;

      for (int i = 0; i < canvasPoints.length - 1; i++) {
        final arcA = segLengths[i];
        final arcB = segLengths[i + 1];
        if (arcB <= segStart || arcA >= segEnd) continue;

        final a = canvasPoints[i];
        final b = canvasPoints[i + 1];
        final segLen = arcB - arcA;

        final tA = segLen == 0
            ? 0.0
            : ((segStart - arcA) / segLen).clamp(0.0, 1.0);
        final tB = segLen == 0
            ? 1.0
            : ((segEnd - arcA) / segLen).clamp(0.0, 1.0);

        final pA = arcA < segStart ? Offset.lerp(a, b, tA)! : a;
        final pB = arcB > segEnd ? Offset.lerp(a, b, tB)! : b;

        if (!started) {
          path.moveTo(pA.dx, pA.dy);
          started = true;
        } else {
          path.lineTo(pA.dx, pA.dy);
        }
        path.lineTo(pB.dx, pB.dy);
      }
      if (started) canvas.drawPath(path, paint);
    }

    // Start/finish cross marker.
    if (canvasPoints.isNotEmpty) {
      canvas.drawCircle(
        canvasPoints.first,
        4,
        Paint()..color = Colors.white..style = PaintingStyle.fill,
      );
      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      const cs = 6.0;
      canvas.drawLine(
        Offset(canvasPoints.first.dx - cs, canvasPoints.first.dy),
        Offset(canvasPoints.first.dx + cs, canvasPoints.first.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(canvasPoints.first.dx, canvasPoints.first.dy - cs),
        Offset(canvasPoints.first.dx, canvasPoints.first.dy + cs),
        crossPaint,
      );
    }

    // Draw position markers.
    void drawMarker(geo.LatLng ll, Color color) {
      final pos = toCanvas(ll);
      canvas.drawCircle(pos, 7,
          Paint()..color = color..style = PaintingStyle.fill);
      canvas.drawCircle(
          pos,
          7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    if (markerA != null) drawMarker(markerA!, markerAColor);
    if (markerB != null) drawMarker(markerB!, markerBColor);
  }

  @override
  bool shouldRepaint(covariant TrackLinePainter old) {
    return old.points != points ||
        old.sector1Fraction != sector1Fraction ||
        old.sector2Fraction != sector2Fraction ||
        old.markerA != markerA ||
        old.markerB != markerB;
  }
}

/// Finds the GPS sample whose timestamp is nearest to [targetMs].
/// Assumes [samples] is sorted by timestamp ascending.
({double latitude, double longitude})? nearestPosition(
  List<({int timestamp, double latitude, double longitude})> samples,
  int targetMs,
) {
  if (samples.isEmpty) return null;
  int lo = 0;
  int hi = samples.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (samples[mid].timestamp < targetMs) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  // lo is the insertion point; check lo-1 vs lo for closest.
  if (lo > 0) {
    final prev = (targetMs - samples[lo - 1].timestamp).abs();
    final curr = (samples[lo].timestamp - targetMs).abs();
    if (prev < curr) return (latitude: samples[lo - 1].latitude, longitude: samples[lo - 1].longitude);
  }
  return (latitude: samples[lo].latitude, longitude: samples[lo].longitude);
}
