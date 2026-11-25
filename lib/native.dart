import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'icons.dart';

class AppInfo {
  const AppInfo(this.package, this.activity, this.label, this.category, [this.installed = 0]);

  /// When it was installed, in milliseconds; 0 where Android doesn't say.
  final int installed;
  final String package;
  final String activity;
  final String label;
  final String category;

  String get key => '$package/$activity';

  /// Of two apps for one job, such as Samsung's and Google's wallet, only one becomes the iOS
  /// app. These keep their own icon and name, so the two stay apart.
  static Set<String> distinct = {};

  Role? get role => distinct.contains(package) ? null : packageRoles[package];

  /// What the home screen shows; [label] stays searchable.
  String get name => role?.label ?? label;

  bool matches(String query) => label.toLowerCase().contains(query) || name.toLowerCase().contains(query);
}

class DeviceStatus {
  const DeviceStatus({
    this.battery = 100,
    this.charging = false,
    this.wifi = false,
    this.cellular = false,
    this.torch = false,
    this.doNotDisturb = false,
    this.volume = 0.5,
    this.brightness = 0.5,
    this.carrier = '',
    this.ringer = 2,
    this.rotationLocked = false,
    this.headphones,
    this.live,
  });
  final int battery;
  final bool charging, wifi, cellular, torch, doNotDisturb;
  final double volume, brightness;
  final String carrier;

  /// Android's ringer mode: 0 silent, 1 vibrate, 2 normal.
  final int ringer;
  final bool rotationLocked;

  /// Name of the connected headphones.
  final String? headphones;
  final LiveActivity? live;
}

class Alert {
  const Alert(this.key, this.package, this.app, this.title, this.text, this.time, this.canReply, [this.avatar, this.picture]);

  /// The sender's picture, shown with the app's icon as a badge, and an attached image.
  final Uint8List? avatar, picture;
  final String key, package, app;
  final String? title, text;
  final DateTime time;

  /// The app accepts an answer right from the notification.
  final bool canReply;
}

class Media {
  const Media(this.title, this.artist, this.playing, [this.art]);
  final String title, artist;
  final bool playing;

  /// The cover, when the app provides one.
  final Uint8List? art;
}

/// A running clock from another app, iOS's Live Activity: a call, a timer, a stopwatch.
class LiveActivity {
  const LiveActivity(this.key, this.package, this.title, this.since, this.countDown, this.call);
  final String key, package;
  final String? title;

  /// Start of the clock, or its end when it counts down.
  final DateTime since;
  final bool countDown, call;
}

class Event {
  const Event(this.title, this.begin, this.allDay, this.color);
  final String title;
  final DateTime begin;
  final bool allDay;
  final int color;
}

class Hour {
  const Hour(this.time, this.temperature, this.code);
  final DateTime time;
  final int temperature, code;
}

class Day {
  const Day(this.time, this.code, this.high, this.low);
  final DateTime time;
  final int code, high, low;
}

class Weather {
  const Weather(this.city, this.temperature, this.code, this.day, this.high, this.low, this.hours, this.days);
  final String city;
  final int temperature, code, high, low;
  final bool day;
  final List<Hour> hours;
  final List<Day> days;
}

/// Calls into Bridge.kt.
class Native {
  static const _channel = MethodChannel('glas/native');
  static final _events = StreamController<String>.broadcast();
  static final _icons = <String, Future<Uint8List?>>{};
  static final _loaded = <String, Uint8List>{};

