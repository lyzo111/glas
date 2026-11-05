import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'icons.dart';
import 'native.dart';
import 'state.dart';

/// A short message the island shows for a few seconds, as iOS does for the ringer switch,
/// Do Not Disturb, the charger, headphones and a low battery.
class _Flash {
  const _Flash(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;
}

/// The Dynamic Island with something to do. Short events flash in it; a call, a timer or a
/// stopwatch from another app runs in it; music shows its cover and opens into a player.
class LiveIsland extends StatefulWidget {
  const LiveIsland({super.key, required this.state});
  final AppState state;

  @override
  State<LiveIsland> createState() => _LiveIslandState();
}

class _LiveIslandState extends State<LiveIsland> {
  /// What the island last saw. Null until the first status, so starting up flashes nothing.
  DeviceStatus? _seen;
  DateTime _focusAt = DateTime(0);
  _Flash? _flash;
  Timer? _flashTimer;

  /// Ticks once a second while a clock runs in the island.
  Timer? _clock;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _seen = _state.status;
    _state.addListener(_changed);
    _syncClock();
  }

  @override
  void dispose() {
    _state.removeListener(_changed);
    _flashTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _show(_Flash flash) {
    setState(() => _flash = flash);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _changed() {
    final now = _state.status;
    final was = _seen;
    _seen = now;
    _syncClock();
    if (was == null) return;
    if (now.charging && !was.charging) {
      _show(_Flash(Icons.bolt_rounded, const Color(0xFF30D158), '${now.battery} %'));
    } else if (now.doNotDisturb != was.doNotDisturb) {
      _focusAt = DateTime.now();
      _show(
        now.doNotDisturb
            ? const _Flash(Icons.dark_mode_rounded, Color(0xFF5E5CE6), 'Nicht stören')
            : const _Flash(Icons.dark_mode_outlined, Colors.white, 'Nicht stören aus'),
      );
    } else if (now.ringer != was.ringer && DateTime.now().difference(_focusAt) > const Duration(seconds: 3)) {
      // Android flips the ringer along with Do Not Disturb; only a change of its own shows.
      _show(switch (now.ringer) {
        0 => const _Flash(Icons.notifications_off_rounded, Color(0xFFFF453A), 'Lautlos'),
        1 => const _Flash(Icons.vibration_rounded, Color(0xFFFF9F0A), 'Vibrieren'),
        _ => const _Flash(Icons.notifications_rounded, Colors.white, 'Klingeln'),
      });
    } else if (now.headphones != null && now.headphones != was.headphones) {
      _show(_Flash(Icons.headphones_rounded, Colors.white, now.headphones!));
    } else if (!now.charging && now.battery < 20 && was.battery >= 20) {
      _show(_Flash(Icons.battery_alert_rounded, const Color(0xFFFF453A), '${now.battery} %'));
    }
  }

  void _syncClock() {
    if (_state.status.live == null) {
      _clock?.cancel();
      _clock = null;
    } else {
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _tap() {
    final live = _state.status.live;
    if (live != null) {
      Native.call('openNotification', live.key);
    } else if (_state.media != null) {
      openOverlay<void>(context, (_) => _IslandPlayer(state: _state), origin: Offset(MediaQuery.sizeOf(context).width / 2, 0));
    }
  }

  static String _duration(Duration d) {
    final s = d.inSeconds.abs();
    final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final media = _state.media;
    final live = _state.status.live;
    final flash = _flash;
    Widget content = const SizedBox();
    var width = p(126);
    if (flash != null) {
      // At most as wide as the gap between the time and the status icons.
      width = p(flash.text.length > 9 ? 206 : 190);
      content = Row(
        children: [
          Icon(flash.icon, color: flash.color, size: p(20)),
          SizedBox(width: p(8)),
          const Spacer(),
          Flexible(
            flex: 6,
            child: Text(
              flash.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sf(p(14), weight: 600, color: flash.color),
            ),
          ),
        ],
      );
    } else if (live != null) {
      width = p(196);
      final color = live.call ? const Color(0xFF30D158) : const Color(0xFFFF9F0A);
      final app = _state.apps.values.where((a) => a.package == live.package).firstOrNull;
      final elapsed = live.countDown ? live.since.difference(DateTime.now()) : DateTime.now().difference(live.since);
      content = Row(
        children: [
          if (live.call)
            Container(
              width: p(24),
              height: p(24),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(Icons.call_rounded, color: Colors.white, size: p(15)),
            )
          else if (app != null)
            ClipOval(
              child: AppIcon(app: app, size: p(24)),
            )
          else
            Icon(Icons.timer_rounded, color: color, size: p(20)),
          const Spacer(),
          Text(
            _duration(elapsed),
            style: sf(p(14), weight: 600, color: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      );
    } else if (media != null) {
      width = p(196);
      content = Row(
        children: [
          _Cover(media: media, size: p(24), radius: p(6)),
          const Spacer(),
          _Waves(playing: media.playing, size: p(18)),
        ],
      );
    }
    return GestureDetector(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: const IosSpring(),
        width: width,
        height: p(36),
        padding: EdgeInsets.symmetric(horizontal: p(7)),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(p(18))),
        child: ClipRect(child: content),
      ),
    );
  }
}

/// The album cover, or Apple Music's red tile with a note when the app sends none.
class _Cover extends StatelessWidget {
  const _Cover({required this.media, required this.size, required this.radius});
  final Media media;
  final double size, radius;

  @override
  Widget build(BuildContext context) {
    final art = media.art;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: art != null
            ? Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: const Color(0xFFFA2D48),
                child: Center(child: MusicNote(size: size * 0.58)),
              ),
      ),
    );
  }
}

/// The bars that dance next to music in the island.
class _Waves extends StatefulWidget {
  const _Waves({required this.playing, required this.size});
  final bool playing;
  final double size;

  @override
  State<_Waves> createState() => _WavesState();
}

class _WavesState extends State<_Waves> with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _beat.repeat();
  }

