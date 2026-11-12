import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import 'appwidgets.dart';
import 'control_center.dart';
import 'glass.dart';
import 'layout.dart';
import 'library.dart';
import 'native.dart';
import 'overlays.dart';
import 'customize.dart';
import 'setup.dart';
import 'state.dart';
import 'island.dart';
import 'today.dart';
import 'widgets.dart';

class _Drag {
  _Drag(this.item, this.from, this.start, this.position);
  final HomeItem item;
  final Place from;
  final Offset start;
  Offset position;
  bool moved = false;
  Offset grab = Offset.zero;

  /// Page or Place.dock under the finger, with the dock position or the grid cell.
  int? hoverPage;
  int hoverIndex = 0;
  int hoverColumn = 0;
  int hoverRow = 0;

  /// The app or folder that would swallow the dragged app.
  HomeItem? mergeTarget;

  /// A cell the finger rests on, taken over as [hoverColumn]/[hoverRow] once it stays.
  (int, int, int)? pending;
}

/// Page turns settle as quickly as on iOS; Flutter's default spring is much softer.
class _PagePhysics extends BouncingScrollPhysics {
  const _PagePhysics({super.parent});

  @override
  _PagePhysics applyTo(ScrollPhysics? ancestor) => _PagePhysics(parent: buildParent(ancestor));

  @override
  // A softer spring than before: the page glides out like iOS's instead of snapping.
  SpringDescription get spring => SpringDescription.withDampingRatio(mass: 1, stiffness: 140, ratio: 1);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _pages = PageController();
  final _gridKeys = <int, GlobalKey>{};
  final _dockKey = GlobalKey();

