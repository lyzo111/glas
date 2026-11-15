import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'appwidgets.dart';
import 'glass.dart';
import 'layout.dart';
import 'state.dart';
import 'widgets.dart';

/// How a widget of another app is kept in the Today view: "app:size:host id:provider:app name".
String todayAppEntry(WidgetSize size, int hostId, WidgetProvider provider) => 'app:${size.name}:$hostId:${provider.id}:${provider.app}';

/// The iOS Today view: the page left of the first one, reached by the same swipe as any
/// other page. It holds the widgets the user picks, on the grid of the home screen, so two
/// small ones share a row. It is edited together with the home screen: holding a widget
/// starts it, the plus of the edit bar adds to it.
class TodayView extends StatefulWidget {
  const TodayView({super.key, required this.state, required this.editing, required this.wiggle, required this.onSearch, required this.onEdit});
  final AppState state;

  /// The home screen's edit mode, and its wiggle from 0 to 1 and back.
  final bool editing;
  final Animation<double> wiggle;

  /// Pulling the view down opens the search, as on the home screen.
  final VoidCallback onSearch;
  final VoidCallback onEdit;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  bool _searching = false;

  List<String> get _today => widget.state.settings.today;

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

  Widget _widget(Ios p, String entry, WidgetItem item) {
    final face = _face(p, entry, item);
    if (!widget.editing) return face;
    // Neighbours lean opposite ways, as the icons of the home screen do.
    final way = entry.hashCode.isEven ? 1 : -1;
    return AnimatedBuilder(
      animation: widget.wiggle,
      child: face,
      builder: (_, child) => Transform.rotate(angle: way * (widget.wiggle.value - 0.5) * 0.018, child: child),
    );
  }

  Widget _face(Ios p, String entry, WidgetItem item) => Stack(
    clipBehavior: Clip.none,
    children: [
      SizedBox(
        width: item.width == 4 ? p.fullWidth : p.smallWidth,
        height: p.icon + (item.height - 1) * p.rowPitch,
        // Android draws a widget of another app and takes its taps itself.
        child: item.kind == WidgetKind.app
            ? AppWidgetView(item: item, live: true, locked: widget.editing)
            : IgnorePointer(
                ignoring: widget.editing,
                child: GestureDetector(
                  onTap: () => openWidget(item.kind, widget.state),
                  child: HomeWidget(kind: item.kind, size: item.size, state: widget.state, scale: p.unit),
                ),
              ),
      ),
      if (widget.editing)
        Positioned(
          left: -p(8),
          top: -p(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _remove(entry, item),
            child: Container(
              width: p(24),
              height: p(24),
              decoration: const BoxDecoration(
                color: Color(0xF2C9C9CE),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 3, color: Color(0x33000000))],
              ),
              child: Icon(CupertinoIcons.minus, size: p(15), color: const Color(0xFF2C2C2E)),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final rows = _rows();
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.dragDetails != null && n.metrics.pixels < -p(80) && !_searching && !widget.editing) {
          _searching = true;
          widget.onSearch();
          Future.delayed(const Duration(milliseconds: 600), () => _searching = false);
        }
        return false;
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, p.gridTop, 0, MediaQuery.viewPaddingOf(context).bottom + p(40)),
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
                widget.editing ? 'Tippe oben links auf den Pinsel,\num Widgets hinzuzufügen' : 'Noch keine Widgets',
                textAlign: TextAlign.center,
                style: sf(p(17), color: Colors.white70, height: 1.3),
              ),
            ),
          if (!widget.editing)
            Center(
              child: GestureDetector(
                onTap: widget.onEdit,
                child: Glass(
                  radius: p(18),
                  tint: 0.16,
                  blur: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: p(18), vertical: p(9)),
                    child: Text('Bearbeiten', style: sf(p(15), weight: 600)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
