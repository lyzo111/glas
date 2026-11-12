import 'dart:math';

import 'package:flutter/material.dart';

import 'appwidgets.dart';
import 'glass.dart';
import 'icons.dart';
import 'layout.dart';
import 'native.dart';
import 'state.dart';

/// Built-in home screen widgets, drawn after the iOS ones. Widgets of other apps are hosted
/// natively, see appwidgets.dart.
class HomeWidget extends StatelessWidget {
  const HomeWidget({super.key, required this.kind, required this.size, required this.state, required this.scale});
  final WidgetKind kind;
  final WidgetSize size;
  final AppState state;

  /// Size of one iOS point.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final p = Ios(scale);
    return Ticker(
      builder: (_, now) {
        final face = switch (kind) {
          WidgetKind.weather => _Weather(state, p, size: size),
          WidgetKind.calendar => _Card(
            p,
            child: switch (size) {
              WidgetSize.small => _Calendar(state, now, p),
              WidgetSize.medium => _Agenda(state, now, p),
              WidgetSize.large => Column(
                children: [
                  Expanded(child: _Agenda(state, now, p)),
                  Expanded(child: _Month(now, p)),
                ],
              ),
            },
          ),
          WidgetKind.month => _Card(p, child: _Month(now, p)),
          WidgetKind.clock => _Card(
            p,
            color: const Color(0xFF1C1C1E),
            child: size == WidgetSize.small
                ? CustomPaint(
                    painter: _ClockPainter(now, glass: _glass),
                    size: Size.infinite,
                  )
                : _ClockWide(now, p),
          ),
          WidgetKind.battery => _Card(p, child: size == WidgetSize.small ? _Battery(state, p) : _BatteryWide(state, p)),
          WidgetKind.music => size == WidgetSize.small ? _MusicSmall(state, p) : _Music(state, p),
          WidgetKind.worldClock => _WorldClock(state, now, p, wide: size != WidgetSize.small),
          WidgetKind.note => _Note(state, p),
          WidgetKind.shortcuts => _Shortcuts(state, p, wide: size != WidgetSize.small),
          WidgetKind.photos => _Photo(state, p),
          WidgetKind.date => _Card(p, child: _DateFace(now, p)),
          WidgetKind.app => const SizedBox(),
        };
        // A photo stays a photo; everything else turns to glass with the icons.
        if (!_glass || (kind == WidgetKind.photos && state.photo != null)) return face;
        return _GlassFace(p, light: _lightKinds.contains(kind), child: face);
      },
    );
  }
}

/// Whether the glass icon styles are on; the widgets then turn to glass as well.
bool get _glass => IconStyle.current.glass;

const _lightKinds = {WidgetKind.calendar, WidgetKind.month, WidgetKind.battery, WidgetKind.date, WidgetKind.note};

/// A widget in the clear or tinted style, as iOS draws it: its picture keeps only its
/// brightness, which becomes ink on a pane of glass. [light] says the picture is dark on
/// white; otherwise it is light on dark.
class _GlassFace extends StatelessWidget {
  const _GlassFace(this.p, {required this.light, required this.child});
  final Ios p;
  final bool light;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = IconStyle.current;
    final ink = glassInk(look);
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: CustomPaint(
        foregroundPainter: GlassEdge(p(24)),
        child: DecoratedBox(
          decoration: glassPane(look),
          child: ColorFiltered(
            colorFilter: light ? toneFilter(ink, floor: 0.97, gain: 1.2, inverted: true) : toneFilter(ink, floor: 0.13, gain: 1.25),
            // The corners outside the card must read as background too.
            child: ColoredBox(color: light ? Colors.white : _night, child: child),
          ),
        ),
      ),
    );
  }
}

/// The white card most iOS widgets sit on in light mode.
class _Card extends StatelessWidget {
  const _Card(this.p, {required this.child, this.color = Colors.white});
  final Ios p;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(p(24)),
    child: ColoredBox(
      color: color,
      child: SizedBox.expand(child: child),
    ),
  );
}

const _red = Color(0xFFFF3B30);
const _ink = Color(0xFF1C1C1E);
const _dim = Color(0xFF8E8E93);
const _night = Color(0xFF1C1C1E);

