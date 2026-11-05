import 'package:flutter/material.dart';

import 'glass.dart';
import 'layout.dart';
import 'state.dart';
import 'widgets.dart';

/// The iOS Today view left of the first page: a column of widgets the user picks.
class TodayView extends StatefulWidget {
  const TodayView({super.key, required this.state, required this.onSearch, required this.onAdd});
  final AppState state;
  final VoidCallback onSearch;

  /// Opens the widget gallery; the picked widget arrives through the settings.
  final Future<void> Function() onAdd;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  bool _editing = false;

  List<String> get _today => widget.state.settings.today;

  /// Entries whose kind or size no longer exists are skipped.
  (WidgetKind, WidgetSize)? _parse(String entry) {
    final parts = entry.split(':');
    final kind = WidgetKind.values.asNameMap()[parts.first];
    if (kind == null) return null;
    final size = WidgetSize.values.asNameMap()[parts.length > 1 ? parts[1] : ''];
    return (kind, size != null && kind.sizes.contains(size) ? size : kind.sizes.first);
  }

  void _remove(String entry) {
    setState(() => _today.remove(entry));
    widget.state.commit();
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Backdrop(
      dim: 0.28,
      onDismiss: () => Navigator.of(context).pop(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -250) Navigator.of(context).pop();
        },
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(p(27), p(14), p(27), p(40)),
            physics: const BouncingScrollPhysics(),
            children: [
              GestureDetector(
                onTap: widget.onSearch,
                child: Glass(
                  radius: p(18),
                  tint: 0.16,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: p(12), vertical: p(9)),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.8), size: p(20)),
                        SizedBox(width: p(6)),
                        Text('Suchen', style: sf(p(17), color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: p(22)),
              for (final entry in _today)
                if (_parse(entry) case (final kind, final size))
                  Padding(
                    padding: EdgeInsets.only(bottom: p(22)),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: size.width == 4 ? p.fullWidth : p.smallWidth,
                            height: p.icon + (size.height - 1) * p.rowPitch,
                            child: IgnorePointer(
                              ignoring: _editing,
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
                                decoration: const BoxDecoration(color: Color(0xE6303036), shape: BoxShape.circle),
                                child: Icon(Icons.remove, size: p(16), color: Colors.white),
                              ),
                            ),
                          ),
                      ],
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
      radius: p(16),
      tint: 0.16,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: p(16), vertical: p(8)),
        child: Text(label, style: sf(p(15), weight: 600)),
      ),
    ),
  );
}
