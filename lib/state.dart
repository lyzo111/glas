import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'glass.dart';
import 'icons.dart';
import 'layout.dart';
import 'native.dart';
import 'preset.dart';

/// Everything the user can customize. Read by the home and the lock screen engines alike.
class Settings {
  Settings({
    this.wallpaper = 0,
    this.wallpaperPath,
    this.lockWallpaper,
    this.lockWallpaperPath,
    this.lockEnabled = false,
    this.lockWeight = 600,
    this.lockLeft = 'auto',
    this.lockRight = 'auto',
    this.lockFont = 'inter',
    this.lockSize = 1,
    this.lockStretch = 1,
    this.lockGlass = false,
    this.lockFilter = 'none',
    this.lockNotify = 'stack',
    this.lockInline = 'none',
    this.lockFocus = false,
    this.standBy = true,
    this.note = '',
    List<String>? controls,
    this.lockDepth = true,
    this.lockDepthKey,
    this.lockDepthPath,
    List<Map<String, dynamic>>? looks,
    this.look = 0,
    this.largeIcons = false,
    this.compactHome = false,
    this.blurHome = false,
    this.dimHome = false,
    this.perspective = true,
    List<String>? today,
    this.lockColor = 0xFFFFFFFF,
    List<String>? lockWidgets,
    this.setupDone = false,
    this.layoutVersion = 0,
    this.iconStyle = 'standard',
    this.iconTint = 0xFF64D2FF,
    this.glassTone = 'dark',
    this.systemWallpaper,
    List<String>? recent,
  }) : controls = controls ?? ['rotation', 'timer', 'calculator', 'qr'],
       looks = looks ?? [],
       today = today ?? ['weather:medium', 'calendar:medium', 'battery:medium', 'music:medium'],
       lockWidgets = lockWidgets ?? ['battery', 'weather', 'week', 'alerts'],
       recent = recent ?? [];

  /// Preset wallpaper index; a path wins over it.
  int wallpaper;
  String? wallpaperPath;

  /// Null uses the home wallpaper.
  int? lockWallpaper;
  String? lockWallpaperPath;
  bool lockEnabled;
  double lockWeight;

  /// Corner shortcuts: "auto" follows Android's lock screen, otherwise "torch", "camera",
  /// "none" or an app's key.
  String lockLeft;
  String lockRight;

  /// The lock screen clock: a font family, its size, how tall it is drawn, and whether it is
  /// Liquid Glass. [lockFilter] tints the lock wallpaper: none, mono, duotone or wash.
  String lockFont;
  double lockSize;
  double lockStretch;
  bool lockGlass;
  String lockFilter;

  /// How notifications show on the lock screen, as iOS offers: count, stack or list.
  String lockNotify;

  /// The small widget next to the date: none, weather, battery or event.
  String lockInline;

  /// Do Not Disturb comes on with this lock screen, as a Focus linked to it in iOS.
  bool lockFocus;

  /// The bedside clock on the charger, turned on its side.
  bool standBy;

  /// Text of the note widget.
  String note;

  /// Extra buttons in Control Centre, by the keys of controlChoices.
  List<String> controls;

  /// The depth effect, the wallpaper it was computed for, and the cut-out subject. A key
  /// without a path means that picture has no subject.
  bool lockDepth;
  String? lockDepthKey;
  String? lockDepthPath;

  /// Saved wallpapers, each with its own lock and home screen setup as in iOS's gallery,
  /// stored as the [lookKeys] of [toJson]. [look] is the one in use.
  final List<Map<String, dynamic>> looks;
  int look;

  static const lookKeys = [
    'wallpaper', 'wallpaperPath', 'lockWallpaper', 'lockWallpaperPath', 'lockColor', 'lockWeight', 'lockWidgets', //
    'lockLeft',
    'lockRight',
    'lockFont',
    'lockSize',
    'lockStretch',
    'lockGlass',
    'lockFilter',
    'lockNotify',
    'lockInline',
    'lockFocus',
    'lockDepth',
    'lockDepthKey',
    'lockDepthPath', 'blurHome', 'dimHome',
  ];

  /// Names the lock wallpaper, so a depth cut-out can be matched to the picture it came from.
  String get lockKey {
    final path = lockWallpaper == null ? (lockWallpaperPath ?? wallpaperPath) : null;
    return path ?? 'preset-${lockWallpaper ?? wallpaper}';
  }

