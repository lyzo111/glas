import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'lock_screen.dart';
import 'icons.dart';
import 'native.dart';
import 'state.dart';

const _blue = Color(0xFF0A84FF);
const _green = Color(0xFF34C759);
const _orange = Color(0xFFFF9500);

/// Buttons that can be added to Control Centre, with name and icon.
const controlChoices = {
  'rotation': ('Ausrichtungssperre', CupertinoIcons.lock_rotation),
  'timer': ('Timer', CupertinoIcons.timer),
  'alarm': ('Wecker', CupertinoIcons.alarm_fill),
  'calculator': ('Rechner', Icons.calculate_rounded),
  'notes': ('Notizen', CupertinoIcons.square_pencil),
  'qr': ('Code-Scanner', CupertinoIcons.qrcode_viewfinder),
  'location': ('Ortungsdienste', CupertinoIcons.location_fill),
  'nfc': ('NFC', CupertinoIcons.radiowaves_right),
  'display': ('Dunkelmodus', CupertinoIcons.circle_lefthalf_fill),
  'hotspot': ('Hotspot', CupertinoIcons.personalhotspot),
  'settings': ('Einstellungen', CupertinoIcons.gear_alt_fill),
};

void runControl(String key, AppState state) {
  switch (key) {
    case 'calculator' || 'notes':
      final app = state.appFor(key == 'notes' ? Role.notes : Role.calculator);
      if (app != null) state.launch(app, null);
    case 'qr':
      Native.call('camera');
    case 'rotation':
      Native.call('control', key).then((_) => Future<void>.delayed(const Duration(milliseconds: 250))).then((_) => state.refresh());
    default:
      Native.call('control', key);
  }
}

/// iOS 26's Control Centre: four columns of round cells that tiles span. On top the plus
/// that edits it and the power button, below them carrier and battery.
class ControlCenter extends StatelessWidget {
  const ControlCenter({super.key, required this.state});
  final AppState state;

