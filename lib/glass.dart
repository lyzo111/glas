import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'native.dart';

/// Measurements in iOS points. The reference is a 393 × 852 pt iPhone, which has the same
/// proportions as a Galaxy S24, so scaling by width reproduces the iPhone layout.
class Ios {
  const Ios(this.unit);
  factory Ios.of(BuildContext context) => Ios(MediaQuery.sizeOf(context).width / 393);

  final double unit;
  double call(double points) => points * unit;

  // Measured on an iOS 26 home screen: its icons are a little larger and closer together
  // than the 60 pt ones before it.
  double get icon => 64 * unit;
  double get margin => 28.5 * unit;
  double get columnPitch => 90.5 * unit;
  double get rowPitch => 98.5 * unit;
  double get gridTop => 67 * unit;
  double get widgetGap => 22 * unit;
  double get fullWidth => 335.5 * unit;
  double get dockHeight => 96 * unit;
  double get smallWidth => (fullWidth - widgetGap) / 2;
}

/// The iOS type scale, set in Inter. SF Pro may not be shipped outside Apple platforms.
TextStyle sf(double size, {double weight = 400, Color color = Colors.white, double? height, double? tracking, List<Shadow>? shadows}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: size * (tracking ?? (size >= 20 ? -0.022 : -0.011)),
  shadows: shadows,
  fontVariations: [FontVariation('wght', weight), FontVariation('opsz', size.clamp(14, 32))],
  fontFeatures: const [FontFeature.enable('ss03'), FontFeature.enable('cv11')],
);

const iconShadow = [Shadow(blurRadius: 5, color: Color(0x73000000), offset: Offset(0, 0.5))];

const wallpapers = ['blue', 'sunrise', 'green', 'violet', 'graphite'];

class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key, required this.preset, this.path, this.frosted = false});
  final int preset;
  final String? path;

  /// Decoded at a tiny size and scaled up, which reads as a blur at no cost per frame.
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final file = path != null && File(path!).existsSync() ? path : null;
    final asset = 'assets/wallpapers/${wallpapers[preset.clamp(0, wallpapers.length - 1)]}.png';
    if (frosted) {
      return FutureBuilder<ui.Image>(
        future: _frost(file, asset),
        builder: (_, snapshot) => snapshot.data == null
            ? const SizedBox.expand()
            : RawImage(image: snapshot.data, fit: BoxFit.cover, width: double.infinity, height: double.infinity, filterQuality: FilterQuality.medium),
      );
    }
    if (file != null) {
      // A camera photo decoded at full size takes long enough to show black first.
      final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 1.1).round();
      return Image.file(File(file), fit: BoxFit.cover, width: double.infinity, height: double.infinity, cacheWidth: width, gaplessPlayback: true);
    }
    return Image.asset(asset, fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true);
  }

  /// The encoded picture, for handing it to Android.
  static Future<Uint8List> bytes(int preset, String? path) async {
    if (path != null && File(path).existsSync()) return File(path).readAsBytes();
    final data = await rootBundle.load('assets/wallpapers/${wallpapers[preset.clamp(0, wallpapers.length - 1)]}.png');
    return data.buffer.asUint8List();
  }

  static final _frosted = <String, Future<ui.Image>>{};

  /// Blurs the wallpaper once into a small bitmap; scaling that up costs nothing per frame.
  static Future<ui.Image> _frost(String? file, String asset) => _frosted[file ?? asset] ??= () async {
    final bytes = file != null ? await File(file).readAsBytes() : (await rootBundle.load(asset)).buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 135);
    final image = (await codec.getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(
      image,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.mirror),
    );
    return recorder.endRecording().toImage(image.width, image.height);
  }();
}