  Map<String, dynamic> currentLook() {
    final json = jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>;
    return {for (final key in lookKeys) key: json[key]};
  }

  /// These settings as they would be with [saved] in use.
  Settings withLook(Map<String, dynamic> saved) => Settings.fromJson({...toJson(), ...saved});

  void useLook(int index) {
    look = index.clamp(0, looks.length - 1);
    final s = withLook(looks[look]);
    wallpaper = s.wallpaper;
    wallpaperPath = s.wallpaperPath;
    lockWallpaper = s.lockWallpaper;
    lockWallpaperPath = s.lockWallpaperPath;
    lockColor = s.lockColor;
    lockWeight = s.lockWeight;
    lockWidgets = s.lockWidgets;
    lockLeft = s.lockLeft;
    lockRight = s.lockRight;
    lockFont = s.lockFont;
    lockSize = s.lockSize;
    lockStretch = s.lockStretch;
    lockGlass = s.lockGlass;
    lockFilter = s.lockFilter;
    lockNotify = s.lockNotify;
    lockInline = s.lockInline;
    lockFocus = s.lockFocus;
    lockDepth = s.lockDepth;
    lockDepthKey = s.lockDepthKey;
    lockDepthPath = s.lockDepthPath;
    blurHome = s.blurHome;
    dimHome = s.dimHome;
  }

  /// Keeps the look in use in step with every change made to it.
  void storeLook() {
    if (looks.isEmpty) look = 0;
    if (look >= looks.length) {
      looks.add(currentLook());
    } else {
      looks[look] = currentLook();
    }
  }

  /// iOS's home screen options: icons without names, a softened or darkened wallpaper, and
  /// the wallpaper shifting as the phone tilts.
  bool largeIcons;

  /// Apps and widgets close up to the top left instead of staying where they were put.
  bool compactHome;
  bool blurHome;
  bool dimHome;
  bool perspective;

  /// Widgets of the Today view, as "kind:size".
  List<String> today;
  int lockColor;
  List<String> lockWidgets;
  bool setupDone;

  /// Below [presetVersion], the saved layout is replaced by the current preset.
  int layoutVersion;

  /// Name of an [IconStyle], with the colour of the tinted style.
  String iconStyle;
  int iconTint;

  /// Whether the glass styles are light, dark or follow Android ("auto").
  String glassTone;

  void applyIconStyle() {
    IconStyle.current = IconStyle.values.asNameMap()[iconStyle] ?? IconStyle.standard;
    compactLayout = compactHome;
    IconStyle.tint = Color(iconTint);
    IconStyle.darkGlass = glassTone == 'dark' || (glassTone == 'auto' && PlatformDispatcher.instance.platformBrightness == Brightness.dark);
  }

  /// Which wallpapers Android was last given.
  String? systemWallpaper;

  /// Most recently opened apps, newest first.
  List<String> recent;

