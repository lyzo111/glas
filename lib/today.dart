import 'package:flutter/material.dart';

import 'appwidgets.dart';
import 'glass.dart';
import 'layout.dart';
import 'state.dart';
import 'widgets.dart';

/// How a widget of another app is kept in the Today view: "app:size:host id:provider:app name".
String todayAppEntry(WidgetSize size, int hostId, WidgetProvider provider) => 'app:${size.name}:$hostId:${provider.id}:${provider.app}';

/// The iOS Today view left of the first page: the widgets the user picks, laid out on the
/// grid of the home screen, so two small ones share a row.
class TodayView extends StatefulWidget {
  const TodayView({super.key, required this.state, required this.onSearch, required this.onAdd});
  final AppState state;

  /// Pulling the view down opens the search, as on the home screen.
  final VoidCallback onSearch;

  /// Opens the widget gallery; the picked widget arrives through the settings.
  final Future<void> Function() onAdd;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  bool _editing = false;
  bool _searching = false;

  List<String> get _today => widget.state.settings.today;

  // A widget of another app arrives only after Android's consent, once the gallery is gone.
  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  /// Entries whose kind or size no longer exists are skipped.
  WidgetItem? _parse(String entry) {
    final parts = entry.split(':');
    final kind = WidgetKind.values.asNameMap()[parts.first];
    if (kind == null) return null;
    final size = WidgetSize.values.asNameMap()[parts.length > 1 ? parts[1] : ''];
    final item = WidgetItem('today-$entry', kind, size != null && kind.sizes.contains(size) ? size : kind.sizes.first);
    if (kind.builtIn) return item;
    final hostId = parts.length > 3 ? int.tryParse(parts[2]) : null;
    if (hostId == null) return null;
    return item
      ..hostId = hostId
      ..provider = parts[3]
      ..title = parts.skip(4).join(':');
  }

  void _remove(String entry, WidgetItem item) {
    setState(() => _today.remove(entry));
    // Android keeps a hosted widget alive until its id is given back.
    if (item.hostId != null) AppWidgets.delete(item.hostId!);
    widget.state.commit();
  }

  /// Small widgets pair up, wide ones take a row of their own.
  List<List<(String, WidgetItem)>> _rows() {
    final rows = <List<(String, WidgetItem)>>[];
    for (final entry in _today) {
      final item = _parse(entry);
      if (item == null) continue;
      final small = item.width < 4;
      if (small && rows.isNotEmpty && rows.last.length == 1 && rows.last.first.$2.width < 4) {
        rows.last.add((entry, item));
      } else {
        rows.add([(entry, item)]);
      }
    }
    return rows;
  }

  Widget _widget(Ios p, String entry, WidgetItem item) => Stack(
    clipBehavior: Clip.none,
    children: [
      SizedBox(
        width: item.width == 4 ? p.fullWidth : p.smallWidth,
        height: p.icon + (item.height - 1) * p.rowPitch,
        // Android draws a widget of another app and takes its taps itself.
        child: item.kind == WidgetKind.app
            ? AppWidgetView(item: item, live: true, locked: _editing)
            : IgnorePointer(
                ignoring: _editing,
                child: GestureDetector(
                  onTap: () => openWidget(item.kind, widget.state),
                  child: HomeWidget(kind: item.kind, size: item.size, state: widget.state, scale: p.unit),
                ),
              ),
      ),
      if (_editing)
        Positioned(
          left: -p(8),
          top: -p(8),
          child: GestureDetector(
            onTap: () => _remove(entry, item),
            child: Container(
              width: p(24),
              height: p(24),
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

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final rows = _rows();
    return Backdrop(
      dim: 0.28,
      // Taps between widgets stay here; a swipe to the left or up closes the view.
      tapToClose: false,
      onDismiss: () => Navigator.of(context).pop(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -250) Navigator.of(context).pop();
        },
        child: SafeArea(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.dragDetails != null && n.metrics.pixels < -p(80) && !_searching && !_editing) {
                _searching = true;
                widget.onSearch();
                Future.delayed(const Duration(milliseconds: 600), () => _searching = false);
              }
              return false;
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(0, p(22), 0, p(40)),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              children: [
                for (final row in rows)
                  Padding(
                    padding: EdgeInsets.only(bottom: p.rowPitch - p.icon),
                    child: Center(
                      child: SizedBox(
                        width: p.fullWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [for (final (entry, item) in row) _widget(p, entry, item)],
                        ),
                      ),
                    ),
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: p(60)),
                    child: Text(
                      'Noch keine Widgets',
                      textAlign: TextAlign.center,
                      style: sf(p(17), color: Colors.white70),
                    ),
                  ),
                Center(
                  child: Wrap(
                    spacing: p(10),
                    children: [
                      if (_editing)
                        _Button(
                          p: p,
                          label: 'Widget hinzufügen',
                          onTap: () async {
                            await widget.onAdd();
                            if (mounted) setState(() {});
                          },
                        ),
                      _Button(p: p, label: _editing ? 'Fertig' : 'Bearbeiten', onTap: () => setState(() => _editing = !_editing)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.p, required this.label, required this.onTap});
  final Ios p;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Glass(
      radius: p(18),
      tint: 0.16,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: p(18), vertical: p(9)),
        child: Text(label, style: sf(p(15), weight: 600)),
      ),
    ),
  );
}
