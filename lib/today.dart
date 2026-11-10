import 'package:flutter/material.dart';

import 'glass.dart';
import 'layout.dart';
import 'state.dart';
import 'widgets.dart';

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

  /// Entries whose kind or size no longer exists are skipped.
  (WidgetKind, WidgetSize)? _parse(String entry) {
    final parts = entry.split(':');
    final kind = WidgetKind.values.asNameMap()[parts.first];
    if (kind == null || !kind.builtIn) return null;
    final size = WidgetSize.values.asNameMap()[parts.length > 1 ? parts[1] : ''];
    return (kind, size != null && kind.sizes.contains(size) ? size : kind.sizes.first);
  }

  void _remove(String entry) {
    setState(() => _today.remove(entry));
    widget.state.commit();
  }

  /// Small widgets pair up, wide ones take a row of their own.
  List<List<(String, WidgetKind, WidgetSize)>> _rows() {
    final rows = <List<(String, WidgetKind, WidgetSize)>>[];
    for (final entry in _today) {
      final parsed = _parse(entry);
      if (parsed == null) continue;
      final item = (entry, parsed.$1, parsed.$2);
      final small = parsed.$2.width < 4;
      if (small && rows.isNotEmpty && rows.last.length == 1 && rows.last.first.$3.width < 4) {
        rows.last.add(item);
      } else {
        rows.add([item]);
      }
    }
    return rows;
  }

  Widget _widget(Ios p, String entry, WidgetKind kind, WidgetSize size) => Stack(
    clipBehavior: Clip.none,
    children: [
      SizedBox(
        width: size.width == 4 ? p.fullWidth : p.smallWidth,
        height: p.icon + (size.height - 1) * p.rowPitch,
        child: IgnorePointer(
          ignoring: _editing,
          child: GestureDetector(
            onTap: () => openWidget(kind, widget.state),
            child: HomeWidget(kind: kind, size: size, state: widget.state, scale: p.unit),
          ),
        ),
      ),
      if (_editing)
        Positioned(
          left: -p(8),
          top: -p(8),
          child: GestureDetector(
            onTap: () => _remove(entry),
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
                          children: [for (final (entry, kind, size) in row) _widget(p, entry, kind, size)],
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
