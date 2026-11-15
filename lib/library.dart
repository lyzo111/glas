import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'glass.dart';
import 'native.dart';
import 'overlays.dart';
import 'state.dart';

/// Last page: every installed app, sorted into automatic categories.
class AppLibrary extends StatefulWidget {
  const AppLibrary({super.key, required this.state});
  final AppState state;

  @override
  State<AppLibrary> createState() => _AppLibraryState();
}

class _AppLibraryState extends State<AppLibrary> {
  String _query = '';

  AppState get _state => widget.state;

  void _menu(AppInfo app, Offset position) => openOverlay<void>(
    context,
    (_) => QuickActions(
      position: position,
      preview: AppIcon(app: app, size: Ios.of(context).icon),
      actions: [
        QuickAction('Zum Home-Bildschirm', CupertinoIcons.plus_app, () {
          _state.layout.addApp(app.key);
          _state.commit();
        }),
        QuickAction('App-Info', CupertinoIcons.info_circle, () => Native.call('appInfo', app.package)),
        QuickAction('App löschen', CupertinoIcons.trash, () => Native.call('uninstall', app.package), destructive: true),
      ],
    ),
  );

  /// [around] puts the name beside or below the icon; a tap or hold on it counts like one
  /// on the icon, instead of falling through to whatever closes the page behind.
  Widget _icon(AppInfo app, double size, {Widget Function(Widget icon)? around}) => Builder(
    builder: (iconContext) {
      final icon = AppIcon(app: app, size: size, badge: _state.badges[app.package] ?? 0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _state.launch(app, iconContext),
        onLongPressStart: (d) => _menu(app, d.globalPosition),
        child: around == null ? icon : around(icon),
      );
    },
  );

  void _openCategory(String name, List<AppInfo> apps) => openOverlay<void>(context, (context) {
    final p = Ios.of(context);
    return Backdrop(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(p(16), p(24), p(16), 0),
          child: Column(
            children: [
              Text(name, style: sf(p(30), weight: 700)),
              SizedBox(height: p(22)),
              Expanded(
                child: GridView(
                  padding: EdgeInsets.only(bottom: p(30)),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: p.rowPitch),
                  children: [
                    for (final app in apps)
                      _icon(
                        app,
                        p.icon,
                        around: (icon) => Column(
                          children: [
                            icon,
                            SizedBox(height: p(6)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: p(2)),
                              child: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(12.5), weight: 500)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });

  /// A group as iOS draws it: three apps to open at once, and in the fourth place the next
  /// four small, which open the whole group.
  Widget _category(Ios p, String name, List<AppInfo> apps) {
    return LayoutBuilder(
      builder: (context, box) {
        final pad = p(11.5), gap = p(10.5);
        final size = (box.maxWidth - pad * 2 - gap) / 2;
        final overflow = apps.length > 4;
        final shown = apps.take(overflow ? 3 : 4).toList();
        final inner = size * 0.05, between = size * 0.09;
        final small = (size - inner * 2 - between) / 2;
        return Column(
          children: [
            SizedBox.square(
              dimension: box.maxWidth,
              child: FolderPane(
                radius: p(34),
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final app in shown) _icon(app, size),
                      if (overflow)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openCategory(name, apps),
                          child: SizedBox.square(
                            dimension: size,
                            child: Padding(
                              padding: EdgeInsets.all(inner),
                              child: Wrap(
                                spacing: between,
                                runSpacing: between,
                                children: [for (final app in apps.skip(3).take(4)) AppIcon(app: app, size: small)],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: p(8)),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sf(p(13.5), weight: 500, shadows: iconShadow),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final q = _query.trim().toLowerCase();
    final all = _state.apps.values.toList();
    final search = Padding(
      padding: EdgeInsets.fromLTRB(p(24.5), p(6), p(24.5), p(30)),
      child: Glass(
        radius: p(24),
        tint: 0.16,
        blur: false,
        child: SizedBox(
          height: p(47),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The name stands in the middle with its lens, as on iOS, until something is typed.
              if (_query.isEmpty)
                IgnorePointer(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.search, color: Colors.white, size: p(21)),
                      SizedBox(width: p(7)),
                      Text('App-Mediathek', style: sf(p(19.5))),
                    ],
                  ),
                ),
              TextField(
                style: sf(p(19.5)),
                textAlign: TextAlign.center,
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: p(18)),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
      ),
    );
    if (q.isNotEmpty) {
      final found = all.where((a) => a.matches(q)).toList();
      return Column(
        children: [
          search,
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: p(24.5)),
              children: [
                for (final app in found)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: p(6)),
                    child: _icon(
                      app,
                      p(44),
                      around: (icon) => Row(
                        children: [
                          icon,
                          SizedBox(width: p(14)),
                          Expanded(child: Text(app.name, style: sf(p(17)))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    final groups = <String, List<AppInfo>>{};
    for (final app in all) {
      groups.putIfAbsent(app.category, () => []).add(app);
    }
    final recent = [for (final key in _state.settings.recent) ?_state.apps[key]];
    final added = all.where((a) => a.installed > 0).toList()..sort((a, b) => b.installed.compareTo(a.installed));
    final names = groups.keys.toList()..sort();
    for (final list in groups.values) {
      list.sort((a, b) => (b.role == null ? 0 : 1) - (a.role == null ? 0 : 1));
    }
    final tile = (MediaQuery.sizeOf(context).width - p(24.5) * 2 - p(20)) / 2;
    return Column(
      children: [
        search,
        Expanded(
          child: GridView(
            padding: EdgeInsets.fromLTRB(p(24.5), 0, p(24.5), MediaQuery.viewPaddingOf(context).bottom + p(16)),
            physics: const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: p(20), mainAxisExtent: tile + p(36)),
            children: [
              if (recent.isNotEmpty) _category(p, 'Vorschläge', recent.take(4).toList()),
              if (added.isNotEmpty) _category(p, 'Zuletzt hinzugefügt', added.take(12).toList()),
              for (final name in names) _category(p, name, groups[name]!),
            ],
          ),
        ),
      ],
    );
  }
}
