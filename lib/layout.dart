import 'dart:math';

const columns = 4;
const rows = 6;
const dockSize = 4;
const folderCapacity = 27;

enum WidgetSize {
  small('Klein', 2, 2),
  medium('Mittel', 4, 2),
  large('Groß', 4, 4);

  const WidgetSize(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;
}

enum WidgetKind {
  weather('Wetter', [WidgetSize.small, WidgetSize.medium, WidgetSize.large]),
  calendar('Kalender', [WidgetSize.small, WidgetSize.medium, WidgetSize.large]),
  month('Monat', [WidgetSize.small]),
  clock('Uhr', [WidgetSize.small, WidgetSize.medium]),
  battery('Batterien', [WidgetSize.small, WidgetSize.medium]),
  music('Musik', [WidgetSize.medium, WidgetSize.small]),
  worldClock('Weltuhr', [WidgetSize.medium, WidgetSize.small]),
  note('Notiz', [WidgetSize.small, WidgetSize.medium]),
  shortcuts('Kurzbefehle', [WidgetSize.medium, WidgetSize.small]),
  photos('Fotos', [WidgetSize.small, WidgetSize.medium, WidgetSize.large]),
  date('Datum', [WidgetSize.small]);

  const WidgetKind(this.label, this.sizes);
  final String label;

  /// The first size is the one a new widget gets.
  final List<WidgetSize> sizes;
}

/// Something on the home screen. [id] is stable across rearranging.
sealed class HomeItem {
  String get id;
  int get width => 1;
  int get height => 1;

  /// Grid position once the user placed something on this page; null flows into the first gap.
  int? column;
  int? row;

  Map<String, dynamic> get _cell => column == null ? const {} : {'column': column, 'row': row};
  Map<String, dynamic> toJson();

  static HomeItem fromJson(Map<String, dynamic> j) {
    final item = switch (j['type']) {
      'app' => AppItem(j['key'] as String),
      'folder' => FolderItem(j['id'] as String, j['name'] as String, (j['apps'] as List).cast<String>()),
      _ => _widget(j),
    };
    return item
      ..column = j['column'] as int?
      ..row = j['row'] as int?;
  }

  static WidgetItem _widget(Map<String, dynamic> j) {
    // Version 2.0 kept sizes in the kind's name.
    final (kind, size) = switch (j['kind']) {
      'weatherWide' => (WidgetKind.weather, WidgetSize.medium),
      'agenda' => (WidgetKind.calendar, WidgetSize.medium),
      final String name => (WidgetKind.values.byName(name), null),
      _ => throw const FormatException('widget without kind'),
    };
    final saved = j['size'] as String?;
    final stack = [for (final name in j['stack'] as List? ?? const []) ?WidgetKind.values.asNameMap()[name]];
    return WidgetItem(j['id'] as String, kind, saved == null ? size : WidgetSize.values.byName(saved), stack);
  }
}

class AppItem extends HomeItem {
  AppItem(this.key);

  /// "package/activity"
  final String key;

  @override
  String get id => key;

  @override
  Map<String, dynamic> toJson() => {'type': 'app', 'key': key, ..._cell};
}

class FolderItem extends HomeItem {
  FolderItem(this.id, this.name, this.apps);

  @override
  final String id;
  String name;
  final List<String> apps;

  @override
  Map<String, dynamic> toJson() => {'type': 'folder', 'id': id, 'name': name, 'apps': apps, ..._cell};
}

class WidgetItem extends HomeItem {
  WidgetItem(this.id, this.kind, [WidgetSize? size, List<WidgetKind>? stack]) : size = size ?? kind.sizes.first, stack = stack ?? [];

  /// Further widgets of the same size, swiped through in one place: iOS's widget stack.
  final List<WidgetKind> stack;

  @override
  final String id;

  /// The widget showing first; changes when it is taken out of its stack.
  WidgetKind kind;
  WidgetSize size;

  @override
  int get width => size.width;