/// Glass for a panel that stays put over the wallpaper, like the dock. Shows the frosted
/// wallpaper instead of blurring live, so it stays cheap while pages slide past it.
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    required this.radius,
    required this.offset,
    required this.wallpaper,
    this.wallpaperPath,
    this.tint = 0.12,
  });
  final Widget child;
  final double radius;

  /// Top left corner of the panel on the screen.
  final Offset offset;
  final int wallpaper;
  final String? wallpaperPath;
  final double tint;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        foregroundPainter: _Rim(radius),
        child: Stack(
          children: [
            Positioned(
              left: -offset.dx,
              top: -offset.dy,
              width: screen.width,
              height: screen.height,
              child: Wallpaper(preset: wallpaper, path: wallpaperPath, frosted: true),
            ),
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: tint)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Saturates what the blur lets through, which is most of what makes iOS materials look wet.
final _vibrance = ColorFilter.matrix(_saturation(1.7));

List<double> _saturation(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final i = 1 - s;
  return [i * r + s, i * g, i * b, 0, 0, i * r, i * g + s, i * b, 0, 0, i * r, i * g, i * b + s, 0, 0, 0, 0, 0, 1, 0];
}

ImageFilter glassFilter(double sigma) => ImageFilter.compose(
  outer: _vibrance,
  inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
);

/// Liquid Glass: blurred, saturated backdrop with a specular rim along the edge.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 24, this.tint = 0.1, this.sigma = 24, this.rim = true, this.dark = false, this.blur = true});
  final Widget child;
  final double radius;
  final double tint;
  final double sigma;
  final bool rim;
  final bool dark;

  /// Off for anything that scrolls or shows up many times: a live blur costs a full
  /// render pass for each one, every frame.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final color = (dark ? Colors.black : Colors.white).withValues(alpha: tint);
    final body = CustomPaint(
      foregroundPainter: rim ? _Rim(radius) : null,
      child: ColoredBox(color: color, child: child),
    );
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: blur ? BackdropFilter(filter: glassFilter(sigma), child: body) : body,
    );
  }
}

class _Rim extends CustomPainter {
  const _Rim(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RSuperellipse.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    canvas.drawRSuperellipse(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.34),
          ],
          stops: const [0, 0.38, 0.62, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius;
}

/// Spring that overshoots a little, close to the default iOS sheet and folder animation.
class IosSpring extends Curve {
  const IosSpring();