// ------------------------------------------------------------------- Weather

bool _rainy(int code) => (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
bool _snowy(int code) => (code >= 71 && code <= 77) || code == 85 || code == 86;
bool _stormy(int code) => code >= 95;
bool _cloudy(int code) => code >= 3 && code <= 48;

String weatherText(int code) => switch (code) {
  0 => 'Klar',
  1 => 'Meist klar',
  2 => 'Teils bewölkt',
  3 => 'Bewölkt',
  45 || 48 => 'Nebel',
  _ when _stormy(code) => 'Gewitter',
  _ when _snowy(code) => 'Schnee',
  _ when code >= 51 && code <= 57 => 'Nieselregen',
  _ when _rainy(code) => 'Regen',
  _ => 'Bewölkt',
};

List<Color> _sky(Weather? w) {
  if (_glass) return const [_night, _night];
  if (w == null) return const [Color(0xFF2D7DD2), Color(0xFF7DB9E8)];
  if (!w.day) return const [Color(0xFF0B1026), Color(0xFF2A3560)];
  if (_rainy(w.code) || _stormy(w.code)) return const [Color(0xFF4A5868), Color(0xFF7D8A99)];
  if (_cloudy(w.code)) return const [Color(0xFF5B7C9E), Color(0xFF9DB4C8)];
  return const [Color(0xFF1F73D1), Color(0xFF6DB6F2)];
}

/// Filled, coloured weather symbol like the SF multicolour glyphs.
class WeatherGlyph extends StatelessWidget {
  const WeatherGlyph({super.key, required this.code, required this.day, required this.size});
  final int code;
  final bool day;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clear = code <= 1;
    final partly = code == 2;
    final sky = Icon(
      day ? Icons.wb_sunny_rounded : Icons.nightlight_round,
      size: clear ? size : size * 0.72,
      color: day ? const Color(0xFFFFD60A) : Colors.white,
    );
    if (clear) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: sky),
      );
    }
    final wet = _rainy(code) || _snowy(code) || _stormy(code);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (partly) Positioned(right: -size * 0.04, top: -size * 0.08, child: sky),
          Positioned(
            left: 0,
            right: 0,
            top: wet ? -size * 0.14 : size * 0.06,
            child: Icon(Icons.cloud_rounded, size: size, color: Colors.white),
          ),
          if (wet)
            Positioned(
              left: 0,
              right: 0,
              bottom: -size * 0.04,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: size * 0.03),
                      child: _snowy(code)
                          ? Icon(Icons.ac_unit, size: size * 0.2, color: Colors.white)
                          : Icon(Icons.water_drop, size: size * 0.2, color: const Color(0xFF64D2FF)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Weather extends StatelessWidget {
  const _Weather(this.state, this.p, {required this.size});
  final AppState state;
  final Ios p;
  final WidgetSize size;

  bool get wide => size != WidgetSize.small;

  Widget _hours(Weather w) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final (i, h) in w.hours.take(6).indexed)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(i == 0 ? 'Jetzt' : '${h.time.hour}', style: sf(p(12), weight: 600)),
            SizedBox(height: p(5)),
            WeatherGlyph(code: h.code, day: h.time.hour >= 7 && h.time.hour < 19, size: p(17)),
            SizedBox(height: p(5)),
            Text('${h.temperature}°', style: sf(p(13), weight: 600)),
          ],
        ),
    ],
  );

  Widget _days(Weather w) => Column(
    children: [
      for (final (i, d) in w.days.skip(1).take(5).indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : p(7)),
          child: Row(
            children: [
              SizedBox(
                width: p(100),
                child: Text(weekdays[d.time.weekday - 1], style: sf(p(14), weight: 600)),
              ),
              WeatherGlyph(code: d.code, day: true, size: p(18)),
              const Spacer(),
              Text('${d.low}°', style: sf(p(14), weight: 600, color: Colors.white.withValues(alpha: 0.65))),
              SizedBox(width: p(12)),
              SizedBox(
                width: p(30),
                child: Text('${d.high}°', textAlign: TextAlign.right, style: sf(p(14), weight: 600)),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final w = state.weather;
    final located = state.permissions['location'] == true;
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(w == null || w.city.isEmpty ? 'Wetter' : w.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(14), weight: 600)),
            ),
            SizedBox(width: p(3)),
            Icon(Icons.navigation, size: p(10), color: Colors.white),
          ],
        ),
        Text(w == null ? '--°' : '${w.temperature}°', style: sf(p(42), weight: 300, height: 1.12)),
      ],
    );
    final foot = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (w != null) ...[
          WeatherGlyph(code: w.code, day: w.day, size: p(18)),
          SizedBox(height: p(3)),
          Text(weatherText(w.code), maxLines: 1, style: sf(p(13), weight: 600)),
          Text('H:${w.high}° T:${w.low}°', maxLines: 1, style: sf(p(13), weight: 600)),
        ] else
          Text(located ? 'Wird geladen …' : 'Standort erlauben', style: sf(p(13), weight: 600)),
      ],
    );
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _sky(w)),
        ),
        child: Padding(
          padding: EdgeInsets.all(p(15)),
          child: wide
              ? Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: head),
                        foot,
                      ],
                    ),
                    const Spacer(),
                    if (w != null) _hours(w),
                    if (w != null && size == WidgetSize.large) ...[
                      const Spacer(),
                      Divider(height: p(1), thickness: 0.5, color: Colors.white38),
                      const Spacer(),
                      _days(w),
                      const Spacer(),
                    ],
                  ],
                )
              : SizedBox.expand(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const Spacer(), foot]),
                ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Calendar

