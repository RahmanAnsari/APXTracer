/// Lightweight matrix backed by a flat row-major `List<double>`.
///
/// All arithmetic operators return new instances; internal mutation is limited
/// to [set] / [add] calls made during construction of intermediate results.
class Matrix {
  final int rows;
  final int cols;
  final List<double> _d; // row-major

  Matrix(this.rows, this.cols) : _d = List.filled(rows * cols, 0.0);

  factory Matrix.identity(int n) {
    final m = Matrix(n, n);
    for (int i = 0; i < n; i++) {
      m._d[i * n + i] = 1.0;
    }
    return m;
  }

  factory Matrix.diagonal(List<double> v) {
    final n = v.length;
    final m = Matrix(n, n);
    for (int i = 0; i < n; i++) {
      m._d[i * n + i] = v[i];
    }
    return m;
  }

  double get(int r, int c) => _d[r * cols + c];
  void set(int r, int c, double v) => _d[r * cols + c] = v;
  void add(int r, int c, double v) => _d[r * cols + c] += v;

  Matrix operator +(Matrix o) {
    assert(rows == o.rows && cols == o.cols);
    final r = Matrix(rows, cols);
    for (int i = 0; i < _d.length; i++) {
      r._d[i] = _d[i] + o._d[i];
    }
    return r;
  }

  Matrix operator -(Matrix o) {
    assert(rows == o.rows && cols == o.cols);
    final r = Matrix(rows, cols);
    for (int i = 0; i < _d.length; i++) {
      r._d[i] = _d[i] - o._d[i];
    }
    return r;
  }

  /// Cache-friendly i-k-j loop for matrix multiply.
  Matrix operator *(Matrix o) {
    assert(cols == o.rows);
    final r = Matrix(rows, o.cols);
    for (int i = 0; i < rows; i++) {
      for (int k = 0; k < cols; k++) {
        final aik = _d[i * cols + k];
        if (aik == 0.0) continue;
        for (int j = 0; j < o.cols; j++) {
          r._d[i * o.cols + j] += aik * o._d[k * o.cols + j];
        }
      }
    }
    return r;
  }

  Matrix scale(double s) {
    final r = Matrix(rows, cols);
    for (int i = 0; i < _d.length; i++) {
      r._d[i] = _d[i] * s;
    }
    return r;
  }

  Matrix transpose() {
    final r = Matrix(cols, rows);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        r._d[j * rows + i] = _d[i * cols + j];
      }
    }
    return r;
  }

  /// Gauss-Jordan elimination with partial pivoting.
  Matrix inverse() {
    assert(rows == cols, 'Only square matrices can be inverted');
    final n = rows;
    final aug = List.generate(n, (i) {
      final row = List<double>.filled(2 * n, 0.0);
      for (int j = 0; j < n; j++) {
        row[j] = _d[i * n + j];
      }
      row[n + i] = 1.0;
      return row;
    });

    for (int col = 0; col < n; col++) {
      int pivot = col;
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[pivot][col].abs()) pivot = row;
      }
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;

      final pv = aug[col][col];
      if (pv.abs() < 1e-14) throw StateError('Matrix is singular');
      final inv = 1.0 / pv;
      for (int j = 0; j < 2 * n; j++) {
        aug[col][j] *= inv;
      }

      for (int row = 0; row < n; row++) {
        if (row == col) continue;
        final f = aug[row][col];
        if (f == 0.0) continue;
        for (int j = 0; j < 2 * n; j++) {
          aug[row][j] -= f * aug[col][j];
        }
      }
    }

    final r = Matrix(n, n);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        r._d[i * n + j] = aug[i][n + j];
      }
    }
    return r;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    for (int i = 0; i < rows; i++) {
      sb.write('[');
      for (int j = 0; j < cols; j++) {
        if (j > 0) sb.write(', ');
        sb.write(get(i, j).toStringAsFixed(5));
      }
      sb.writeln(']');
    }
    return sb.toString();
  }
}

/// Build an (n×1) column-vector Matrix from a list.
Matrix colVec(List<double> v) {
  final m = Matrix(v.length, 1);
  for (int i = 0; i < v.length; i++) {
    m.set(i, 0, v[i]);
  }
  return m;
}

/// Utility – handy in tests.
List<double> vecToList(Matrix m) {
  assert(m.cols == 1);
  return List.generate(m.rows, (i) => m.get(i, 0));
}
