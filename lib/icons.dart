import 'dart:math';

import 'package:flutter/material.dart';

import 'glass.dart';

/// System apps that get an iOS icon and name in place of the Android ones.
enum Role {
  phone('Telefon'),
  messages('Nachrichten'),
  safari('Safari'),
  mail('Mail'),
  camera('Kamera'),
  photos('Fotos'),
  music('Musik'),
  calendar('Kalender'),
  clock('Uhr'),
  settings('Einstellungen'),
  calculator('Rechner'),
  notes('Notizen'),
  reminders('Erinnerungen'),
  maps('Karten'),
  files('Dateien'),
  contacts('Kontakte'),
  health('Health'),
  store('App Store'),
  wallet('Wallet'),
  voice('Sprachmemos'),
  find('Wo ist?');

  const Role(this.label);
  final String label;
}

const packageRoles = {
  'com.samsung.android.dialer': Role.phone,
  'com.google.android.dialer': Role.phone,
  'com.android.dialer': Role.phone,
  'com.samsung.android.messaging': Role.messages,
  'com.google.android.apps.messaging': Role.messages,
  'com.sec.android.app.sbrowser': Role.safari,
  'com.android.browser': Role.safari,
  'com.google.android.gm': Role.mail,
  'com.samsung.android.email.provider': Role.mail,
  'com.sec.android.app.camera': Role.camera,
  'com.android.camera2': Role.camera,
  'com.google.android.GoogleCamera': Role.camera,
  'com.sec.android.gallery3d': Role.photos,
  'com.apple.android.music': Role.music,
  'com.samsung.android.calendar': Role.calendar,
  'com.sec.android.app.clockpackage': Role.clock,
  'com.google.android.deskclock': Role.clock,
  'com.android.settings': Role.settings,
  'com.sec.android.app.popupcalculator': Role.calculator,
  'com.google.android.calculator': Role.calculator,
  'com.samsung.android.app.notes': Role.notes,
  'com.google.android.keep': Role.notes,
  'com.samsung.android.app.reminder': Role.reminders,
  'com.google.android.apps.maps': Role.maps,
  'com.sec.android.app.myfiles': Role.files,
  'com.google.android.apps.nbu.files': Role.files,
  'com.samsung.android.app.contacts': Role.contacts,
  'com.google.android.contacts': Role.contacts,
  'com.sec.android.app.shealth': Role.health,
  'com.android.vending': Role.store,
  'com.samsung.android.spay': Role.wallet,
  'com.google.android.apps.walletnfcrel': Role.wallet,
  'com.sec.android.app.voicenote': Role.voice,
  'com.samsung.android.app.find': Role.find,
};

/// Installed packages that lose out on a role: per role one app wins, a default app first,
/// then the order of [packageRoles].
Set<String> rolesTaken(Set<String> installed, Set<String> defaults) {
  final winners = <Role, String>{};
  for (final pick in [true, false]) {
    for (final MapEntry(key: package, value: role) in packageRoles.entries) {
      if (!installed.contains(package) || (pick && !defaults.contains(package))) continue;
      winners.putIfAbsent(role, () => package);
    }
  }
  return {
    for (final MapEntry(key: package, value: role) in packageRoles.entries)
      if (installed.contains(package) && winners[role] != package) package,
  };
}

/// Drawn iOS-style app icon. Sits inside the rounded clip of [AppIcon].
class RoleIcon extends StatelessWidget {
  const RoleIcon({super.key, required this.role, required this.size, this.dark = false});
  final Role role;
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (role == Role.calendar || role == Role.clock) {
      return Ticker(
        builder: (_, now) => CustomPaint(size: Size.square(size), painter: _RolePainter(role, now, dark)),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(size), painter: _RolePainter(role, DateTime(2000), dark)),
    );
  }
}

const _accent = {
  Role.phone: Color(0xFF34C759),
  Role.messages: Color(0xFF34C759),
  Role.mail: Color(0xFF0A84FF),
  Role.music: Color(0xFFFF375F),
  Role.store: Color(0xFF0A84FF),
};

const _dayShort = ['MO', 'DI', 'MI', 'DO', 'FR', 'SA', 'SO'];

class _RolePainter extends CustomPainter {
  _RolePainter(this.role, this.now, this.dark);
  final Role role;
  final DateTime now;
  final bool dark;

  late Canvas _c;
  late double _s;