  @override
  int get height => size.height;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'widget',
    'id': id,
    'kind': kind.name,
    'size': size.name,
    if (stack.isNotEmpty) 'stack': [for (final k in stack) k.name],
    ..._cell,
  };
}

/// Free space held open under a dragged item; never saved.
class GapItem extends HomeItem {
  GapItem(this.width, this.height);

  @override
  final int width;
  @override
  final int height;
  @override
  String get id => 'gap';
  @override
  Map<String, dynamic> toJson() => throw UnsupportedError('GapItem is not saved');
}

/// Grid position of an item, in cells.
class Slot {
  const Slot(this.column, this.row, this.item);
  final int column;
  final int row;
  final HomeItem item;

  bool overlaps(int c, int r, int w, int h) => column < c + w && c < column + item.width && row < r + h && r < row + item.height;
}

List<List<bool>> _grid() => List.generate(rows, (_) => List.filled(columns, false));

void _mark(List<List<bool>> used, int c, int r, HomeItem item) {
  for (var y = r; y < r + item.height; y++) {
    for (var x = c; x < c + item.width; x++) {
      used[y][x] = true;
    }
  }
}

bool _free(List<List<bool>> used, int c, int r, HomeItem item) {
  if (c < 0 || r < 0 || c + item.width > columns || r + item.height > rows) return false;
  for (var y = r; y < r + item.height; y++) {
    for (var x = c; x < c + item.width; x++) {
      if (used[y][x]) return false;
    }
  }
  return true;
}

/// Places items where the user put them; the rest flow in order around them, each into the
/// first free spot. Flowing items that no longer fit are left out.
List<Slot> pack(List<HomeItem> items) {
  final used = _grid();
  final pinned = <HomeItem>{};
  for (final item in items) {
    final c = item.column, r = item.row;
    if (c != null && r != null && _free(used, c, r, item)) {
      _mark(used, c, r, item);
      pinned.add(item);
    }
  }
  final slots = <Slot>[];
  var full = false;
  for (final item in items) {
    if (pinned.contains(item)) {
      slots.add(Slot(item.column!, item.row!, item));
      continue;
    }
    final spot = full ? null : _firstFree(used, item);
    if (spot == null) {
      full = true;
      continue;
    }
    final (c, r) = spot;
    _mark(used, c, r, item);
    slots.add(Slot(c, r, item));
  }
  return slots;
}

(int, int)? _firstFree(List<List<bool>> used, HomeItem item) {
  for (var r = 0; r <= rows - item.height; r++) {
    for (var c = 0; c <= columns - item.width; c++) {
      if (_free(used, c, r, item)) return (c, r);
    }
  }
  return null;
}

/// How many items of a page fit.
int overflowIndex(List<HomeItem> items) => pack(items).length;

/// Widgets only sit on the left or right half, or across the full width.
(int, int) snapCell(HomeItem item, int column, int row) =>
    (item.width == 2 ? ((column / 2).round() * 2).clamp(0, columns - 2) : column.clamp(0, columns - item.width), row.clamp(0, rows - item.height));

class Arranged {
  const Arranged(this.slots, this.overflow);
  final List<Slot> slots;
  final List<HomeItem> overflow;
}

/// Puts [moving] on a cell. Only what it covers moves, each to the closest free spot; ties
/// go forward, the way iOS pushes icons along. What finds no room is reported as overflow.
Arranged arrange(List<Slot> others, HomeItem moving, int column, int row) {
  final (c, r) = snapCell(moving, column, row);
  final kept = [Slot(c, r, moving)];
  final bumped = <Slot>[];
  for (final slot in others) {
    (slot.overlaps(c, r, moving.width, moving.height) ? bumped : kept).add(slot);
  }
  bumped.sort((a, b) => a.row != b.row ? a.row - b.row : a.column - b.column);
  final overflow = <HomeItem>[];
  for (final slot in bumped) {
    final spot = _nearest(kept, slot);
    if (spot == null) {
      overflow.add(slot.item);
    } else {
      kept.add(Slot(spot.$1, spot.$2, slot.item));
    }
  }
  return Arranged(kept, overflow);
}

