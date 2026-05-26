import 'dart:math' as math;

import 'kalman_models.dart';
import 'matrix.dart';

/// 15-state Extended Kalman Filter for IMU/GPS sensor fusion.
///
/// ─── State vector (15 × 1) ───────────────────────────────────────────────
///   idx  0–2  : position   px, py, pz      metres, local ENU frame
///   idx  3–5  : velocity   vx, vy, vz      m/s,    ENU
///   idx  6–8  : attitude   roll φ, pitch θ, yaw ψ  radians, ZYX Euler
///   idx  9–11 : accel bias bax, bay, baz   m/s²,   body frame
///   idx 12–14 : gyro  bias bgx, bgy, bgz   rad/s,  body frame
///
/// ─── Coordinate frames ────────────────────────────────────────────────────
///   Navigation : ENU – East(+X) North(+Y) Up(+Z)
///   Body       : right-hand frame tied to the device / vehicle
///   Rotation   : R_bn transforms body → navigation (ZYX Euler)
///
/// ─── Sensor model ─────────────────────────────────────────────────────────
///   Accel measurement : f_body = R_nb·(a_nav − g_nav) + b_a + η_a
///                       g_nav  = [0, 0, −9.80665] (ENU, gravity = −Z)
///   Gyro  measurement : ω_body = ω_true + b_g + η_g
///
/// ─── Usage ────────────────────────────────────────────────────────────────
///   final filter = DeadReckoningFilter();
///
///   // (optional) level the attitude from stationary accel samples
///   final att = filter.alignWithGravity(staticSamples);
///   filter.initWithGps(firstFix,
///       initialRoll: att.roll, initialPitch: att.pitch);
///
///   imuStream.listen(filter.predictWithImu);
///   gpsStream.listen(filter.updateWithGps);
///
///   final nav = filter.state;  // lat/lon derived, or use nav.px/py in ENU
///
/// ─── Limitations ──────────────────────────────────────────────────────────
///   Euler parameterisation has a singularity at pitch = ±90°.
///   For ground vehicles and handheld devices this is never reached.
class DeadReckoningFilter {
  static const int _n = 15;
  static const double _gravity = 9.80665; // m/s²
  static const double _maxDt = 0.5; // seconds – stale-IMU gap threshold
  static const double _maxGpsAccuracy = 50.0; // metres – reject bad fixes

  final FilterConfig config;

  late Matrix _state; // state vector   (15×1)
  late Matrix _cov;   // covariance     (15×15)
  bool _initialized = false;

  double _originLat = 0.0, _originLon = 0.0, _originAlt = 0.0;
  DateTime? _lastImuTime;

  DeadReckoningFilter({this.config = const FilterConfig()});

  bool get isInitialized => _initialized;

  // ─── Initialization ────────────────────────────────────────────────────────

  /// Estimate roll and pitch from averaged accelerometer readings while the
  /// device is stationary on flat ground. Pass ≥0.5 s of samples.
  ///
  /// Returns a record so the caller can log or inspect the values before
  /// passing them to [initWithGps].
  ({double roll, double pitch}) alignWithGravity(List<ImuData> samples) {
    assert(samples.isNotEmpty);
    double ax = 0, ay = 0, az = 0;
    for (final s in samples) {
      ax += s.ax;
      ay += s.ay;
      az += s.az;
    }
    ax /= samples.length;
    ay /= samples.length;
    az /= samples.length;

    // When stationary: f_body = R_nb·[0, 0, +g]
    //   f[0] = −g·sin(θ)         → θ = arcsin(−ax / g)
    //   f[1] = +g·cos(θ)·sin(φ)  }
    //   f[2] = +g·cos(θ)·cos(φ)  } → φ = arctan2(ay, az)
    final pitch = math.asin((-ax / _gravity).clamp(-1.0, 1.0));
    final roll = math.atan2(ay, az);
    return (roll: roll, pitch: pitch);
  }

