import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'layout.dart';
import 'native.dart';
import 'state.dart';

/// A widget another app offers, as Android reports it.
class WidgetProvider {
  WidgetProvider._(Map<String, dynamic> j)
    : id = j['provider'] as String,
      package = j['package'] as String,
      label = j['label'] as String? ?? '',
      app = j['app'] as String? ?? '',
      _cellsX = j['cellsX'] as int? ?? 2,
      _cellsY = j['cellsY'] as int? ?? 2,
      _minCellsX = j['minCellsX'] as int?,
      _minCellsY = j['minCellsY'] as int?;

  /// The provider's component, which is what Android binds.
  final String id;
  final String package;

  /// The widget's own name, such as "Streak", and the name of its app.
  final String label;
  final String app;

  final int _cellsX, _cellsY;
  final int? _minCellsX, _minCellsY;

  /// The iOS sizes this widget has room in. Android widgets come in any number of cells;
  /// one that asks for more than the grid has gets the largest size.
  List<WidgetSize> get sizes {
    final width = min(min(_minCellsX ?? _cellsX, _cellsX), 4), height = min(min(_minCellsY ?? _cellsY, _cellsY), 4);
    return [
      for (final size in WidgetSize.values)
        if (size.width >= width && size.height >= height) size,
    ];
  }

  /// The size closest to what the widget asks for.
  WidgetSize get preferred => sizes.firstWhere((s) => s.width >= _cellsX && s.height >= _cellsY, orElse: () => sizes.last);
}

/// The native widget host: lists what the installed apps offer and binds one for the home screen.
abstract final class AppWidgets {
  static const _channel = MethodChannel('glas/widgets');
  static final _previews = <String, Future<Uint8List?>>{};

  static Future<List<WidgetProvider>> providers() async {
    try {
      final list = await _channel.invokeListMethod<Map>('providers') ?? const [];
      return [for (final j in list) WidgetProvider._(j.cast<String, dynamic>())];
    } on Exception {
      return const [];
    }
  }

  /// The picture the app ships for its widget, or its icon.
  static Future<Uint8List?> preview(String provider) => _previews[provider] ??= _channel.invokeMethod<Uint8List>('preview', provider);

  /// Android's id for the new widget; null when the user said no or left the widget's setup.
  static Future<int?> bind(String provider) async {
    try {
      return await _channel.invokeMethod<int>('bind', provider);
    } on Exception {
      return null;
    }
  }

  static Future<void> delete(int id) async {
    try {
      await _channel.invokeMethod<void>('delete', id);
    } on Exception {
      // The id is lost with the host then anyway.
    }
  }
}

/// A widget of another app on the home screen. Android draws it and takes its taps; Glas
/// only gives it the place and the rounded corners of an iOS widget.
class AppWidgetView extends StatelessWidget {
  const AppWidgetView({super.key, required this.item, required this.live, this.locked = false});
  final WidgetItem item;

  /// Off for pictures of the widget, as under the finger while it is dragged: Android
  /// updates only one view per widget.
  final bool live;

  /// In edit mode the widget must not react to taps.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final id = item.hostId;
    if (!live || id == null || defaultTargetPlatform != TargetPlatform.android) {
      return Glass(
        radius: p(24),
        tint: 0.16,
        blur: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.widgets_outlined, size: p(30), color: Colors.white.withValues(alpha: 0.85)),
              SizedBox(height: p(6)),
              Text(item.title ?? item.kind.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(13), weight: 600)),
            ],
          ),
        ),
      );
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(p(24)),
      child: IgnorePointer(
        ignoring: locked,
        child: LayoutBuilder(
          builder: (context, box) => AndroidView(
            // A new size needs a new view: Android lays the widget out for the size it is told.
            key: ValueKey('$id-${item.size.name}'),
            viewType: 'glas/appwidget',
            creationParams: {'id': id, 'width': box.maxWidth, 'height': box.maxHeight},
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
      ),
    );
  }
}

/// The lower part of the widget gallery: every app that offers widgets, as in the iOS gallery.
class AppWidgetList extends StatefulWidget {
  const AppWidgetList({super.key, required this.state, required this.onPick});
  final AppState state;
  final void Function(WidgetProvider, WidgetSize) onPick;

