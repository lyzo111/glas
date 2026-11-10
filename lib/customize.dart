import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'icons.dart';
import 'state.dart';

/// The "Anpassen" sheet of the iOS home screen editor: the four icon styles, the colour of
/// the tinted one, and how bright the glass is. The home screen stays visible behind it,
/// so every change shows on the real icons.
class CustomizeSheet extends StatefulWidget {
  const CustomizeSheet({super.key, required this.state});
  final AppState state;

  @override
  State<CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<CustomizeSheet> {
  static const _neutral = Color(0xFFD6D6DB);

  AppState get _state => widget.state;
  Settings get _settings => _state.settings;

  late double _hue;
  late double _strength;
  Color? _wallpaper;

  @override
  void initState() {
    super.initState();
    final tint = HSVColor.fromColor(Color(_settings.iconTint));
    _hue = tint.hue;
    _strength = tint.saturation;
    _readWallpaper();
  }

  /// iOS offers a tint taken from the wallpaper: its mean colour, pushed to full brightness.
  Future<void> _readWallpaper() async {
    try {
      final bytes = await Wallpaper.bytes(_settings.wallpaper, _settings.wallpaperPath);
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 12);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || !mounted) return;
      final count = data.lengthInBytes ~/ 4;
      var r = 0, g = 0, b = 0;
      for (var i = 0; i < count; i++) {
        r += data.getUint8(i * 4);
        g += data.getUint8(i * 4 + 1);
        b += data.getUint8(i * 4 + 2);
      }
      final mean = HSVColor.fromColor(Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count));
      setState(() => _wallpaper = mean.saturation < 0.08 ? _neutral : mean.withSaturation(max(mean.saturation, 0.5)).withValue(1).toColor());
    } catch (_) {
      // Without a readable wallpaper the swatch is simply missing.
    }
  }

  void _style(IconStyle style) {
    _settings
      ..iconStyle = style.name
      ..applyIconStyle();
    _state.commit();
  }

  /// While a slider moves the icons follow without a save; the save comes when it is let go.
  void _tint(Color color, {bool save = true}) {
    _settings
      ..iconTint = color.toARGB32()
      ..applyIconStyle();
    save ? _state.commit() : _state.repaint();
  }

  void _slide({double? hue, double? strength}) {
    setState(() {
      _hue = hue ?? _hue;
      _strength = strength ?? _strength;
    });
    _tint(HSVColor.fromAHSV(1, _hue, _strength, 1).toColor(), save: false);
  }

  void _pick(Color color) {
    final tint = HSVColor.fromColor(color);
    setState(() {
      _hue = tint.hue;
      _strength = tint.saturation;
    });
    _tint(color);
  }

  void _tone(String tone) {
    _settings
      ..glassTone = tone
      ..applyIconStyle();
    _state.commit();
  }

  Widget _round(Ios p, IconData icon, bool on, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: p(44),
      height: p(44),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: on ? 0.92 : 0.16),
      ),
      child: Icon(icon, size: p(22), color: on ? Colors.black : Colors.white),
    ),
  );

  Widget _styles(Ios p) {
    final sample = _state.appFor(Role.phone) ?? _state.appFor(Role.messages);
    return Row(
      children: [
        for (final style in IconStyle.values)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _style(style),
              child: Column(
                children: [
                  AppIcon(app: sample, size: p(58), style: style),
                  SizedBox(height: p(8)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: p(7), vertical: p(4)),
                    decoration: BoxDecoration(
                      color: style == IconStyle.current ? Colors.white.withValues(alpha: 0.24) : Colors.transparent,
                      borderRadius: BorderRadius.circular(p(12)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(style.label, maxLines: 1, softWrap: false, style: sf(p(12.5), weight: 600, height: 1.2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _swatches(Ios p) {
    final current = Color(_settings.iconTint).toARGB32();
    final colors = [_neutral, ?_wallpaper, for (final color in iconTints.skip(1)) Color(color)];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final color in colors.take(8))
          GestureDetector(
            onTap: () => _pick(color),
            child: Container(
              width: p(34),
              height: p(34),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: color.toARGB32() == current ? Colors.white : Colors.white.withValues(alpha: 0.18),
                  width: color.toARGB32() == current ? p(3) : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tones(Ios p) => Container(
    padding: EdgeInsets.all(p(3)),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(p(22))),
    child: Row(
      children: [
        for (final (tone, label) in const [('light', 'Hell'), ('dark', 'Dunkel'), ('auto', 'Automatisch')])
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tone(tone),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: p(38),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _settings.glassTone == tone ? Colors.white.withValues(alpha: 0.28) : Colors.transparent,
                  borderRadius: BorderRadius.circular(p(19)),
                ),
                child: Text(label, style: sf(p(15), weight: 600)),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: () => Navigator.of(context).pop(), behavior: HitTestBehavior.opaque),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(p(10), 0, p(10), p(10)),
              child: Glass(
                radius: p(40),
                tint: 0.36,
                dark: true,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(p(18), p(16), p(18), p(22)),
                  child: ListenableBuilder(
                    listenable: _state,
                    builder: (context, _) {
                      final look = IconStyle.current;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _round(p, Icons.wb_sunny_rounded, _settings.dimHome, () {
                                _settings.dimHome = !_settings.dimHome;
                                _state.commit();
                              }),
                              Expanded(
                                child: Text('Anpassen', textAlign: TextAlign.center, style: sf(p(17), weight: 600)),
                              ),
                              _round(p, _settings.largeIcons ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, _settings.largeIcons, () {
                                _settings.largeIcons = !_settings.largeIcons;
                                _state.commit();
                              }),
                            ],
                          ),
                          SizedBox(height: p(18)),
                          _styles(p),
                          if (look == IconStyle.tinted) ...[
                            SizedBox(height: p(20)),
                            _Track(
                              value: _hue / 360,
                              colors: [for (var hue = 0; hue <= 360; hue += 30) HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor()],
                              thumb: HSVColor.fromAHSV(1, _hue, 1, 1).toColor(),
                              onChanged: (value) => _slide(hue: value * 360),
                              onEnd: _state.commit,
                            ),
                            SizedBox(height: p(14)),
                            _Track(
                              value: _strength,
                              colors: [Colors.white, HSVColor.fromAHSV(1, _hue, 1, 1).toColor()],
                              thumb: HSVColor.fromAHSV(1, _hue, _strength, 1).toColor(),
                              onChanged: (value) => _slide(strength: value),
                              onEnd: _state.commit,
                            ),
                            SizedBox(height: p(18)),
                            _swatches(p),
                          ],
                          if (look.glass) ...[SizedBox(height: p(20)), _tones(p)],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slider in the iOS colour picker's shape: the track shows what each position gives.
class _Track extends StatelessWidget {
  const _Track({required this.value, required this.colors, required this.thumb, required this.onChanged, required this.onEnd});
  final double value;
  final List<Color> colors;
  final Color thumb;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final height = p(30);
    return LayoutBuilder(
      builder: (context, box) {
        final travel = box.maxWidth - height;
        void move(Offset at) => onChanged(((at.dx - height / 2) / travel).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (drag) => move(drag.localPosition),
          onHorizontalDragUpdate: (drag) => move(drag.localPosition),
          onHorizontalDragEnd: (_) => onEnd(),
          onTapDown: (tap) => move(tap.localPosition),
          onTapUp: (_) => onEnd(),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
                Positioned(
                  left: value.clamp(0.0, 1.0) * travel,
                  top: 0,
                  child: Container(
                    width: height,
                    height: height,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: thumb,
                      border: Border.all(color: Colors.white, width: p(3)),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x40000000))],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