String _eventTime(Event e) => e.allDay ? 'Ganztägig' : clockText(e.begin);

class _Calendar extends StatelessWidget {
  const _Calendar(this.state, this.now, this.p);
  final AppState state;
  final DateTime now;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final today = state.events.where((e) => e.begin.day == now.day && e.begin.month == now.month).take(2).toList();
    return Padding(
      padding: EdgeInsets.all(p(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(weekdays[now.weekday - 1].toUpperCase(), style: sf(p(12), weight: 700, color: _red, tracking: 0.01)),
          Text('${now.day}', style: sf(p(40), weight: 300, color: _ink, height: 1.12)),
          const Spacer(),
          if (today.isEmpty)
            Text('Heute keine Ereignisse', maxLines: 2, style: sf(p(13), weight: 500, color: _dim, height: 1.2))
          else
            for (final e in today)
              Padding(
                padding: EdgeInsets.only(top: p(3)),
                child: Row(
                  children: [
                    Container(
                      width: p(3.5),
                      height: p(28),
                      decoration: BoxDecoration(color: Color(e.color), borderRadius: BorderRadius.circular(p(2))),
                    ),
                    SizedBox(width: p(6)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sf(p(12.5), weight: 600, color: _ink),
                          ),
                          Text(_eventTime(e), maxLines: 1, style: sf(p(11.5), color: _dim)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month(this.now, this.p);
  final DateTime now;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(now.year, now.month);
    final count = DateTime(now.year, now.month + 1, 0).day;
    final blanks = first.weekday - 1;
    final style = sf(p(10), weight: 600, color: _ink, height: 1);
    return Padding(
      padding: EdgeInsets.all(p(13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(months[now.month - 1].toUpperCase(), style: sf(p(11), weight: 700, color: _red, tracking: 0.01)),
          SizedBox(height: p(5)),
          Expanded(
            child: GridView.count(
              crossAxisCount: 7,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.08,
              children: [
                for (final d in 'MDMDFSS'.split(''))
                  Center(
                    child: Text(d, style: sf(p(9), weight: 700, color: _dim, height: 1)),
                  ),
                for (var i = 0; i < blanks; i++) const SizedBox(),
                for (var d = 1; d <= count; d++)
                  Center(
                    child: d == now.day
                        ? Container(
                            width: p(16),
                            height: p(16),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                            child: Text('$d', style: style.copyWith(color: Colors.white)),
                          )
                        : Text('$d', style: style),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Agenda extends StatelessWidget {
  const _Agenda(this.state, this.now, this.p);
  final AppState state;
  final DateTime now;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(p(15)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: p(92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weekdays[now.weekday - 1].toUpperCase(), style: sf(p(12), weight: 700, color: _red, tracking: 0.01)),
                Text('${now.day}', style: sf(p(40), weight: 300, color: _ink, height: 1.12)),
              ],
            ),
          ),
          Expanded(
            child: state.events.isEmpty
                ? Center(
                    child: Text('Keine Ereignisse', style: sf(p(14), weight: 500, color: _dim)),
                  )
                : Column(
                    children: [
                      for (final e in state.events.take(3))
                        Padding(
                          padding: EdgeInsets.only(bottom: p(6)),
                          child: Row(
                            children: [
                              Container(
                                width: p(3.5),
                                height: p(32),
                                decoration: BoxDecoration(color: Color(e.color), borderRadius: BorderRadius.circular(p(2))),
                              ),
                              SizedBox(width: p(7)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: sf(p(13.5), weight: 600, color: _ink),
                                    ),
                                    Text('${e.begin.day}.${e.begin.month}. · ${_eventTime(e)}', maxLines: 1, style: sf(p(12), color: _dim)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- Clock

class _ClockPainter extends CustomPainter {
  _ClockPainter(this.time, {this.glass = false});
  final DateTime time;

  /// On glass the face is a faint disc with light numerals and hands.
  final bool glass;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = min(size.width, size.height) / 2 * 0.86;
    final ink = glass ? Colors.white : Colors.black;
    canvas.drawCircle(c, r, Paint()..color = glass ? Colors.white.withValues(alpha: 0.16) : Colors.white);
    for (var i = 1; i <= 12; i++) {
      final a = i * pi / 6;
      final text = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: '$i',
          style: sf(r * 0.2, weight: 500, color: ink, height: 1),
        ),
      )..layout();
      text.paint(canvas, c + Offset(sin(a), -cos(a)) * (r * 0.8) - Offset(text.width / 2, text.height / 2));
    }
    void hand(double turns, double length, double width, Color color) {
      final a = turns * 2 * pi;
      canvas.drawLine(
        c,
        c + Offset(sin(a), -cos(a)) * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand((time.hour % 12 + time.minute / 60) / 12, r * 0.48, r * 0.075, ink);
    hand(time.minute / 60, r * 0.7, r * 0.055, ink);
    canvas.drawCircle(c, r * 0.05, Paint()..color = const Color(0xFFFF9500));
  }

  @override
  bool shouldRepaint(_ClockPainter old) => old.time.minute != time.minute || old.glass != glass;
}

class _ClockWide extends StatelessWidget {
  const _ClockWide(this.now, this.p);
  final DateTime now;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: p(8)),
      child: Row(
        children: [
          SizedBox.square(
            dimension: p(150),
            child: CustomPaint(painter: _ClockPainter(now)),
          ),
          SizedBox(width: p(8)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(clockText(now), style: sf(p(46), weight: 300, height: 1.1)),
                ),
                Text(weekdays[now.weekday - 1], style: sf(p(15), weight: 600, color: const Color(0xFFFF9500))),
                Text('${now.day}. ${months[now.month - 1]}', style: sf(p(14), color: _dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Battery

class _Battery extends StatelessWidget {
  const _Battery(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final level = state.status.battery;
    final color = state.status.charging ? const Color(0xFF34C759) : (level <= 20 ? _red : const Color(0xFF34C759));
    return Padding(
      padding: EdgeInsets.all(p(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: p(68),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: level / 100,
                  strokeWidth: p(7),
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: const Color(0xFFE5E5EA),
                ),
                Icon(state.status.charging ? Icons.bolt : Icons.smartphone_rounded, size: p(28), color: _ink),
              ],
            ),
          ),
          const Spacer(),
          Text('$level %', style: sf(p(28), weight: 600, color: _ink, height: 1)),
          SizedBox(height: p(2)),
          Text('Dieses Gerät', style: sf(p(12), weight: 500, color: _dim)),
        ],
      ),
    );
  }
}

class _BatteryWide extends StatelessWidget {
  const _BatteryWide(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final level = state.status.battery;
    final charging = state.status.charging;
    return Padding(
      padding: EdgeInsets.all(p(18)),
      child: Row(
        children: [
          SizedBox.square(
            dimension: p(112),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: level / 100,
                  strokeWidth: p(10),
                  strokeCap: StrokeCap.round,
                  color: level <= 20 && !charging ? _red : const Color(0xFF34C759),
                  backgroundColor: const Color(0xFFE5E5EA),
                ),
                Icon(charging ? Icons.bolt : Icons.smartphone_rounded, size: p(44), color: _ink),
              ],
            ),
          ),
          SizedBox(width: p(22)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$level %', style: sf(p(38), weight: 600, color: _ink, height: 1.1)),
                Text('Dieses Gerät', style: sf(p(14), weight: 500, color: _dim)),
                Text(charging ? 'Wird geladen' : 'Akku', style: sf(p(14), color: _dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- Music

const _musicGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFB5C74), Color(0xFFB3123A)]);

class _MusicSmall extends StatelessWidget {
  const _MusicSmall(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final media = state.media;
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: DecoratedBox(
        decoration: _glass ? const BoxDecoration(color: _night) : const BoxDecoration(gradient: _musicGradient),
        child: Padding(
          padding: EdgeInsets.all(p(15)),
          child: SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: p(54),
                      height: p(54),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(p(10))),
                      alignment: Alignment.center,
                      child: MusicNote(size: p(30)),
                    ),
                    GestureDetector(
                      onTap: () => Native.call('mediaAction', 'toggle'),
                      child: Icon(media?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: p(34)),
                    ),
                  ],
                ),
                const Spacer(),
                Text(media?.title ?? 'Nichts wird abgespielt', maxLines: 2, overflow: TextOverflow.ellipsis, style: sf(p(14), weight: 600, height: 1.2)),
                if (media != null && media.artist.isNotEmpty)
                  Text(
                    media.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sf(p(13), color: Colors.white.withValues(alpha: 0.75)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Music extends StatelessWidget {
  const _Music(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final media = state.media;
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: DecoratedBox(
        decoration: _glass ? const BoxDecoration(color: _night) : const BoxDecoration(gradient: _musicGradient),
        child: Padding(
          padding: EdgeInsets.all(p(16)),
          child: Row(
            children: [
              Container(
                width: p(126),
                height: p(126),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(p(14))),
                alignment: Alignment.center,
                child: MusicNote(size: p(64)),
              ),
              SizedBox(width: p(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: MusicNote(size: p(20)),
                    ),
                    const Spacer(),
                    Text(media?.title ?? 'Nichts wird abgespielt', maxLines: 2, overflow: TextOverflow.ellipsis, style: sf(p(16), weight: 600, height: 1.2)),
                    if (media != null && media.artist.isNotEmpty)
                      Text(
                        media.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sf(p(14), color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    SizedBox(height: p(10)),
                    GestureDetector(
                      onTap: () => Native.call('mediaAction', 'toggle'),
                      child: Container(
                        height: p(32),
                        padding: EdgeInsets.symmetric(horizontal: p(14)),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(p(16))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(media?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: p(20)),
                            SizedBox(width: p(4)),
                            Text(media?.playing == true ? 'Pause' : 'Abspielen', style: sf(p(14), weight: 600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What tapping a widget opens.
void openWidget(WidgetKind kind, AppState state) {
  AppInfo? target;
  switch (kind) {
    case WidgetKind.calendar || WidgetKind.month:
      target = state.appFor(Role.calendar);
    case WidgetKind.clock:
      target = state.appFor(Role.clock);
    case WidgetKind.music:
      target = state.appFor(Role.music);
    case WidgetKind.battery:
      target = state.appFor(Role.settings);
    case WidgetKind.worldClock:
      target = state.appFor(Role.clock);
    case WidgetKind.date:
      target = state.appFor(Role.calendar);
    case WidgetKind.photos:
      if (state.permissions['photos'] != true) {
        Native.call('openPermission', 'photos');
        return;
      }
      target = state.appFor(Role.photos);
    case WidgetKind.note || WidgetKind.shortcuts || WidgetKind.app:
      break;
    case WidgetKind.weather:
      Native.call(state.permissions['location'] == true ? 'openWeather' : 'openPermission', state.permissions['location'] == true ? null : 'location');
  }
  if (target != null) state.launch(target, null);
}

// --------------------------------------------------------------- Widget stack

/// Which widget of a stack is showing, by item id; a tap opens that one.
final stackPage = <String, int>{};

/// iOS's widget stack: widgets of one size in one place, swiped through vertically, with
/// dots at the side telling where in the stack one is.
class WidgetStack extends StatefulWidget {
  const WidgetStack({
    super.key,
    required this.id,
    required this.faces,
    required this.size,
    required this.state,
    required this.scale,
    this.live = false,
    this.locked = false,
  });
  final String id;
  final List<WidgetItem> faces;

  /// For widgets of other apps in the stack, as in [AppWidgetView].
  final bool live;
  final bool locked;
  final WidgetSize size;
  final AppState state;
  final double scale;

  @override
  State<WidgetStack> createState() => _WidgetStackState();
}

class _WidgetStackState extends State<WidgetStack> {
  late final _pages = PageController(initialPage: stackPage[widget.id] ?? 0);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios(widget.scale);
    final current = stackPage[widget.id] ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Two cards peeking out below say there is more here, like a stack of notifications.
        // Only the strip of each that sticks out is drawn: a glass widget would let the rest
        // show through, and the back card would show through the front one.
        for (final (inset, drop, above, alpha) in [(p(22), p(9), p(4.5), 0.22), (p(11), p(4.5), 0.0, 0.4)])
          Positioned(
            left: inset,
            right: inset,
            bottom: -drop,
            height: drop - above,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: p(40),
                maxHeight: p(40),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _peekColor(alpha), borderRadius: BorderRadius.circular(p(18))),
                ),
              ),
            ),
          ),
        PageView(
          controller: _pages,
          scrollDirection: Axis.vertical,
          onPageChanged: (i) => setState(() => stackPage[widget.id] = i),
          children: [
            for (final face in widget.faces)
              face.kind == WidgetKind.app
                  ? AppWidgetView(item: face, live: widget.live, locked: widget.locked)
                  : HomeWidget(kind: face.kind, size: widget.size, state: widget.state, scale: widget.scale),
          ],
        ),
        Positioned(
          right: -p(13),
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: p(4), horizontal: p(2.5)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.faces.length; i++)
                    Container(
                      width: p(5),
                      height: p(5),
                      margin: EdgeInsets.symmetric(vertical: p(2)),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_glass ? glassInk(IconStyle.current) : Colors.white).withValues(alpha: i == current ? 1 : 0.45),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cards under a stack: white, or in the glass styles the colour of the glass.
Color _peekColor(double alpha) {
  final look = IconStyle.current;
  if (!look.glass) return Colors.white.withValues(alpha: alpha);
  final pane = (glassPane(look).gradient! as LinearGradient).colors.last;
  return pane.withValues(alpha: (pane.a * alpha / 0.4).clamp(0.0, 1.0));
}

// ----------------------------------------------------------------- World clock

class _WorldClock extends StatelessWidget {
  const _WorldClock(this.state, this.now, this.p, {required this.wide});
  final AppState state;
  final DateTime now;
  final Ios p;
  final bool wide;

  String _shift(int seconds) {
    final hours = (seconds - now.timeZoneOffset.inSeconds) / 3600;
    if (hours == 0) return 'Heute';
    final text = hours == hours.roundToDouble() ? hours.round().abs().toString() : hours.abs().toStringAsFixed(1);
    return '${hours > 0 ? '+' : '−'}$text Std.';
  }

  @override
  Widget build(BuildContext context) {
    final utc = now.toUtc();
    final zones = state.zones.entries.take(wide ? 4 : 2).toList();
    DateTime local(int seconds) => utc.add(Duration(seconds: seconds));
    return _Card(
      p,
      color: const Color(0xFF1C1C1E),
      child: zones.isEmpty
          ? Center(
              child: Icon(Icons.public_rounded, color: _dim, size: p(40)),
            )
          : wide
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: p(10), vertical: p(14)),
              child: Row(
                children: [
                  for (final z in zones)
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox.square(
                            dimension: p(62),
                            child: CustomPaint(painter: _ClockPainter(local(z.value))),
                          ),
                          SizedBox(height: p(6)),
                          Text(z.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(12), weight: 600)),
                          Text(_shift(z.value), style: sf(p(11), color: _dim)),
                        ],
                      ),
                    ),
                ],
              ),
            )
          : Padding(
              padding: EdgeInsets.all(p(14)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final z in zones)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(z.key, style: sf(p(13), weight: 600)),
                        Text(clockText(local(z.value)), style: sf(p(26), weight: 300, height: 1.1)),
                        Text(_shift(z.value), style: sf(p(11), color: _dim)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

// ------------------------------------------------------------------------ Note

class _Note extends StatelessWidget {
  const _Note(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final text = state.settings.note;
    return _Card(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: p(34),
            width: double.infinity,
            color: const Color(0xFFFFC61E),
            padding: EdgeInsets.symmetric(horizontal: p(14)),
            alignment: Alignment.centerLeft,
            child: Text('Notiz', style: sf(p(14), weight: 700, color: Colors.white)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(p(14), p(10), p(14), p(12)),
              child: Text(
                text.isEmpty ? 'Tippen, um etwas zu notieren' : text,
                overflow: TextOverflow.fade,
                style: sf(p(15), weight: text.isEmpty ? 400 : 500, color: text.isEmpty ? _dim : _ink, height: 1.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Shortcuts

/// iOS's Shortcuts widget, filled with the apps used most recently.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts(this.state, this.p, {required this.wide});
  final AppState state;
  final Ios p;
  final bool wide;

  static const _colors = [Color(0xFF0A84FF), Color(0xFFFF9F0A), Color(0xFF30D158), Color(0xFFBF5AF2)];

  @override
  Widget build(BuildContext context) {
    final apps = [
      for (final key in state.settings.recent) ?state.apps[key],
      ...state.apps.values,
    ].fold<List<AppInfo>>([], (list, app) => list.contains(app) || list.length >= 4 ? list : (list..add(app)));
    return _Card(
      p,
      color: const Color(0xFF1C1C1E),
      child: Padding(
        padding: EdgeInsets.all(p(10)),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: p(8),
          crossAxisSpacing: p(8),
          childAspectRatio: wide ? 2.3 : 1,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            for (var i = 0; i < apps.length; i++)
              GestureDetector(
                onTap: () => state.launch(apps[i], context),
                child: Container(
                  padding: EdgeInsets.all(p(wide ? 9 : 6)),
                  decoration: BoxDecoration(color: _colors[i % 4], borderRadius: BorderRadius.circular(p(14))),
                  child: wide
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AppIcon(app: apps[i], size: p(22)),
                            Text(apps[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(13), weight: 600)),
                          ],
                        )
                      : Center(
                          child: AppIcon(app: apps[i], size: p(30)),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- Photos

class _Photo extends StatelessWidget {
  const _Photo(this.state, this.p);
  final AppState state;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final photo = state.photo;
    if (photo == null) {
      return _Card(
        p,
        color: const Color(0xFF1C1C1E),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.white, size: p(32)),
            SizedBox(height: p(8)),
            Text(state.permissions['photos'] == true ? 'Keine Fotos' : 'Fotos erlauben', style: sf(p(13), weight: 600)),
          ],
        ),
      );
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)]),
            ),
          ),
          Positioned(
            left: p(14),
            bottom: p(12),
            child: Text('Für dich', style: sf(p(14), weight: 700)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------ Date

class _DateFace extends StatelessWidget {
  const _DateFace(this.now, this.p);
  final DateTime now;
  final Ios p;

  static const _days = ['MONTAG', 'DIENSTAG', 'MITTWOCH', 'DONNERSTAG', 'FREITAG', 'SAMSTAG', 'SONNTAG'];
  static const _months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(_days[now.weekday - 1], style: sf(p(13), weight: 700, color: _red)),
      Text('${now.day}', style: sf(p(62), weight: 300, color: _ink, height: 1.05)),
      Text(_months[now.month - 1], style: sf(p(14), weight: 600, color: _dim)),
    ],
  );
}