  @override
  double transformInternal(double t) => 1 - exp(-6.5 * t) * cos(7.5 * t);
}

/// Name of every [openOverlay] page, so they can be closed together.
const overlayRoute = 'overlay';

/// Transparent page that springs open, from [origin] (screen position) when given.
Future<T?> openOverlay<T>(BuildContext context, WidgetBuilder builder, {Offset? origin}) {
  final size = MediaQuery.sizeOf(context);
  final alignment = origin == null ? Alignment.center : Alignment(origin.dx / size.width * 2 - 1, origin.dy / size.height * 2 - 1);
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      settings: const RouteSettings(name: overlayRoute),
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(parent: animation, curve: const IosSpring(), reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.45)),
          child: ScaleTransition(
            alignment: alignment,
            scale: Tween(begin: origin == null ? 0.94 : 0.2, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Full screen frosted backdrop. A tap anywhere that nothing else claims closes the overlay,
/// and so does swiping up, the way iOS sheets go away. Lists and buttons on top win over both.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.dim = 0.3, this.sigma = 34, this.onDismiss, this.tapToClose = true});
  final Widget child;

  /// Off where taps belong to the content, like a gallery; a swipe up still closes.
  final bool tapToClose;
  final double dim;
  final double sigma;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    void dismiss() => (onDismiss ?? () => Navigator.of(context).pop())();
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: tapToClose ? dismiss : null,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -250) dismiss();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: glassFilter(sigma),
              child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

String clockText(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

String dateText(DateTime t) => '${weekdays[t.weekday - 1]}, ${t.day}. ${months[t.month - 1]}';

/// Rebuilds when the minute changes.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder});
  final Widget Function(BuildContext, DateTime) builder;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(seconds: 60 - DateTime.now().second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// Black pill drawn around the camera hole, like the Dynamic Island.
class Island extends StatelessWidget {
  const Island({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Container(
      width: p(126),
      height: p(36),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(p(18))),
    );
  }
}

double islandCenter(BuildContext context) {
  final p = Ios.of(context);
  return max(p(18) + 3, MediaQuery.viewPaddingOf(context).top / 2);
}

/// Own status bar in place of the hidden Android one. The lock screen shows the carrier
/// where the home screen shows the time.
class StatusRow extends StatelessWidget {
  const StatusRow({super.key, required this.status, this.lock = false, this.island = const Island()});
  final DeviceStatus status;
  final bool lock;

  /// The island in the middle, a live one where the screen has the state for it.
  final Widget island;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final center = islandCenter(context);
    final side = (MediaQuery.sizeOf(context).width - p(126)) / 2;
    final style = sf(p(lock ? 15 : 16.5), weight: 600, shadows: iconShadow);
    return SizedBox(
      height: center * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: center - p(18), child: island),
          Positioned(
            left: 0,
            width: side,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: lock
                    ? Text(status.carrier, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)
                    : Ticker(builder: (_, now) => Text(clockText(now), style: style)),
              ),
            ),
          ),
          Positioned(
            right: 0,
            width: side,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (status.cellular) ...[SignalGlyph(height: p(11.5)), SizedBox(width: p(5))],
                  if (status.wifi) ...[Icon(CupertinoIcons.wifi, color: Colors.white, size: p(17.5)), SizedBox(width: p(5))],
                  BatteryGlyph(level: status.battery, charging: status.charging),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SignalGlyph extends StatelessWidget {
  const SignalGlyph({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(height * 1.5, height), painter: _Signal());
}

class _Signal extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bar = size.width / 5.2;
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 4; i++) {
      final h = size.height * (0.34 + i * 0.22);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * bar * 1.4, size.height - h, bar, h), Radius.circular(bar * 0.3)), paint);
    }
  }

  @override
  bool shouldRepaint(_Signal old) => false;
}

/// The filled iOS battery with the percentage cut into it.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({super.key, required this.level, required this.charging, this.plain = false});
  final int level;
  final bool charging;

  /// Without the number, where the percentage stands next to it.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final fill = charging
        ? const Color(0xFF34C759)
        : level <= 20
        ? const Color(0xFFFF3B30)
        : Colors.white;
    final dark = fill == Colors.white ? Colors.black : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: p(27),
          height: p(13),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.38), borderRadius: BorderRadius.circular(p(4.2))),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: level.clamp(6, 100) / 100,
                child: ColoredBox(color: fill),
              ),
              if (!plain)
                Center(
                  child: Text('$level', style: sf(p(10.5), weight: 700, color: dark, height: 1, tracking: -0.02)),
                ),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(left: p(1)),
          width: p(1.6),
          height: p(4.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(p(1.5))),
          ),
        ),
      ],
    );
  }
}

/// The icon styles of the iOS home screen editor, in its order.
enum IconStyle {
  standard('Standard'),
  dark('Dunkel'),
  clear('Transparent'),
  tinted('Eingefärbt');

  const IconStyle(this.label);
  final String label;

  /// Whether icons and widgets are glass with a glyph of one colour.
  bool get glass => this == clear || this == tinted;

  /// Set from the settings; every [AppIcon] reads them.
  static IconStyle current = IconStyle.standard;
  static Color tint = const Color(0xFF64D2FF);

  /// The glass styles come light or dark.
  static bool darkGlass = true;
}

const iconTints = [0xFFD6D6DB, 0xFF64D2FF, 0xFF0A84FF, 0xFF5E5CE6, 0xFFFF375F, 0xFFFF9F0A, 0xFFFFD60A, 0xFF30D158];

