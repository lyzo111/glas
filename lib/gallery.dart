import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'appwidgets.dart';
import 'glass.dart';
import 'icons.dart';
import 'layout.dart';
import 'native.dart';
import 'state.dart';
import 'widgets.dart';

/// One widget in one size: drawn by Glas ([kind]) or by another app ([provider]).
class _Face {
  const _Face(this.label, this.size, {this.kind, this.provider});
  final String label;
  final WidgetSize size;
  final WidgetKind? kind;
  final WidgetProvider? provider;
}

/// An app in the gallery with everything it offers.
class _Entry {
  const _Entry(this.name, this.faces, {this.role, this.package});
  final String name;
  final List<_Face> faces;

  /// The iOS app a built-in widget belongs to, or the Android package.
  final Role? role;
  final String? package;
}

/// The built-in widgets under the apps iOS lists them with.
const _builtIn = [
  ('Batterien', null, [WidgetKind.battery]),
  ('Fotos', Role.photos, [WidgetKind.photos]),
  ('Kalender', Role.calendar, [WidgetKind.calendar, WidgetKind.month, WidgetKind.date]),
  ('Kurzbefehle', null, [WidgetKind.shortcuts]),
  ('Musik', Role.music, [WidgetKind.music]),
  ('Notizen', Role.notes, [WidgetKind.note]),
  ('Uhr', Role.clock, [WidgetKind.clock, WidgetKind.worldClock]),
  ('Wetter', null, [WidgetKind.weather]),
];

/// What the gallery suggests on top, in the mix iOS shows there.
const _suggested = [
  (WidgetKind.weather, WidgetSize.small),
  (WidgetKind.calendar, WidgetSize.small),
  (WidgetKind.music, WidgetSize.medium),
  (WidgetKind.clock, WidgetSize.small),
  (WidgetKind.battery, WidgetSize.small),
  (WidgetKind.photos, WidgetSize.medium),
  (WidgetKind.note, WidgetSize.small),
  (WidgetKind.month, WidgetSize.small),
  (WidgetKind.shortcuts, WidgetSize.medium),
];

/// The sheet behind the plus of the iOS edit mode: a search field, a few suggestions drawn
/// as they will look, then every app that has widgets, by name. An app opens its widgets to
/// swipe through, with the button that adds the one showing.
class WidgetGallery extends StatefulWidget {
  const WidgetGallery({super.key, required this.state, required this.onPick, this.onPickApp, this.only});
  final AppState state;

  /// Shows only widgets of this size, for adding to a stack.
  final WidgetSize? only;
  final void Function(WidgetKind, WidgetSize) onPick;

  /// With this the gallery also lists the widgets of the installed apps.
  final void Function(WidgetProvider, WidgetSize)? onPickApp;

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  String _query = '';
  List<_Entry> _entries = [];
  final _packages = <String, AppInfo>{};

  @override
  void initState() {
    super.initState();
    for (final app in widget.state.apps.values) {
      _packages.putIfAbsent(app.package, () => app);
    }
    _entries = _sorted(const []);
    // Android's list arrives a moment later; the rows are built one by one as they scroll in.
    if (widget.onPickApp != null) {
      AppWidgets.providers().then((all) {
        if (mounted) setState(() => _entries = _sorted(all));
      });
    }
  }

  bool _fits(WidgetSize size) => widget.only == null || size == widget.only;