  void _editControls(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, refresh) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final e in controlChoices.entries)
            CheckboxListTile(
              title: Text(e.value.$1),
              secondary: Icon(e.value.$2),
              value: state.settings.controls.contains(e.key),
              onChanged: (on) {
                on == true ? state.settings.controls.add(e.key) : state.settings.controls.remove(e.key);
                state.commit();
                refresh(() {});
              },
            ),
        ],
      ),
    ),
  );

  Widget _corner(Ios p, IconData icon, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: p(29),
      height: p(29),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
      child: Icon(icon, size: p(16), color: Colors.white),
    ),
  );

  /// A tile two cells wide: the symbol on the left, its name beside it.
  Widget _pill(Ios p, {required Widget symbol, required List<Widget> text, required bool active, required VoidCallback onTap}) => _Tile(
    p,
    round: true,
    active: active,
    onTap: onTap,
    child: Row(
      children: [
        SizedBox(width: p(13)),
        SizedBox(
          width: p(40),
          child: Center(child: symbol),
        ),
        SizedBox(width: p(9)),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: text),
        ),
        SizedBox(width: p(8)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final gap = p(16.5), margin = p(38.5);
    final cell = (MediaQuery.sizeOf(context).width - margin * 2 - gap * 3) / 4;
    final two = cell * 2 + gap;
    return Backdrop(
      dim: 0.42,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final s = state.status;
          final media = state.media;
          final ink = Colors.white;
          return Padding(
            padding: EdgeInsets.fromLTRB(margin, 0, margin, p(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: p(23)),
                Row(
                  children: [
                    _corner(p, CupertinoIcons.plus, () => _editControls(context)),
                    const Spacer(),
                    _corner(p, CupertinoIcons.power, () => Native.screenOff()),
                  ],
                ),
                SizedBox(height: p(27)),
                Row(
                  children: [
                    SizedBox(width: p(8)),
                    if (s.cellular) ...[SignalGlyph(height: p(11.5)), SizedBox(width: p(6))],
                    Expanded(
                      child: Text(s.carrier, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(16.5), weight: 500)),
                    ),
                    Text('${s.battery} %', style: sf(p(16.5), weight: 500)),
                    SizedBox(width: p(6)),
                    BatteryGlyph(level: s.battery, charging: s.charging, plain: true),
                    SizedBox(width: p(8)),
                  ],
                ),
                SizedBox(height: p(30)),
                Row(
                  children: [
                    SizedBox(
                      width: two,
                      height: two,
                      child: _Tile(
                        p,
                        child: Padding(
                          padding: EdgeInsets.all(p(13)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Round(p, CupertinoIcons.airplane, _orange, false, () => Native.call('panel', 'airplane')),
                                  _Round(p, CupertinoIcons.personalhotspot, _green, false, () => Native.call('control', 'hotspot')),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Round(p, CupertinoIcons.wifi, Colors.white, s.wifi, () => Native.call('panel', 'wifi')),
                                  // The fourth place holds four small ones, as on iOS.
                                  SizedBox.square(
                                    dimension: p(54.5),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            _Round(p, CupertinoIcons.chart_bar_fill, _green, s.cellular, () => Native.call('panel', 'internet'), size: 24.5),
                                            _Round(p, CupertinoIcons.bluetooth, _blue, false, () => Native.call('panel', 'bluetooth'), size: 24.5),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            _Round(p, CupertinoIcons.location_fill, _blue, false, () => Native.call('control', 'location'), size: 24.5),
                                            _Round(p, CupertinoIcons.radiowaves_right, _blue, false, () => Native.call('control', 'nfc'), size: 24.5),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: two,
                      height: two,
                      child: _Tile(
                        p,
                        child: Padding(
                          padding: EdgeInsets.all(p(15)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                media?.title ?? 'Keine Wiedergabe',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sf(p(15), weight: 600, height: 1.2),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Transport(p, CupertinoIcons.backward_fill, 'previous', 24),
                                  _Transport(p, media?.playing == true ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, 'toggle', 32),
                                  _Transport(p, CupertinoIcons.forward_fill, 'next', 24),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap),
                SizedBox(
                  height: two,
                  child: Row(
                    children: [
                      SizedBox(
                        width: two,
                        child: Column(
                          children: [
                            SizedBox(
                              height: cell,
                              child: _pill(
                                p,
                                active: s.torch,
                                onTap: () async {
                                  await Native.call('torch', !s.torch);
                                  await Future<void>.delayed(const Duration(milliseconds: 250));
                                  await state.refresh();
                                },
                                symbol: Icon(
                                  s.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                                  size: p(30),
                                  color: s.torch ? const Color(0xFF0A84FF) : ink,
                                ),
                                text: [
                                  Text('Taschen-\nlampe', style: sf(p(15), weight: 500, height: 1.2, color: s.torch ? Colors.black : ink)),
                                  Text(s.torch ? 'Ein' : 'Aus', style: sf(p(15), height: 1.2, color: (s.torch ? Colors.black : ink).withValues(alpha: 0.55))),
                                ],
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: cell,
                              child: _pill(
                                p,
                                active: s.doNotDisturb,
                                onTap: () async {
                                  if (state.permissions['notifications'] != true) {
                                    return Native.call('openPermission', 'notifications');
                                  }
                                  await Native.call('doNotDisturb', !s.doNotDisturb);
                                  await Future<void>.delayed(const Duration(milliseconds: 300));
                                  await state.refresh();
                                },
                                symbol: Container(
                                  width: p(40),
                                  height: p(40),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: s.doNotDisturb ? const Color(0xFF5E5CE6) : Colors.white.withValues(alpha: 0.2),
                                  ),
                                  child: Icon(CupertinoIcons.moon_fill, size: p(22), color: Colors.white),
                                ),
                                text: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Fokus', style: sf(p(15), weight: 500, color: s.doNotDisturb ? Colors.black : ink)),
                                      SizedBox(width: p(4)),
                                      Icon(
                                        CupertinoIcons.chevron_up_chevron_down,
                                        size: p(13),
                                        color: (s.doNotDisturb ? Colors.black : ink).withValues(alpha: 0.55),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: gap),
                      SizedBox(
                        width: cell,
                        child: _Slider(
                          p,
                          icon: CupertinoIcons.sun_max_fill,
                          initial: s.brightness,
                          onChanged: (v) {
                            if (state.permissions['writeSettings'] == true) {
                              Native.call('brightness', v);
                            } else {
                              Native.call('openPermission', 'writeSettings');
                            }
                          },
                        ),
                      ),
                      SizedBox(width: gap),
                      SizedBox(
                        width: cell,
                        child: _Slider(p, icon: CupertinoIcons.speaker_2_fill, initial: s.volume, onChanged: (v) => Native.call('volume', v)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                // The camera, then the buttons the user picked behind the plus.
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox.square(
                      dimension: cell,
                      child: _Tile(
                        p,
                        round: true,
                        onTap: () => Native.call('camera'),
                        child: Icon(CupertinoIcons.camera_fill, size: p(27), color: Colors.white),
                      ),
                    ),
                    for (final key in state.settings.controls)
                      if (controlChoices[key] case (_, final icon))
                        SizedBox.square(
                          dimension: cell,
                          child: _Tile(
                            p,
                            round: true,
                            active: key == 'rotation' && s.rotationLocked,
                            onTap: () => runControl(key, state),
                            child: Icon(icon, size: p(27), color: key == 'rotation' && s.rotationLocked ? Colors.black : Colors.white),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport(this.p, this.icon, this.action, this.size);
  final Ios p;
  final IconData icon;
  final String action;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Native.call('mediaAction', action),
    child: Icon(icon, size: p(size), color: Colors.white),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.p, {required this.child, this.onTap, this.active = false, this.round = false});
  final Ios p;
  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Also without an action: a tile isn't empty space that closes the control centre.
      onTap: onTap ?? () {},
      child: Glass(
        radius: round ? 200 : p(38),
        tint: active ? 0.94 : 0.1,
        child: SizedBox.expand(child: Center(child: child)),
      ),
    );
  }
}

/// A round switch inside the connectivity tile; [color] is what it turns when on.
class _Round extends StatelessWidget {
  const _Round(this.p, this.icon, this.color, this.on, this.onTap, {this.size = 54.5});
  final Ios p;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: p(size),
        height: p(size),
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color : Colors.white.withValues(alpha: 0.16)),
        // White is the one colour that needs a dark symbol on it.
        child: Icon(icon, color: on && color == Colors.white ? const Color(0xFF1C1C1E) : Colors.white, size: p(size * 0.46)),
      ),
    );
  }
}

class _Slider extends StatefulWidget {
  const _Slider(this.p, {required this.icon, required this.initial, required this.onChanged});
  final Ios p;
  final IconData icon;
  final double initial;
  final ValueChanged<double> onChanged;

  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  late var _value = widget.initial;

  void _update(Offset local, double height) {
    final value = (1 - local.dy / height).clamp(0.0, 1.0);
    setState(() => _value = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onVerticalDragUpdate: (d) => _update(d.localPosition, box.maxHeight),
        onTapDown: (d) => _update(d.localPosition, box.maxHeight),
        child: Glass(
          radius: 200,
          tint: 0.1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: _value,
                  widthFactor: 1,
                  child: const ColoredBox(color: Color(0xF2FFFFFF)),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.6),
                child: Icon(widget.icon, size: p(24), color: _value > 0.24 ? const Color(0xFF636366) : Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipe down from the top left: iOS 26's Notification Centre, the lock screen with every
/// notification. Clock on top, a button that clears them all, torch and camera below.
class NotificationCenter extends StatelessWidget {
  const NotificationCenter({super.key, required this.state});
  final AppState state;

  static const _days = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];
  static const _months = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'];

  void _clearAll() {
    HapticFeedback.mediumImpact();
    for (final alert in state.alerts) {
      Native.call('dismissNotification', alert.key);
    }
    Future<void>.delayed(const Duration(milliseconds: 300), state.refresh);
  }

  Widget _round(Ios p, IconData icon, {bool on = false, required VoidCallback onTap}) => GestureDetector(
    onTap: onTap,
    child: Glass(
      radius: p(30),
      tint: on ? 0.92 : 0.12,
      child: SizedBox.square(
        dimension: p(58),
        child: Icon(icon, color: on ? Colors.black : Colors.white, size: p(26)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Backdrop(
        dim: 0.42,
        tapToClose: false,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(p(10), islandCenter(context) * 2 + p(10), p(10), 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Ticker(
                        builder: (_, now) => Column(
                          children: [
                            Text('${_days[now.weekday - 1]} ${now.day}. ${_months[now.month - 1]}', style: sf(p(22), weight: 600, tracking: 0)),
                            LockClock(text: clockText(now), settings: state.settings, p: p),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: p(10)),
                    Row(
                      children: [
                        SizedBox(width: p(10)),
                        Expanded(child: Text('Mitteilungszentrale', style: sf(p(28), weight: 500))),
                        if (state.alerts.isNotEmpty)
                          GestureDetector(
                            onTap: _clearAll,
                            child: Glass(
                              radius: p(17),
                              tint: 0.16,
                              child: SizedBox.square(
                                dimension: p(34),
                                child: Icon(CupertinoIcons.xmark, color: Colors.white, size: p(16)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: p(10)),
                    if (state.permissions['notifications'] != true)
                      Center(
                        child: TextButton(
                          onPressed: () => Native.call('openPermission', 'notifications'),
                          child: Text('Zugriff auf Mitteilungen erlauben', style: sf(p(16), weight: 500, color: _blue)),
                        ),
                      )
                    else if (state.alerts.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('Keine älteren Mitteilungen', style: sf(p(16), weight: 500, color: Colors.white.withValues(alpha: 0.7))),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.only(bottom: p(110)),
                          physics: const BouncingScrollPhysics(),
                          children: [for (final alert in state.alerts) AlertCard(alert: alert, app: _appFor(alert))],
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: p(46),
                right: p(46),
                bottom: p(51),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _round(
                      p,
                      state.status.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                      on: state.status.torch,
                      onTap: () async {
                        await Native.call('torch', !state.status.torch);
                        await Future<void>.delayed(const Duration(milliseconds: 250));
                        await state.refresh();
                      },
                    ),
                    _round(p, CupertinoIcons.camera_fill, onTap: () => Native.call('camera')),
                  ],
                ),
              ),
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
}