  /// What is white on the colourful tile takes the app's colour on the dark one.
  Color get _glyph_ => dark ? _accent[role] ?? Colors.white : Colors.white;
  Color get _paper => dark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _ink => dark ? Colors.white : Colors.black;

  void _fill(Color top, Color bottom) {
    if (dark) {
      top = const Color(0xFF2C2C2E);
      bottom = const Color(0xFF0E0E10);
    }
    _c.drawRect(
      Offset.zero & Size.square(_s),
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(Offset.zero & Size.square(_s)),
    );
  }

  Offset _p(double x, double y) => Offset(x * _s, y * _s);
  Rect _r(double l, double t, double r, double b) => Rect.fromLTRB(l * _s, t * _s, r * _s, b * _s);
  RRect _rr(double l, double t, double r, double b, double radius) => RRect.fromRectAndRadius(_r(l, t, r, b), Radius.circular(radius * _s));
  Paint _solid(Color color) => Paint()..color = color;
  Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = width * _s;

  void _glyph(IconData icon, Color color, double size, {Offset shift = Offset.zero}) {
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, fontSize: size * _s, color: color, height: 1),
      ),
    )..layout();
    text.paint(_c, _p(0.5, 0.5) + shift * _s - Offset(text.width / 2, text.height / 2));
  }

  void _text(String value, double size, double weight, Color color, double centerY) {
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: value,
        style: sf(size * _s, weight: weight, color: color, height: 1),
      ),
    )..layout();
    text.paint(_c, Offset((_s - text.width) / 2, centerY * _s - text.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _s = size.width;
    switch (role) {
      case Role.phone:
        _fill(const Color(0xFF67F07F), const Color(0xFF0DBA2C));
        _glyph(Icons.call, _glyph_, 0.64);
      case Role.messages:
        _fill(const Color(0xFF67F07F), const Color(0xFF0DBA2C));
        final bubble = Path()..addOval(_r(0.14, 0.17, 0.86, 0.75));
        final tail = Path()
          ..moveTo(0.29 * _s, 0.66 * _s)
          ..quadraticBezierTo(0.30 * _s, 0.80 * _s, 0.19 * _s, 0.85 * _s)
          ..quadraticBezierTo(0.36 * _s, 0.85 * _s, 0.45 * _s, 0.72 * _s)
          ..close();
        canvas.drawPath(Path.combine(PathOperation.union, bubble, tail), _solid(_glyph_));
      case Role.safari:
        _safari();
      case Role.mail:
        _fill(const Color(0xFF1FD1FB), const Color(0xFF1A5BEF));
        final body = _rr(0.14, 0.25, 0.86, 0.75, 0.07);
        canvas.drawRRect(body, _solid(_glyph_));
        canvas.save();
        canvas.clipRRect(body);
        final flap = Path()
          ..moveTo(0.11 * _s, 0.25 * _s)
          ..lineTo(0.5 * _s, 0.56 * _s)
          ..lineTo(0.89 * _s, 0.25 * _s);
        canvas.drawPath(flap, _line(dark ? const Color(0xFF0E0E10) : const Color(0xFF1F8FF2), 0.028));
        canvas.restore();
      case Role.camera:
        _camera();
      case Role.photos:
        _photos();
      case Role.music:
        _fill(const Color(0xFFFB6A80), const Color(0xFFF2263F));
        paintMusicNote(canvas, _r(0.16, 0.16, 0.84, 0.84), _glyph_);
      case Role.calendar:
        _fill(Colors.white, Colors.white);
        _text(_dayShort[now.weekday - 1], 0.155, 600, const Color(0xFFFF3B30), 0.205);
        _text('${now.day}', 0.5, 400, _ink, 0.6);
      case Role.clock:
        _clock();
      case Role.settings:
        _settings();
      case Role.calculator:
        _calculator();
      case Role.notes:
        _fill(const Color(0xFFFFFFFF), const Color(0xFFF4F4F2));
        canvas.drawRect(
          _r(0, 0, 1, 0.27),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFDE5A), Color(0xFFFFC61E)],
            ).createShader(_r(0, 0, 1, 0.27)),
        );
        for (var i = 0; i < 4; i++) {
          final y = 0.42 + i * 0.145;
          canvas.drawLine(_p(0, y), _p(1, y), _line(const Color(0xFFD9D9D6), 0.009));
        }
        for (var x = 0.09; x < 0.96; x += 0.082) {
          canvas.drawCircle(_p(x, 0.27), 0.0085 * _s, _solid(const Color(0xFFA8A8A4)));
        }
      case Role.reminders:
        _fill(Colors.white, Colors.white);
        const dots = [Color(0xFF0A84FF), Color(0xFFFF3B30), Color(0xFFFF9500)];
        for (var i = 0; i < 3; i++) {
          final y = 0.25 + i * 0.25;
          canvas.drawCircle(_p(0.25, y), 0.085 * _s, _solid(dots[i]));
          canvas.drawCircle(_p(0.25, y), 0.05 * _s, _solid(_paper));
          canvas.drawCircle(_p(0.25, y), 0.036 * _s, _solid(dots[i]));
          canvas.drawLine(_p(0.42, y), _p(0.86, y), _line(const Color(0xFFD5D5DA), 0.024));
        }
      case Role.maps:
        _maps();
      case Role.files:
        _fill(Colors.white, const Color(0xFFF0F3F8));
        final back = _rr(0.13, 0.22, 0.87, 0.77, 0.07);
        canvas.drawRRect(back, _solid(const Color(0xFF5FB6F9)));
        canvas.drawRRect(_rr(0.13, 0.22, 0.46, 0.40, 0.06), _solid(const Color(0xFF5FB6F9)));
        canvas.drawRRect(
          _rr(0.13, 0.35, 0.87, 0.77, 0.07),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7CCBFF), Color(0xFF2E96F5)],
            ).createShader(_r(0, 0.35, 1, 0.77)),
        );
      case Role.contacts:
        _fill(const Color(0xFFD7DAE0), const Color(0xFF9EA3AD));
        canvas.drawCircle(_p(0.5, 0.38), 0.17 * _s, _solid(Colors.white));
        canvas.drawOval(_r(0.17, 0.61, 0.83, 1.12), _solid(Colors.white));
      case Role.health:
        _fill(Colors.white, Colors.white);
        _glyph(Icons.favorite, const Color(0xFFFF375F), 0.62, shift: const Offset(0.14, -0.14));
      case Role.store:
        _fill(const Color(0xFF2CC1FB), const Color(0xFF1570EF));
        final white = _line(_glyph_, 0.062);
        canvas.drawLine(_p(0.56, 0.2), _p(0.3, 0.68), white);
        canvas.drawLine(_p(0.44, 0.2), _p(0.70, 0.68), white);
        canvas.drawLine(_p(0.2, 0.66), _p(0.58, 0.66), white);
        canvas.drawLine(_p(0.70, 0.66), _p(0.8, 0.66), white);
        canvas.drawLine(_p(0.3, 0.68), _p(0.25, 0.77), white);
      case Role.wallet:
        _fill(const Color(0xFF1C1C1E), Colors.black);
        const cards = [Color(0xFF2FB7F5), Color(0xFFFFC42E), Color(0xFF34C759), Color(0xFFFF453A)];
        for (var i = 0; i < 4; i++) {
          final top = 0.2 + i * 0.13;
          canvas.drawRRect(_rr(0.15, top, 0.85, top + 0.3, 0.05), _solid(cards[i]));
        }
        canvas.drawRRect(_rr(0.12, 0.56, 0.88, 0.8, 0.07), _solid(const Color(0xFF1C1C1E)));
      case Role.voice:
        _fill(const Color(0xFF1C1C1E), Colors.black);
        const bars = [0.1, 0.22, 0.34, 0.16, 0.42, 0.26, 0.12, 0.3, 0.2, 0.08];
        for (var i = 0; i < bars.length; i++) {
          final x = 0.16 + i * 0.076;
          canvas.drawLine(_p(x, 0.5 - bars[i] / 2), _p(x, 0.5 + bars[i] / 2), _line(const Color(0xFFFF3B30), 0.03));
        }
      case Role.find:
        _fill(const Color(0xFF52E26F), const Color(0xFF1AB54A));
        for (final r in [0.34, 0.23, 0.12]) {
          canvas.drawCircle(_p(0.5, 0.5), r * _s, _line(Colors.white.withValues(alpha: 0.75), 0.02));
        }
        canvas.drawCircle(_p(0.5, 0.5), 0.06 * _s, _solid(Colors.white));
    }
  }

  void _safari() {
    _fill(const Color(0xFFFFFFFF), const Color(0xFFE6E6EA));
    final rect = _r(0.09, 0.09, 0.91, 0.91);
    _c.drawOval(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1AD6FD), Color(0xFF1D62F0)],
        ).createShader(rect),
    );
    final center = _p(0.5, 0.5);
    final major = _line(Colors.white, 0.012);
    final minor = _line(Colors.white.withValues(alpha: 0.7), 0.006);
    for (var i = 0; i < 48; i++) {
      final a = i * pi / 24;
      final d = Offset(sin(a), -cos(a)) * _s;
      _c.drawLine(center + d * 0.385, center + d * (i % 4 == 0 ? 0.34 : 0.36), i % 4 == 0 ? major : minor);
    }
    const angle = 0.72;
    final tip = Offset(sin(angle), -cos(angle)) * _s;
    final side = Offset(cos(angle), sin(angle)) * _s * 0.052;
    _c.drawPath(
      Path()
        ..moveTo(center.dx + tip.dx * 0.31, center.dy + tip.dy * 0.31)
        ..lineTo(center.dx + side.dx, center.dy + side.dy)
        ..lineTo(center.dx - side.dx, center.dy - side.dy)
        ..close(),
      _solid(const Color(0xFFFF3B30)),
    );
    _c.drawPath(
      Path()
        ..moveTo(center.dx - tip.dx * 0.31, center.dy - tip.dy * 0.31)
        ..lineTo(center.dx + side.dx, center.dy + side.dy)
        ..lineTo(center.dx - side.dx, center.dy - side.dy)
        ..close(),
      _solid(Colors.white),
    );
  }

  void _photos() {
    _fill(Colors.white, Colors.white);
    const petals = [
      Color(0xFFFF9500),
      Color(0xFFFFCC00),
      Color(0xFF8ED44B),
      Color(0xFF34C759),
      Color(0xFF32ADE6),
      Color(0xFF5E5CE6),
      Color(0xFFAF52DE),
      Color(0xFFFF3B30),
    ];
    final center = _p(0.5, 0.5);
    for (var i = 0; i < 8; i++) {
      _c.save();
      _c.translate(center.dx, center.dy);
      _c.rotate(i * pi / 4);
      _c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(-0.105 * _s, -0.39 * _s, 0.105 * _s, -0.015 * _s), Radius.circular(0.105 * _s)),
        Paint()
          ..color = petals[i].withValues(alpha: 0.82)
          ..blendMode = dark ? BlendMode.plus : BlendMode.multiply,
      );
      _c.restore();
    }
  }

  void _clock() {
    _fill(const Color(0xFF1C1C1E), Colors.black);
    final center = _p(0.5, 0.5);
    _c.drawCircle(center, 0.425 * _s, _solid(dark ? const Color(0xFF2C2C2E) : Colors.white));
    for (var i = 1; i <= 12; i++) {
      final a = i * pi / 6;
      final text = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: '$i',
          style: sf(0.085 * _s, weight: 500, color: _ink, height: 1),
        ),
      )..layout();
      final p = center + Offset(sin(a), -cos(a)) * (0.335 * _s);
      text.paint(_c, p - Offset(text.width / 2, text.height / 2));
    }
    void hand(double turns, double length, double width, Color color) {
      final a = turns * 2 * pi;
      _c.drawLine(center, center + Offset(sin(a), -cos(a)) * (length * _s), _line(color, width));
    }

    hand((now.hour % 12 + now.minute / 60) / 12, 0.2, 0.034, _ink);
    hand(now.minute / 60, 0.3, 0.026, _ink);
    hand(now.second / 60, 0.34, 0.01, const Color(0xFFFF9500));
    _c.drawCircle(center, 0.03 * _s, _solid(const Color(0xFFFF9500)));
  }

  /// iOS 26's Camera icon: nothing but a large lens. Its glass catches a cool light at the
  /// top and a warm one below; on the dark and the glass tile the barrel is two fine rings.
  void _camera() {
    _fill(Colors.white, const Color(0xFFD0D1D7));
    final c = _p(0.5, 0.5);
    Rect disc(double r) => Rect.fromCircle(center: c, radius: r * _s);
    Paint shade(double r, List<Color> colors) =>
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(disc(r));
    Paint glow(Color color, double blur) => Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * _s);

    final double glass;
    if (dark) {
      glass = 0.338;
      _c.drawCircle(c, 0.386 * _s, _line(const Color(0xFFD2D2D6), 0.024));
      _c.drawCircle(c, 0.35 * _s, _line(const Color(0xFF85858A), 0.012));
    } else {
      glass = 0.29;
      _c.drawCircle(c + Offset(0, 0.014 * _s), 0.372 * _s, glow(const Color(0x40000000), 0.018));
      // Brushed metal outside, a bevel that catches the light from below, then the dark barrel.
      _c.drawCircle(c, 0.372 * _s, shade(0.372, const [Color(0xFFF6F6F8), Color(0xFF8B8C93)]));
      _c.drawCircle(c, 0.338 * _s, shade(0.338, const [Color(0xFF63646A), Color(0xFFC4C5CA)]));
      _c.drawCircle(c, 0.318 * _s, shade(0.318, const [Color(0xFF3B3C42), Color(0xFF141518)]));
    }
    _c.drawCircle(
      c,
      glass * _s,
      Paint()
        ..shader = RadialGradient(
          colors: dark ? const [Color(0xFF1B1B1F), Color(0xFF09090B)] : const [Color(0xFF27315E), Color(0xFF0B0F24), Color(0xFF04050C)],
          stops: dark ? null : const [0, 0.62, 1],
        ).createShader(disc(glass)),
    );
    _c.save();
    _c.clipPath(Path()..addOval(disc(glass)));
    // The elements of the lens show as faint rings in the glass.
    _c.drawCircle(c, glass * 0.74 * _s, _line(Colors.white.withValues(alpha: 0.08), 0.01));
    _c.drawCircle(c, glass * 0.46 * _s, _line(Colors.white.withValues(alpha: 0.07), 0.01));
    _c.drawOval(
      Rect.fromCenter(center: c + Offset(dark ? 0 : -0.05, -0.125) * _s, width: 0.25 * _s, height: 0.15 * _s),
      glow(dark ? const Color(0xF0FFFFFF) : const Color(0xF0C4DCFF), 0.028),
    );
    _c.drawOval(
      Rect.fromCenter(center: c + Offset(dark ? 0 : 0.05, 0.14) * _s, width: 0.24 * _s, height: 0.085 * _s),
      glow(dark ? const Color(0x8CFFFFFF) : const Color(0xC0C272FF), 0.026),
    );
    if (!dark) {
      _c.drawOval(Rect.fromCenter(center: c + const Offset(0.11, 0.1) * _s, width: 0.09 * _s, height: 0.06 * _s), glow(const Color(0xA0FF6A7C), 0.022));
    }
    _c.drawArc(disc(glass - 0.035), 0.22 * pi, 0.56 * pi, false, _line(Colors.white.withValues(alpha: 0.2), 0.012));
    _c.restore();
  }

  /// iOS 26's Settings icon: a cog with fine round teeth, a smaller and dimmer cog inside it,
  /// and three spokes over both that meet in a hub with hollowed sides.
  void _settings() {
    _fill(const Color(0xFF9D9DA2), const Color(0xFF5E5E63));
    final c = _p(0.5, 0.5);

    // A ring from [hole] to [root] with [count] round-tipped teeth reaching [tip].
    void cog(double tip, double root, double hole, int count, Paint paint) {
      final width = pi * (tip + root) / count * 0.5 * _s;
      final tooth = Path()
        ..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(-width / 2, -tip * _s, width / 2, -(root - 0.012) * _s),
            topLeft: Radius.circular(width / 2),
            topRight: Radius.circular(width / 2),
          ),
        );
      final teeth = Path();
      for (var i = 0; i < count; i++) {
        teeth.addPath(tooth, Offset.zero, matrix4: (Matrix4.translationValues(c.dx, c.dy, 0)..rotateZ(i * 2 * pi / count)).storage);
      }
      _c.drawPath(teeth, paint);
      _c.drawCircle(
        c,
        (root + hole) / 2 * _s,
        Paint()
          ..color = paint.color
          ..shader = paint.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = (root - hole) * _s,
      );
    }

    // Three arms of [half] the width, [length] long; where two meet, the corner is hollowed
    // out by an arc that starts [fillet] up each arm.
    Path spokes(double length, double half, double fillet) {
      Offset at(double angle, double along, double across) => c + (Offset(cos(angle), sin(angle)) * along + Offset(-sin(angle), cos(angle)) * across) * _s;
      final inner = half / tan(pi / 3) + fillet;
      final path = Path();
      for (var k = 0; k < 3; k++) {
        final angle = k * 2 * pi / 3, next = angle + 2 * pi / 3;
        final near = at(angle, length, -half), far = at(angle, length, half), turn = at(angle, inner, half);
        k == 0 ? path.moveTo(near.dx, near.dy) : path.lineTo(near.dx, near.dy);
        path
          ..lineTo(far.dx, far.dy)
          ..lineTo(turn.dx, turn.dy)
          ..arcToPoint(at(next, inner, -half), radius: Radius.circular(fillet * tan(pi / 3) * _s), clockwise: false);
      }
      return path..close();
    }

    final metal = dark
        ? _solid(const Color(0xFFC8C8CD))
        : (Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFAFAFC), Color(0xFFCDCDD2)],
            ).createShader(Rect.fromCircle(center: c, radius: 0.4 * _s)));

    if (!dark) {
      _c.save();
      _c.translate(0, 0.012 * _s);
      cog(0.396, 0.35, 0.29, 38, _solid(const Color(0x38000000)));
      _c.restore();
    }
    // The hub's hole has to cut through to the tile, whatever is on it.
    _c.saveLayer(Offset.zero & Size.square(_s), Paint());
    cog(0.238, 0.208, 0.15, 24, _solid(dark ? const Color(0xFF85858A) : const Color(0xFFB4B4B9)));
    cog(0.396, 0.35, 0.29, 38, metal);
    _c.drawPath(spokes(0.3, 0.04, 0.085), metal);
    _c.drawCircle(c, 0.03 * _s, Paint()..blendMode = BlendMode.clear);
    _c.restore();
  }

  void _calculator() {
    _fill(const Color(0xFF1C1C1E), Colors.black);
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        final color = column == 3
            ? const Color(0xFFFF9500)
            : row == 0
            ? const Color(0xFFA5A5AA)
            : const Color(0xFF4A4A4E);
        _c.drawCircle(_p(0.215 + column * 0.19, 0.215 + row * 0.19), 0.077 * _s, _solid(color));
      }
    }
  }

  void _maps() {
    _fill(const Color(0xFF8EDB7B), const Color(0xFF5FC45E));
    _c.drawPath(
      Path()
        ..moveTo(0.46 * _s, 0)
        ..lineTo(_s, 0)
        ..lineTo(_s, 0.62 * _s)
        ..close(),
      _solid(const Color(0xFF7CCBFA)),
    );
    final road = _line(const Color(0xFFFFD84A), 0.09);
    _c.drawPath(
      Path()
        ..moveTo(-0.05 * _s, 0.72 * _s)
        ..quadraticBezierTo(0.35 * _s, 0.62 * _s, 0.56 * _s, 1.05 * _s),
      road,
    );
    final white = _line(Colors.white, 0.06);
    _c.drawPath(
      Path()
        ..moveTo(0.3 * _s, 1.05 * _s)
        ..quadraticBezierTo(0.42 * _s, 0.5 * _s, 0.95 * _s, 0.42 * _s),
      white,
    );
    _c.drawCircle(_p(0.3, 0.3), 0.14 * _s, _solid(const Color(0xFF0A84FF)));
    _c.drawCircle(_p(0.3, 0.3), 0.14 * _s, _line(Colors.white, 0.03));
    _glyph(Icons.navigation, Colors.white, 0.17, shift: const Offset(-0.2, -0.2));
  }

  @override
  bool shouldRepaint(_RolePainter old) => old.now != now || old.role != role || old.dark != dark;
}

