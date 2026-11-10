import 'package:flutter_test/flutter_test.dart';
import 'package:glas/icons.dart';
import 'package:glas/layout.dart';
import 'package:glas/native.dart';
import 'package:glas/preset.dart';

AppInfo app(String package, [String category = 'Sonstige']) => AppInfo(package, 'Main', package, category);

const samsung = [
  'com.samsung.android.dialer',
  'com.sec.android.app.sbrowser',
  'com.samsung.android.messaging',
  'com.apple.android.music',
  'com.sec.android.gallery3d',
  'com.sec.android.app.camera',
  'com.sec.android.app.clockpackage',
  'com.google.android.apps.maps',
  'com.google.android.gm',
  'com.samsung.android.app.notes',
  'com.samsung.android.app.reminder',
  'com.sec.android.app.popupcalculator',
  'com.android.vending',
  'com.sec.android.app.myfiles',
  'com.sec.android.app.shealth',
  'com.android.settings',
  'com.whatsapp',
  'com.instagram.android',
  'com.spotify.music',
  'com.google.android.youtube',
];

void main() {
  roleTests();
  final apps = [for (final p in samsung) app(p), for (var i = 0; i < 300; i++) app('org.app$i', i.isEven ? 'Soziale Netzwerke' : 'Unterhaltung')];

  test('Dock ist Telefon, Browser, Nachrichten, Musik', () {
    final l = presetLayout(apps, {'phone': 'com.samsung.android.dialer', 'sms': 'com.samsung.android.messaging'});
    expect(l.dock.map((i) => (i as AppItem).key.split('/').first), [
      'com.samsung.android.dialer',
      'com.sec.android.app.sbrowser',
      'com.samsung.android.messaging',
      'com.apple.android.music',
    ]);
  });

  test('erste Seite ist voll belegt, passt und beginnt mit Widgets', () {
    final l = presetLayout(apps, const {});
    expect(l.pages, hasLength(2));
    expect(l.pages[0].take(2).every((i) => i is WidgetItem), isTrue);
    expect(overflowIndex(l.pages[0]), l.pages[0].length);
    expect(pack(l.pages[0]).fold<int>(0, (n, s) => n + s.item.width * s.item.height), columns * rows);
  });

  test('der Rest bleibt in Ordnern und der Mediathek', () {
    final l = presetLayout(apps, const {});
    expect(overflowIndex(l.pages[1]), l.pages[1].length);
    expect(l.pages[1].whereType<FolderItem>().map((f) => f.name), containsAll(['Soziale Netzwerke', 'Unterhaltung']));
    expect(l.seen, hasLength(apps.length));
    l.sync(apps.map((a) => a.key));
    expect(l.pages, hasLength(2));
  });

  test('keine App erscheint doppelt', () {
    final l = presetLayout(apps, const {});
    final keys = [
      for (final item in l.all)
        if (item is AppItem) item.key else if (item is FolderItem) ...item.apps,
    ];
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('kommt mit einem leeren Gerät klar', () {
    final l = presetLayout([app('a')], const {});
    expect(l.dock, isEmpty);
    expect(overflowIndex(l.pages[0]), l.pages[0].length);
  });
}

void roleTests() {
  test('von zwei Wallets wird nur Samsungs zur iOS-App', () {
    expect(rolesTaken({'com.samsung.android.spay', 'com.google.android.apps.walletnfcrel'}, {}), {'com.google.android.apps.walletnfcrel'});
  });

  test('die Standard-App gewinnt ihre Rolle', () {
    expect(rolesTaken({'com.samsung.android.messaging', 'com.google.android.apps.messaging'}, {'com.google.android.apps.messaging'}), {
      'com.samsung.android.messaging',
    });
  });
}