  /// "changed" (status, notifications), "apps" or "home".
  static Stream<String> get events => _events.stream;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tilt') return _tilted(call.arguments as List);
      if (call.method == 'appsUpdated') {
        _forgetPackages((call.arguments as List).cast<String>());
        _events.add('apps');
        return;
      }
      _events.add(call.method);
    });
  }

  /// How far the phone leans from where it is usually held, about -1 to 1 on each axis.
  static final tilt = ValueNotifier<Offset>(Offset.zero);

  /// Gravity as it is, for telling when the phone lies on its side.
  static final gravity = ValueNotifier<Offset>(const Offset(0, 9.8));
  static Offset? _rest;

  /// The resting position drifts along slowly, so only movement shows, not the posture.
  static void _tilted(List values) {
    final now = Offset((values[0] as num).toDouble(), (values[1] as num).toDouble());
    gravity.value = now;
    final rest = _rest = Offset.lerp(_rest ?? now, now, 0.02)!;
    final lean = (now - rest) / 3;
    tilt.value = Offset.lerp(tilt.value, Offset(lean.dx.clamp(-1.0, 1.0), lean.dy.clamp(-1.0, 1.0)), 0.25)!;
  }

  static Future<List<AppInfo>> apps() async {
    final list = await _channel.invokeListMethod<Map>('apps') ?? [];
    final apps = [
      for (final a in list)
        AppInfo(a['package'] as String, a['activity'] as String, a['label'] as String, a['category'] as String, (a['installed'] as int?) ?? 0),
    ];
    final defaultApps = await defaults();
    AppInfo.distinct = rolesTaken(apps.map((a) => a.package).toSet(), defaultApps.values.toSet());
    return apps..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// [layer] is "plain", "foreground" or "mono".
  static Future<Uint8List?> icon(AppInfo app, [String layer = 'plain']) => _icons['${app.key}|$layer'] ??= _channel
      .invokeMethod<Uint8List>('icon', {'package': app.package, 'activity': app.activity, 'layer': layer})
      .then((bytes) {
        if (bytes != null) _loaded['${app.key}|$layer'] = bytes;
        return bytes;
      });

  static Uint8List? iconNow(AppInfo app, String layer) => _loaded['${app.key}|$layer'];

  /// Fetches icons anew, but keeps showing the ones already loaded meanwhile. Android reports
  /// app changes often, and clearing them made the whole home screen reload its icons.
  static void forgetIcons() => _icons.clear();

  /// An installed or updated app may have a new icon. The bytes shown so far must go too:
  /// [iconNow] would otherwise keep showing the old icon until Glas restarts.
  static void _forgetPackages(List<String> packages) {
    bool stale(String key) => packages.any((p) => key.startsWith('$p/'));
    _icons.removeWhere((key, _) => stale(key));
    _loaded.removeWhere((key, _) => stale(key));
  }

  /// [origin] is the icon's rectangle in physical pixels.
  static Future<void> launch(AppInfo app, Rect? origin) => _channel.invokeMethod('launch', {
    'package': app.package,
    'activity': app.activity,
    if (origin != null) ...{'x': origin.left.round(), 'y': origin.top.round(), 'size': origin.width.round()},
  });

  static Future<void> call(String method, [Object? argument]) => _channel.invokeMethod(method, argument);

  static Future<List<(String, String)>> shortcuts(String package) async {
    final list = await _channel.invokeListMethod<Map>('shortcuts', package) ?? [];
    return [for (final s in list) (s['id'] as String, s['label'] as String)];
  }

  static Future<DeviceStatus> status() async {
    final s = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return DeviceStatus(
      battery: s['battery'] as int? ?? 100,
      charging: s['charging'] as bool? ?? false,
      wifi: s['wifi'] as bool? ?? false,
      cellular: s['cellular'] as bool? ?? false,
      torch: s['torch'] as bool? ?? false,
      doNotDisturb: s['doNotDisturb'] as bool? ?? false,
      volume: (s['volume'] as num? ?? 0.5).toDouble(),
      brightness: (s['brightness'] as num? ?? 0.5).toDouble(),
      carrier: s['carrier'] as String? ?? '',
      ringer: s['ringer'] as int? ?? 2,
      rotationLocked: s['rotationLocked'] as bool? ?? false,
      headphones: s['headphones'] as String?,
      live: switch (s['live']) {
        final Map l => LiveActivity(
          l['key'] as String,
          l['package'] as String,
          l['title'] as String?,
          DateTime.fromMillisecondsSinceEpoch(l['when'] as int),
          l['countDown'] as bool? ?? false,
          l['call'] as bool? ?? false,
        ),
        _ => null,
      },
    );
  }

  static Future<Map<String, bool>> permissions() async => await _channel.invokeMapMethod<String, bool>('permissions') ?? {};

  /// Packages of the default phone, SMS and browser apps, by "phone", "sms", "browser".
  static Future<Map<String, String>> defaults() async => await _channel.invokeMapMethod<String, String>('defaults') ?? {};

  static Future<List<Alert>> notifications() async {
    final list = await _channel.invokeListMethod<Map>('notifications') ?? [];
    return [
      for (final n in list)
        Alert(
          n['key'] as String,
          n['package'] as String,
          n['app'] as String,
          n['title'] as String?,
          n['text'] as String?,
          DateTime.fromMillisecondsSinceEpoch(n['time'] as int),
          n['canReply'] as bool? ?? false,
          n['avatar'] as Uint8List?,
          n['picture'] as Uint8List?,
        ),
    ];
  }

  /// What Android's own lock screen has in its two corners, if the phone tells.
  static Future<List<String>> lockShortcuts() async => await _channel.invokeListMethod<String>('lockShortcuts') ?? [];

  /// The lock wallpaper's subject cut out: a path, "" without a subject, null to retry later.
  static Future<String?> depthCutout(Uint8List image) => _channel.invokeMethod<String>('depthCutout', image);

  /// False without the accessibility service.
  static Future<Map<String, int>> zones() async => await _channel.invokeMapMethod<String, int>('zones') ?? {};

  /// A recent photo, picked by [seed]; null without access.
  static Future<Uint8List?> photo(int seed) => _channel.invokeMethod<Uint8List>('photo', seed);

  static Future<bool> screenOff() async => await _channel.invokeMethod<bool>('screenOff') ?? false;

  static Future<void> openLocked(AppInfo app) => _channel.invokeMethod('openLocked', {'package': app.package, 'activity': app.activity});

  static Future<Media?> media() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('media');
    if (m == null) return null;
    return Media(m['title'] as String? ?? 'Unbekannt', m['artist'] as String? ?? '', m['playing'] as bool? ?? false, m['art'] as Uint8List?);
  }

  static Future<List<Event>> events_() async {
    final list = await _channel.invokeListMethod<Map>('events') ?? [];
    return [for (final e in list) Event(e['title'] as String, DateTime.fromMillisecondsSinceEpoch(e['begin'] as int), e['allDay'] as bool, e['color'] as int)];
  }

  /// Latest cached forecast; the bridge fetches a new one in the background when it's old.
  static Future<Weather?> weather() async {
    final w = await _channel.invokeMapMethod<String, dynamic>('weather');
    if (w == null) return null;
    return Weather(
      w['city'] as String? ?? '',
      w['temperature'] as int,
      w['code'] as int,
      w['day'] as bool,
      w['high'] as int,
      w['low'] as int,
      [for (final h in w['hours'] as List) Hour(DateTime.fromMillisecondsSinceEpoch(h['time'] as int), h['temperature'] as int, h['code'] as int)],
      [for (final d in w['days'] as List) Day(DateTime.fromMillisecondsSinceEpoch(d['time'] as int), d['code'] as int, d['high'] as int, d['low'] as int)],
    );
  }

  /// Packages by last use, newest first; empty without usage access.
  static Future<String?> pickWallpaper() => _channel.invokeMethod<String>('pickWallpaper');

  static Future<bool> setSystemWallpaper(Uint8List home, Uint8List lock) async =>
      await _channel.invokeMethod<bool>('setWallpaper', {'home': home, 'lock': lock}) ?? false;
}