  /// Initialise the filter with the first valid GPS fix.
  ///
  /// [initialRoll] and [initialPitch] come from [alignWithGravity]; if omitted
  /// they are assumed zero (device nominally level).
  /// Yaw is seeded from [gps.heading] when available and speed > 0.5 m/s,
  /// otherwise zero (unknown heading).
  void initWithGps(
    GpsData gps, {
    double initialRoll = 0.0,
    double initialPitch = 0.0,
  }) {
    _originLat = gps.latitude;
    _originLon = gps.longitude;
    _originAlt = gps.altitude;

    _state = Matrix(_n, 1);
    _state.set(6, 0, initialRoll);
    _state.set(7, 0, initialPitch);

    if (gps.speed != null && gps.heading != null && gps.speed! > 0.5) {
      // GPS heading is CW from North; ENU yaw is CCW from East
      final hdgRad = gps.heading! * math.pi / 180.0;
      final yawEnu = math.pi / 2.0 - hdgRad;
      _state.set(3, 0, gps.speed! * math.sin(hdgRad)); // vx (East)
      _state.set(4, 0, gps.speed! * math.cos(hdgRad)); // vy (North)
      _state.set(8, 0, _wrap(yawEnu));
    }

    _cov = _buildInitialCovariance();
    _initialized = true;
    _lastImuTime = null;
  }

  // ─── Predict step (IMU at ~100 Hz) ────────────────────────────────────────

  /// Propagate the state forward using one IMU sample.
  ///
  /// Safe to call before [initWithGps]; those calls are silently ignored.
  void predictWithImu(ImuData imu) {
    if (!_initialized) return;

    final dt = _computeDt(imu.timestamp);
    if (dt <= 0 || dt > _maxDt) return;

    final phi   = _state.get(6, 0);
    final theta = _state.get(7, 0);
    final psi   = _state.get(8, 0);

    // Bias-corrected measurements
    final ax = imu.ax - _state.get(9,  0);
    final ay = imu.ay - _state.get(10, 0);
    final az = imu.az - _state.get(11, 0);
    final ox = imu.gx - _state.get(12, 0);
    final oy = imu.gy - _state.get(13, 0);
    final oz = imu.gz - _state.get(14, 0);

    final rbn = _buildRbn(phi, theta, psi);

    // Specific force rotated to the navigation frame
    final sfx = rbn[0][0] * ax + rbn[0][1] * ay + rbn[0][2] * az;
    final sfy = rbn[1][0] * ax + rbn[1][1] * ay + rbn[1][2] * az;
    final sfz = rbn[2][0] * ax + rbn[2][1] * ay + rbn[2][2] * az;

    // True acceleration = specific force − gravity  (g_nav = [0,0,−g] in ENU)
    final anx = sfx;
    final any = sfy;
    final anz = sfz - _gravity;

    // Euler-angle kinematics: [φ̇, θ̇, ψ̇] = Ω · ω_corrected
    final tt  = math.tan(theta);
    final cph = math.cos(phi), sph = math.sin(phi);
    final cth = math.cos(theta);
    final phiDot = ox + sph * tt * oy + cph * tt * oz;
    final thtDot = cph * oy - sph * oz;
    final psiDot = (sph * oy + cph * oz) / cth;

    // ── Nonlinear state propagation (forward Euler / RK1) ───────────────────
    _state.add(0, 0, _state.get(3, 0) * dt);
    _state.add(1, 0, _state.get(4, 0) * dt);
    _state.add(2, 0, _state.get(5, 0) * dt);
    _state.add(3, 0, anx * dt);
    _state.add(4, 0, any * dt);
    _state.add(5, 0, anz * dt);
    _state.set(6, 0, _wrap(_state.get(6, 0) + phiDot * dt));
    _state.set(7, 0, _wrap(_state.get(7, 0) + thtDot * dt));
    _state.set(8, 0, _wrap(_state.get(8, 0) + psiDot * dt));
    // biases: mean unchanged; their covariance grows via Q (random-walk model)

    // ── Covariance propagation ───────────────────────────────────────────────
    final bigF  = _buildBigF(phi, theta, psi, rbn, ax, ay, az, ox, oy, oz);
    // First-order discretisation: Fd = I + F·dt
    final fd = Matrix.identity(_n) + bigF.scale(dt);
    final qd = _buildQd(dt);
    _cov = fd * _cov * fd.transpose() + qd;
    _symmetrize(_cov);
  }