  Map<String, dynamic> toJson() => {
    'wallpaper': wallpaper,
    'wallpaperPath': wallpaperPath,
    'lockWallpaper': lockWallpaper,
    'lockWallpaperPath': lockWallpaperPath,
    'lockEnabled': lockEnabled,
    'lockWeight': lockWeight,
    'lockLeft': lockLeft,
    'lockRight': lockRight,
    'lockFont': lockFont,
    'lockSize': lockSize,
    'lockStretch': lockStretch,
    'lockGlass': lockGlass,
    'lockFilter': lockFilter,
    'lockNotify': lockNotify,
    'lockInline': lockInline,
    'lockFocus': lockFocus,
    'standBy': standBy,
    'note': note,
    'controls': controls,
    'lockDepth': lockDepth,
    'lockDepthKey': lockDepthKey,
    'lockDepthPath': lockDepthPath,
    'looks': looks,
    'look': look,
    'largeIcons': largeIcons,
    'compactHome': compactHome,
    'blurHome': blurHome,
    'dimHome': dimHome,
    'perspective': perspective,
    'today': today,
    'lockColor': lockColor,
    'lockWidgets': lockWidgets,
    'setupDone': setupDone,
    'layoutVersion': layoutVersion,
    'iconStyle': iconStyle,
    'iconTint': iconTint,
    'glassTone': glassTone,
    'systemWallpaper': systemWallpaper,
    'recent': recent,
  };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    wallpaper: j['wallpaper'] as int? ?? 0,
    wallpaperPath: j['wallpaperPath'] as String?,
    lockWallpaper: j['lockWallpaper'] as int?,
    lockWallpaperPath: j['lockWallpaperPath'] as String?,
    lockEnabled: j['lockEnabled'] as bool? ?? false,
    lockWeight: (j['lockWeight'] as num? ?? 600).toDouble(),
    lockLeft: j['lockLeft'] as String? ?? 'auto',
    lockRight: j['lockRight'] as String? ?? 'auto',
    lockFont: j['lockFont'] as String? ?? 'inter',
    lockSize: (j['lockSize'] as num? ?? 1).toDouble(),
    lockStretch: (j['lockStretch'] as num? ?? 1).toDouble(),
    lockGlass: j['lockGlass'] as bool? ?? false,
    lockFilter: j['lockFilter'] as String? ?? 'none',
    lockNotify: j['lockNotify'] as String? ?? 'stack',
    lockInline: j['lockInline'] as String? ?? 'none',
    lockFocus: j['lockFocus'] as bool? ?? false,
    standBy: j['standBy'] as bool? ?? true,
    note: j['note'] as String? ?? '',
    controls: (j['controls'] as List?)?.cast<String>(),
    lockDepth: j['lockDepth'] as bool? ?? true,
    lockDepthKey: j['lockDepthKey'] as String?,
    lockDepthPath: j['lockDepthPath'] as String?,
    looks: (j['looks'] as List?)?.map((l) => Map<String, dynamic>.from(l as Map)).toList(),
    look: j['look'] as int? ?? 0,
    largeIcons: j['largeIcons'] as bool? ?? false,
    compactHome: j['compactHome'] as bool? ?? false,
    blurHome: j['blurHome'] as bool? ?? false,
    dimHome: j['dimHome'] as bool? ?? false,
    perspective: j['perspective'] as bool? ?? true,
    today: (j['today'] as List?)?.cast<String>(),
    lockColor: j['lockColor'] as int? ?? 0xFFFFFFFF,
    lockWidgets: (j['lockWidgets'] as List?)?.cast<String>(),
    setupDone: j['setupDone'] as bool? ?? false,
    layoutVersion: j['layoutVersion'] as int? ?? 0,
    iconStyle: j['iconStyle'] as String? ?? 'standard',
    iconTint: j['iconTint'] as int? ?? 0xFF64D2FF,
    glassTone: j['glassTone'] as String? ?? 'dark',
    systemWallpaper: j['systemWallpaper'] as String?,
    recent: (j['recent'] as List?)?.cast<String>(),
  );

  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/settings.json');

  static Future<Settings> load() async {
    try {
      final file = await _file();
      if (await file.exists()) return Settings.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('settings.json unreadable: $e');
    }
    return Settings();
  }

  /// Saves one after another; the home and the lock screen also save at the same time, so each
  /// write goes through its own temporary file before replacing the real one.
  Future<void> save() => _saving = _saving.then((_) => _write()).catchError((Object e) => debugPrint('settings not saved: $e'));

  static Future<void> _saving = Future.value();

  Future<void> _write() async {
    final file = await _file();
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()));
    await tmp.rename(file.path);
  }
}

const presetVersion = 2;

class AppState extends ChangeNotifier {
  AppState(this.layout, this.settings, this._file);

  HomeLayout layout;

  /// Replaced when the lock screen, which stays alive, reads changes made on the home screen.
  Settings settings;
  final File _file;
  Map<String, AppInfo> apps = {};
  DeviceStatus status = const DeviceStatus();
  Map<String, int> badges = {};
  List<Alert> alerts = [];
  Media? media;
  Weather? weather;
  List<Event> events = [];
  Map<String, bool> permissions = {};
  List<String> androidShortcuts = [];

  /// World clock cities with their current offset from UTC in seconds.
  Map<String, int> zones = {};

  /// A picture for the photos widget, chosen anew every hour.
  Uint8List? photo;
  DateTime _photoAt = DateTime(0);
  StreamSubscription<String>? _events;
  Timer? _timer;