/// Apple Music's beamed pair of notes, which no Material icon has.
void paintMusicNote(Canvas canvas, Rect area, Color color) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  canvas
    ..save()
    ..translate(area.left, area.top)
    ..scale(area.width);
  canvas.drawPath(
    Path()
      ..addPolygon(const [Offset(0.33, 0.27), Offset(0.85, 0.13), Offset(0.85, 0.25), Offset(0.33, 0.39)], true)
      ..addRect(const Rect.fromLTRB(0.33, 0.28, 0.39, 0.78))
      ..addRect(const Rect.fromLTRB(0.79, 0.14, 0.85, 0.68)),
    paint,
  );
  for (final head in const [Offset(0.27, 0.78), Offset(0.73, 0.68)]) {
    canvas
      ..save()
      ..translate(head.dx, head.dy)
      ..rotate(-0.35)
      ..drawOval(Rect.fromCenter(center: Offset.zero, width: 0.25, height: 0.19), paint)
      ..restore();
  }
  canvas.restore();
}

class MusicNote extends StatelessWidget {
  const MusicNote({super.key, required this.size, this.color = Colors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MusicNotePainter(color));
}

class _MusicNotePainter extends CustomPainter {
  const _MusicNotePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => paintMusicNote(canvas, Offset.zero & size, color);

  @override
  bool shouldRepaint(_MusicNotePainter old) => old.color != color;
}
