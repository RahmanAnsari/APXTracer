import 'dart:math' as math;

/// Raw IMU measurement (accelerometer + gyroscope), expected at ~100 Hz.
class ImuData {
  /// Specific force in the device body frame (m/s²).
  /// Includes gravity – i.e. a stationary, flat device reads ≈ [0, 0, +9.81].
  final double ax, ay, az;

  /// Angular rate in the device body frame (rad/s).
  final double gx, gy, gz;

  final DateTime timestamp;

  const ImuData({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.timestamp,
  });
}

/// A GPS fix from the hardware.
class GpsData {
  final double latitude;   // degrees
  final double longitude;  // degrees
  final double altitude;   // metres above WGS-84 ellipsoid

  /// Horizontal speed over ground (m/s). Most GPS chipsets report this.
  final double? speed;

  /// Course over ground measured CW from North (degrees, 0–360).
  final double? heading;

  /// 1-sigma horizontal accuracy reported by the GPS chipset (metres).
  final double accuracy;

  final DateTime timestamp;

  const GpsData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.speed,
    this.heading,
    required this.accuracy,
    required this.timestamp,
  });
}

/// Output navigation state produced by [DeadReckoningFilter].
///
/// Position is expressed in a local ENU (East-North-Up) frame whose origin
/// is the first GPS fix passed to [DeadReckoningFilter.initWithGps].
class NavState {
  /// Position relative to ENU origin (metres).
  final double px, py, pz;

  /// Velocity in the ENU frame (m/s).
  final double vx, vy, vz;

  /// ZYX Euler attitude (radians): roll φ (X), pitch θ (Y), yaw ψ (Z).
  final double roll, pitch, yaw;

  /// Estimated accelerometer bias in the body frame (m/s²).
  final double biasAx, biasAy, biasAz;

  /// Estimated gyroscope bias in the body frame (rad/s).
  final double biasGx, biasGy, biasGz;

  /// WGS-84 coordinates of the ENU origin.
  final double originLat, originLon, originAlt;

  const NavState({
    required this.px,
    required this.py,
    required this.pz,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.biasAx,
    required this.biasAy,
    required this.biasAz,
    required this.biasGx,
    required this.biasGy,
    required this.biasGz,
    required this.originLat,
    required this.originLon,
    required this.originAlt,
  });

  /// Horizontal speed over ground (m/s).
  double get groundSpeed => math.sqrt(vx * vx + vy * vy);

  /// 3-D speed magnitude (m/s).
  double get speed3d => math.sqrt(vx * vx + vy * vy + vz * vz);

  /// Yaw angle converted to degrees (0 = East, CCW positive in ENU).
  double get yawDeg => yaw * 180.0 / math.pi;

  /// Compass bearing from North in degrees (0 = North, 90 = East, CW).
  double get bearingDeg {
    final b = 90.0 - yaw * 180.0 / math.pi;
    return ((b % 360) + 360) % 360;
  }

  /// Reconstruct approximate latitude from ENU position.
  double get latitude {
    const R = 6378137.0;
    return originLat + (py / R) * (180.0 / math.pi);
  }

  /// Reconstruct approximate longitude from ENU position.
  double get longitude {
    const R = 6378137.0;
    return originLon +
        (px / (R * math.cos(originLat * math.pi / 180.0))) * (180.0 / math.pi);
  }

  double get altitude => originAlt + pz;
}

/// Tuning parameters for [DeadReckoningFilter].
///
/// The defaults suit a typical consumer MEMS IMU (e.g. ICM-42688-P,
/// LSM6DSO) paired with a ≈3 m–accuracy GPS module.
class FilterConfig {
  /// Accelerometer white-noise std-dev (m/s²). Typical range: 0.05–0.3.
  final double accelNoiseSigma;

  /// Gyroscope white-noise std-dev (rad/s). Typical range: 0.003–0.02.
  final double gyroNoiseSigma;

  /// Accelerometer bias random-walk std-dev per √second (m/s² / √s).
  final double accelBiasNoiseSigma;

  /// Gyroscope bias random-walk std-dev per √second (rad/s / √s).
  final double gyroBiasNoiseSigma;

  /// Minimum GPS position noise std-dev (metres).
  /// Actual measurement noise = max(gps.accuracy, gpsPositionNoiseSigma).
  final double gpsPositionNoiseSigma;

  /// GPS horizontal speed noise std-dev (m/s).
  final double gpsSpeedNoiseSigma;

  /// Initial 1-sigma uncertainty for roll/pitch (radians).
  final double initialAttitudeSigma;

  /// Initial 1-sigma uncertainty for yaw (radians).
  final double initialYawSigma;

  /// Initial 1-sigma uncertainty for each velocity component (m/s).
  final double initialVelocitySigma;

  const FilterConfig({
    this.accelNoiseSigma = 0.1,
    this.gyroNoiseSigma = 0.01,
    this.accelBiasNoiseSigma = 0.001,
    this.gyroBiasNoiseSigma = 0.0001,
    this.gpsPositionNoiseSigma = 3.0,
    this.gpsSpeedNoiseSigma = 0.3,
    this.initialAttitudeSigma = 0.05,
    this.initialYawSigma = 0.3,
    this.initialVelocitySigma = 0.5,
  });
}