/// The pane of a glass icon or widget. A live blur behind each one would cost a render pass
/// apiece, so the pane is a see-through sheet and the rim does the rest.
BoxDecoration glassPane(IconStyle look, {double strength = 1}) {
  final dark = IconStyle.darkGlass;
  final tint = IconStyle.tint;
  final colors = switch (look) {
    IconStyle.tinted when dark => [
      Color.lerp(const Color(0xFF34343A), tint, 0.34)!.withValues(alpha: 0.74),
      Color.lerp(const Color(0xFF060608), tint, 0.2)!.withValues(alpha: 0.74),
    ],
    IconStyle.tinted => [Color.lerp(Colors.white, tint, 0.4)!.withValues(alpha: 0.66), Color.lerp(Colors.white, tint, 0.62)!.withValues(alpha: 0.6)],
    _ when dark => [const Color(0xFF4A4A52).withValues(alpha: 0.5), const Color(0xFF0C0C10).withValues(alpha: 0.5)],
    _ => [Colors.white.withValues(alpha: 0.4), Colors.white.withValues(alpha: 0.22)],
  };
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [for (final color in colors) color.withValues(alpha: color.a * strength)],
    ),
  );
}

/// The tile of a folder or of a group in the App Library. In the glass styles it is a pane in
/// the colour of the icons, a little thinner so the icons on it stand out; otherwise it is
/// the frosted grey of iOS.
class FolderPane extends StatelessWidget {
  const FolderPane({super.key, required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = IconStyle.current;
    if (!look.glass) {
      return Glass(radius: radius, tint: look == IconStyle.dark ? 0.34 : 0.24, dark: look == IconStyle.dark, blur: false, child: child);
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        foregroundPainter: GlassEdge(radius, strength: 0.8),
        child: DecoratedBox(decoration: glassPane(look, strength: 0.62), child: child),
      ),
    );
  }
}

/// The colour of what is drawn on a [glassPane].
Color glassInk(IconStyle look) {
  if (look == IconStyle.tinted) return Color.lerp(IconStyle.tint, Colors.white, IconStyle.darkGlass ? 0.42 : 0.9)!;
  return Colors.white.withValues(alpha: IconStyle.darkGlass ? 0.88 : 0.97);
}

/// Turns brightness into coverage of one flat colour: what is brighter than [floor] shows, or
/// with [inverted] what is darker than it. Only for pictures without transparency, since a
/// see-through edge pixel would come out solid.
ColorFilter toneFilter(Color tint, {double floor = 0.18, double gain = 1.7, bool inverted = false}) {
  final s = (inverted ? -gain : gain) * tint.a;
  final offset = (inverted ? gain * floor : -gain * floor) * 255 * tint.a;
  return ColorFilter.matrix([
    ...[0, 0, 0, 0, tint.r * 255],
    ...[0, 0, 0, 0, tint.g * 255],
    ...[0, 0, 0, 0, tint.b * 255],
    ...[s * 0.2126, s * 0.7152, s * 0.0722, 0, offset],
  ]);
}

/// The specular edge of glass: light catches the top left and the bottom right.
class GlassEdge extends CustomPainter {
  const GlassEdge(this.radius, {this.strength = 1});
  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.78 * strength),
            Colors.white.withValues(alpha: 0.14 * strength),
            Colors.white.withValues(alpha: 0.08 * strength),
            Colors.white.withValues(alpha: 0.5 * strength),
          ],
          stops: const [0, 0.36, 0.64, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassEdge old) => old.radius != radius || old.strength != strength;
}

