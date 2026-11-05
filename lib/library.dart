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
        QuickAction('Zum Home-Bildschirm', Icons.add_box_outlined, () {
          _state.layout.addApp(app.key);
          _state.commit();
        }),
        QuickAction('App-Info', Icons.info_outline, () => Native.call('appInfo', app.package)),
        QuickAction('App löschen', Icons.delete_outline, () => Native.call('uninstall', app.package), destructive: true),
      ],
    ),
  );

  Widget _icon(AppInfo app, double size) => Builder(
    builder: (iconContext) => GestureDetector(
      onTap: () => _state.launch(app, iconContext),
      onLongPressStart: (d) => _menu(app, d.globalPosition),
      child: AppIcon(app: app, size: size, badge: _state.badges[app.package] ?? 0),
    ),
  );

  void _openCategory(String name, List<AppInfo> apps) => openOverlay<void>(
    context,
    (_) => Backdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  childAspectRatio: 0.78,
                  children: [
                    for (final app in apps)
                      Column(
                        children: [
                          _icon(app, 60),
                          const SizedBox(height: 5),
                          Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(12, weight: 500)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _category(String name, List<AppInfo> apps) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.maxWidth - 40) / 2;
        final overflow = apps.length > 4;
        final shown = apps.take(overflow ? 3 : 4).toList();
        return Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Glass(
                radius: 24,
                tint: 0.14,
                blur: false,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final app in shown) _icon(app, size),
                      if (overflow)
                        GestureDetector(
                          onTap: () => _openCategory(name, apps),
                          child: SizedBox.square(
                            dimension: size,
                            child: Wrap(
                              spacing: 3,
                              runSpacing: 3,
                              children: [for (final app in apps.skip(3).take(4)) AppIcon(app: app, size: (size - 3) / 2)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, style: sf(12, weight: 500, shadows: iconShadow)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = _state.apps.values.toList();
    final search = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Glass(
        radius: 18,
        tint: 0.16,
        blur: false,
        child: TextField(
          style: sf(17),
          decoration: const InputDecoration(
            hintText: 'App-Mediathek',
            prefixIcon: Icon(Icons.search, color: Colors.white70),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (v) => setState(() => _query = v),
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final app in found)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _icon(app, 44),
                        const SizedBox(width: 14),
                        Expanded(child: Text(app.name, style: sf(16))),
                      ],
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
    final names = groups.keys.toList()..sort();
    for (final list in groups.values) {
      list.sort((a, b) => (b.role == null ? 0 : 1) - (a.role == null ? 0 : 1));
    }
    return Column(
      children: [
        search,
        Expanded(
          child: GridView.count(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewPaddingOf(context).bottom + 16),
            physics: const BouncingScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 20,
            childAspectRatio: 0.88,
            children: [if (recent.isNotEmpty) _category('Vorschläge', recent.take(4).toList()), for (final name in names) _category(name, groups[name]!)],
          ),
        ),
      ],
    );
  }
}
