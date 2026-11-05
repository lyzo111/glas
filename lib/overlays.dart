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

/// Search over apps, with a calculator and web search as fallbacks.
class Spotlight extends StatefulWidget {
  const Spotlight({super.key, required this.state});
  final AppState state;

  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> {
  String _query = '';

  void _open(AppInfo app, BuildContext iconContext) {
    widget.state.launch(app, iconContext);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final q = _query.trim().toLowerCase();
    final result = q.isEmpty ? null : calculate(q);
    final matches = q.isEmpty
        ? [for (final key in state.settings.recent) ?state.apps[key]]
        : (state.apps.values.where((a) => a.matches(q)).toList()..sort((a, b) {
            final x = a.name.toLowerCase().startsWith(q) ? 0 : 1, y = b.name.toLowerCase().startsWith(q) ? 0 : 1;
            return x != y ? x - y : a.name.compareTo(b.name);
          }));
    final showSettings = q.isNotEmpty && 'einstellungen glas anpassen sperrbildschirm'.contains(q);
    final p = Ios.of(context);
    final field = Glass(
      radius: p(24),
      tint: 0.14,
      child: TextField(
        autofocus: true,
        style: sf(p(17)),
        cursorColor: const Color(0xFF0A84FF),
        decoration: InputDecoration(
          hintText: 'Suchen',
          hintStyle: sf(p(17), color: Colors.white.withValues(alpha: 0.7)),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.8), size: p(21)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: p(13)),
        ),
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _query = v),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Native.call('webSearch', v.trim());
        },
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
                children: [
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '= ${_number(result)}',
                        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w300),
                      ),
                    ),
                  if (q.isEmpty && matches.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Zuletzt verwendet',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ),
                  for (final app in matches.take(12))
                    Builder(
                      builder: (iconContext) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AppIcon(app: app, size: p(44)),
                        title: Text(app.name, style: sf(p(17))),
                        onTap: () => _open(app, iconContext),
                      ),
                    ),
                  if (showSettings)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tune, color: Colors.white, size: 36),
                      title: const Text('Glas anpassen', style: TextStyle(color: Colors.white)),
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SetupScreen(state: state))),
                    ),
                  if (q.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.public, color: Colors.white, size: 36),
                      title: Text('„${_query.trim()}“ im Web suchen', style: const TextStyle(color: Colors.white)),
                      onTap: () => Native.call('webSearch', _query.trim()),
                    ),
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
