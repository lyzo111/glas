import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home.dart';
import 'lock_screen.dart';
import 'native.dart';
import 'state.dart';

ThemeData get _theme => ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Inter',
  colorSchemeSeed: const Color(0xFF0A84FF),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);

/// The layout is measured in iOS points, so Android's font scale must not stretch it.
Widget _fixedText(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
  child: child!,
);

void _prepareWindow() {
  // The home screen draws its own status bar; the gesture bar stays Android's.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Native.init();
  _prepareWindow();
  final state = await AppState.load();
  runApp(
    MaterialApp(
      title: 'Glas',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      builder: _fixedText,
      home: HomeScreen(state: state),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> lockMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  Native.init();
  _prepareWindow();
  final state = await AppState.loadForLock();
  runApp(
    MaterialApp(
      title: 'Glas',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      builder: _fixedText,
      home: LockScreen(state: state),
    ),
  );
}
