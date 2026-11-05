// Renders the bundled wallpapers: layered glass sheets in the spirit of the iOS abstracts.
// Run with `dart tool/wallpapers.dart` from the project root.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const width = 720, height = 1560;

typedef Rgb = List<double>;

Rgb hex(int c) => [(c >> 16 & 255) / 255, (c >> 8 & 255) / 255, (c & 255) / 255];
Rgb mix(Rgb a, Rgb b, double t) => [for (var i = 0; i < 3; i++) a[i] + (b[i] - a[i]) * t];
double smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class Sheet {
  const Sheet(this.base, this.a1, this.f1, this.p1, this.a2, this.f2, this.p2, this.tilt, this.rim, this.body, this.deep);
  final double base, a1, f1, p1, a2, f2, p2, tilt;
  final int rim, body, deep;

  double edge(double u, double v) =>
      base + tilt * u + a1 * sin(f1 * u + p1 + 0.9 * v) + a2 * sin(f2 * u + p2 - 1.4 * v);
}

class Scheme {
  const Scheme(this.name, this.top, this.bottom, this.sheets);
  final String name;
  final int top, bottom;
  final List<Sheet> sheets;
}

const schemes = [
  Scheme('blue', 0xFF0B1F6B, 0xFF020716, [
    Sheet(0.10, 0.09, 2.6, 0.4, 0.035, 6.1, 1.2, 0.20, 0xFF7FD4FF, 0xFF1F63E8, 0xFF0A2A96),
    Sheet(0.34, 0.10, 3.1, 2.3, 0.030, 7.0, 0.3, -0.16, 0xFFD6A8FF, 0xFF5B3BE6, 0xFF1C1490),
    Sheet(0.56, 0.08, 2.4, 4.4, 0.028, 5.3, 2.0, 0.22, 0xFFFF9FD0, 0xFF8A2BC9, 0xFF2A0E72),
    Sheet(0.78, 0.07, 3.3, 1.1, 0.024, 6.6, 3.7, -0.12, 0xFF8FB8FF, 0xFF16339E, 0xFF050E3A),
  ]),
  Scheme('sunrise', 0xFFFFC36A, 0xFF3A0A36, [
    Sheet(0.12, 0.08, 2.8, 1.0, 0.03, 6.0, 0.2, 0.18, 0xFFFFF0B0, 0xFFFF9A3D, 0xFFE8562A),
    Sheet(0.36, 0.10, 2.5, 3.2, 0.03, 6.4, 1.9, -0.18, 0xFFFFD1A0, 0xFFFF5A5F, 0xFFC4235E),
    Sheet(0.60, 0.08, 3.0, 5.1, 0.03, 5.6, 0.7, 0.20, 0xFFFFA0C8, 0xFFC02A86, 0xFF6E1270),
    Sheet(0.80, 0.07, 2.7, 2.2, 0.02, 7.1, 4.1, -0.10, 0xFFE58CFF, 0xFF5A1A8E, 0xFF22084A),
  ]),
  Scheme('green', 0xFF0B3D3A, 0xFF02100F, [
    Sheet(0.14, 0.09, 2.5, 2.0, 0.03, 6.3, 0.9, -0.18, 0xFFB6FFD8, 0xFF1FBF8F, 0xFF0B6E66),
    Sheet(0.38, 0.09, 3.2, 0.6, 0.03, 5.7, 2.6, 0.18, 0xFFA8F0FF, 0xFF1794B8, 0xFF0A4F78),
    Sheet(0.62, 0.08, 2.6, 3.7, 0.03, 6.8, 1.4, -0.20, 0xFFD6FFA8, 0xFF2EA65E, 0xFF0F5238),
    Sheet(0.82, 0.06, 3.0, 5.4, 0.02, 7.2, 0.4, 0.12, 0xFF8AE8C8, 0xFF0F6A5C, 0xFF041F20),
  ]),
  Scheme('violet', 0xFF2A0F5E, 0xFF0A0420, [
    Sheet(0.10, 0.09, 3.0, 3.0, 0.03, 6.0, 1.0, -0.20, 0xFFFFC2F0, 0xFFC33BE0, 0xFF6A18B0),
    Sheet(0.34, 0.10, 2.4, 0.9, 0.03, 6.5, 3.1, 0.20, 0xFFBDB4FF, 0xFF6A4CF2, 0xFF2C1CA8),
    Sheet(0.58, 0.08, 3.2, 4.8, 0.03, 5.5, 2.2, -0.16, 0xFFFFB0B8, 0xFFE03A7E, 0xFF7A1270),
    Sheet(0.80, 0.07, 2.8, 2.6, 0.02, 7.0, 0.8, 0.14, 0xFFA8A0FF, 0xFF3A2AA8, 0xFF10083E),
  ]),
  Scheme('graphite', 0xFF3A3D45, 0xFF050507, [
    Sheet(0.12, 0.09, 2.7, 1.4, 0.03, 6.2, 0.6, 0.18, 0xFFE8ECF4, 0xFF7E8594, 0xFF3C414C),
    Sheet(0.36, 0.09, 3.1, 3.6, 0.03, 5.8, 2.4, -0.18, 0xFFC8CDD8, 0xFF565C69, 0xFF262A32),
    Sheet(0.60, 0.08, 2.5, 0.2, 0.03, 6.9, 3.0, 0.20, 0xFFA8AEBC, 0xFF3A3F4A, 0xFF16181E),
    Sheet(0.80, 0.07, 3.0, 4.9, 0.02, 7.1, 1.7, -0.12, 0xFF8A909E, 0xFF22252C, 0xFF08090B),
  ]),
];