  List<_Entry> _sorted(List<WidgetProvider> providers) {
    final entries = <_Entry>[
      for (final (name, role, kinds) in _builtIn)
        _Entry(name, [
          for (final kind in kinds)
            for (final size in kind.sizes)
              if (_fits(size)) _Face(kind.label, size, kind: kind),
        ], role: role),
    ];
    final byApp = <String, List<_Face>>{};
    final names = <String, String>{};
    for (final provider in providers) {
      names[provider.package] = provider.app;
      final faces = byApp.putIfAbsent(provider.package, () => []);
      // The size the widget asks for comes first, as the one iOS would show first.
      for (final size in [provider.preferred, ...provider.sizes.where((s) => s != provider.preferred)]) {
        if (_fits(size)) faces.add(_Face(provider.label, size, provider: provider));
      }
    }
    for (final MapEntry(key: package, value: faces) in byApp.entries) {
      entries.add(_Entry(names[package]!, faces, package: package));
    }
    return entries.where((e) => e.faces.isNotEmpty).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _open(_Entry entry, [int first = 0]) async {
    final face = await openOverlay<_Face>(context, (_) => _WidgetDetail(state: widget.state, entry: entry, first: first, icon: _iconOf(entry)));
    if (face == null || !mounted) return;
    Navigator.of(context).pop();
    if (face.kind != null) {
      widget.onPick(face.kind!, face.size);
    } else {
      widget.onPickApp!(face.provider!, face.size);
    }
  }

  Widget _iconOf(_Entry entry, [double points = 30]) {
    final size = Ios.of(context)(points);
    final role = entry.role;
    final app = entry.package != null ? _packages[entry.package] : (role != null ? widget.state.appFor(role) : null);
    if (app != null) return AppIcon(app: app, size: size);
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(size * 0.2237),
      child: role != null
          ? RoleIcon(role: role, size: size)
          : Container(
              width: size,
              height: size,
              color: const Color(0xFF30D158),
              child: Icon(CupertinoIcons.square_grid_2x2_fill, size: size * 0.6, color: Colors.white),
            ),
    );
  }