  @override
  State<AppWidgetList> createState() => _AppWidgetListState();
}

class _AppWidgetListState extends State<AppWidgetList> {
  /// Providers by app, in the order of the apps' names; null while loading.
  List<List<WidgetProvider>>? _apps;

  @override
  void initState() {
    super.initState();
    AppWidgets.providers().then((all) {
      if (!mounted) return;
      final byApp = <String, List<WidgetProvider>>{};
      for (final provider in all) {
        byApp.putIfAbsent(provider.package, () => []).add(provider);
      }
      setState(() => _apps = byApp.values.toList()..sort((a, b) => a.first.app.toLowerCase().compareTo(b.first.app.toLowerCase())));
    });
  }

  Future<void> _open(List<WidgetProvider> app) async {
    final picked = await openOverlay<(WidgetProvider, WidgetSize)>(context, (_) => _AppWidgetSheet(state: widget.state, providers: app));
    if (picked != null) widget.onPick(picked.$1, picked.$2);
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    final apps = _apps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: p(6), bottom: p(12)),
          child: Text('Apps', style: sf(p(22), weight: 700)),
        ),
        if (apps == null || apps.isEmpty)
          Text(
            apps == null ? 'Widgets werden geladen …' : 'Keine App auf diesem Gerät bietet Widgets an.',
            style: sf(p(15), color: Colors.white.withValues(alpha: 0.65)),
          )
        else
          Glass(
            radius: p(22),
            tint: 0.14,
            blur: false,
            child: Column(
              children: [
                for (final (index, app) in apps.indexed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _open(app),
                    child: Column(
                      children: [
                        if (index > 0)
                          Container(
                            height: 0.5,
                            margin: EdgeInsets.only(left: p(66)),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: p(14), vertical: p(9)),
                          child: Row(
                            children: [
                              AppIcon(app: _appOf(app.first.package), size: p(38)),
                              SizedBox(width: p(14)),
                              Expanded(
                                child: Text(app.first.app, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(17))),
                              ),
                              Text('${app.length}', style: sf(p(15), color: Colors.white.withValues(alpha: 0.55))),
                              SizedBox(width: p(4)),
                              Icon(Icons.chevron_right_rounded, size: p(22), color: Colors.white.withValues(alpha: 0.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  AppInfo? _appOf(String package) {
    for (final app in widget.state.apps.values) {
      if (app.package == package) return app;
    }
    return null;
  }
}

/// The widgets of one app, each with the sizes it has room in.
class _AppWidgetSheet extends StatelessWidget {
  const _AppWidgetSheet({required this.state, required this.providers});
  final AppState state;
  final List<WidgetProvider> providers;

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Backdrop(
      dim: 0.5,
      tapToClose: false,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(p(27), p(16), p(27), 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: EdgeInsets.only(right: p(10), top: p(6), bottom: p(6)),
                      child: Icon(Icons.chevron_left_rounded, size: p(30), color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(providers.first.app, maxLines: 1, overflow: TextOverflow.ellipsis, style: sf(p(28), weight: 700)),
                  ),
                ],
              ),
              SizedBox(height: p(14)),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: p(30)),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final provider in providers)
                      Padding(
                        padding: EdgeInsets.only(bottom: p(26)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).pop((provider, provider.preferred)),
                              child: Container(
                                height: p(150),
                                alignment: Alignment.centerLeft,
                                child: FutureBuilder(
                                  future: AppWidgets.preview(provider.id),
                                  builder: (_, image) => image.data == null
                                      ? const SizedBox()
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(p(18)),
                                          child: Image.memory(image.data!, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                                        ),
                                ),
                              ),
                            ),
                            SizedBox(height: p(8)),
                            Text(provider.label, style: sf(p(15), weight: 600)),
                            SizedBox(height: p(8)),
                            Wrap(
                              spacing: p(8),
                              children: [
                                for (final size in provider.sizes)
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pop((provider, size)),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: p(14), vertical: p(7)),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: size == provider.preferred ? 0.3 : 0.14),
                                        borderRadius: BorderRadius.circular(p(16)),
                                      ),
                                      child: Text(size.label, style: sf(p(14), weight: 600)),
                                    ),
                                  ),
                              ],
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
  }
}
