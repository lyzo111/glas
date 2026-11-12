import 'package:flutter_test/flutter_test.dart';
import 'package:glas/layout.dart';

List<String> keys(int n) => [for (var i = 0; i < n; i++) 'a/$i'];
List<String> ids(List<HomeItem> items) => items.map((i) => i.id).toList();

void main() {
  placementTests();
  group('pack', () {
    test('füllt Zeile für Zeile', () {
      final slots = pack([for (final k in keys(5)) AppItem(k)]);
      expect([slots[3].column, slots[3].row], [3, 0]);
      expect([slots[4].column, slots[4].row], [0, 1]);
    });

    test('Apps fließen um Widgets herum', () {
      final slots = pack([AppItem('a'), WidgetItem('w', WidgetKind.clock), AppItem('b'), AppItem('c'), AppItem('d')]);
      expect([slots[1].column, slots[1].row], [1, 0]);
      expect([slots[2].column, slots[2].row], [3, 0]);
      expect([slots[3].column, slots[3].row], [0, 1]);
      expect([slots[4].column, slots[4].row], [3, 1]);
    });

    test('überlappt nie und meldet den Überlauf', () {
      final items = <HomeItem>[WidgetItem('t', WidgetKind.music), WidgetItem('c', WidgetKind.clock), for (final k in keys(30)) AppItem(k)];
      final slots = pack(items);
      expect(slots, hasLength(2 + 12));
      final cells = <String>{};
      for (final s in slots) {
        for (var y = 0; y < s.item.height; y++) {
          for (var x = 0; x < s.item.width; x++) {
            expect(cells.add('${s.column + x},${s.row + y}'), isTrue);
          }
        }
      }
      expect(cells.length, columns * rows);
    });
  });

  group('sync', () {
    test('neue Apps kommen ans Ende, volle Seiten laufen über', () {
      final l = HomeLayout()..sync(keys(30));
      expect(l.pages, hasLength(2));
      expect(l.pages[0], hasLength(24));
      expect(l.pages[1], hasLength(6));
    });

    test('deinstallierte Apps verschwinden, auch aus Ordnern', () {
      final l = HomeLayout()..sync(keys(3));
      l.merge(const Place(0, 1), const Place(0, 0));
      expect(l.pages[0].first, isA<FolderItem>());
      l.sync(['a/0', 'a/2']);
      expect(ids(l.pages[0]), ['a/0', 'a/2']);
    });

    test('vom Home entfernte App bleibt weg und kann zurück', () {
      final l = HomeLayout()..sync(keys(2));
      l.remove(l.pages[0].first);
      l.sync(keys(2));
      expect(ids(l.pages[0]), ['a/1']);
      l.addApp('a/0');
      l.addApp('a/0');
      expect(ids(l.pages[0]), ['a/1', 'a/0']);
    });
  });

  group('Verschieben', () {
    test('innerhalb einer Seite', () {
      final l = HomeLayout()..sync(keys(4));
      l.move(const Place(0, 3), const Place(0, 0));
      expect(ids(l.pages[0]), ['a/3', 'a/0', 'a/1', 'a/2']);
    });

    test('in das Dock, das maximal vier Plätze hat', () {
      final l = HomeLayout()..sync(keys(6));
      for (var i = 0; i < 4; i++) {
        expect(l.move(const Place(0, 0), Place(Place.dock, i)), isTrue);
      }
      expect(l.move(const Place(0, 0), const Place(Place.dock, 0)), isFalse);
      expect(l.dock, hasLength(4));
      expect(l.pages[0], hasLength(2));
    });

    test('Widgets dürfen nicht ins Dock', () {
      final l = HomeLayout()..sync(keys(1));
      l.addWidget(WidgetKind.clock, 0);
      final widget = l.pages[0].indexWhere((i) => i is WidgetItem);
      expect(l.move(Place(0, widget), const Place(Place.dock, 0)), isFalse);
    });

    test('auf volle Seite schiebt den Rest weiter', () {
      final l = HomeLayout()..sync(keys(25));
      l.move(const Place(1, 0), const Place(0, 0));
      expect(ids(l.pages[0]).first, 'a/24');
      expect(l.pages[0], hasLength(24));
      expect(ids(l.pages[1]), ['a/23']);
    });

    test('leere Seiten verschwinden', () {
      final l = HomeLayout()..sync(keys(25));
      l.move(const Place(1, 0), const Place(0, 23));
      l.move(const Place(1, 0), const Place(0, 0));
      expect(l.pages.length, 2);
      l.remove(l.pages[1].first);
      expect(l.pages, hasLength(1));
    });
  });

  group('Ordner', () {
    test('entsteht aus zwei Apps und nimmt weitere auf', () {
      final l = HomeLayout()..sync(keys(3));
      l.merge(const Place(0, 1), const Place(0, 0));
      l.merge(const Place(0, 1), const Place(0, 0));
      expect((l.pages[0].single as FolderItem).apps, keys(3));
    });

    test('nimmt jede App nur einmal auf und räumt Doppelte beim Abgleich auf', () {
      final l = HomeLayout()..sync(keys(4));
      l.merge(const Place(0, 1), const Place(0, 0));
      final folder = l.pages[0][0] as FolderItem;
      l.addApp('a/1');
      expect(l.pages[0].whereType<AppItem>().map((a) => a.key), ['a/2', 'a/3']);
      folder.apps.addAll(['a/1', 'a/1']);
      l.sync(keys(4));
      expect(folder.apps, ['a/0', 'a/1']);
    });

    test('löst sich auf, wenn nur eine App übrig bleibt', () {
      final l = HomeLayout()..sync(keys(2));
      l.merge(const Place(0, 1), const Place(0, 0));
      l.removeFromFolder(l.pages[0].single as FolderItem, 'a/1');
      expect(ids(l.pages[0]), ['a/0', 'a/1']);
    });

    test('Widgets und Ordner lassen sich nicht zusammenlegen', () {
      final l = HomeLayout()..sync(keys(2));
      l.addWidget(WidgetKind.clock, 0);
      final widget = l.pages[0].indexWhere((i) => i is WidgetItem);
      final app = l.pages[0].indexWhere((i) => i is AppItem);
      expect(l.merge(Place(0, app), Place(0, widget)), isFalse);
      expect(l.merge(Place(0, widget), Place(0, app)), isFalse);
    });
  });

  test('übersteht Speichern und Laden', () {
    final l = HomeLayout()..sync(keys(5));
    l.addWidget(WidgetKind.music, 0);
    l.merge(const Place(0, 2), const Place(0, 1));
    l.move(const Place(0, 1), const Place(Place.dock, 0));
    final again = HomeLayout.fromJson(l.toJson());
    expect(again.toJson().toString(), l.toJson().toString());
    expect(again.seen, l.seen);
  });

  group('Rechner', () {
    test('rechnet mit Punkt vor Strich und Klammern', () {
      expect(calculate('2+3*4'), 14);
      expect(calculate('(2+3)*4'), 20);
      expect(calculate('12,5 / 5'), 2.5);
      expect(calculate('-3+5'), 2);
      expect(calculate('3 × 3'), 9);
    });

    test('ignoriert alles andere', () {
      expect(calculate('chrome'), isNull);
      expect(calculate('42'), isNull);
      expect(calculate('2+'), isNull);
      expect(calculate('1/0'), isNull);
      expect(calculate('(2'), isNull);
    });
  });
}