  // ─── Update step (GPS, any rate) ──────────────────────────────────────────

  /// Fuse a GPS fix into the filter.
  ///
  /// Performs:
  ///   1. 3-DOF position update (always, when accuracy is acceptable)
  ///   2. Scalar horizontal-speed update (when [GpsData.speed] is non-null)
  void updateWithGps(GpsData gps) {
    if (!_initialized) return;
    if (gps.accuracy > _maxGpsAccuracy) return;

    final enu = _toEnu(gps.latitude, gps.longitude, gps.altitude);
    final sigP = math.max(gps.accuracy, config.gpsPositionNoiseSigma);

    // ── 3-DOF position update ────────────────────────────────────────────────
    final rPos = Matrix.diagonal([
      sigP * sigP,
      sigP * sigP,
      (sigP * 2.5) * (sigP * 2.5), // vertical GPS is ~2-3× less accurate
    ]);
    final innPos = colVec([
      enu[0] - _state.get(0, 0),
      enu[1] - _state.get(1, 0),
      enu[2] - _state.get(2, 0),
    ]);
    _ekfUpdate(_buildHPosition(), rPos, innPos);

    // ── Scalar horizontal-speed update ───────────────────────────────────────
    if (gps.speed != null) {
      final sigV = config.gpsSpeedNoiseSigma;
      final rVel = Matrix.diagonal([sigV * sigV]);
      final vx   = _state.get(3, 0), vy = _state.get(4, 0);
      final vMag = math.sqrt(vx * vx + vy * vy);
      final innV = colVec([gps.speed! - vMag]);
      _ekfUpdate(_buildHHorizontalSpeed(), rVel, innV);
    }
  }

  // ─── State accessor ────────────────────────────────────────────────────────