(int, int)? _nearest(List<Slot> taken, Slot from) {
  final used = _grid();
  for (final slot in taken) {
    _mark(used, slot.column, slot.row, slot.item);
  }
  final item = from.item;
  (int, int)? best;
  var score = 1 << 30;
  for (var r = 0; r <= rows - item.height; r++) {
    for (var c = 0; c <= columns - item.width; c++) {
      if (!_free(used, c, r, item)) continue;
      if (item.width == 2 && c.isOdd) continue;
      final backwards = r < from.row || (r == from.row && c < from.column);
      final distance = (c - from.column).abs() + (r - from.row).abs();
      final value = distance * 2 + (backwards ? 1 : 0);
      if (value < score) {
        score = value;
        best = (c, r);
      }
    }
  }
  return best;
}

/// Where an item sits: page index, or -1 for the dock.
class Place {
  const Place(this.page, this.index);
  final int page;
  final int index;

  static const dock = -1;
  bool get inDock => page == dock;
}

class HomeLayout {
  HomeLayout({List<List<HomeItem>>? pages, List<HomeItem>? dock, Set<String>? seen, List<List<HomeItem>>? hidden})
    : pages = pages ?? [[]],
      dock = dock ?? [],
      seen = seen ?? {},
      hidden = hidden ?? [];

  final List<List<HomeItem>> pages;
  final List<HomeItem> dock;

  /// Pages switched off in the page overview, kept as they were to switch back on.
  final List<List<HomeItem>> hidden;

  /// The last visible page can't go.
  void hidePage(int page) {
    if (pages.length <= 1 || page >= pages.length) return;
    hidden.add(pages.removeAt(page));
  }

  void showPage(int index) {
    pages.add(hidden.removeAt(index));
    _tidy();
  }

  /// What was on it stays in the App Library.
  void deleteHidden(int index) => hidden.removeAt(index);

  /// Every app ever placed. An app removed from the home screen stays here, so it lives on
  /// in the App Library without being added back.
  final Set<String> seen;

  var _nextId = 0;
  String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  Iterable<HomeItem> get all => pages.expand((p) => p).followedBy(dock);

  /// Brings the layout in line with the installed apps. New apps go to the end, removed
  /// ones disappear, also from folders.
  void sync(Iterable<String> installed) {
    final apps = installed.toSet();
    for (final list in [...pages, ...hidden, dock]) {
      list.removeWhere((item) => item is AppItem && !apps.contains(item.key));
      for (final folder in list.whereType<FolderItem>()) {
        folder.apps.removeWhere((key) => !apps.contains(key));
      }
      _dissolveFolders(list);
    }
    final fresh = apps.where((key) => !seen.contains(key)).toList();
    seen.addAll(apps);
    for (final key in fresh) {
      final last = pages.last;
      if (overflowIndex([...last, AppItem(key)]) > last.length) {
        last.add(AppItem(key));
      } else {
        pages.add([AppItem(key)]);
      }
    }
    _tidy();
  }

  void _dissolveFolders(List<HomeItem> list) {
    for (var i = list.length - 1; i >= 0; i--) {
      final item = list[i];
      if (item is FolderItem && item.apps.length < 2) {
        list.removeAt(i);
        if (item.apps.isNotEmpty) list.insert(i, AppItem(item.apps.single));
      }
    }
  }

  /// Pushes what doesn't fit to the following pages and drops empty pages.
  void _tidy() {
    for (var i = 0; i < pages.length; i++) {
      final placed = pack(pages[i]).map((s) => s.item).toSet();
      final spill = pages[i].where((item) => !placed.contains(item)).toList();
      if (spill.isEmpty) continue;
      pages[i].removeWhere(spill.contains);
      for (final item in spill) {
        item
          ..column = null
          ..row = null;
      }
      if (i + 1 == pages.length) pages.add([]);
      pages[i + 1].insertAll(0, spill);
    }
    pages.removeWhere((p) => p.isEmpty);
    if (pages.isEmpty) pages.add([]);
  }

