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

/// The iOS 18 grid: four columns of 1 × 1 cells that tiles span.
/// Buttons that can be added to Control Centre, with name and icon.
const controlChoices = {
  'rotation': ('Ausrichtungssperre', Icons.screen_lock_rotation_rounded),
  'timer': ('Timer', Icons.timer_outlined),
  'alarm': ('Wecker', Icons.alarm_rounded),
  'calculator': ('Rechner', Icons.calculate_outlined),
  'notes': ('Notizen', Icons.sticky_note_2_outlined),
  'qr': ('Code-Scanner', Icons.qr_code_scanner_rounded),
  'location': ('Ortungsdienste', Icons.location_on_outlined),
  'nfc': ('NFC', Icons.nfc_rounded),
  'display': ('Dunkelmodus', Icons.contrast_rounded),
  'hotspot': ('Hotspot', Icons.wifi_tethering_rounded),
  'settings': ('Einstellungen', Icons.settings_outlined),
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

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final gap = p(16);
    final cell = (MediaQuery.sizeOf(context).width - p(32) * 2 - gap * 3) / 4;
    final two = cell * 2 + gap;
    return Backdrop(
      dim: 0.42,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final s = state.status;
          final media = state.media;
          return Padding(
            padding: EdgeInsets.fromLTRB(p(32), 0, p(32), p(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: islandCenter(context) * 2 + p(40)),
                Row(
                  children: [
                    SizedBox(
                      width: two,
                      height: two,
                      child: _Tile(
                        p,
                        child: Padding(
                          padding: EdgeInsets.all(p(11)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Round(p, Icons.flight_rounded, _orange, false, () => Native.call('panel', 'airplane')),
                                  _Round(p, Icons.cell_tower_rounded, _green, s.cellular, () => Native.call('panel', 'internet')),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Round(p, Icons.wifi_rounded, _blue, s.wifi, () => Native.call('panel', 'wifi')),
                                  _Round(p, Icons.bluetooth_rounded, _blue, false, () => Native.call('panel', 'bluetooth')),
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
                          padding: EdgeInsets.all(p(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                media?.title ?? 'Nicht abgespielt',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sf(p(14), weight: 600, height: 1.2),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _Transport(p, Icons.fast_rewind_rounded, 'previous', 26),
                                  _Transport(p, media?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded, 'toggle', 34),
                                  _Transport(p, Icons.fast_forward_rounded, 'next', 26),
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
                              child: _Tile(
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.nightlight_round, size: p(24), color: s.doNotDisturb ? const Color(0xFF5E5CE6) : Colors.white),
                                    SizedBox(width: p(8)),
                                    Text('Fokus', style: sf(p(15), weight: 600, color: s.doNotDisturb ? Colors.black : Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: cell,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  SizedBox.square(
                                    dimension: cell,
                                    child: _Tile(
                                      p,
                                      round: true,
                                      active: s.torch,
                                      onTap: () async {
                                        await Native.call('torch', !s.torch);
                                        await Future<void>.delayed(const Duration(milliseconds: 250));
                                        await state.refresh();
                                      },
                                      child: Icon(
                                        s.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                                        size: p(26),
                                        color: s.torch ? Colors.black : Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox.square(
                                    dimension: cell,
                                    child: _Tile(
                                      p,
                                      round: true,
                                      onTap: () => Native.call('camera'),
                                      child: Icon(Icons.photo_camera_rounded, size: p(26), color: Colors.white),
                                    ),
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
                          icon: Icons.wb_sunny_rounded,
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
                        child: _Slider(p, icon: Icons.volume_up_rounded, initial: s.volume, onChanged: (v) => Native.call('volume', v)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                // The buttons the user picked, as Control Centre lets one arrange in iOS.
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final key in state.settings.controls)
                      if (controlChoices[key] case (_, final icon))
                        SizedBox.square(
                          dimension: cell,
                          child: _Tile(
                            p,
                            round: true,
                            active: key == 'rotation' && s.rotationLocked,
                            onTap: () => runControl(key, state),
                            child: Icon(icon, size: p(26), color: key == 'rotation' && s.rotationLocked ? Colors.black : Colors.white),
                          ),
                        ),
                  ],
                ),
                SizedBox(height: gap),
                Center(
                  child: GestureDetector(
                    onTap: () => _editControls(context),
                    child: Glass(
                      radius: p(16),
                      tint: 0.12,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: p(14), vertical: p(7)),
                        child: Text('Steuerelemente bearbeiten', style: sf(p(13), weight: 600)),
                      ),
                    ),
                  ),
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
        radius: round ? 200 : p(30),
        tint: active ? 0.94 : 0.1,
        child: SizedBox.expand(child: Center(child: child)),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round(this.p, this.icon, this.color, this.on, this.onTap);
  final Ios p;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: p(58),
        height: p(58),
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color : Colors.white.withValues(alpha: 0.16)),
        child: Icon(icon, color: Colors.white, size: p(26)),
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
          radius: p(34),
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
                alignment: const Alignment(0, 0.78),
                child: Icon(widget.icon, size: p(24), color: _value > 0.16 ? const Color(0xFF636366) : Colors.white),
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
      radius: p(25),
      tint: on ? 0.92 : 0.12,
      child: SizedBox.square(
        dimension: p(50),
        child: Icon(icon, color: on ? Colors.black : Colors.white, size: p(22)),
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
                padding: EdgeInsets.fromLTRB(p(16), islandCenter(context) * 2 + p(10), p(16), 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Ticker(
                        builder: (_, now) => Column(
                          children: [
                            Text('${_days[now.weekday - 1]} ${now.day}. ${_months[now.month - 1]}', style: sf(p(20), weight: 600, tracking: 0)),
                            LockClock(text: clockText(now), settings: state.settings, p: p),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: p(10)),
                    Row(
                      children: [
                        Expanded(child: Text('Mitteilungszentrale', style: sf(p(28), weight: 700))),
                        if (state.alerts.isNotEmpty)
                          GestureDetector(
                            onTap: _clearAll,
                            child: Glass(
                              radius: p(20),
                              tint: 0.16,
                              child: SizedBox.square(
                                dimension: p(40),
                                child: Icon(Icons.close_rounded, color: Colors.white, size: p(22)),
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
                bottom: p(42),
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
                    _round(p, Icons.photo_camera_rounded, onTap: () => Native.call('camera')),
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