  /// The suggestions: small ones side by side, wide ones on a row of their own.
  List<Widget> _mosaic(Ios p) {
    final faces = [
      for (final (kind, size) in _suggested)
        if (_fits(size) && kind.sizes.contains(size)) (kind, size),
    ];
    final rows = <List<(WidgetKind, WidgetSize)>>[];
    for (final face in faces) {
      final small = face.$2.width < 4;
      if (small && rows.isNotEmpty && rows.last.length == 1 && rows.last.first.$2.width < 4) {
        rows.last.add(face);
      } else {
        rows.add([face]);
      }
    }
    Widget tile(WidgetKind kind, WidgetSize size) => GestureDetector(
      // The previews ignore touches, so the whole tile has to take the tap.
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final entry = _entries.firstWhere((e) => e.faces.any((f) => f.kind == kind));
        _open(entry, entry.faces.indexWhere((f) => f.kind == kind && f.size == size));
      },
      child: SizedBox(
        width: size.width == 4 ? p.fullWidth : p.smallWidth,
        height: p.icon + (size.height - 1) * p.rowPitch,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: HomeWidget(kind: kind, size: size, state: widget.state, scale: p.unit),
          ),
        ),
      ),
    );
    return [
      for (final row in rows)
        Padding(
          padding: EdgeInsets.only(bottom: p(20)),
          child: Center(
            child: SizedBox(
              width: p.fullWidth,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final (kind, size) in row) tile(kind, size)]),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final q = _query.trim().toLowerCase();
    final entries = q.isEmpty ? _entries : _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
    final side = (MediaQuery.sizeOf(context).width - p.fullWidth) / 2;
    return Backdrop(
      dim: 0.5,
      // A tap between two widgets must not close it; swiping up or back does.
      tapToClose: false,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(height: p(8)),
            Container(
              width: p(36),
              height: p(5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(p(3))),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(side, p(14), side, p(16)),
              child: Glass(
                radius: p(22),
                tint: 0.16,
                blur: false,
                child: SizedBox(
                  height: p(44),
                  child: Row(
                    children: [
                      SizedBox(width: p(13)),
                      Icon(CupertinoIcons.search, size: p(19), color: Colors.white.withValues(alpha: 0.6)),
                      SizedBox(width: p(7)),
                      Expanded(
                        child: TextField(
                          style: sf(p(17)),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Widgets suchen',
                            hintStyle: sf(p(17), color: Colors.white.withValues(alpha: 0.6)),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      SizedBox(width: p(13)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (q.isEmpty) SliverList.list(children: _mosaic(p)),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, p(4), side, MediaQuery.viewPaddingOf(context).bottom + p(30)),
                    // Row by row, so a long list of apps costs nothing until it scrolls in.
                    sliver: SliverList.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final first = index == 0, last = index == entries.length - 1;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _open(entry),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(first ? p(24) : 0), bottom: Radius.circular(last ? p(24) : 0)),
                            ),
                            child: Column(
                              children: [
                                if (!first)
                                  Container(
                                    height: 0.5,
                                    margin: EdgeInsets.only(left: p(58)),
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: p(14), vertical: p(9)),
                                  child: Row(
                                    children: [
                                      _iconOf(entry),
                                      SizedBox(width: p(14)),
                                      Expanded(
                                        child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(17))),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The widgets of one app, one size at a time, with the button that adds the one showing.
class _WidgetDetail extends StatefulWidget {
  const _WidgetDetail({required this.state, required this.entry, required this.first, required this.icon});
  final AppState state;
  final _Entry entry;
  final int first;
  final Widget icon;

  @override
  State<_WidgetDetail> createState() => _WidgetDetailState();
}

class _WidgetDetailState extends State<_WidgetDetail> {
  late var _page = widget.first.clamp(0, widget.entry.faces.length - 1);
  late final _pages = PageController(initialPage: _page, viewportFraction: 0.92);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _preview(Ios p, _Face face) {
    final width = face.size.width == 4 ? p.fullWidth : p.smallWidth;
    final height = p.icon + (face.size.height - 1) * p.rowPitch;
    final Widget child;
    if (face.kind != null) {
      child = IgnorePointer(
        child: HomeWidget(kind: face.kind!, size: face.size, state: widget.state, scale: p.unit),
      );
    } else {
      // Android only hands out a picture until the widget is really added.
      child = Glass(
        radius: p(24),
        tint: 0.14,
        blur: false,
        child: FutureBuilder(
          future: AppWidgets.preview(face.provider!.id),
          builder: (_, image) => image.data == null
              ? Center(
                  child: Icon(CupertinoIcons.square_grid_2x2, size: p(30), color: Colors.white.withValues(alpha: 0.7)),
                )
              : Padding(
                  padding: EdgeInsets.all(p(8)),
                  child: Image.memory(image.data!, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                ),
        ),
      );
    }
    return Center(
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final faces = widget.entry.faces;
    final face = faces[_page];
    return Backdrop(
      dim: 0.55,
      tapToClose: false,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(p(16), p(10), p(16), p(6)),
                  child: Container(
                    width: p(34),
                    height: p(34),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
                    child: Icon(CupertinoIcons.chevron_left, size: p(17), color: Colors.white),
                  ),
                ),
              ),
            ),
            widget.icon,
            SizedBox(height: p(10)),
            Text(widget.entry.name, style: sf(p(22), weight: 700)),
            SizedBox(height: p(4)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: p(30)),
              child: Text(
                '${face.label} · ${face.size.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sf(p(15), color: Colors.white.withValues(alpha: 0.65)),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [for (final face in faces) _preview(p, face)],
              ),
            ),
            SizedBox(
              height: p(7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (faces.length > 1)
                    for (var i = 0; i < faces.length; i++)
                      Container(
                        width: p(7),
                        height: p(7),
                        margin: EdgeInsets.symmetric(horizontal: p(4)),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: i == _page ? 1 : 0.38),
                        ),
                      ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(face),
              child: Container(
                height: p(50),
                margin: EdgeInsets.fromLTRB(p(28), p(22), p(28), p(18)),
                decoration: BoxDecoration(color: const Color(0xFF0A84FF), borderRadius: BorderRadius.circular(p(25))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.plus, size: p(18), color: Colors.white),
                    SizedBox(width: p(6)),
                    Text('Widget hinzufügen', style: sf(p(17), weight: 600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