  List<HomeItem> _list(int page) => page == Place.dock ? dock : pages[page];

  /// Moves an item. A full dock refuses; widgets never go into the dock.
  bool move(Place from, Place to) {
    final item = _list(from.page)[from.index];
    if (to.inDock && !from.inDock && (dock.length >= dockSize || item.width > 1)) return false;
    _list(from.page).removeAt(from.index);
    while (to.page >= pages.length) {
      pages.add([]);
    }
    item
      ..column = null
      ..row = null;
    final target = _list(to.page);
    target.insert(min(to.index, target.length), item);
    _tidy();
    return true;
  }

  /// Freezes a page where it is, so taking one item away doesn't close the gap.
  void pin(int page) {
    if (page < 0 || page >= pages.length) return;
    for (final slot in pack(pages[page])) {
      slot.item
        ..column = slot.column
        ..row = slot.row;
    }
  }

  /// Puts an item on a cell of a page. What it covers makes room, everything else stays.
  void drop(HomeItem item, int page, int column, int row) {
    for (final list in [...pages, dock]) {
      list.remove(item);
    }
    while (page >= pages.length) {
      pages.add([]);
    }
    final result = arrange(pack(pages[page]), item, column, row);
    pages[page].clear();
    for (final slot in result.slots) {
      slot.item
        ..column = slot.column
        ..row = slot.row;
      pages[page].add(slot.item);
    }
    pages[page].sort((a, b) => a.row != b.row ? a.row! - b.row! : a.column! - b.column!);
    if (result.overflow.isNotEmpty) {
      if (page + 1 == pages.length) pages.add([]);
      for (final spilled in result.overflow) {
        spilled
          ..column = null
          ..row = null;
        pages[page + 1].add(spilled);
      }
    }
    _tidy();
  }

  /// Changes a widget's size where it stands. Icons in the way make room as for a drop.
  void resize(WidgetItem item, WidgetSize size) {
    for (var page = 0; page < pages.length; page++) {
      if (!pages[page].contains(item)) continue;
      final slot = pack(pages[page]).firstWhere((s) => s.item == item);
      item.size = size;
      drop(item, page, slot.column, slot.row);
      return;
    }
  }

  /// Drops [from] onto the item at [to], making a folder or adding to one. A new folder is
  /// called [name], as iOS names it after the apps' category.
  bool merge(Place from, Place to, {String name = 'Ordner'}) {
    final source = _list(from.page)[from.index];
    final target = _list(to.page)[to.index];
    if (identical(source, target) || source is! AppItem) return false;
    if (target is FolderItem) {
      if (target.apps.length >= folderCapacity) return false;
      target.apps.add(source.key);
    } else if (target is AppItem) {
      _list(to.page)[to.index] = FolderItem(_id('folder'), name, [target.key, source.key])
        ..column = target.column
        ..row = target.row;
    } else {
      return false;
    }
    _list(from.page).removeAt(from.index);
    _tidy();
    return true;
  }

  /// Takes an app out of a folder and puts it behind the folder.
  void removeFromFolder(FolderItem folder, String key) {
    folder.apps.remove(key);
    for (final list in [...pages, dock]) {
      final index = list.indexOf(folder);
      if (index < 0) continue;
      if (identical(list, dock) && dock.length >= dockSize) {
        pages.last.add(AppItem(key));
      } else {
        list.insert(index + 1, AppItem(key));
      }
      _dissolveFolders(list);
    }
    _tidy();
  }

  void remove(HomeItem item) {
    for (final list in [...pages, dock]) {
      list.remove(item);
    }
    _tidy();
  }

