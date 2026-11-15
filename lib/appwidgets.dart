import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'layout.dart';

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
              Icon(CupertinoIcons.square_grid_2x2, size: p(30), color: Colors.white.withValues(alpha: 0.85)),
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