  NavState get state {
    assert(_initialized, 'Call initWithGps() first');
    return NavState(
      px: _state.get(0, 0), py: _state.get(1, 0), pz: _state.get(2, 0),
      vx: _state.get(3, 0), vy: _state.get(4, 0), vz: _state.get(5, 0),
      roll:  _state.get(6, 0),
      pitch: _state.get(7, 0),
      yaw:   _state.get(8, 0),
      biasAx: _state.get(9,  0),
      biasAy: _state.get(10, 0),
      biasAz: _state.get(11, 0),
      biasGx: _state.get(12, 0),
      biasGy: _state.get(13, 0),
      biasGz: _state.get(14, 0),
      originLat: _originLat,
      originLon: _originLon,
      originAlt: _originAlt,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  double _computeDt(DateTime now) {
    final last = _lastImuTime;
    _lastImuTime = now;
    if (last == null) return 0.0;
    return now.difference(last).inMicroseconds / 1e6;
  }

  Matrix _buildInitialCovariance() {
    final s = config;
    return Matrix.diagonal([
      // position: 1 m horizontal, 2 m vertical (GPS-seeded)
      1.0, 1.0, 4.0,
      // velocity
      s.initialVelocitySigma * s.initialVelocitySigma,
      s.initialVelocitySigma * s.initialVelocitySigma,
      s.initialVelocitySigma * s.initialVelocitySigma,
      // attitude (roll & pitch levelled; yaw more uncertain)
      s.initialAttitudeSigma * s.initialAttitudeSigma,
      s.initialAttitudeSigma * s.initialAttitudeSigma,
      s.initialYawSigma * s.initialYawSigma,
      // accel bias
      0.05 * 0.05, 0.05 * 0.05, 0.05 * 0.05,
      // gyro bias
      0.005 * 0.005, 0.005 * 0.005, 0.005 * 0.005,
    ]);
  }

  // ── Rotation matrix R_bn : body → ENU  (ZYX Euler) ───────────────────────
  //
  //  R_bn = Rz(ψ)·Ry(θ)·Rx(φ)
  //
  //   row 0: [cψ·cθ,  cψ·sθ·sφ − sψ·cφ,  cψ·sθ·cφ + sψ·sφ]
  //   row 1: [sψ·cθ,  sψ·sθ·sφ + cψ·cφ,  sψ·sθ·cφ − cψ·sφ]
  //   row 2: [−sθ,    cθ·sφ,              cθ·cφ            ]
  List<List<double>> _buildRbn(double phi, double theta, double psi) {
    final cp = math.cos(phi), sp = math.sin(phi);
    final ct = math.cos(theta), st = math.sin(theta);
    final cy = math.cos(psi), sy = math.sin(psi);
    return [
      [cy * ct,  cy * st * sp - sy * cp,  cy * st * cp + sy * sp],
      [sy * ct,  sy * st * sp + cy * cp,  sy * st * cp - cy * sp],
      [-st,      ct * sp,                 ct * cp               ],
    ];
  }

  // ── Attitude kinematics matrix Ω  ([φ̇,θ̇,ψ̇] = Ω·ω_corrected) ────────────
  List<List<double>> _buildOmega(double phi, double theta) {
    final cp = math.cos(phi), sp = math.sin(phi);
    final ct = math.cos(theta), tt = math.tan(theta);
    return [
      [1.0, sp * tt,  cp * tt],
      [0.0, cp,      -sp     ],
      [0.0, sp / ct,  cp / ct],
    ];
  }

  // ── Jacobian of velocity w.r.t. attitude: ∂(R_bn·a_c)/∂[φ,θ,ψ] ──────────
  //
  // Returns a 3×3 matrix whose columns are ∂/∂φ, ∂/∂θ, ∂/∂ψ respectively.
  // Derivation: differentiate R_bn = Rz·Ry·Rx term by term.
  //
  //   ∂/∂φ = Rz·Ry·(∂Rx/∂φ)·a_c
  //   ∂/∂θ = Rz·(∂Ry/∂θ)·Rx·a_c
  //   ∂/∂ψ = (∂Rz/∂ψ)·Ry·Rx·a_c
  List<List<double>> _buildFva(
    double phi, double theta, double psi,
    double a0, double a1, double a2,
  ) {
    final cp = math.cos(phi), sp = math.sin(phi);
    final ct = math.cos(theta), st = math.sin(theta);
    final cy = math.cos(psi), sy = math.sin(psi);

    // ── ∂/∂φ ─────────────────────────────────────────────────────────────────
    // p = cφ·a1 − sφ·a2 ,  q = −sφ·a1 − cφ·a2
    final p = cp * a1 - sp * a2;
    final q = -sp * a1 - cp * a2;
    final dPhi0 = cy * st * p - sy * q;
    final dPhi1 = sy * st * p + cy * q;
    final dPhi2 = ct * p;

    // ── ∂/∂θ ─────────────────────────────────────────────────────────────────
    // Rx·a = [a0, p, sapa]  where sapa = sφ·a1 + cφ·a2
    // ∂Ry/∂θ · [a0, p, sapa] = [−sθ·a0 + cθ·sapa, 0, −cθ·a0 − sθ·sapa]
    final sapa = sp * a1 + cp * a2;
    final v0 = -st * a0 + ct * sapa;
    final v2 = -ct * a0 - st * sapa;
    final dTht0 = cy * v0;
    final dTht1 = sy * v0;
    final dTht2 = v2;

    // ── ∂/∂ψ ─────────────────────────────────────────────────────────────────
    // w = Ry·Rx·a: w0 = ct·a0 + st·sapa, w1 = p, w2 = −st·a0 + ct·sapa
    final w0 = ct * a0 + st * sapa;
    final w1 = p;
    // ∂Rz/∂ψ · w = [−sψ·w0−cψ·w1, cψ·w0−sψ·w1, 0]
    final dPsi0 = -sy * w0 - cy * w1;
    final dPsi1 =  cy * w0 - sy * w1;
    const dPsi2 = 0.0;

    return [
      [dPhi0, dTht0, dPsi0],
      [dPhi1, dTht1, dPsi1],
      [dPhi2, dTht2, dPsi2],
    ];
  }

  // ── Jacobian of attitude kinematics w.r.t. attitude ──────────────────────
  //
  // ∂[φ̇,θ̇,ψ̇]/∂[φ,θ,ψ]  (columns for ψ are all zero)
  List<List<double>> _buildFaa(
    double phi, double theta,
    double ox, double oy, double oz,
  ) {
    final cp = math.cos(phi), sp = math.sin(phi);
    final ct = math.cos(theta), st = math.sin(theta), tt = math.tan(theta);

    final dPhiPhi   = tt * (cp * oy - sp * oz);
    final dPhiTheta = (sp * oy + cp * oz) / (ct * ct);
    final dThtPhi   = -sp * oy - cp * oz;
    final dPsiPhi   = (cp * oy - sp * oz) / ct;
    final dPsiTheta = st * (sp * oy + cp * oz) / (ct * ct);

    return [
      [dPhiPhi,  dPhiTheta, 0.0],
      [dThtPhi,  0.0,       0.0],
      [dPsiPhi,  dPsiTheta, 0.0],
    ];
  }

  // ── Full 15×15 continuous-time state Jacobian F = ∂f/∂x ─────────────────
  Matrix _buildBigF(
    double phi, double theta, double psi,
    List<List<double>> rbn,
    double ax, double ay, double az, // bias-corrected body accel
    double ox, double oy, double oz, // bias-corrected body gyro
  ) {
    final bigF = Matrix(_n, _n);

    // ∂ṗ/∂v = I₃
    bigF.set(0, 3, 1.0);
    bigF.set(1, 4, 1.0);
    bigF.set(2, 5, 1.0);

    // ∂v̇/∂attitude (rows 3-5, cols 6-8)
    final fva = _buildFva(phi, theta, psi, ax, ay, az);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        bigF.set(3 + i, 6 + j, fva[i][j]);
      }
    }

    // ∂v̇/∂b_a = −R_bn (rows 3-5, cols 9-11)
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        bigF.set(3 + i, 9 + j, -rbn[i][j]);
      }
    }

    // ∂[φ̇,θ̇,ψ̇]/∂[φ,θ,ψ] (rows 6-8, cols 6-8)
    final faa = _buildFaa(phi, theta, ox, oy, oz);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        bigF.set(6 + i, 6 + j, faa[i][j]);
      }
    }

    // ∂[φ̇,θ̇,ψ̇]/∂b_g = −Ω (rows 6-8, cols 12-14)
    final omega = _buildOmega(phi, theta);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        bigF.set(6 + i, 12 + j, -omega[i][j]);
      }
    }

    return bigF;
  }

  // ── Discrete process noise Qd ─────────────────────────────────────────────
  //
  // Velocity : Q_v = R_bn·(σa²·I)·R_bn^T·dt = σa²·I·dt   (R orthogonal)
  // Attitude : approximated as σg²·I·dt   (valid, small angles)
  // Biases   : random-walk variance grows as σ_b²·dt
  Matrix _buildQd(double dt) {
    final sa2  = config.accelNoiseSigma      * config.accelNoiseSigma      * dt;
    final sg2  = config.gyroNoiseSigma       * config.gyroNoiseSigma       * dt;
    final sba2 = config.accelBiasNoiseSigma  * config.accelBiasNoiseSigma  * dt;
    final sbg2 = config.gyroBiasNoiseSigma   * config.gyroBiasNoiseSigma   * dt;

    final qd = Matrix(_n, _n);
    qd.set(3,  3,  sa2);
    qd.set(4,  4,  sa2);
    qd.set(5,  5,  sa2);
    qd.set(6,  6,  sg2);
    qd.set(7,  7,  sg2);
    qd.set(8,  8,  sg2);
    qd.set(9,  9,  sba2);
    qd.set(10, 10, sba2);
    qd.set(11, 11, sba2);
    qd.set(12, 12, sbg2);
    qd.set(13, 13, sbg2);
    qd.set(14, 14, sbg2);
    return qd;
  }

  // ── EKF measurement update (Joseph form for numerical stability) ──────────
  void _ekfUpdate(Matrix hMat, Matrix rNoise, Matrix innovation) {
    final ht = hMat.transpose();
    final sInv = (hMat * _cov * ht + rNoise).inverse();
    final kGain = _cov * ht * sInv;

    // State correction
    final dx = kGain * innovation;
    for (int i = 0; i < _n; i++) {
      _state.add(i, 0, dx.get(i, 0));
    }

    // Joseph form: P = (I−KH)·P·(I−KH)^T + K·R·K^T
    final ikh = Matrix.identity(_n) - kGain * hMat;
    _cov = ikh * _cov * ikh.transpose() + kGain * rNoise * kGain.transpose();
    _symmetrize(_cov);

    // Keep Euler angles in (−π, π]
    _state.set(6, 0, _wrap(_state.get(6, 0)));
    _state.set(7, 0, _wrap(_state.get(7, 0)));
    _state.set(8, 0, _wrap(_state.get(8, 0)));
  }

  // ── Measurement matrices H ────────────────────────────────────────────────

  /// H for 3-DOF GPS position measurement (3×15).
  Matrix _buildHPosition() {
    final hMat = Matrix(3, _n);
    hMat.set(0, 0, 1.0);
    hMat.set(1, 1, 1.0);
    hMat.set(2, 2, 1.0);
    return hMat;
  }

  /// H for scalar horizontal-speed measurement (1×15).
  ///
  ///   z = ‖[vx, vy]‖  →  H = [0,0,0, vx/‖v_h‖, vy/‖v_h‖, 0, 0, …]
  Matrix _buildHHorizontalSpeed() {
    final vx  = _state.get(3, 0), vy = _state.get(4, 0);
    final mag = math.sqrt(vx * vx + vy * vy);
    final hMat = Matrix(1, _n);
    if (mag > 0.05) {
      hMat.set(0, 3, vx / mag);
      hMat.set(0, 4, vy / mag);
    }
    return hMat;
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Convert WGS-84 (lat/lon/alt) to local ENU relative to the stored origin.
  List<double> _toEnu(double lat, double lon, double alt) {
    const earthRadius = 6378137.0; // WGS-84 equatorial radius (metres)
    final latRef = _originLat * math.pi / 180.0;
    final dLat   = (lat - _originLat) * math.pi / 180.0;
    final dLon   = (lon - _originLon) * math.pi / 180.0;
    return [
      dLon * earthRadius * math.cos(latRef), // East
      dLat * earthRadius,                    // North
      alt - _originAlt,                      // Up
    ];
  }

  /// Force P to be exactly symmetric – counteracts floating-point drift.
  void _symmetrize(Matrix mat) {
    for (int i = 0; i < _n; i++) {
      for (int j = i + 1; j < _n; j++) {
        final avg = (mat.get(i, j) + mat.get(j, i)) * 0.5;
        mat.set(i, j, avg);
        mat.set(j, i, avg);
      }
    }
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }
}