/// App icon in the continuous-corner shape, plus an optional notification badge.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, required this.size, this.badge = 0, this.style});
  final AppInfo? app;
  final double size;
  final int badge;

  /// Overrides the chosen style, for the previews of the style picker.
  final IconStyle? style;

  Widget _empty() => ColoredBox(
    color: Colors.white24,
    child: SizedBox.square(dimension: size),
  );

  /// [Future]s would flash an empty icon on each rebuild, so known bytes are used directly.
  /// [color] paints the picture's shape in one colour, for the mask layer.
  Widget _bitmap(AppInfo info, String layer, int cache, {Color? color}) {
    final known = Native.iconNow(info, layer);
    Widget image(Uint8List bytes) => Image.memory(
      bytes,
      width: size,
      height: size,
      cacheWidth: cache,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      color: color,
      colorBlendMode: BlendMode.srcIn,
    );

    if (known != null) return image(known);
    return FutureBuilder<Uint8List?>(future: Native.icon(info, layer), builder: (_, snapshot) => snapshot.data == null ? _empty() : image(snapshot.data!));
  }

  Widget _face(AppInfo info, IconStyle look, int cache) {
    final role = info.role;
    if (look == IconStyle.standard) {
      // Apple Music is the real thing, so its own icon beats a drawn copy.
      return role == null || role == Role.music ? _bitmap(info, 'plain', cache) : RoleIcon(role: role, size: size);
    }
    if (look == IconStyle.dark && role != null) return RoleIcon(role: role, size: size, dark: true);
    final Widget glyph;
    if (look == IconStyle.dark) {
      glyph = _bitmap(info, 'foreground', cache);
    } else if (role != null && role != Role.music) {
      glyph = ColorFiltered(
        colorFilter: toneFilter(glassInk(look)),
        child: RoleIcon(role: role, size: size, dark: true),
      );
    } else {
      glyph = _bitmap(info, 'mono', cache, color: glassInk(look));
    }
    return DecoratedBox(
      decoration: look.glass
          ? glassPane(look)
          : const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2C2C2E), Color(0xFF0E0E10)]),
            ),
      child: SizedBox.square(dimension: size, child: glyph),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = app;
    final look = style ?? IconStyle.current;
    final radius = BorderRadius.circular(size * 0.2237);
    // Decoded a step above what is shown, and in few sizes so the pictures are shared.
    final pixels = size * MediaQuery.devicePixelRatioOf(context);
    final cache = pixels <= 96
        ? 96
        : pixels <= 192
        ? 192
        : 288;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRSuperellipse(borderRadius: radius, child: info == null ? _empty() : _face(info, look, cache)),
          // Light along the edge, as on the Liquid Glass icons; the glass styles catch more of it.
          IgnorePointer(
            child: CustomPaint(size: Size.square(size), painter: look.glass ? GlassEdge(size * 0.2237) : _IconEdge(size * 0.2237)),
          ),
          if (badge > 0)
            Positioned(
              right: -size * 0.1,
              top: -size * 0.1,
              child: Container(
                constraints: BoxConstraints(minWidth: size * 0.38),
                height: size * 0.38,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: size * 0.1),
                // Red, and in the glass styles the pale disc iOS puts there instead.
                decoration: BoxDecoration(
                  color: look.glass ? const Color(0xFFE8ECF2) : const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(size * 0.19),
                ),
                child: Text('$badge', style: sf(size * 0.24, weight: 500, height: 1, color: look.glass ? const Color(0xFF3A3A3C) : Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconEdge extends CustomPainter {
  const _IconEdge(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(rect.deflate(0.4), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.36), Colors.white.withValues(alpha: 0.05)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_IconEdge old) => old.radius != radius;
}

/// A list row of the notification stack, on the lock screen and in the notification centre.
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert, this.app, this.stacked = 0});
  final Alert alert;
  final AppInfo? app;

  /// Further notifications of the same app, shown as cards peeking out below.
  final int stacked;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final age = DateTime.now().difference(alert.time);
    final when = age.inMinutes < 1
        ? 'Jetzt'
        : age.inHours < 1
        ? 'Vor ${age.inMinutes} Min.'
        : age.inDays < 1
        ? 'Vor ${age.inHours} Std.'
        : 'Vor ${age.inDays} T.';
    final card = Glass(
      radius: p(28),
      tint: 0.16,
      child: Padding(
        padding: EdgeInsets.fromLTRB(p(14), p(13), p(17), p(13)),
        child: Row(
          children: [
            if (alert.avatar != null)
              SizedBox.square(
                dimension: p(40),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipOval(
                      child: Image.memory(alert.avatar!, width: p(40), height: p(40), fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                    if (app != null)
                      Positioned(
                        right: -p(3),
                        bottom: -p(3),
                        child: AppIcon(app: app, size: p(18)),
                      ),
                  ],
                ),
              )
            else if (app != null)
              AppIcon(app: app, size: p(40))
            else
              SizedBox.square(
                dimension: p(40),
                child: Icon(CupertinoIcons.bell_fill, color: Colors.white, size: p(26)),
              ),
            SizedBox(width: p(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(alert.title ?? alert.app, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(16), weight: 600)),
                      ),
                      SizedBox(width: p(8)),
                      Text(when, style: sf(p(14), color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ),
                  if (alert.text != null) Text(alert.text!, maxLines: 2, overflow: TextOverflow.ellipsis, style: sf(p(16), height: 1.25)),
                  if (alert.canReply)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _ReplySheet.open(context, alert),
                      child: Padding(
                        padding: EdgeInsets.only(top: p(6)),
                        child: Text('Antworten', style: sf(p(14), weight: 600)),
                      ),
                    ),
                ],
              ),
            ),
            if (alert.picture != null) ...[
              SizedBox(width: p(10)),
              ClipRRect(
                borderRadius: BorderRadius.circular(p(8)),
                child: Image.memory(alert.picture!, width: p(40), height: p(40), fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ],
          ],
        ),
      ),
    );
    return Dismissible(
      key: ValueKey(alert.key),
      onDismissed: (_) => Native.call('dismissNotification', alert.key),
      child: GestureDetector(
        onTap: () => Native.call('openNotification', alert.key),
        child: Padding(
          padding: EdgeInsets.only(bottom: p(stacked > 0 ? 18 : 8)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = min(stacked, 2); i > 0; i--)
                Positioned(
                  left: p(i * 10.0),
                  right: p(i * 10.0),
                  bottom: -p(i * 7.0),
                  height: p(40),
                  child: Opacity(
                    opacity: i == 1 ? 0.7 : 0.4,
                    child: Glass(radius: p(20), tint: 0.16, rim: false, child: const SizedBox.expand()),
                  ),
                ),
              card,
            ],
          ),
        ),
      ),
    );
  }
}

