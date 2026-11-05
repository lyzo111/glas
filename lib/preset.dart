import 'icons.dart';
import 'layout.dart';
import 'native.dart';

/// Third-party apps a new phone would have out on the first page, most popular first.
const _quickApps = [
  'com.whatsapp',
  'com.instagram.android',
  'com.spotify.music',
  'com.google.android.youtube',
  'org.thoughtcrime.securesms',
  'com.netflix.mediaclient',
  'org.telegram.messenger',
  'com.discord',
  'com.amazon.mShop.android.shopping',
  'com.paypal.android.p2pmobile',
];

const _firstPage = [
  Role.photos, Role.camera, Role.clock, Role.maps, //
  Role.mail, Role.notes, Role.reminders, Role.calculator,
  Role.store, Role.files, Role.health, Role.settings,
];

const _folderOrder = ['Soziale Netzwerke', 'Unterhaltung', 'Produktivität', 'Reisen', 'Nachrichten', 'Spiele', 'Kreativität', 'Dienstprogramme'];

/// The home screen of a freshly unboxed phone, built from what is installed. Everything else
/// waits in the App Library, as on iOS, so a phone with 300 apps still starts out tidy.
HomeLayout presetLayout(List<AppInfo> apps, Map<String, String> defaults) {
  final used = <String>{};

  AppInfo? take(bool Function(AppInfo) test) {
    for (final app in apps) {
      if (!used.contains(app.key) && test(app)) {
        used.add(app.key);
        return app;
      }
    }
    return null;
  }

  AppInfo? byRole(Role role) => take((a) => a.role == role);
  AppInfo? byPackage(String? package) => package == null ? null : take((a) => a.package == package);

  final dock = <HomeItem>[
    for (final app in [
      byPackage(defaults['phone']) ?? byRole(Role.phone),
      byPackage(defaults['browser']) ?? byRole(Role.safari),
      byPackage(defaults['sms']) ?? byRole(Role.messages),
      byRole(Role.music) ?? byPackage('com.spotify.music') ?? byPackage('com.sec.android.app.music'),
    ])
      if (app != null) AppItem(app.key),
  ];

  final first = <HomeItem>[
    WidgetItem('preset-weather', WidgetKind.weather, WidgetSize.small),
    WidgetItem('preset-calendar', WidgetKind.calendar),
    for (final role in _firstPage)
      if (byRole(role) case final app?) AppItem(app.key),
  ];
  for (final package in _quickApps) {
    if (overflowIndex([...first, AppItem('probe')]) <= first.length) break;
    if (byPackage(package) case final app?) first.add(AppItem(app.key));
  }

  final second = <HomeItem>[
    WidgetItem('preset-music', WidgetKind.music),
    WidgetItem('preset-clock', WidgetKind.clock),
    WidgetItem('preset-battery', WidgetKind.battery),
  ];
  final groups = <String, List<String>>{};
  for (final app in apps) {
    if (!used.contains(app.key)) groups.putIfAbsent(app.category, () => []).add(app.key);
  }
  for (final name in _folderOrder) {
    final keys = groups[name];
    if (keys == null || keys.length < 2) continue;
    if (overflowIndex([...second, AppItem('probe')]) <= second.length) break;
    final label = name == 'Dienstprogramme' ? 'Extras' : name;
    second.add(FolderItem('preset-$name', label, keys.take(folderCapacity).toList()));
  }

  return HomeLayout(pages: [first, second], dock: dock, seen: apps.map((a) => a.key).toSet());
}
