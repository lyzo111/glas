import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'island.dart';
import 'layout.dart';
import 'native.dart';
import 'state.dart';
import 'widgets.dart';

/// Clock fonts. Besides Inter these are Android's own families, found by their alias.
const lockFonts = {'inter': 'Standard', 'serif': 'Serif', 'sans-serif-condensed': 'Schmal', 'monospace': 'Mono', 'cursive': 'Schreibschrift'};

const lockFilters = {'none': 'Original', 'mono': 'Schwarzweiß', 'duotone': 'Duoton', 'wash': 'Farbverlauf'};

/// The lock screen clock as iOS 26 draws it: any font and size, stretched taller on request,
/// solid or as Liquid Glass with a light rim around translucent digits.
class LockClock extends StatelessWidget {
  const LockClock({super.key, required this.text, required this.settings, required this.p});
  final String text;
  final Settings settings;
  final Ios p;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final color = Color(s.lockColor);
    final inter = s.lockFont == 'inter';
    final size = p(104) * s.lockSize;
    TextStyle style({Color? fill, List<Shadow>? shadows}) => TextStyle(
      fontFamily: inter ? 'Inter' : s.lockFont,
      color: fill,
      fontSize: size,
      height: 1.08,
      letterSpacing: inter ? -p(3.2) * s.lockSize : 0,
      fontWeight: FontWeight.values[((s.lockWeight / 100).round() - 1).clamp(0, 8)],
      fontVariations: inter ? [FontVariation('wght', s.lockWeight), const FontVariation('opsz', 32)] : null,
      fontFeatures: [const FontFeature.tabularFigures(), if (inter) const FontFeature.enable('ss03')],
      shadows: shadows ?? const [Shadow(blurRadius: 18, color: Color(0x33000000))],
    );
    final Widget digits = s.lockGlass
        ? _GlassDigits(
            text: text,
            style: style(shadows: const []),
            color: color,
            rim: p(2.6),
          )
        : Text(text, maxLines: 1, style: style(fill: color));
    if (s.lockStretch == 1) return digits;
    return SizedBox(
      height: size * 1.08 * s.lockStretch,
      child: Transform(alignment: Alignment.topCenter, transform: Matrix4.diagonal3Values(1, s.lockStretch, 1), child: digits),
    );
  }
}

/// Liquid Glass digits: a faint body inside a bright rim. The rim is a stroke with the
/// filled shape cut out of it, so it only runs along the outside; a plain stroke would also
/// trace where a font builds a digit from overlapping parts, like Inter's 1.
class _GlassDigits extends StatelessWidget {
  const _GlassDigits({required this.text, required this.style, required this.color, required this.rim});
  final String text;
  final TextStyle style;
  final Color color;
  final double rim;

  @override
  Widget build(BuildContext context) {
    final layout = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return CustomPaint(size: layout.size, painter: _GlassPainter(text, style, color, rim));
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.text, this.style, this.color, this.rim);
  final String text;
  final TextStyle style;
  final Color color;
  final double rim;

  void _draw(Canvas canvas, Paint paint) => (TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(foreground: paint),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout()).paint(canvas, Offset.zero);

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, Paint()..color = color.withValues(alpha: 0.26));
    canvas.saveLayer((Offset.zero & size).inflate(rim), Paint());
    _draw(
      canvas,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.95),
    );
    _draw(canvas, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.text != text || old.style != style || old.color != color || old.rim != rim;
}

/// The lock screen exactly as the phone draws it, at full screen size; whoever shows it
/// scales it down. So wallpaper, clock and depth sit where they really do.
class LockPreview extends StatelessWidget {
  const LockPreview({super.key, required this.state, this.look});
  final AppState state;

  /// A saved look to show instead of the one in use.
  final Settings? look;

  @override
  Widget build(BuildContext context) {
    final s = look ?? state.settings;
    final p = Ios.of(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          LockWallpaper(settings: s),
          Padding(
            padding: EdgeInsets.only(bottom: p(94)),
            child: Ticker(
              builder: (_, now) => LockFace(state: state, now: now, look: s),
            ),
          ),
          LockDepth(settings: s, clockTop: islandCenter(context) * 2 + p(14)),
        ],
      ),
    );
  }
}