/// Text field above the keyboard for answering a message without opening its app.
class _ReplySheet extends StatefulWidget {
  const _ReplySheet(this.alert);
  final Alert alert;

  static void open(BuildContext context, Alert alert) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => _ReplySheet(alert),
  );

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Native.call('replyNotification', {'key': widget.alert.key, 'text': text});
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(p(12), 0, p(12), MediaQuery.viewInsetsOf(context).bottom + p(12)),
      child: Glass(
        radius: p(24),
        tint: 0.24,
        child: Padding(
          padding: EdgeInsets.fromLTRB(p(16), p(4), p(6), p(4)),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  cursorColor: Colors.white,
                  textCapitalization: TextCapitalization.sentences,
                  style: sf(p(16)),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Antwort an ${widget.alert.title ?? widget.alert.app}',
                    hintStyle: sf(p(16), color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
              IconButton(onPressed: _send, color: const Color(0xFF0A84FF), iconSize: p(30), icon: const Icon(CupertinoIcons.arrow_up_circle_fill)),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaControls extends StatelessWidget {
  const MediaControls({super.key, required this.media});
  final Media media;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    Widget button(IconData icon, String action, double size) =>
        IconButton(color: Colors.white, iconSize: p(size), icon: Icon(icon), onPressed: () => Native.call('mediaAction', action));
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(15), weight: 600)),
              if (media.artist.isNotEmpty)
                Text(
                  media.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sf(p(14), color: Colors.white.withValues(alpha: 0.7)),
                ),
            ],
          ),
        ),
        button(CupertinoIcons.backward_fill, 'previous', 30),
        button(media.playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, 'toggle', 36),
        button(CupertinoIcons.forward_fill, 'next', 30),
      ],
    );
  }
}
