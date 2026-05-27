import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Represents a geographic circuit layout auto-generated from GPS path data.
class Track {
  final String id;
  final String? name;
  final List<LatLng> polyline;
  final LatLng startFinish;
  final double sector1Fraction; // 0.333
  final double sector2Fraction; // 0.666

  /// Arc length of the refined circuit polyline in metres.
  /// Zero until [PostSessionPipeline] Stage 5 refines it from the best lap.
  final double lengthM;

  final int sessionCount;
  final int lastDriven; // Unix epoch ms

  const Track({
    required this.id,
    this.name,
    required this.polyline,
    required this.startFinish,
    this.sector1Fraction = 1 / 3,
    this.sector2Fraction = 2 / 3,
    this.lengthM = 0.0,
    this.sessionCount = 1,
    required this.lastDriven,
  });

  /// Serializes this track to a map for database storage.
  /// The polyline is JSON-encoded as a list of [lat, lng] pairs.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'polyline': jsonEncode(
        polyline.map((p) => [p.latitude, p.longitude]).toList(),
      ),
      'start_lat': startFinish.latitude,
      'start_lng': startFinish.longitude,
      'sector1_fraction': sector1Fraction,
      'sector2_fraction': sector2Fraction,
      'length_m': lengthM,
      'session_count': sessionCount,
      'last_driven': lastDriven,
      'created_at': lastDriven,
    };
  }

  /// Creates a [Track] from a database row map.
  /// The polyline is decoded from a JSON string of [lat, lng] pairs.
  factory Track.fromMap(Map<String, dynamic> map) {
    final polylineJson = jsonDecode(map['polyline'] as String) as List<dynamic>;
    final polyline = polylineJson
        .map((p) => LatLng(
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ))
        .toList();

    return Track(
      id: map['id'] as String,
      name: map['name'] != null ? map['name'] as String : null,
      polyline: polyline,
      startFinish: LatLng(
        (map['start_lat'] as num).toDouble(),
        (map['start_lng'] as num).toDouble(),
      ),
      sector1Fraction: (map['sector1_fraction'] as num).toDouble(),
      sector2Fraction: (map['sector2_fraction'] as num).toDouble(),
      lengthM: map['length_m'] != null ? (map['length_m'] as num).toDouble() : 0.0,
      sessionCount: map['session_count'] as int,
      lastDriven: map['last_driven'] as int,
    );
  }

  /// Returns the circuit polyline as a GeoJSON Feature (LineString).
  ///
  /// GeoJSON uses [longitude, latitude] coordinate order per RFC 7946.
  Map<String, dynamic> toGeoJson() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': polyline.map((p) => [p.longitude, p.latitude]).toList(),
      },
      'properties': {
        'id': id,
        'name': name,
        'length_m': lengthM,
        'sector1_fraction': sector1Fraction,
        'sector2_fraction': sector2Fraction,
      },
    };
  }
}