  /// Scroll position. A notifier, so a page turn doesn't rebuild the whole screen each frame.
  final _position = ValueNotifier<double>(0);
  late final _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));

  StreamSubscription<String>? _home;
  late final AppLifecycleListener _life;
  bool _editing = false;
  _Drag? _drag;
  Timer? _flip;
  Timer? _settle;

  /// After a page turn the finger has to leave the edge before the next one.
  bool _flipped = false;

  /// A finger on an icon in edit mode, so the pages hold still and the icon is what moves.

  /// Pulling the first page to the right opens the Today view, once per pull.
  bool _todayOpen = false;

  /// Icons are a little bigger in iOS's large style, and lose their names.
  double get _iconSize => Ios.of(context).icon * (_state.settings.largeIcons ? 1.18 : 1);

  double _pullStartY = 0;
  Offset? _edgeStart;

  /// The finger that touched down at the top edge. Only its own moves may open a centre.
  int? _edgePointer;

  AppState get _state => widget.state;
  HomeLayout get _layout => _state.layout;
  GlobalKey _gridKey(int page) => _gridKeys[page] ??= GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
    _pages.addListener(() {
      final page = _pages.page ?? 0;
      _position.value = page;
      // The wiggle repaints every icon each frame; while a page slides it would stutter.
      if (_editing) {
        final turning = (page - page.roundToDouble()).abs() > 0.02;
        if (turning && _wiggle.isAnimating) {
          _wiggle.stop();
        } else if (!turning && !_wiggle.isAnimating) {
          _wiggle.repeat(reverse: true);
        }
      }
    });
    // Opening an app closes Notification and Control Centre, as on iOS; otherwise they are
    // still open when coming back.
    _life = AppLifecycleListener(
      onHide: () {
        if (mounted) Navigator.of(context).popUntil((r) => r.settings.name != overlayRoute);
      },
    );
    _home = Native.events.listen((event) {
      if (event != 'home' || !mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _setEditing(false);
      if (_pages.hasClients) _pages.animateToPage(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    });
  }

  /// The phone is ready at once; only what Android reserves for the user is left to confirm.
  void _firstRun() {
    if (_state.settings.setupDone) return;
    _state.settings.setupDone = true;
    _state.commit();
    if (!mounted) return;
    openOverlay<void>(context, (_) => ReadySheet(state: _state));
  }

  @override
  void dispose() {
    _home?.cancel();
    _life.dispose();
    _flip?.cancel();
    _settle?.cancel();
    _wiggle.dispose();
    _position.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _setEditing(bool on) {
    if (_editing == on) return;
    setState(() => _editing = on);
    on ? _wiggle.repeat(reverse: true) : _wiggle.stop();
  }

  // ------------------------------------------------------------ Drag & drop

  void _startDrag(HomeItem item, Place from, Offset position, Offset grab) {
    HapticFeedback.mediumImpact();
    setState(() => _drag = _Drag(item, from, position, position)..grab = grab);
  }

  void _onMove(PointerMoveEvent event) {
    final drag = _drag;
    if (drag == null) return;
    drag.position = event.position;
    if (!drag.moved && (drag.position - drag.start).distance > 12) {
      drag.moved = true;
      _layout.pin(drag.from.page);
      _setEditing(true);
    }
    if (drag.moved) _updateHover(drag);
    setState(() {});
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  void _updateHover(_Drag drag) {
    final page = _pages.page?.round() ?? 0;
    final grid = _rectOf(_gridKey(page));
    final dock = _rectOf(_dockKey);
    final p = drag.position;
    drag.mergeTarget = null;

    if (dock != null && p.dy >= dock.top - 8 && drag.item.width == 1) {
      final count = _layout.dock.where((i) => i != drag.item).length;
      if (count < dockSize || drag.from.inDock) {
        drag.hoverPage = Place.dock;
        drag.hoverIndex = (((p.dx - dock.left) / dock.width) * (count + 1)).floor().clamp(0, count);
        _flip?.cancel();
        _flip = null;
        return;
      }
    }
    // Dragged past the last page, the item opens a new one.
    if (page >= _layout.pages.length) {
      drag
        ..hoverPage = page
        ..hoverColumn = 0
        ..hoverRow = 0;
      return;
    }
    if (grid == null) {
      drag.hoverPage = null;
      return;
    }

    final cellW = grid.width / columns, cellH = grid.height / rows;
    final local = p - grid.topLeft;
    final corner = local - drag.grab;
    final column = (corner.dx / cellW).round().clamp(0, columns - 1);
    final row = (corner.dy / cellH).round().clamp(0, rows - 1);

    // Held over the middle of an icon, an app goes into it instead of pushing it aside. The
    // icons are looked up where they are drawn now, already moved aside for the gap.
    final over = drag.item is AppItem ? _iconUnder(page, local, cellW, cellH) : null;
    if (over != null) {
      drag.mergeTarget = over;
      drag.pending = null;
      _settle?.cancel();
    } else if (drag.hoverPage != page) {
      drag
        ..hoverPage = page
        ..hoverColumn = column
        ..hoverRow = row;
    } else if ((column, row) != (drag.hoverColumn, drag.hoverRow) && drag.pending != (page, column, row)) {
      // Icons only make room once the finger rests, so passing over them doesn't stir the page.
      drag.pending = (page, column, row);
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 200), () {
        final pending = drag.pending;
        if (!identical(_drag, drag) || pending == null) return;
        setState(() {
          drag
            ..hoverPage = pending.$1
            ..hoverColumn = pending.$2
            ..hoverRow = pending.$3
            ..pending = null;
        });
      });
    }

    // Holding at the screen edge turns the page, once per visit to the edge.
    // Near the edge with the finger, or with the held item partly off the screen: on a phone
    // the very edge is hard to reach, and a widget is held far from its own edges.
    final ios = Ios.of(context);
    final zone = ios(30);
    final item = drag.item;
    final held = item is WidgetItem ? (item.width == 4 ? ios.fullWidth : ios.smallWidth) : ios.icon;
    final heldLeft = p.dx - drag.grab.dx;
    final edge = p.dx < zone || heldLeft < -held * 0.25 ? -1 : (p.dx > grid.right - zone || heldLeft + held > grid.right + held * 0.25 ? 1 : 0);
    if (edge == 0) {
      _flip?.cancel();
      _flip = null;
      _flipped = false;
    } else {
      // The first turn waits a little, further ones a little longer, so an app can travel
      // across several pages but never by accident.
      _flip ??= Timer(Duration(milliseconds: _flipped ? 900 : 450), () {
        _flip = null;
        _flipped = true;
        final target = (page + edge).clamp(0, _layout.pages.length);
        _pages.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut).whenComplete(() {
          // A finger resting at the edge sends no more moves, so the next turn is checked here.
          if (identical(_drag, drag) && mounted) setState(() => _updateHover(drag));
        });
      });
    }
  }

  /// The app or folder whose icon is under [local], as the page shows it right now.
  HomeItem? _iconUnder(int page, Offset local, double cellW, double cellH) {
    final p = Ios.of(context);
    final column = (local.dx / cellW).floor(), row = (local.dy / cellH).floor();
    final fx = local.dx / cellW - column, fy = (local.dy - row * cellH) / p.icon;
    // Generous on purpose: most of the icon and its label count, only the gaps between
    // icons move things around.
    if (fx < 0.12 || fx > 0.88 || fy < -0.15 || fy > 1.25) return null;
    for (final s in _pagePreview(page)) {
      final item = s.item;
      if ((item is AppItem || item is FolderItem) && s.column == column && s.row == row && item != _drag?.item) return item;
    }
    return null;
  }

  void _onUp(PointerEvent event) {
    final drag = _drag;
    if (drag == null) return;
    _flip?.cancel();
    _flip = null;
    _settle?.cancel();
    _flipped = false;
    setState(() => _drag = null);
    if (!drag.moved) {
      if (!_editing) _showMenu(drag.item, drag.from, drag.position, drag.position - drag.grab);
      return;
    }
    final page = drag.hoverPage;
    if (page == null) return;
    final from = Place(drag.from.page, _list(drag.from.page).indexOf(drag.item));
    final target = drag.mergeTarget;
    if (target != null) {
      final name = target is AppItem ? _state.apps[target.key]?.category ?? 'Ordner' : 'Ordner';
      _layout.merge(from, Place(page, _layout.pages[page].indexOf(target)), name: name);
    } else if (page == Place.dock) {
      _layout.move(from, Place(page, drag.hoverIndex));
    } else {
      _layout.drop(drag.item, page, drag.hoverColumn, drag.hoverRow);
    }
    HapticFeedback.lightImpact();
    _state.commit();
  }

  List<HomeItem> _list(int page) => page == Place.dock ? _layout.dock : _layout.pages[page];

  /// What the dock shows right now: the dragged item taken out, a gap where it would land.
  List<HomeItem> _dockPreview() {
    final drag = _drag;
    if (drag == null || !drag.moved) return _layout.dock;
    final list = _layout.dock.where((i) => i != drag.item).toList();
    if (drag.hoverPage == Place.dock) {
      list.insert(min(drag.hoverIndex, list.length), GapItem(drag.item.width, drag.item.height));
    }
    return list;
  }

  /// What a page shows right now, with icons already making room for the dragged item.
  List<Slot> _pagePreview(int page) {
    final drag = _drag;
    final items = page < _layout.pages.length ? _layout.pages[page] : <HomeItem>[];
    if (drag == null || !drag.moved) return pack(items);
    final others = pack(items.where((i) => i != drag.item).toList());
    if (drag.hoverPage != page) return others;
    if (compactLayout) {
      final rest = items.where((i) => i != drag.item).toList();
      return pack(rest..insert(flowIndex(rest, drag.item, drag.hoverColumn, drag.hoverRow), GapItem(drag.item.width, drag.item.height)));
    }
    return arrange(others, GapItem(drag.item.width, drag.item.height), drag.hoverColumn, drag.hoverRow).slots;
  }

  // ------------------------------------------------------------- Actions

  /// [corner] is the held item's top left corner on screen.
  Future<void> _showMenu(HomeItem item, Place place, Offset position, Offset corner) async {
    final p = Ios.of(context);
    final app = item is AppItem ? _state.apps[item.key] : null;
    final shortcuts = app == null ? const <(String, String)>[] : await Native.shortcuts(app.package);
    if (!mounted) return;
    await openOverlay<void>(
      context,
      (_) => QuickActions(
        position: position,
        frame: item is WidgetItem ? corner & Size(item.width == 4 ? p.fullWidth : p.smallWidth, p.icon + (item.height - 1) * p.rowPitch) : null,
        preview: _itemPreview(item),
        actions: [
          for (final (id, label) in shortcuts) QuickAction(label, Icons.bolt, () => Native.call('startShortcut', {'package': app!.package, 'id': id})),
          if (item is WidgetItem && item.kind.sizes.length > 1)
            for (final size in WidgetSize.values)
              if (item.kind.sizes.contains(size))
                QuickAction(
                  size.label,
                  size == item.size
                      ? Icons.check_rounded
                      : size == WidgetSize.small
                      ? Icons.crop_square_rounded
                      : size == WidgetSize.medium
                      ? Icons.crop_16_9_rounded
                      : Icons.crop_din_rounded,
                  () {
                    _layout.resize(item, size);
                    _state.commit();
                  },
                ),
          if (item is WidgetItem) QuickAction('Zu Stapel hinzufügen', Icons.layers_outlined, () => _addToStack(item)),
          if (item is WidgetItem && item.stack.isNotEmpty)
            QuickAction('Dieses Widget aus Stapel entfernen', Icons.layers_clear_outlined, () {
              final hostId = _layout.removeFromStack(item, (stackPage[item.id] ?? 0).clamp(0, item.stack.length));
              if (hostId != null) AppWidgets.delete(hostId);
              stackPage[item.id] = 0;
              _state.commit();
            }),
          QuickAction('Home-Bildschirm bearbeiten', Icons.apps, () => _setEditing(true)),
          if (item is FolderItem) QuickAction('Umbenennen', Icons.edit_outlined, () => _rename(item)),
          if (app != null) QuickAction('App-Info', Icons.info_outline, () => Native.call('appInfo', app.package)),
          QuickAction(
            item is WidgetItem
                ? (item.stack.isEmpty ? 'Widget entfernen' : 'Stapel entfernen')
                : item is FolderItem
                ? 'Ordner entfernen'
                : 'Vom Home-Bildschirm entfernen',
            Icons.remove_circle_outline,
            () => _remove(item),
          ),
          if (app != null) QuickAction('App löschen', Icons.delete_outline, () => Native.call('uninstall', app.package), destructive: true),
        ],
      ),
    );
  }

  /// A folder only goes after asking, as on iOS; its apps stay in the App Library.
  Future<void> _remove(HomeItem item) async {
    if (item is FolderItem) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('„${item.name}“ entfernen?'),
          content: const Text('Die Apps bleiben in der App-Mediathek.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Entfernen', style: TextStyle(color: Color(0xFFFF453A))),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    _layout.remove(item);
    // Android keeps a hosted widget alive until its id is given back.
    if (item is WidgetItem) item.hostIds.forEach(AppWidgets.delete);
    _state.commit();
  }

  Future<void> _rename(FolderItem folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ordner umbenennen'),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('OK'))],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      folder.name = name.trim();
      _state.commit();
    }
  }

  void _openFolder(FolderItem folder, Offset origin) => openOverlay<void>(
    context,
    (_) => FolderView(state: _state, folder: folder),
    origin: origin,
  );

  /// Reacts while the finger moves: a swipe from the screen edge also tells Android to show
  /// its bars, which can cancel the touch before a gesture would have finished.
  void _pullFromEdge(PointerMoveEvent event) {
    final start = _edgeStart;
    if (event.pointer != _edgePointer) return;
    if (start == null || _drag != null || _editing) return;
    if (event.position.dy - start.dy < Ios.of(context)(30)) return;
    _edgeStart = null;
    final right = start.dx > MediaQuery.sizeOf(context).width * 0.62;
    openOverlay<void>(context, (_) => right ? ControlCenter(state: _state) : NotificationCenter(state: _state));
    Future<void>.delayed(const Duration(milliseconds: 300), () => Native.call('dropStatusBar'));
  }

  /// Widgets of the same size go into one stack, as on iOS.
  void _addToStack(WidgetItem item) => openOverlay<void>(
    context,
    (_) => WidgetGallery(
      state: _state,
      only: item.size,
      onPick: (kind, _) {
        item.stack.add(StackEntry(kind));
        _state.commit();
      },
      onPickApp: (provider, _) async {
        final id = await AppWidgets.bind(provider.id);
        if (id == null) return;
        item.stack.add(StackEntry(WidgetKind.app, hostId: id, provider: provider.id, title: provider.app));
        _state.commit();
      },
    ),
  );

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _state.settings.note);
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Notiz'),
        content: TextField(controller: controller, autofocus: true, maxLines: 6, minLines: 3),
        actions: [TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Fertig'))],
      ),
    );
    if (text == null) return;
    _state.settings.note = text.trim();
    _state.commit();
  }

  void _openSearch() => openOverlay<void>(context, (_) => Spotlight(state: _state));

  Future<void> _openToday() async {
    _todayOpen = true;
    HapticFeedback.selectionClick();
    await openOverlay<void>(
      context,
      (_) => TodayView(
        state: _state,
        onSearch: _openSearch,
        onAdd: () => openOverlay<void>(
          context,
          (_) => WidgetGallery(
            state: _state,
            onPick: (kind, size) {
              _state.settings.today.add('${kind.name}:${size.name}');
              _state.commit();
            },
            onPickApp: (provider, size) async {
              final id = await AppWidgets.bind(provider.id);
              if (id == null) return;
              _state.settings.today.add(todayAppEntry(size, id, provider));
              _state.commit();
            },
          ),
        ),
      ),
      origin: Offset(0, MediaQuery.sizeOf(context).height / 2),
    );
    _todayOpen = false;
  }

  /// The iOS page overview: every page small, with a tick to keep it on the home screen.
  void _openPages() => openOverlay<void>(
    context,
    (_) => StatefulBuilder(
      builder: (context, refresh) {
        final p = Ios.of(context);
        void apply(VoidCallback change) {
          change();
          _state.commit();
          refresh(() {});
        }

        Widget thumb(List<HomeItem> items, bool shown, VoidCallback onToggle, {VoidCallback? onDelete}) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Opacity(
                opacity: shown ? 1 : 0.45,
                child: Glass(
                  radius: p(22),
                  tint: 0.12,
                  child: SizedBox(
                    width: p(150),
                    height: p(150) * 1.62,
                    child: FittedBox(
                      child: Padding(padding: EdgeInsets.all(p(14)), child: _thumbnail(items)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: p(10)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onToggle,
                  child: Icon(
                    shown ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: shown ? const Color(0xFF0A84FF) : Colors.white,
                    size: p(28),
                  ),
                ),
                if (onDelete != null) ...[
                  SizedBox(width: p(14)),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline_rounded, color: const Color(0xFFFF453A), size: p(26)),
                  ),
                ],
              ],
            ),
          ],
        );

        return Backdrop(
          dim: 0.4,
          onDismiss: () => Navigator.of(context).pop(),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(p(20), p(40), p(20), p(40)),
              child: Center(
                child: Wrap(
                  spacing: p(24),
                  runSpacing: p(24),
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < _layout.pages.length; i++) thumb(_layout.pages[i], true, () => apply(() => _layout.hidePage(i))),
                    for (var i = 0; i < _layout.hidden.length; i++)
                      thumb(
                        _layout.hidden[i],
                        false,
                        () => apply(() => _layout.showPage(i)),
                        onDelete: () => apply(() {
                          for (final item in _layout.hidden[i].whereType<WidgetItem>()) {
                            item.hostIds.forEach(AppWidgets.delete);
                          }
                          _layout.deleteHidden(i);
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  /// A page drawn as it looks, without any of its touch handling.
  Widget _thumbnail(List<HomeItem> items) {
    final p = Ios.of(context);
    final size = Size(p.columnPitch * columns, p.rowPitch * rows);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final slot in pack(items))
              () {
                final (left, width) = _place(slot, size);
                return Positioned(
                  left: left,
                  top: slot.row * p.rowPitch,
                  width: width,
                  child: Align(alignment: Alignment.topCenter, child: _itemPreview(slot.item)),
                );
              }(),
          ],
        ),
      ),
    );
  }

  /// Left edge and width of a slot: icons on the grid, widgets on its outer edges.
  (double, double) _place(Slot slot, Size size) {
    final p = Ios.of(context);
    final item = slot.item;
    final wide = item.width > 1;
    final inset = (p.columnPitch - p.icon) / 2;
    final width = item.width == 4 ? p.fullWidth : (wide ? p.smallWidth : p.columnPitch);
    final left = !wide
        ? slot.column * p.columnPitch
        : item.width == 4 || slot.column == 0
        ? inset
        : slot.column == 2
        ? size.width - inset - width
        : (size.width - width) / 2;
    return (left, width);
  }

  void _addWidget() => openOverlay<void>(
    context,
    (_) => WidgetGallery(
      state: _state,
      onPick: (kind, size) {
        final page = (_pages.page?.round() ?? 0).clamp(0, _layout.pages.length - 1);
        _layout.addWidget(kind, page, size);
        _state.commit();
      },
      onPickApp: (provider, size) async {
        // Android asks for consent the first time, and some widgets have a setup screen.
        final id = await AppWidgets.bind(provider.id);
        if (id == null || !mounted) return;
        final page = (_pages.page?.round() ?? 0).clamp(0, _layout.pages.length - 1);
        _layout.addWidget(WidgetKind.app, page, size)
          ..hostId = id
          ..provider = provider.id
          ..title = provider.app;
        _state.commit();
      },
    ),
  );

  void _editMenu() => openOverlay<void>(
    context,
    (_) => QuickActions(
      position: Offset(Ios.of(context)(50), islandCenter(context) - Ios.of(context)(30)),
      preview: const SizedBox(),
      actions: [
        QuickAction('Widget hinzufügen', Icons.add_box_outlined, _addWidget),
        QuickAction('Anpassen', Icons.brush_outlined, () => openOverlay<void>(context, (_) => CustomizeSheet(state: _state))),
        QuickAction(
          'Hintergrund bearbeiten',
          Icons.photo_outlined,
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(state: _state, wallpaperOnly: true))),
        ),
        QuickAction('Seiten bearbeiten', Icons.view_carousel_outlined, _openPages),
        QuickAction(
          'Glas-Einstellungen',
          Icons.settings_outlined,
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(state: _state))),
        ),
      ],
    ),
  );

  // ------------------------------------------------------------------ UI

  /// [live] is for the item's own place on the home screen; everything else is a picture.
  Widget _itemPreview(HomeItem item, {bool live = false}) {
    final p = Ios.of(context);
    return switch (item) {
      AppItem() => AppIcon(app: _state.apps[item.key], size: _iconSize),
      FolderItem() => FolderIcon(state: _state, folder: item, size: _iconSize),
      WidgetItem() => SizedBox(
        width: item.width == 4 ? p.fullWidth : p.smallWidth,
        height: p.icon + (item.height - 1) * p.rowPitch,
        child: item.stack.isNotEmpty
            ? WidgetStack(id: item.id, faces: item.faces, size: item.size, state: _state, scale: p.unit, live: live, locked: _editing)
            : item.kind == WidgetKind.app
            ? AppWidgetView(item: item, live: live, locked: _editing)
            : HomeWidget(kind: item.kind, size: item.size, state: _state, scale: p.unit),
      ),
      GapItem() => const SizedBox(),
    };
  }

  Widget _item(HomeItem item, Place place, double width) {
    final p = Ios.of(context);
    final inDock = place.page == Place.dock;
    final phase = item.id.hashCode % 7;
    final merging = identical(_drag?.mergeTarget, item);
    Widget child = switch (item) {
      GapItem() => const SizedBox(),
      AppItem() => _Labeled(
        label: _state.apps[item.key]?.name ?? '',
        showLabel: !inDock && !_state.settings.largeIcons,
        child: AppIcon(app: _state.apps[item.key], size: _iconSize, badge: _state.badges[_state.apps[item.key]?.package] ?? 0),
      ),
      FolderItem() => _Labeled(
        label: item.name,
        showLabel: !inDock && !_state.settings.largeIcons,
        child: FolderIcon(state: _state, folder: item, size: _iconSize),
      ),
      WidgetItem() => _Labeled(label: item.title ?? item.kind.label, showLabel: true, child: _itemPreview(item, live: true)),
    };
    if (item is GapItem) return child;
    child = AnimatedScale(scale: merging ? 1.14 : 1, duration: const Duration(milliseconds: 150), child: child);

    if (_editing) {
      child = AnimatedBuilder(
        animation: _wiggle,
        child: child,
        builder: (_, inner) => Transform.rotate(angle: (phase.isEven ? 1 : -1) * (_wiggle.value - 0.5) * (item is WidgetItem ? 0.018 : 0.05), child: inner),
      );
      final inset = item is WidgetItem ? 0.0 : (width - _iconSize) / 2;
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: width,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
          Positioned(
            left: inset - p(7),
            top: -p(7),
            child: GestureDetector(
              onTap: () => _remove(item),
              child: Container(
                width: p(23),
                height: p(23),
                decoration: const BoxDecoration(
                  color: Color(0xF2C9C9CE),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(blurRadius: 3, color: Color(0x33000000))],
                ),
                child: Icon(Icons.remove_rounded, size: p(17), color: const Color(0xFF2C2C2E)),
              ),
            ),
          ),
        ],
      );
    }

    return Builder(
      // A quick swipe over an icon turns the page in edit mode too; resting on it first drags it.
      builder: (iconContext) => RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: Duration(milliseconds: _editing ? 120 : 380)),
            (r) => r.onLongPressStart = (d) {
              _startDrag(item, place, d.globalPosition, d.localPosition);
            },
          ),
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r.onTapUp = (d) {
              if (_editing) return;
              if (item is AppItem) {
                final app = _state.apps[item.key];
                if (app != null) _state.launch(app, iconContext);
              } else if (item is FolderItem) {
                _openFolder(item, d.globalPosition);
              } else if (item is WidgetItem) {
                final kinds = [for (final face in item.faces) face.kind];
                final kind = kinds[(stackPage[item.id] ?? 0).clamp(0, kinds.length - 1)];
                kind == WidgetKind.note ? _editNote() : openWidget(kind, _state);
              }
            },
          ),
        },
        behavior: HitTestBehavior.opaque,
        child: child,
      ),
    );
  }

  /// Icons sit on the iOS grid; widgets line up with its outer edges and keep a 22 pt gap.
  Widget _grid(int page, Size size) {
    final p = Ios.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final slot in _pagePreview(page))
          () {
            final item = slot.item;
            final (left, width) = _place(slot, size);

            return AnimatedPositioned(
              key: ValueKey(item.id),
              duration: Duration(milliseconds: _drag == null ? 0 : 240),
              curve: const IosSpring(),
              left: left,
              top: slot.row * p.rowPitch,
              width: width,
              height: item.height * p.rowPitch,
              child: Align(alignment: Alignment.topCenter, child: _item(item, Place(page, _list(page).indexOf(item)), width)),
            );
          }(),
      ],
    );
  }

  Widget _dots(double position) {
    final p = Ios.of(context);
    // The App Library has no dot on iOS; in edit mode the empty page for new things has one.
    final count = _layout.pages.length + (_editing ? 1 : 0);
    final dots = Glass(
      radius: p(15),
      tint: 0.14,
      blur: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: p(9), vertical: p(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: EdgeInsets.symmetric(horizontal: p(4)),
                width: p(7),
                height: p(7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: (position - i).abs() < 0.5 ? 1 : 0.38),
                ),
              ),
          ],
        ),
      ),
    );
    // In edit mode the dots lead to the page overview, as on iOS.
    return _editing ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: _openPages, child: dots) : dots;
  }

  Widget _searchPill() {
    final p = Ios.of(context);
    return GestureDetector(
      onTap: _openSearch,
      child: Glass(
        radius: p(15),
        tint: 0.14,
        blur: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(p(11), p(6), p(13), p(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: p(15), color: Colors.white),
              SizedBox(width: p(3)),
              Text('Suchen', style: sf(p(13), weight: 500, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dock() {
    final p = Ios.of(context);
    final items = _dockPreview();
    final screen = MediaQuery.sizeOf(context);
    return FrostedPanel(
      radius: p(40),
      tint: 0.12,
      offset: Offset(p(12), screen.height - p(12 + 92)),
      wallpaper: _state.settings.wallpaper,
      wallpaperPath: _state.settings.wallpaperPath,
      child: SizedBox(
        key: _dockKey,
        height: p(92),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: items.length >= dockSize ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
          children: [
            SizedBox(width: p(27 - 12 - 16.5)),
            for (final item in items)
              SizedBox(
                width: p.columnPitch,
                height: _iconSize,
                child: Center(child: _item(item, Place(Place.dock, _layout.dock.indexOf(item)), p.columnPitch)),
              ),
            SizedBox(width: p(27 - 12 - 16.5)),
          ],
        ),
      ),
    );
  }

  Widget _editBar() {
    final p = Ios.of(context);
    return Padding(
      padding: EdgeInsets.only(top: islandCenter(context) - p(21), left: p(12), right: p(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pill(icon: Icons.brush_rounded, onTap: _editMenu),
          const Spacer(),
          _Pill(icon: Icons.check_rounded, onTap: () => _setEditing(false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final settings = _state.settings;
        final size = Size(p.columnPitch * columns, p.rowPitch * rows);
        final lastPage = _layout.pages.length - 1;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (_, _) => _setEditing(false),
          child: Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: false,
            body: Listener(
              onPointerDown: (e) {
                _edgeStart = e.position.dy < p(70) ? e.position : null;
                _edgePointer = e.pointer;
              },
              onPointerMove: (e) {
                _pullFromEdge(e);
                _onMove(e);
              },
              // A touch that ended must not open a centre later, for example when Glas comes
              // back to the front and Android hands over a stray move.
              onPointerUp: (e) {
                _edgeStart = null;
                _onUp(e);
              },
              onPointerCancel: (e) {
                _edgeStart = null;
                _onUp(e);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: _HomeWallpaper(settings: settings)),
                  // The App Library's frosted page: a tiny copy of the wallpaper, which looks
                  // like a blur but costs nothing per frame.
                  ValueListenableBuilder<double>(
                    valueListenable: _position,
                    builder: (_, position, child) {
                      // In edit mode the last page is an empty one for new things, not the library.
                      final amount = _editing ? 0.0 : (position - lastPage).clamp(0.0, 1.0);
                      return amount == 0 ? const SizedBox() : Opacity(opacity: amount, child: child);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Wallpaper(preset: settings.wallpaper, path: settings.wallpaperPath, frosted: true),
                        const ColoredBox(color: Color(0x33000000)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPress: () => _setEditing(true),
                    onTap: () => _setEditing(false),
                    // In edit mode a pull for the search would take sideways swipes meant to
                    // turn the page, and iOS doesn't open it there either.
                    onVerticalDragStart: _editing ? null : (d) => _pullStartY = d.globalPosition.dy,
                    onVerticalDragEnd: _editing
                        ? null
                        : (d) {
                            if (_pullStartY >= p(70) && (d.primaryVelocity ?? 0) > 150) _openSearch();
                          },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotificationListener<ScrollUpdateNotification>(
                          onNotification: (n) {
                            if (n.dragDetails != null && n.metrics.pixels < -p(70) && !_todayOpen && !_editing) _openToday();
                            return false;
                          },
                          child: PageView.builder(
                            controller: _pages,
                            // Builds the neighbouring pages ahead, so the App Library is ready
                            // before the swipe reaches it.
                            allowImplicitScrolling: true,
                            physics: _drag != null ? const NeverScrollableScrollPhysics() : const _PagePhysics(),
                            itemCount: _layout.pages.length + 1,
                            itemBuilder: (_, page) {
                              if (page == _layout.pages.length && !_editing) {
                                return RepaintBoundary(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: p(62)),
                                    child: AppLibrary(state: _state),
                                  ),
                                );
                              }
                              return RepaintBoundary(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: p.gridTop),
                                    child: SizedBox(key: _gridKey(page), width: size.width, height: size.height, child: _grid(page, size)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _position,
                          builder: (_, position, child) {
                            final visible = _editing ? 1.0 : (lastPage + 1 - position).clamp(0.0, 1.0);
                            final turning = (position - position.roundToDouble()).abs() > 0.01;
                            if (visible == 0) return const SizedBox();
                            return Opacity(
                              opacity: visible,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: p(12 + 92 + 13),
                                    child: Center(child: _editing || turning ? _dots(position) : _searchPill()),
                                  ),
                                  child!,
                                ],
                              ),
                            );
                          },
                          child: Positioned(
                            left: p(12),
                            right: p(12),
                            bottom: p(12),
                            child: RepaintBoundary(child: _dock()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_editing)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: StatusRow(
                        status: _state.status,
                        island: LiveIsland(state: _state),
                      ),
                    )
                  else ...[
                    const Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _IslandOnly())),
                    Positioned(top: 0, left: 0, right: 0, child: _editBar()),
                  ],
                  if (_drag?.moved ?? false)
                    Positioned(
                      left: _drag!.position.dx - _drag!.grab.dx,
                      top: _drag!.position.dy - _drag!.grab.dy,
                      child: IgnorePointer(child: Transform.scale(scale: 1.1, child: _itemPreview(_drag!.item))),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The wallpaper with iOS's options: softened, darkened, and shifting against the tilt of
/// the phone. It is drawn a little larger so the shift never shows an edge.
class _HomeWallpaper extends StatelessWidget {
  const _HomeWallpaper({required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    Widget picture = Wallpaper(preset: settings.wallpaper, path: settings.wallpaperPath, frosted: settings.blurHome);
    if (settings.dimHome) {
      picture = Stack(
        fit: StackFit.expand,
        children: [
          picture,
          const ColoredBox(color: Color(0x66000000)),
        ],
      );
    }
    if (!settings.perspective) return picture;
    return ValueListenableBuilder<Offset>(
      valueListenable: Native.tilt,
      child: picture,
      builder: (_, tilt, child) => Transform.translate(
        offset: tilt * -p(14),
        child: Transform.scale(scale: 1.08, child: child),
      ),
    );
  }
}

class _IslandOnly extends StatelessWidget {
  const _IslandOnly();

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Padding(
      padding: EdgeInsets.only(top: islandCenter(context) - p(18)),
      child: const Center(child: Island()),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.showLabel, required this.child});
  final String label;
  final bool showLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (showLabel)
          Padding(
            padding: EdgeInsets.only(top: p(6)),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sf(p(12), weight: 500, shadows: iconShadow),
            ),
          ),
      ],
    );
  }
}

/// The two glass capsules iOS shows above the home screen while it is edited.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // The capsule is small; the finger gets a little more room around it.
      child: Padding(
        padding: EdgeInsets.all(p(8)),
        child: Glass(
          radius: p(13),
          tint: 0.16,
          child: SizedBox(
            width: p(60),
            height: p(26),
            child: Icon(icon, size: p(17), color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The sheet behind the plus of the iOS edit mode: every widget, shown as it will look.
class WidgetGallery extends StatelessWidget {
  const WidgetGallery({super.key, required this.state, required this.onPick, this.onPickApp, this.only});
  final AppState state;

  /// Shows only widgets of this size, for adding to a stack.
  final WidgetSize? only;
  final void Function(WidgetKind, WidgetSize) onPick;

  /// With this the gallery also lists the widgets of the installed apps.
  final void Function(WidgetProvider, WidgetSize)? onPickApp;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Backdrop(
      dim: 0.45,
      // A tap between two widgets must not close it; swiping up or back does.
      tapToClose: false,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(p(27), p(16), p(27), 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Widgets', style: sf(p(34), weight: 700)),
              SizedBox(height: p(16)),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: p(30)),
                  physics: const BouncingScrollPhysics(),
                  // Built ahead, so the list of apps is ready before it scrolls into view.
                  scrollCacheExtent: ScrollCacheExtent.pixels(p(2400)),
                  children: [
                    for (final kind in WidgetKind.values)
                      for (final size in kind.sizes)
                        if (kind.builtIn && (only == null || size == only))
                          GestureDetector(
                            // The previews ignore touches, so the whole tile has to take the tap.
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.of(context).pop();
                              onPick(kind, size);
                            },
                            child: Padding(
                              padding: EdgeInsets.only(bottom: p(24)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: size.width == 4 ? p.fullWidth : p.smallWidth,
                                    height: p.icon + (size.height - 1) * p.rowPitch,
                                    child: IgnorePointer(
                                      child: HomeWidget(kind: kind, size: size, state: state, scale: p.unit),
                                    ),
                                  ),
                                  SizedBox(height: p(8)),
                                  Text(kind.label, style: sf(p(15), weight: 600)),
                                  Text(size.label, style: sf(p(13), color: Colors.white.withValues(alpha: 0.65))),
                                ],
                              ),
                            ),
                          ),
                    if (onPickApp != null)
                      AppWidgetList(
                        state: state,
                        only: only,
                        onPick: (provider, size) {
                          Navigator.of(context).pop();
                          onPickApp!(provider, size);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