Rgb shade(Scheme s, double u, double v) {
  var color = mix(hex(s.top), hex(s.bottom), v);
  for (final sheet in s.sheets) {
    final d = v - sheet.edge(u, v);
    // The sheet above casts a soft shadow on what lies behind its edge.
    if (d < 0) {
      final shadow = exp(d * 22) * 0.45;
      color = [for (final c in color) c * (1 - shadow)];
    }
    final inside = smooth(-0.0016, 0.0016, d);
    if (inside > 0) {
      final depth = max(d, 0.0);
      var body = mix(hex(sheet.body), hex(sheet.deep), smooth(0.0, 0.34, depth));
      body = mix(body, hex(sheet.rim), exp(-depth * 34) * 0.92);
      body = mix(body, [1, 1, 1], exp(-depth * 260) * 0.5);
      color = mix(color, body, inside);
    }
  }
  return color;
}

List<int> _crc() => List.generate(256, (n) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      return c;
    });

final _table = _crc();

Uint8List chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  var crc = 0xFFFFFFFF;
  for (final b in body) {
    crc = _table[(crc ^ b) & 255] ^ (crc >> 8);
  }
  crc ^= 0xFFFFFFFF;
  final out = BytesBuilder();
  out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  out.add(body);
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  Directory('assets/wallpapers').createSync(recursive: true);
  for (final scheme in schemes) {
    final random = Random(7);
    final raw = Uint8List((width * 3 + 1) * height);
    var i = 0;
    for (var y = 0; y < height; y++) {
      raw[i++] = 0;
      for (var x = 0; x < width; x++) {
        final c = shade(scheme, x / width, y / height);
        // One step of noise hides the banding that dark gradients get on an AMOLED panel.
        final noise = random.nextDouble();
        raw[i++] = (c[0].clamp(0.0, 1.0) * 255 + noise).floor().clamp(0, 255);
        raw[i++] = (c[1].clamp(0.0, 1.0) * 255 + noise).floor().clamp(0, 255);
        raw[i++] = (c[2].clamp(0.0, 1.0) * 255 + noise).floor().clamp(0, 255);
      }
    }
    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8)
      ..setUint8(9, 2);
    final png = BytesBuilder()
      ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      ..add(chunk('IHDR', header.buffer.asUint8List()))
      ..add(chunk('IDAT', ZLibCodec(level: 9).encode(raw)))
      ..add(chunk('IEND', []));
    File('assets/wallpapers/${scheme.name}.png').writeAsBytesSync(png.takeBytes());
    stdout.writeln(scheme.name);
  }
}