/// The saved looks side by side, picked right on the lock screen like iOS's gallery. Only a
/// swipe up or Android's back gesture closes it, as for an app; taps always pick.
class _LookPicker extends StatefulWidget {
  const _LookPicker({required this.state});
  final AppState state;

  @override
  State<_LookPicker> createState() => _LookPickerState();
}

class _LookPickerState extends State<_LookPicker> {
  late final _pages = PageController(viewportFraction: 0.66, initialPage: widget.state.settings.look);
  Offset _down = Offset.zero;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Taps are read above the gallery: while it still glides after a swipe, its pages ignore
  /// touches, and the tap was lost. A tap on a neighbour at the side picks that one.
  void _tapped(Offset at) {
    final s = widget.state.settings;
    final width = MediaQuery.sizeOf(context).width;
    final side = width * (1 - 0.66) / 2;
    final current = (_pages.hasClients ? (_pages.page ?? s.look.toDouble()) : s.look.toDouble()).round();
    final index = (current + (at.dx < side ? -1 : (at.dx > width - side ? 1 : 0))).clamp(0, s.looks.length - 1);
    widget.state.chooseLook(index);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.settings;
    final screen = MediaQuery.sizeOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Backdrop(
        dim: 0.6,
        tapToClose: false,
        child: Column(
          children: [
            const Spacer(),
            SizedBox(
              height: screen.height * 0.62,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _down = e.position,
                onPointerUp: (e) {
                  if ((e.position - _down).distance < 24) _tapped(e.position);
                },
                child: PageView(
                  controller: _pages,
                  children: [
                    for (var i = 0; i < s.looks.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: screen.aspectRatio,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: FittedBox(
                                    child: SizedBox.fromSize(
                                      size: screen,
                                      child: LockPreview(state: widget.state, look: i == s.look ? null : s.withLook(s.looks[i])),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(i == s.look ? '✓ Aktiv' : 'Hintergrund ${i + 1}', style: sf(15, weight: 600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text('Zum Schließen nach oben wischen', style: sf(13, color: Colors.white.withValues(alpha: 0.6))),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

/// iOS's StandBy: on the charger and lying on its side, the lock screen turns into a bedside
/// clock, red at night. Glas stays in portrait, so the faces are drawn turned. Swiping
/// switches between the big clock and clock with widgets; a tap asks for the PIN.
class StandBy extends StatelessWidget {
  const StandBy({super.key, required this.state, required this.turns});
  final AppState state;
  final int turns;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    Widget small(WidgetKind kind) => FittedBox(
      child: SizedBox(
        width: p.smallWidth,
        height: p.icon + p.rowPitch,
        child: HomeWidget(kind: kind, size: WidgetSize.small, state: state, scale: p.unit),
      ),
    );
    // A Material, or Flutter underlines all text in yellow.
    return Material(
      color: Colors.black,
      child: GestureDetector(
        onTap: () => Native.call('unlock'),
        child: ColoredBox(
          color: Colors.black,
          child: RotatedBox(
            quarterTurns: turns,
            child: PageView(
              children: [
                Ticker(
                  builder: (_, now) {
                    final night = now.hour >= 22 || now.hour < 6;
                    final color = night ? const Color(0xFFFF3B30) : Color(state.settings.lockColor);
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: FittedBox(
                        child: Text(
                          clockText(now),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 220,
                            height: 1,
                            color: color,
                            fontVariations: const [FontVariation('wght', 700)],
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Row(
                    children: [
                      Expanded(child: Center(child: small(WidgetKind.clock))),
                      const SizedBox(width: 28),
                      Expanded(child: Center(child: small(state.events.isEmpty ? WidgetKind.weather : WidgetKind.calendar))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lock wallpaper with its filter, and with [moving] the perspective shift on tilt.
class LockWallpaper extends StatelessWidget {
  const LockWallpaper({super.key, required this.settings, this.moving = false, this.cutout});
  final Settings settings;
  final bool moving;

  /// Draws only the cut-out subject at this path, filtered and moved like the wallpaper.
  final String? cutout;

  /// Dark parts go to a deep shade of [tint], light parts to [tint] itself.
  static List<double> _duotone(Color tint) {
    double row(double c) => c * 0.75;
    final r = tint.r, g = tint.g, b = tint.b;
    return [
      row(r) * 0.2126, row(r) * 0.7152, row(r) * 0.0722, 0, r * 0.25 * 255, //
      row(g) * 0.2126, row(g) * 0.7152, row(g) * 0.0722, 0, g * 0.25 * 255,
      row(b) * 0.2126, row(b) * 0.7152, row(b) * 0.0722, 0, b * 0.25 * 255,
      0, 0, 0, 1, 0,
    ];
  }

  static const _gray = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final white = s.lockColor == 0xFFFFFFFF;
    final tint = white ? const Color(0xFF5E5CE6) : Color(s.lockColor);
    final cut = cutout;
    Widget picture = cut != null
        ? Image.file(File(cut), fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true)
        : Wallpaper(preset: s.lockWallpaper ?? s.wallpaper, path: s.lockWallpaper == null ? (s.lockWallpaperPath ?? s.wallpaperPath) : null);
    picture = switch (s.lockFilter) {
      'mono' => ColorFiltered(colorFilter: const ColorFilter.matrix(_gray), child: picture),
      'duotone' => ColorFiltered(colorFilter: ColorFilter.matrix(_duotone(tint)), child: picture),
      // The wash lies on the wallpaper only; over the subject it would cover its outline.
      'wash' when cut == null => Stack(
        fit: StackFit.expand,
        children: [
          picture,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint.withValues(alpha: 0.75), tint.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.35)],
              ),
            ),
          ),
        ],
      ),
      _ => picture,
    };
    if (!moving || !s.perspective) return picture;
    final p = Ios.of(context);
    return ValueListenableBuilder<Offset>(
      valueListenable: Native.tilt,
      child: picture,
      builder: (_, tilt, child) => Transform.translate(
        offset: tilt * -p(14),
        child: Transform.scale(scale: 1.08, child: child),
      ),
    );
  }
}

/// iOS's depth effect: the wallpaper's subject drawn again over the clock, down to the clock's
/// lower edge, so it seems to stand in front of the time. [clockTop] is where the lock face
/// starts drawing.
class LockDepth extends StatelessWidget {
  const LockDepth({super.key, required this.settings, required this.clockTop, this.moving = false});
  final Settings settings;
  final double clockTop;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    // A cut-out belongs to one picture; while the current one is being worked on, none shows.
    final path = s.lockDepth && s.lockDepthKey == s.lockKey ? s.lockDepthPath : null;
    if (path == null || !File(path).existsSync()) return const SizedBox.shrink();
    final p = Ios.of(context);
    final screen = MediaQuery.sizeOf(context);
    final bottom = clockTop + p(17 + 10) + p(20) * 1.3 + p(104) * s.lockSize * 1.08 * s.lockStretch;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: SizedBox(
            width: screen.width,
            height: bottom,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: screen.height,
              maxHeight: screen.height,
              child: LockWallpaper(settings: s, moving: moving, cutout: path),
            ),
          ),
        ),
      ),
    );
  }
}

const lockWidgetLabels = {'battery': 'Batterie', 'weather': 'Wetter', 'week': 'Kalenderwoche', 'alerts': 'Mitteilungen', 'year': 'Jahresfortschritt'};

int calendarWeek(DateTime date) {
  final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
  final firstDay = DateTime(thursday.year);
  return thursday.difference(firstDay).inDays ~/ 7 + 1;
}

/// Lock screen content, also used as the live preview in the editor.
class LockFace extends StatelessWidget {
  const LockFace({super.key, required this.state, required this.now, this.interactive = true, this.onCardTouched, this.look});
  final AppState state;

  /// Settings of a saved look to show instead of the current one, for the gallery.
  final Settings? look;
  final DateTime now;
  final bool interactive;

  /// A finger came down on a notification or the player, where taps have their own meaning.
  final VoidCallback? onCardTouched;

  /// Round complication, 50 pt like the iOS lock screen widgets.
  Widget _widget(Ios p, String id, Color color) {
    final style = sf(p(15), weight: 600, color: color, height: 1);
    final small = sf(p(9.5), weight: 600, color: color, height: 1, tracking: 0);
    double? gauge;
    final List<Widget> content;
    switch (id) {
      case 'battery':
        gauge = state.status.battery / 100;
        content = [
          Icon(state.status.charging ? Icons.bolt : Icons.battery_full, size: p(13), color: color),
          SizedBox(height: p(1)),
          Text('${state.status.battery}', style: style),
        ];
      case 'weather':
        final w = state.weather;
        content = [
          if (w != null) WeatherGlyph(code: w.code, day: w.day, size: p(15)),
          SizedBox(height: p(2)),
          Text(w == null ? '--°' : '${w.temperature}°', style: style),
        ];
      case 'week':
        content = [Text('KW', style: small), SizedBox(height: p(2)), Text('${calendarWeek(now)}', style: style)];
      case 'alerts':
        content = [Icon(Icons.notifications_rounded, size: p(14), color: color), SizedBox(height: p(1)), Text('${state.alerts.length}', style: style)];
      default:
        gauge = now.difference(DateTime(now.year)).inDays / 365;
        content = [Text('${now.year}', style: small), SizedBox(height: p(2)), Text('${(gauge * 100).round()}', style: style)];
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: p(6)),
      child: Glass(
        radius: p(25),
        tint: 0.14,
        sigma: 14,
        rim: false,
        child: SizedBox.square(
          dimension: p(50),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (gauge != null)
                Padding(
                  padding: EdgeInsets.all(p(2.5)),
                  child: CircularProgressIndicator(
                    value: gauge,
                    strokeWidth: p(3),
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.24),
                  ),
                ),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: content),
            ],
          ),
        ),
      ),
    );
  }

  AppInfo? _appFor(Alert alert) {
    for (final app in state.apps.values) {
      if (app.package == alert.package) return app;
    }
    return null;
  }

  /// The date, with iOS's small inline widget after it: weather, battery or the next event.
  Widget _dateLine(Ios p, Settings s, Color color) {
    final style = sf(p(20), weight: 600, color: color, tracking: 0, shadows: iconShadow);
    final extra = <Widget>[];
    switch (s.lockInline) {
      case 'weather':
        final w = state.weather;
        if (w != null) extra.addAll([WeatherGlyph(code: w.code, day: w.day, size: p(19)), Text(' ${w.temperature}°', style: style)]);
      case 'battery':
        final b = state.status;
        extra.addAll([Icon(b.charging ? Icons.bolt_rounded : Icons.battery_full_rounded, color: color, size: p(19)), Text(' ${b.battery} %', style: style)]);
      case 'event':
        final next = state.events.where((e) => e.allDay || e.begin.isAfter(now)).firstOrNull;
        if (next != null) {
          final time = next.allDay ? '' : '${next.begin.hour.toString().padLeft(2, '0')}:${next.begin.minute.toString().padLeft(2, '0')} ';
          extra.add(
            Flexible(
              child: Text('$time${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          );
        }
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: p(24)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dateText(now), style: style),
          if (extra.isNotEmpty) ...[SizedBox(width: p(10)), ...extra],
        ],
      ),
    );
  }

  /// Newest first and one stack per app, the way iOS groups them.
  List<(Alert, int)> _stacks() {
    final seen = <String, int>{};
    final order = <Alert>[];
    for (final alert in state.alerts) {
      if (seen.containsKey(alert.package)) {
        seen[alert.package] = seen[alert.package]! + 1;
      } else {
        seen[alert.package] = 0;
        order.add(alert);
      }
    }
    return [for (final alert in order) (alert, seen[alert.package]!)];
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final s = look ?? state.settings;
    final color = Color(s.lockColor);
    final media = state.media;
    final stacks = _stacks();
    return Column(
      children: [
        SizedBox(height: interactive ? islandCenter(context) * 2 + p(14) : p(30)),
        Icon(Icons.lock_rounded, size: p(17), color: color),
        SizedBox(height: p(10)),
        _dateLine(p, s, color),
        LockClock(text: clockText(now), settings: s, p: p),
        if (s.lockWidgets.isNotEmpty) ...[
          SizedBox(height: p(10)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final id in s.lockWidgets) _widget(p, id, color)]),
        ],
        if (interactive)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: p(16)),
              child: ListView(
                reverse: true,
                padding: EdgeInsets.only(bottom: p(16)),
                physics: const BouncingScrollPhysics(),
                children: [
                  // A reversed list fills from the bottom, so the newest stack comes last.
                  if (media != null)
                    Listener(
                      onPointerDown: (_) => onCardTouched?.call(),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: p(8)),
                        child: Glass(
                          radius: p(26),
                          tint: 0.2,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(p(16), p(10), p(6), p(10)),
                            child: MediaControls(media: media),
                          ),
                        ),
                      ),
                    ),
                  if (s.lockNotify == 'count' && state.alerts.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: p(8)),
                        child: Glass(
                          radius: p(18),
                          tint: 0.2,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: p(16), vertical: p(8)),
                            child: Text(state.alerts.length == 1 ? '1 Mitteilung' : '${state.alerts.length} Mitteilungen', style: sf(p(15), weight: 600)),
                          ),
                        ),
                      ),
                    )
                  else if (s.lockNotify == 'list')
                    for (final alert in state.alerts.reversed)
                      Listener(
                        onPointerDown: (_) => onCardTouched?.call(),
                        child: AlertCard(alert: alert, app: _appFor(alert)),
                      )
                  else
                    for (final (alert, more) in stacks.reversed)
                      Listener(
                        onPointerDown: (_) => onCardTouched?.call(),
                        child: AlertCard(alert: alert, app: _appFor(alert), stacked: more),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

const _swipeHint = 'Zum Öffnen nach oben streichen';
const _doubleTap = Duration(milliseconds: 320);
const _holdTime = Duration(milliseconds: 380);

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _tracking = false;
  double _startY = 0;
  double _startX = 0;

  /// A long press on the bare lock screen opens the gallery of saved looks, as on iOS.
  Timer? _press;
  DateTime _downAt = DateTime(0);
  DateTime? _lastTap;

  /// The touch began on a corner button or a card, set before [_start] sees it: a Listener's
  /// child hears a pointer first.
  bool _onButton = false;
  bool _onCard = false;
  String _hintText = _swipeHint;

  @override
  void initState() {
    super.initState();
    _lift.addListener(() => setState(() {}));
    _hint.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _lift.dispose();
    _hint.dispose();
    _press?.cancel();
    super.dispose();
  }

  /// Raw pointer events, because the notification list would win a gesture contest. A long
  /// list scrolls, so there the swipe has to start below it.
  void _start(PointerDownEvent event, double height) {
    _startY = event.position.dy;
    _startX = event.position.dx;
    _downAt = DateTime.now();
    _tracking = !_onButton && (widget.state.alerts.length <= 3 || event.position.dy > height * 0.82);
    _lift.stop();
    _press?.cancel();
    if (!_onButton && !_onCard) _press = Timer(const Duration(milliseconds: 600), _pickLook);
  }

  void _pickLook() {
    if (widget.state.settings.looks.length < 2 || !mounted) return;
    _tracking = false;
    HapticFeedback.mediumImpact();
    openOverlay<void>(context, (_) => _LookPicker(state: widget.state));
  }

  void _move(PointerMoveEvent event, double height) {
    if ((event.position - Offset(_startX, _startY)).distance > 12) _press?.cancel();
    if (_tracking) _lift.value = (_lift.value - event.delta.dy / height).clamp(0.0, 1.0);
  }

  /// Two quick taps on the bare screen turn it off, like on Android's own lock screen.
  void _tap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) < _doubleTap) {
      _lastTap = null;
      _turnOff();
      return;
    }
    _lastTap = now;
    _hintText = _swipeHint;
    _hint.forward(from: 0);
  }

  Future<void> _turnOff() async {
    if (await Native.screenOff() || !mounted) return;
    _hintText = 'In Glas „Doppeltippen zum Ausschalten“ erlauben';
    _hint.forward(from: 0);
  }

  void _end(PointerEvent event, double height) {
    _press?.cancel();
    final tap = event is PointerUpEvent && !_onButton && !_onCard && (event.position.dy - _startY).abs() < 8 && DateTime.now().difference(_downAt) < _doubleTap;
    _onButton = false;
    _onCard = false;
    if (tap) _tap();
    // As on iOS, a swipe to the left opens the camera.
    final dx = event.position.dx - _startX, dy = event.position.dy - _startY;
    if (event is PointerUpEvent && !_onButton && dx < -MediaQuery.sizeOf(context).width * 0.28 && dy.abs() < dx.abs() / 2) {
      _tracking = false;
      _lift.animateTo(0, curve: const IosSpring());
      HapticFeedback.lightImpact();
      Native.call('camera');
      return;
    }
    if (!_tracking) return;
    _tracking = false;
    if (_lift.value > 0.2) {
      HapticFeedback.lightImpact();
      _lift.animateTo(1, curve: Curves.easeOutCubic).whenComplete(() {
        Native.call('unlock');
        _lift.value = 0;
      });
    } else {
      _lift.animateTo(0, curve: const IosSpring());
    }
  }

  /// Empty for "none" and for an app that is gone.
  Widget _corner(Ios p, String choice, int index) {
    final state = widget.state;
    final id = state.lockShortcut(choice, index);
    final Widget? button = switch (id) {
      'torch' => _CornerButton(
        p: p,
        on: state.status.torch,
        onPress: () => _onButton = true,
        onTrigger: () async {
          await Native.call('torch', !state.status.torch);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await state.refresh();
        },
        child: Icon(
          state.status.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
          color: state.status.torch ? Colors.black : Colors.white,
          size: p(22),
        ),
      ),
      'camera' => _CornerButton(
        p: p,
        onPress: () => _onButton = true,
        onTrigger: () => Native.call('camera'),
        child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: p(22)),
      ),
      _ => _appButton(p, id),
    };
    return SizedBox.square(dimension: p(50), child: button);
  }

  Widget? _appButton(Ios p, String id) {
    final apps = widget.state.apps.values;
    final app = widget.state.apps[id] ?? apps.where((a) => a.package == id).firstOrNull;
    if (app == null) return null;
    return _CornerButton(
      p: p,
      onPress: () => _onButton = true,
      onTrigger: () => Native.openLocked(app),
      child: AppIcon(app: app, size: p(30)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final state = widget.state;
    final s = state.settings;
    final height = MediaQuery.sizeOf(context).height;
    final hint = sin(_hint.value * pi).clamp(0.0, 1.0);
    final Widget face = PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              LockWallpaper(settings: s, moving: true),
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _start(e, height),
                onPointerMove: (e) => _move(e, height),
                onPointerUp: (e) => _end(e, height),
                onPointerCancel: (e) => _end(e, height),
                child: Transform.translate(
                  offset: Offset(0, -_lift.value * height),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: p(94)),
                        child: Ticker(
                          builder: (_, now) => LockFace(state: state, now: now, onCardTouched: () => _onCard = true),
                        ),
                      ),
                      Positioned(
                        left: p(46),
                        right: p(46),
                        bottom: p(42),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_corner(p, s.lockLeft, 0), _corner(p, s.lockRight, 1)]),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: p(46),
                        child: Opacity(
                          opacity: hint,
                          child: Text(_hintText, textAlign: TextAlign.center, style: sf(p(13), weight: 500)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              LockDepth(settings: s, clockTop: islandCenter(context) * 2 + p(14), moving: true),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: StatusRow(
                  status: state.status,
                  lock: true,
                  island: LiveIsland(state: state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!s.standBy) return face;
    // On the charger and turned on its side, the lock screen becomes StandBy.
    return ListenableBuilder(
      listenable: Listenable.merge([state, Native.gravity]),
      child: face,
      builder: (_, child) {
        final g = Native.gravity.value;
        final sideways = g.dx.abs() > 6.5 && g.dy.abs() < 5;
        return state.status.charging && sideways ? StandBy(state: state, turns: g.dx < 0 ? 1 : 3) : child!;
      },
    );
  }
}

/// The iOS corner buttons react to a firm press and swell while held. Android has no firm
/// press, so a short hold stands in. Raw pointers, so nothing else can claim the touch.
class _CornerButton extends StatefulWidget {
  const _CornerButton({required this.p, required this.child, required this.onPress, required this.onTrigger, this.on = false});
  final Ios p;
  final Widget child;
  final bool on;
  final VoidCallback onPress;
  final VoidCallback onTrigger;

  @override
  State<_CornerButton> createState() => _CornerButtonState();
}

class _CornerButtonState extends State<_CornerButton> {
  bool _held = false;
  Timer? _hold;
  Offset _start = Offset.zero;

  void _down(PointerDownEvent event) {
    widget.onPress();
    _start = event.position;
    setState(() => _held = true);
    _hold = Timer(_holdTime, () {
      HapticFeedback.mediumImpact();
      _release();
      widget.onTrigger();
    });
  }

  void _release() {
    _hold?.cancel();
    if (mounted) setState(() => _held = false);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: (e) {
        if ((e.position - _start).distance > p(24)) _release();
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _held ? 1.22 : 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Glass(
          radius: p(25),
          tint: widget.on ? 0.92 : 0.12,
          sigma: 18,
          child: SizedBox.square(
            dimension: p(50),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}