  @override
  void didUpdateWidget(_Waves old) {
    super.didUpdateWidget(old);
    widget.playing ? _beat.repeat() : _beat.stop();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _beat,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: widget.size * 0.14,
            height: widget.size * (widget.playing ? 0.35 + 0.65 * (0.5 + 0.5 * sin((_beat.value + i * 0.27) * 2 * pi)) : 0.3),
            margin: EdgeInsets.symmetric(horizontal: widget.size * 0.05),
            decoration: BoxDecoration(color: const Color(0xFFFA2D48), borderRadius: BorderRadius.circular(widget.size)),
          ),
      ],
    ),
  );
}

/// The island opened up as on iOS: cover, title and artist on top, the controls below,
/// all inside the black island itself near the top of the screen.
class _IslandPlayer extends StatelessWidget {
  const _IslandPlayer({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    Widget control(IconData icon, String action, double size) =>
        IconButton(onPressed: () => Native.call('mediaAction', action), iconSize: p(size), color: Colors.white, icon: Icon(icon));
    // Without a Material around it, Flutter marks text with yellow lines as a warning.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Color(0x22000000)),
            ),
          ),
          Positioned(
            top: islandCenter(context) - p(18),
            left: p(10),
            right: p(10),
            height: p(176),
            child: Container(
              padding: EdgeInsets.fromLTRB(p(22), p(20), p(22), p(10)),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(p(46))),
              child: ListenableBuilder(
                listenable: state,
                builder: (_, _) {
                  final media = state.media;
                  if (media == null) return const SizedBox();
                  return Column(
                    children: [
                      Row(
                        children: [
                          _Cover(media: media, size: p(56), radius: p(12)),
                          SizedBox(width: p(14)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(16), weight: 600)),
                                if (media.artist.isNotEmpty)
                                  Text(
                                    media.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sf(p(15), color: Colors.white.withValues(alpha: 0.6)),
                                  ),
                              ],
                            ),
                          ),
                          _Waves(playing: media.playing, size: p(22)),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          control(Icons.fast_rewind_rounded, 'previous', 34),
                          control(media.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, 'toggle', 42),
                          control(Icons.fast_forward_rounded, 'next', 34),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