  static Future<AppState> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/layout.json');
    final settings = await Settings.load()
      ..applyIconStyle();
    var layout = HomeLayout();
    try {
      if (settings.layoutVersion >= presetVersion && await file.exists()) {
        layout = HomeLayout.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('layout.json unreadable: $e');
      await file.rename('${file.path}.corrupt');
    }
    final state = AppState(layout, settings, file);
    await state.reloadApps();
    await state.refresh();
    state._events = Native.events.listen((event) async {
      if (event == 'apps') state.reloadApps();
      if (event == 'changed') {
        await state._reloadIfChanged();
        // Android may have changed between light and dark meanwhile.
        state.settings.applyIconStyle();
        state._syncSystemWallpaper();
        state._syncDepth();
        state.refresh();
      }
    });
    state._timer = Timer.periodic(const Duration(seconds: 30), (_) => state.refresh());
    state._syncSystemWallpaper();
    state._syncDepth();
    Native.call('tilt', settings.perspective || settings.standBy);
    return state;
  }

  /// The lock screen only reads: the layout file belongs to the home screen.
  static Future<AppState> loadForLock() async {
    final dir = await getApplicationDocumentsDirectory();
    final state = AppState(
      HomeLayout(),
      await Settings.load()
        ..applyIconStyle(),
      File('${dir.path}/unused'),
    ).._lock = true;
    state.apps = {for (final a in await Native.apps()) a.key: a};
    await state.refresh();
    state._events = Native.events.listen((event) async {
      if (event != 'changed') return;
      state.settings = await Settings.load()
        ..applyIconStyle();
      Native.call('tilt', state.settings.perspective || state.settings.standBy);
      state.refresh();
    });
    Native.call('tilt', state.settings.perspective || state.settings.standBy);
    state._timer = Timer.periodic(const Duration(seconds: 30), (_) => state.refresh());
    return state;
  }

  Future<void> reloadApps() async {
    final list = await Native.apps();
    Native.forgetIcons();
    apps = {for (final a in list) a.key: a};
    if (layout.seen.isEmpty) {
      layout = presetLayout(list, await Native.defaults());
      settings
        ..layoutVersion = presetVersion
        ..setupDone = false
        ..lockWeight = 600;
      await settings.save();
    } else {
      layout.sync(list.map((a) => a.key));
    }
    notifyListeners();
    await saveLayout();
  }

  /// First app with this iOS role, for the widgets that open one.
  AppInfo? appFor(Role role) {
    for (final app in apps.values) {
      if (app.role == role) return app;
    }
    return null;
  }

  /// A launcher must keep working whatever a system service does, so each part may fail alone.
  Future<void> refresh() async {
    Future<void> attempt(Future<void> Function() part) async {
      try {
        await part();
      } catch (e) {
        debugPrint('refresh: $e');
      }
    }

    await attempt(() async => status = await Native.status());
    await attempt(() async => permissions = await Native.permissions());
    await attempt(() async => alerts = await Native.notifications());
    await attempt(() async => media = await Native.media());
    await attempt(() async => weather = await Native.weather() ?? weather);
    await attempt(() async => events = await Native.events_());
    await attempt(() async => androidShortcuts = await Native.lockShortcuts());
    await attempt(() async => zones = await Native.zones());
    if (permissions['photos'] == true && DateTime.now().difference(_photoAt) > const Duration(hours: 1)) {
      await attempt(() async {
        final now = DateTime.now();
        photo = await Native.photo(now.day * 24 + now.hour);
        _photoAt = now;
      });
    }
    final counts = <String, int>{};
    for (final a in alerts) {
      counts[a.package] = (counts[a.package] ?? 0) + 1;
    }
    badges = counts;
    notifyListeners();
  }

