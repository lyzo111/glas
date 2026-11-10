import 'dart:math';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'layout.dart';
import 'native.dart';
import 'setup.dart';
import 'state.dart';

class QuickAction {
  const QuickAction(this.label, this.icon, this.onTap, {this.destructive = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// Long-press menu: the item stays sharp above the blurred screen.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.position, required this.preview, required this.actions, this.frame});
  final Offset position;

  /// Where the held item really is. Given for widgets, so the preview stays exactly in place
  /// and the menu goes below or above it, as on iOS.
  final Rect? frame;
  final Widget preview;
  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final p = Ios.of(context);
    final menuWidth = p(250);
    final menuHeight = actions.length * p(48);
    final box = frame;
    final double left, top;
    if (box != null) {
      left = (box.center.dx - menuWidth / 2).clamp(p(16), size.width - menuWidth - p(16));
      final below = box.bottom + p(12) + menuHeight < size.height - p(30);
      top = below ? box.bottom + p(12) : max(40.0, box.top - menuHeight - p(12));
    } else {
      final above = position.dy + menuHeight + 110 > size.height;
      left = (position.dx - menuWidth / 2).clamp(p(16), size.width - menuWidth - p(16));
      top = above ? max(40.0, position.dy - menuHeight - 90) : position.dy + 60;
    }
    return Backdrop(
      dim: 0.25,
      child: Stack(
        children: [
          Positioned(left: box?.left ?? position.dx - p(30), top: box?.top ?? position.dy - p(40), child: preview),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: Glass(
              radius: p(26),
              tint: 0.22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const Divider(height: 0.5, thickness: 0.5, color: Colors.white12),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        actions[i].onTap();
                      },
                      child: SizedBox(
                        height: p(47.5),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  actions[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sf(p(16), color: actions[i].destructive ? const Color(0xFFFF453A) : Colors.white),
                                ),
                              ),
                              Icon(actions[i].icon, size: p(20), color: actions[i].destructive ? const Color(0xFFFF453A) : Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Folder icon: a frosted tile with up to nine tiny apps.
class FolderIcon extends StatelessWidget {
  const FolderIcon({super.key, required this.state, required this.folder, required this.size});
  final AppState state;
  final FolderItem folder;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.11, gap = size * 0.045;
    final small = (size - pad * 2 - gap * 2) / 3;
    return SizedBox.square(
      dimension: size,
      child: Glass(
        radius: size * 0.2237,
        tint: 0.24,
        blur: false,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final key in folder.apps.take(9)) AppIcon(app: state.apps[key], size: small)],
          ),
        ),
      ),
    );
  }
}

class FolderView extends StatefulWidget {
  const FolderView({super.key, required this.state, required this.folder});
  final AppState state;
  final FolderItem folder;

  @override
  State<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends State<FolderView> {
  late final _name = TextEditingController(text: widget.folder.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _menu(String key, Offset position) {
    final app = widget.state.apps[key];
    openOverlay<void>(
      context,
      (_) => QuickActions(
        position: position,
        preview: AppIcon(app: app, size: 64),
        actions: [
          QuickAction('Aus Ordner entfernen', Icons.drive_file_move_outline, () {
            widget.state.layout.removeFromFolder(widget.folder, key);
            widget.state.commit();
            setState(() {});
            if (widget.folder.apps.length < 2) Navigator.of(context).maybePop();
          }),
          if (app != null) QuickAction('App-Info', Icons.info_outline, () => Native.call('appInfo', app.package)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final apps = widget.folder.apps;
    return Backdrop(
      dim: 0.2,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: p(32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                textAlign: TextAlign.center,
                style: sf(p(34), weight: 700),
                decoration: const InputDecoration(border: InputBorder.none),
                onChanged: (v) {
                  if (v.trim().isEmpty) return;
                  widget.folder.name = v.trim();
                  widget.state.commit();
                },
              ),
              SizedBox(height: p(10)),
              GestureDetector(
                onTap: () {},
                child: Glass(
                  radius: p(40),
                  tint: 0.14,
                  child: Padding(
                    padding: EdgeInsets.all(p(20)),
                    child: GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 3,
                      childAspectRatio: 0.84,
                      mainAxisSpacing: p(8),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        for (final key in apps.take(9))
                          Builder(
                            builder: (iconContext) => GestureDetector(
                              onTap: () {
                                final app = widget.state.apps[key];
                                if (app != null) widget.state.launch(app, iconContext);
                              },
                              onLongPressStart: (d) => _menu(key, d.globalPosition),
                              child: Column(
                                children: [
                                  AppIcon(app: widget.state.apps[key], size: p.icon, badge: widget.state.badges[widget.state.apps[key]?.package] ?? 0),
                                  SizedBox(height: p(6)),
                                  Text(widget.state.apps[key]?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(12), weight: 500)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The iOS search: suggested apps while the field is empty, then the best matches on cards
/// of glass, with a calculator and the web as fallbacks.
class Spotlight extends StatefulWidget {
  const Spotlight({super.key, required this.state});
  final AppState state;

  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> {
  final _text = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _open(AppInfo app, BuildContext iconContext) {
    widget.state.launch(app, iconContext);
    Navigator.of(context).pop();
  }

  void _web() => Native.call('webSearch', _query.trim());

  /// iOS suggests eight apps: here the ones used last, filled up with others.
  List<AppInfo> _suggestions() {
    final apps = widget.state.apps;
    final picked = <AppInfo>[for (final key in widget.state.settings.recent) ?apps[key]];
    for (final app in apps.values) {
      if (picked.length >= 8) break;
      if (!picked.contains(app)) picked.add(app);
    }
    return picked.take(8).toList();
  }

  Widget _card(Ios p, Widget child) => Padding(
    padding: EdgeInsets.only(bottom: p(16)),
    // The backdrop already blurs; the cards only tint it.
    child: Glass(radius: p(26), tint: 0.16, blur: false, child: child),
  );

  Widget _heading(Ios p, String text) => Padding(
    padding: EdgeInsets.fromLTRB(p(14), 0, p(14), p(8)),
    child: Text(text, style: sf(p(20), weight: 700)),
  );

  Widget _symbol(Ios p, IconData icon) => Container(
    width: p(40),
    height: p(40),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
    child: Icon(icon, size: p(22), color: Colors.white),
  );

  Widget _row(Ios p, {required Widget leading, required String title, String? detail, required VoidCallback onTap}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: p(14), vertical: p(9)),
      child: Row(
        children: [
          leading,
          SizedBox(width: p(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(17))),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sf(p(13), color: Colors.white.withValues(alpha: 0.6)),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: p(22), color: Colors.white.withValues(alpha: 0.4)),
        ],
      ),
    ),
  );

  /// Rows on one card, parted by the hairlines of an iOS list.
  Widget _list(Ios p, List<Widget> rows) => _card(
    p,
    Column(
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0)
            Container(
              height: 0.5,
              margin: EdgeInsets.only(left: p(66)),
              color: Colors.white.withValues(alpha: 0.22),
            ),
          row,
        ],
      ],
    ),
  );

  Widget _grid(Ios p, List<AppInfo> apps) => _card(
    p,
    Padding(
      padding: EdgeInsets.fromLTRB(p(6), p(16), p(6), p(4)),
      child: Column(
        children: [
          for (var start = 0; start < apps.length; start += 4)
            Padding(
              padding: EdgeInsets.only(bottom: p(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < 4; column++)
                    Expanded(
                      child: start + column >= apps.length
                          ? const SizedBox()
                          : Builder(
                              builder: (iconContext) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _open(apps[start + column], iconContext),
                                child: Column(
                                  children: [
                                    AppIcon(app: apps[start + column], size: p(58)),
                                    SizedBox(height: p(6)),
                                    Text(
                                      apps[start + column].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: sf(p(12), weight: 500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final p = Ios.of(context);
    final q = _query.trim().toLowerCase();
    final result = q.isEmpty ? null : calculate(q);
    final matches = q.isEmpty
        ? <AppInfo>[]
        : (state.apps.values.where((a) => a.matches(q)).toList()..sort((a, b) {
            final x = a.name.toLowerCase().startsWith(q) ? 0 : 1, y = b.name.toLowerCase().startsWith(q) ? 0 : 1;
            return x != y ? x - y : a.name.compareTo(b.name);
          }));
    final showSettings = q.isNotEmpty && 'einstellungen glas anpassen sperrbildschirm'.contains(q);
    final suggestions = q.isEmpty ? _suggestions() : const <AppInfo>[];

    final field = Glass(
      radius: p(24),
      tint: 0.18,
      child: SizedBox(
        height: p(48),
        child: Row(
          children: [
            SizedBox(width: p(14)),
            Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.8), size: p(21)),
            SizedBox(width: p(8)),
            Expanded(
              child: TextField(
                controller: _text,
                autofocus: true,
                style: sf(p(17)),
                cursorColor: const Color(0xFF0A84FF),
                decoration: InputDecoration(
                  hintText: 'Suchen',
                  hintStyle: sf(p(17), color: Colors.white.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _web();
                },
              ),
            ),
            if (_query.isEmpty)
              SizedBox(width: p(14))
            else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _text.clear();
                  setState(() => _query = '');
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: p(13)),
                  child: Icon(Icons.cancel_rounded, size: p(19), color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
          ],
        ),
      ),
    );

    return Backdrop(
      dim: 0.45,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          p(16),
          islandCenter(context) * 2 + p(12),
          p(16),
          max(MediaQuery.viewInsetsOf(context).bottom, MediaQuery.viewPaddingOf(context).bottom) + p(10),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (suggestions.isNotEmpty) ...[_heading(p, 'Vorschläge'), _grid(p, suggestions)],
                  if (result != null)
                    _card(
                      p,
                      Padding(
                        padding: EdgeInsets.fromLTRB(p(16), p(12), p(16), p(14)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Rechner', style: sf(p(13), weight: 600, color: Colors.white.withValues(alpha: 0.6))),
                                  SizedBox(height: p(2)),
                                  Text('= ${_number(result)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(34), weight: 300, height: 1.15)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (matches.isNotEmpty || showSettings) ...[
                    _heading(p, 'Top-Treffer'),
                    _list(p, [
                      for (final app in matches.take(8))
                        Builder(
                          builder: (iconContext) => _row(
                            p,
                            leading: AppIcon(app: app, size: p(40)),
                            title: app.name,
                            detail: 'App',
                            onTap: () => _open(app, iconContext),
                          ),
                        ),
                      if (showSettings)
                        _row(
                          p,
                          leading: _symbol(p, Icons.tune_rounded),
                          title: 'Glas anpassen',
                          detail: 'Einstellungen',
                          onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SetupScreen(state: state))),
                        ),
                    ]),
                  ],
                  if (q.isNotEmpty) ...[
                    _heading(p, 'Im Web suchen'),
                    _list(p, [_row(p, leading: _symbol(p, Icons.search_rounded), title: _query.trim(), detail: 'Websuche', onTap: _web)]),
                  ],
                ],
              ),
            ),
            SizedBox(height: p(10)),
            field,
          ],
        ),
      ),
    );
  }

  String _number(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '')).replaceAll('.', ',');
}