void placementTests() {
  group('Lückenlos anordnen', () {
    HomeLayout page(int apps) => HomeLayout()..sync(keys(apps));
    tearDown(() => compactLayout = false);

    test('eine App auf leerem Feld rückt ans Ende auf', () {
      compactLayout = true;
      final l = page(3);
      final item = l.pages[0][0];
      l.drop(item, 0, 2, 4);
      expect(ids(l.pages[0]), ['a/1', 'a/2', 'a/0']);
      expect(
        [
          for (final s in pack(l.pages[0])) [s.column, s.row],
        ],
        [
          [0, 0],
          [1, 0],
          [2, 0],
        ],
      );
    });

    test('zwischen zwei Apps abgelegt, reiht sie sich dort ein', () {
      compactLayout = true;
      final l = page(5);
      final item = l.pages[0][4];
      l.drop(item, 0, 1, 0);
      expect(ids(l.pages[0]), ['a/0', 'a/4', 'a/1', 'a/2', 'a/3']);
    });

    test('gespeicherte Lücken zählen nicht, kommen beim Ausschalten aber nicht zurück', () {
      final l = page(3);
      final item = l.pages[0][0];
      l.pin(0);
      l.drop(item, 0, 2, 4);
      compactLayout = true;
      expect([for (final s in pack(l.pages[0])) s.row], [0, 0, 0]);
      l.pin(0);
      compactLayout = false;
      expect([for (final s in pack(l.pages[0])) s.row], [0, 0, 0]);
    });
  });

  group('Freie Platzierung', () {
    HomeLayout page(int apps) => HomeLayout()..sync(keys(apps));

    test('eine App lässt sich auf ein leeres Feld setzen, die anderen bleiben', () {
      final l = page(3);
      final item = l.pages[0][0];
      l.pin(0);
      l.drop(item, 0, 2, 4);
      expect([item.column, item.row], [2, 4]);
      expect(pack(l.pages[0]).where((s) => s.item != item).map((s) => [s.column, s.row]), [
        [1, 0],
        [2, 0],
      ]);
    });

    test('nur was überdeckt wird, weicht aus', () {
      final l = page(8);
      l.pin(0);
      final widget = WidgetItem('w', WidgetKind.clock);
      l.pages[0].add(widget);
      l.drop(widget, 0, 0, 0);
      final slots = pack(l.pages[0]);
      expect(slots.firstWhere((s) => s.item == widget).row, 0);
      final bystander = slots.firstWhere((s) => (s.item as dynamic).id == 'a/3');
      expect([bystander.column, bystander.row], [3, 0]);
      expect(slots, hasLength(9));
    });

    test('hin und zurück ergibt wieder Platz an der alten Stelle', () {
      final l = page(4)..addWidget(WidgetKind.clock, 0);
      l.pin(0);
      final widget = l.pages[0].first;
      l.drop(widget, 0, 0, 3);
      l.drop(widget, 0, 0, 0);
      expect([widget.column, widget.row], [0, 0]);
      final cells = <String>{};
      for (final s in pack(l.pages[0])) {
        for (var y = 0; y < s.item.height; y++) {
          for (var x = 0; x < s.item.width; x++) {
            expect(cells.add('${s.column + x},${s.row + y}'), isTrue);
          }
        }
      }
    });

    test('Widgets rasten links oder rechts ein', () {
      expect(snapCell(WidgetItem('w', WidgetKind.clock), 1, 9), (2, 4));
      expect(snapCell(WidgetItem('m', WidgetKind.music), 3, 2), (0, 2));
    });

    test('auf voller Seite wandert der Überlauf auf die nächste', () {
      final l = page(24);
      l.pin(0);
      final widget = WidgetItem('w', WidgetKind.clock);
      l.pages[0].add(widget);
      l.drop(widget, 0, 0, 0);
      expect(pack(l.pages[0]).length, 21);
      expect(l.pages[1], hasLength(4));
    });

    test('Größe ändern schiebt, was im Weg ist', () {
      final l = page(8)..addWidget(WidgetKind.music, 0);
      final widget = l.pages[0].whereType<WidgetItem>().first;
      l.resize(widget, WidgetSize.small);
      expect([widget.width, widget.height], [2, 2]);
      l.resize(widget, WidgetSize.large);
      expect(widget.height, 4);
      expect(pack(l.pages[0]).any((s) => s.item == widget), isTrue);
      expect(pack(l.pages[0]), hasLength(9));
    });

    test('neues Widget geht in die erste passende Lücke, ohne etwas zu verschieben', () {
      final l = page(8)..pin(0);
      final before = {for (final s in pack(l.pages[0])) s.item.id: (s.column, s.row)};
      l.addWidget(WidgetKind.clock, 0);
      final slots = pack(l.pages[0]);
      final widget = slots.firstWhere((s) => s.item is WidgetItem);
      expect([widget.column, widget.row], [0, 2]);
      for (final s in slots.where((s) => s.item is! WidgetItem)) {
        expect((s.column, s.row), before[s.item.id]);
      }
      expect(l.pages, hasLength(1));
    });

    test('ein Stapel behält Widgets anderer Apps und gibt ihre Ids zurück', () {
      final item = WidgetItem('w', WidgetKind.clock, WidgetSize.small, [
        StackEntry(WidgetKind.app, hostId: 7, provider: 'p/.W', title: 'Duo'),
        StackEntry(WidgetKind.battery),
      ]);
      final loaded = HomeItem.fromJson(item.toJson()) as WidgetItem;
      expect([for (final face in loaded.faces) face.kind], [WidgetKind.clock, WidgetKind.app, WidgetKind.battery]);
      expect([loaded.faces[1].hostId, loaded.faces[1].title], [7, 'Duo']);
      expect(loaded.hostIds, [7]);
      final l = HomeLayout();
      expect(l.removeFromStack(loaded, 0), null);
      expect([loaded.kind, loaded.hostId, loaded.provider], [WidgetKind.app, 7, 'p/.W']);
      expect(l.removeFromStack(loaded, 0), 7);
      expect([loaded.kind, loaded.hostId, loaded.stack], [WidgetKind.battery, null, isEmpty]);
    });

    test('ein Stapel bietet nur Größen an, die alle seine Widgets haben', () {
      final clock = WidgetItem('w', WidgetKind.clock);
      expect(clock.sizes, [WidgetSize.small, WidgetSize.medium]);
      clock.stack.add(StackEntry(WidgetKind.month));
      expect(clock.sizes, [WidgetSize.small]);
      clock.stack.add(StackEntry(WidgetKind.app, hostId: 3));
      expect(clock.sizes, [WidgetSize.small]);
      expect(WidgetItem('a', WidgetKind.app, WidgetSize.medium).sizes, WidgetSize.values);
    });

    test('eine App von einer ausgeblendeten Seite zieht um statt doppelt zu sein', () {
      final l = HomeLayout()..sync(keys(30));
      final key = (l.pages[1].first as AppItem).key;
      l.hidePage(1);
      l.addApp(key);
      expect(l.pages.expand((p) => p).where((i) => i.id == key), hasLength(1));
      expect(l.hidden.expand((p) => p).where((i) => i.id == key), isEmpty);
    });

    test('Position und Größe überstehen Speichern, alte Widgets werden erkannt', () {
      final l = page(2)..addWidget(WidgetKind.weather, 0, WidgetSize.large);
      l.pin(0);
      final again = HomeLayout.fromJson(l.toJson());
      expect(again.toJson().toString(), l.toJson().toString());
      final old = HomeItem.fromJson({'type': 'widget', 'id': 'x', 'kind': 'weatherWide'}) as WidgetItem;
      expect([old.kind, old.size], [WidgetKind.weather, WidgetSize.medium]);
      final agenda = HomeItem.fromJson({'type': 'widget', 'id': 'y', 'kind': 'agenda'}) as WidgetItem;
      expect([agenda.kind, agenda.size], [WidgetKind.calendar, WidgetSize.medium]);
    });
  });
}