  /// A new widget goes into the first gap on [page] that fits it, so nothing moves. Without
  /// one it gets a page of its own right after.
  void addWidget(WidgetKind kind, int page, [WidgetSize? size]) {
    final item = WidgetItem(_id('widget'), kind, size);
    final spot = freeSpot(page, item.width, item.height);
    if (spot != null) {
      drop(item, page, spot.$1, spot.$2);
    } else {
      pages.insert(page + 1, [item]);
      _tidy();
    }
  }

  /// Top left cell of the first free area of this size; widgets keep to iOS's columns.
  (int, int)? freeSpot(int page, int width, int height) {
    if (page >= pages.length) return (0, 0);
    final slots = pack(pages[page]);
    final starts = width == 4 ? [0] : (width == 2 ? [0, 2] : [0, 1, 2, 3]);
    for (var row = 0; row + height <= rows; row++) {
      for (final column in starts) {
        if (slots.every((s) => !s.overlaps(column, row, width, height))) return (column, row);
      }
    }
    return null;
  }

  /// Takes the widget at [index] out of a stack; a stack of one is a plain widget again.
  void removeFromStack(WidgetItem item, int index) {
    if (item.stack.isEmpty) return;
    if (index == 0) {
      item.kind = item.stack.removeAt(0);
    } else {
      item.stack.removeAt(index - 1);
    }
  }

  /// Back on the home screen from the App Library.
  void addApp(String key) {
    if (all.any((i) => i is AppItem && i.key == key)) return;
    pages.last.add(AppItem(key));
    _tidy();
  }

  Map<String, dynamic> toJson() => {
    'pages': pages.map((p) => p.map((i) => i.toJson()).toList()).toList(),
    'dock': dock.map((i) => i.toJson()).toList(),
    'seen': seen.toList(),
    'hidden': hidden.map((p) => p.map((i) => i.toJson()).toList()).toList(),
  };

  factory HomeLayout.fromJson(Map<String, dynamic> j) => HomeLayout(
    pages: (j['pages'] as List).map((p) => (p as List).map((i) => HomeItem.fromJson(i as Map<String, dynamic>)).toList()).toList(),
    dock: (j['dock'] as List).map((i) => HomeItem.fromJson(i as Map<String, dynamic>)).toList(),
    seen: (j['seen'] as List).cast<String>().toSet(),
    hidden: (j['hidden'] as List? ?? []).map((p) => (p as List).map((i) => HomeItem.fromJson(i as Map<String, dynamic>)).toList()).toList(),
  );
}

/// Evaluates a typed calculation for the search, or returns null if it isn't one.
double? calculate(String text) {
  final source = text.replaceAll(' ', '').replaceAll(',', '.').replaceAll('×', '*').replaceAll('÷', '/');
  if (!RegExp(r'^[-+*/().\d]+$').hasMatch(source) || !RegExp(r'\d[-+*/(]|\)').hasMatch(source)) return null;
  var position = 0;

  String? peek() => position < source.length ? source[position] : null;

  late double Function() expression;

  double factor() {
    if (peek() == '-') {
      position++;
      return -factor();
    }
    if (peek() == '(') {
      position++;
      final value = expression();
      if (peek() != ')') throw const FormatException();
      position++;
      return value;
    }
    final start = position;
    while (peek() != null && RegExp(r'[\d.]').hasMatch(peek()!)) {
      position++;
    }
    return double.parse(source.substring(start, position));
  }

  double term() {
    var value = factor();
    while (peek() == '*' || peek() == '/') {
      final op = source[position++];
      final right = factor();
      value = op == '*' ? value * right : value / right;
    }
    return value;
  }

  expression = () {
    var value = term();
    while (peek() == '+' || peek() == '-') {
      final op = source[position++];
      final right = term();
      value = op == '+' ? value + right : value - right;
    }
    return value;
  };

  try {
    final result = expression();
    return position == source.length && result.isFinite ? result : null;
  } on FormatException {
    return null;
  }
}