  /// One save after another, each through its own temporary file: app changes can start
  /// several at once.
  Future<void> saveLayout() => _layoutSaving = _layoutSaving
      .then((_) async {
        final tmp = File('${_file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
        await tmp.writeAsString(jsonEncode(layout.toJson()));
        await tmp.rename(_file.path);
      })
      .catchError((Object e) => debugPrint('layout not saved: $e'));

  Future<void> _layoutSaving = Future.value();

  /// Redraws without saving, while a slider is being dragged.
  void repaint() => notifyListeners();

  /// Saves and redraws after the layout or the settings changed.
  void commit() {
    settings.storeLook();
    notifyListeners();
    saveLayout();
    settings.save();
    if (!_lock) {
      _syncSystemWallpaper();
      _syncDepth();
    }
    Native.call('tilt', settings.perspective || settings.standBy);
  }

  /// The lock screen's copy. It leaves Android's wallpaper and the depth cut-out to the home
  /// screen: setting the wallpaper restarts the lock screen on Samsung, which then shows black.
  bool _lock = false;

  /// Switches to a saved look; [index] past the end saves the current one as a new look.
  void chooseLook(int index) {
    if (index >= settings.looks.length) {
      settings
        ..storeLook()
        ..looks.add(settings.currentLook())
        ..look = settings.looks.length - 1;
    } else {
      settings.useLook(index);
    }
    // A look linked to a Focus switches Do Not Disturb with it, once any look uses that.
    if (settings.looks.any((l) => l['lockFocus'] == true)) Native.call('doNotDisturb', settings.lockFocus);
    commit();
    // The lock screen runs its own copy of the settings; once the file is written, the home
    // screen reads it at once instead of on its next return, and can't write over it meanwhile.
    settings.save().then((_) => Native.call('settingsChanged'));
  }

  /// The lock screen saves too, when a look is picked there; the home screen follows.
  Future<void> _reloadIfChanged() async {
    final saved = await Settings.load();
    if (jsonEncode(saved.toJson()) == jsonEncode(settings.toJson())) return;
    settings = saved..applyIconStyle();
    notifyListeners();
  }

  void deleteLook(int index) {
    if (settings.looks.length <= 1) return;
    settings.looks.removeAt(index);
    settings.useLook(index <= settings.look ? max(0, settings.look - 1) : settings.look);
    commit();
  }

  bool _depthBusy = false;
  var _depthTries = 0;

  /// Cuts the subject out of the lock wallpaper once per picture, in the background.
  Future<void> _syncDepth() async {
    final s = settings;
    final lockPath = s.lockWallpaper == null ? (s.lockWallpaperPath ?? s.wallpaperPath) : null;
    final lockPreset = s.lockWallpaper ?? s.wallpaper;
    final wanted = s.lockKey;
    final have = wanted == s.lockDepthKey && (s.lockDepthPath == null || File(s.lockDepthPath!).existsSync());
    if (!s.lockDepth || have || _depthBusy) return;
    _depthBusy = true;
    try {
      final path = await Native.depthCutout(await Wallpaper.bytes(lockPreset, lockPath));
      if (path != null) {
        s
          ..lockDepthKey = wanted
          ..lockDepthPath = path.isEmpty ? null : path;
        await s.save();
        notifyListeners();
      } else if (_depthTries++ < 15) {
        // Play services is still fetching the model, which takes a minute or two at first.
        Future<void>.delayed(const Duration(minutes: 1), _syncDepth);
      }
    } catch (e) {
      debugPrint('depth: $e');
    } finally {
      _depthBusy = false;
    }
  }

  /// Android's recents screen and PIN prompt can't be restyled, but they show the system's
  /// wallpapers, so those follow the ones chosen in Glas.
  Future<void> _syncSystemWallpaper() async {
    if (_lock) return;
    // Only while the home screen is in front, never under the lock screen.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final s = settings;
    final lockPath = s.lockWallpaper == null ? (s.lockWallpaperPath ?? s.wallpaperPath) : null;
    final lockPreset = s.lockWallpaper ?? s.wallpaper;
    final wanted = '${s.wallpaperPath ?? s.wallpaper}|${lockPath ?? lockPreset}';
    if (wanted == s.systemWallpaper) return;
    final previous = s.systemWallpaper;
    s.systemWallpaper = wanted;
    try {
      final done = await Native.setSystemWallpaper(await Wallpaper.bytes(s.wallpaper, s.wallpaperPath), await Wallpaper.bytes(lockPreset, lockPath));
      if (!done) s.systemWallpaper = previous;
    } catch (e) {
      debugPrint('system wallpaper: $e');
      s.systemWallpaper = previous;
    }
    await s.save();
  }

  /// [choice] is a saved corner setting; the result never is "auto".
  String lockShortcut(String choice, int corner) {
    if (choice != 'auto') return choice;
    if (androidShortcuts.length > corner) return androidShortcuts[corner];
    return const ['torch', 'camera'][corner];
  }

  void launch(AppInfo app, BuildContext? iconContext) {
    Rect? origin;
    final box = iconContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final ratio = MediaQuery.of(iconContext!).devicePixelRatio;
      final topLeft = box.localToGlobal(Offset.zero) * ratio;
      origin = topLeft & (box.size * ratio);
    }
    settings.recent
      ..remove(app.key)
      ..insert(0, app.key);
    if (settings.recent.length > 8) settings.recent.removeLast();
    settings.save();
    Native.launch(app, origin);
  }

  @override
  void dispose() {
    _events?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
