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
        _fill(const Color(0xFFE3E4E6), const Color(0xFF8E9096));
        final body = dark ? const Color(0xFF8E9096) : const Color(0xFF2C2C2E);
        canvas.drawRRect(_rr(0.13, 0.30, 0.87, 0.76, 0.08), _solid(body));
        canvas.drawRRect(_rr(0.36, 0.23, 0.64, 0.36, 0.05), _solid(body));
        canvas.drawCircle(_p(0.5, 0.53), 0.175 * _s, _solid(const Color(0xFFB9BBC0)));
        canvas.drawCircle(_p(0.5, 0.53), 0.135 * _s, _solid(body));
        canvas.drawCircle(_p(0.5, 0.53), 0.075 * _s, _solid(const Color(0xFF4A4E5A)));
        canvas.drawCircle(_p(0.77, 0.39), 0.022 * _s, _solid(const Color(0xFFFFD60A)));
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

  /// iOS 26's Settings icon: a light silver cog with fine teeth on a graphite tile; inside a
  /// dark ring with a band of small teeth, and three spokes meeting at the hub.
  void _settings() {
    _fill(const Color(0xFF9D9DA2), const Color(0xFF5E5E63));
    final c = _p(0.5, 0.5);
    void cog(double outer, double inner, int count, double flat, Paint paint) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final a = i * 2 * pi / count;
        final half = pi / count;
        final corners = [(a - half, inner), (a - half * flat, outer), (a + half * flat, outer), (a + half, inner)];
        for (var j = 0; j < corners.length; j++) {
          final (angle, r) = corners[j];
          final p = c + Offset(cos(angle), sin(angle)) * r * _s;
          i == 0 && j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
      }
      _c.drawPath(path..close(), paint);
    }

    Paint silver(double radius) => Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFAFAFC), Color(0xFFC9C9CE)],
      ).createShader(Rect.fromCircle(center: c, radius: radius * _s));

    // Outer cog with a soft shadow below it.
    _c.save();
    _c.translate(0, 0.012 * _s);
    cog(0.43, 0.385, 40, 0.5, _solid(const Color(0x40000000)));
    _c.restore();
    cog(0.43, 0.385, 40, 0.5, silver(0.43));
    // Dark recess with a ring of small inward teeth.
    _c.drawCircle(c, 0.315 * _s, _solid(const Color(0xFF6B6B70)));
    cog(0.285, 0.255, 40, 0.5, _solid(const Color(0xFFB4B4B9)));
    _c.drawCircle(c, 0.24 * _s, _solid(const Color(0xFF6B6B70)));
    // Three spokes and the hub.
    final spoke = Paint()
      ..color = const Color(0xFFEFEFF2)
      ..strokeWidth = 0.05 * _s
      ..strokeCap = StrokeCap.round;
    for (final degrees in [-10.0, 110.0, 230.0]) {
      final a = degrees * pi / 180;
      _c.drawLine(c, c + Offset(cos(a), sin(a)) * 0.25 * _s, spoke);
    }
    _c.drawCircle(c, 0.058 * _s, silver(0.06));
    _c.drawCircle(c, 0.058 * _s, _line(const Color(0xFF6B6B70), 0.012));
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
