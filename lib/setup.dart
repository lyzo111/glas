import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'glass.dart';
import 'layout.dart';
import 'lock_screen.dart';
import 'native.dart';
import 'state.dart';

const _lockColors = [0xFFFFFFFF, 0xFFFFD60A, 0xFFFF9F0A, 0xFFFF375F, 0xFF64D2FF, 0xFF30D158, 0xFFBF5AF2];

/// The place for permissions, wallpaper and lock screen.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state, this.wallpaperOnly = false});
  final AppState state;

  /// Only the wallpapers, for "Hintergrund bearbeiten" in the home screen editor.
  final bool wallpaperOnly;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  AppState get _state => widget.state;
  Settings get _settings => _state.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _state.refresh();
  }

  Widget _permission(String title, String subtitle, String key, VoidCallback onTap) {
    final granted = _state.permissions[key] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Color(0xFF30D158))
          : TextButton(onPressed: onTap, child: const Text('Erlauben')),
    );
  }

  Widget _option(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: (v) {
      onChanged(v);
      _state.commit();
    },
  );

  Future<void> _toggleLock(bool on) async {
    _settings.lockEnabled = on;
    await Native.call('setLockEnabled', on);
    _state.commit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final lockReady = _state.permissions['notifications'] == true && _state.permissions['overlay'] == true;
        return Scaffold(
          appBar: AppBar(title: Text(widget.wallpaperOnly ? 'Hintergrund' : 'Einstellungen')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.wallpaperOnly) ...[
                Text('Berechtigungen', style: theme.textTheme.titleMedium),
                _permission('Als Startbildschirm', 'Ersetzt den bisherigen Launcher', 'home', () => Native.call('requestHome')),
                _permission(
                  'Mitteilungen',
                  'Für Badges, Mitteilungen und den Sperrbildschirm',
                  'notifications',
                  () => Native.call('openPermission', 'notifications'),
                ),
                _permission(
                  'Über anderen Apps anzeigen',
                  'Damit der Sperrbildschirm erscheinen darf',
                  'overlay',
                  () => Native.call('openPermission', 'overlay'),
                ),
                _permission('Systemeinstellungen ändern', 'Für den Helligkeitsregler', 'writeSettings', () => Native.call('openPermission', 'writeSettings')),
                _permission(
                  'Doppeltippen zum Ausschalten',
                  'Bedienungshilfe „Glas Bildschirm aus“. Sie liest keine Inhalte',
                  'screenOff',
                  () => Native.call('openPermission', 'screenOff'),
                ),
                _permission('Fotos', 'Für das Fotos-Widget. Bilder bleiben auf dem Gerät', 'photos', () => Native.call('openPermission', 'photos')),
                _permission(
                  'Standort',
                  'Für das Wetter. Nur der ungefähre Ort geht an open-meteo.com',
                  'location',
                  () => Native.call('openPermission', 'location'),
                ),
                _permission('Kalender', 'Für die Termine in den Widgets', 'calendar', () => Native.call('openPermission', 'calendar')),
                const Divider(height: 32),
                Text('Home-Bildschirm', style: theme.textTheme.titleMedium),
                _option('Große Icons', 'Ohne App-Namen, wie die große Darstellung in iOS', _settings.largeIcons, (v) => _settings.largeIcons = v),
                _option('Lückenlos anordnen', 'Apps und Widgets rücken nach oben links auf, wie vor iOS 18', _settings.compactHome, (v) {
                  // Gaps back on: every page stays as it looks now.
                  if (!v) {
                    for (var page = 0; page < _state.layout.pages.length; page++) {
                      _state.layout.pin(page);
                    }
                  }
                  _settings.compactHome = v;
                  compactLayout = v;
                }),
                _option('Hintergrund weichzeichnen', null, _settings.blurHome, (v) => _settings.blurHome = v),
                _option('Hintergrund abdunkeln', null, _settings.dimHome, (v) => _settings.dimHome = v),
                _option('Perspektive-Zoom', 'Der Hintergrund bewegt sich beim Neigen mit', _settings.perspective, (v) => _settings.perspective = v),
                const Divider(height: 32),
                Text('Hintergrund', style: theme.textTheme.titleMedium),
              ],
              const SizedBox(height: 12),
              _LookGallery(state: _state),
              const SizedBox(height: 20),
              // The pair iOS shows: lock and home screen side by side, each with its own picture.
              Row(
                children: [
                  Expanded(
                    child: _ScreenPreview(
                      label: 'Sperrbildschirm',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LockEditor(state: _state))),
                      child: LockPreview(state: _state),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ScreenPreview(
                      label: 'Home-Bildschirm',
                      child: Wallpaper(preset: _settings.wallpaper, path: _settings.wallpaperPath, frosted: _settings.blurHome),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Home-Bildschirm-Hintergrund', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              _WallpaperPicker(
                custom: _settings.wallpaperPath,
                selected: _settings.wallpaperPath != null ? -1 : _settings.wallpaper,
                onPreset: (i) {
                  _settings
                    ..wallpaper = i
                    ..wallpaperPath = null;
                  _state.commit();
                },
                onCustom: (path) {
                  _settings.wallpaperPath = path;
                  _state.commit();
                },
              ),
              if (!widget.wallpaperOnly) ...[
                const Divider(height: 32),
                Text('Sperrbildschirm', style: theme.textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Glas-Sperrbildschirm'),
                  subtitle: Text(
                    lockReady
                        ? 'Erscheint vor der System-Sperre. PIN und Fingerabdruck bleiben aktiv.'
                        : 'Braucht die Rechte für Mitteilungen und „Über anderen Apps“.',
                  ),
                  value: _settings.lockEnabled && lockReady,
                  onChanged: lockReady ? _toggleLock : null,
                ),
                _option('StandBy', 'Beim Laden quer gelegt: große Uhr und Widgets, nachts rot', _settings.standBy, (v) => _settings.standBy = v),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(CupertinoIcons.paintbrush),
                  title: const Text('Sperrbildschirm gestalten'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LockEditor(state: _state))),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// iOS's wallpaper gallery: every saved look side by side, the one in use ticked. A tap
/// switches to it, a long press deletes it, the plus saves a new one and opens its editor.
class _LookGallery extends StatelessWidget {
  const _LookGallery({required this.state});
  final AppState state;

  Future<void> _delete(BuildContext context, int index) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hintergrund löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (yes == true) state.deleteLook(index);
  }

  @override
  Widget build(BuildContext context) {
    final s = state.settings;
    if (s.looks.isEmpty) s.storeLook();
    return SizedBox(
      height: 250,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < s.looks.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 100,
                child: GestureDetector(
                  onLongPress: s.looks.length > 1 ? () => _delete(context, i) : null,
                  child: _ScreenPreview(
                    label: i == s.look ? '✓ Aktiv' : 'Hintergrund ${i + 1}',
                    onTap: () => state.chooseLook(i),
                    child: LockPreview(state: state, look: i == s.look ? null : s.withLook(s.looks[i])),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 100,
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      state.chooseLook(s.looks.length);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LockEditor(state: state)));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(child: Icon(CupertinoIcons.plus, size: 36)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Neu'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A screen in miniature: drawn at full phone size, then scaled down, so it looks exact.
class _ScreenPreview extends StatelessWidget {
  const _ScreenPreview({required this.label, required this.child, this.onTap});
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return GestureDetector(
      // The miniature ignores touches, so without this only the label would take the tap.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: screen.width / screen.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FittedBox(
                child: SizedBox(
                  width: screen.width,
                  height: screen.height,
                  child: IgnorePointer(child: child),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _WallpaperPicker extends StatelessWidget {
  const _WallpaperPicker({required this.selected, required this.onPreset, required this.onCustom, this.custom});
  final int selected;

  /// The user's own picture, shown as its own tile next to the one for picking another.
  final String? custom;
  final ValueChanged<int> onPreset;
  final ValueChanged<String> onCustom;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < wallpapers.length; i++)
            GestureDetector(
              onTap: () => onPreset(i),
              child: Container(
                width: 64,
                margin: const EdgeInsets.only(right: 10),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected == i ? Colors.white : Colors.white24, width: selected == i ? 2.5 : 1),
                ),
                child: Wallpaper(preset: i),
              ),
            ),
          if (custom != null)
            Container(
              width: 64,
              margin: const EdgeInsets.only(right: 10),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected == -1 ? Colors.white : Colors.white24, width: selected == -1 ? 2.5 : 1),
              ),
              child: Wallpaper(preset: 0, path: custom),
            ),
          GestureDetector(
            onTap: () async {
              final path = await Native.pickWallpaper();
              if (path != null) onCustom(path);
            },
            child: Container(
              width: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview on top, the same controls iOS offers below: wallpaper, colour, weight, widgets.
class LockEditor extends StatefulWidget {
  const LockEditor({super.key, required this.state});
  final AppState state;

  @override
  State<LockEditor> createState() => _LockEditorState();
}

class _LockEditorState extends State<LockEditor> {
  AppState get _state => widget.state;
  Settings get _settings => _state.settings;

  void _save() {
    _state.commit();
    setState(() {});
  }

  Widget _shortcut(String label, String value, ValueChanged<String> onChanged) {
    final apps = _state.apps.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value == 'auto' || value == 'torch' || value == 'camera' || value == 'none' || _state.apps.containsKey(value) ? value : 'auto',
            items: [
              const DropdownMenuItem(value: 'auto', child: Text('Wie Android')),
              const DropdownMenuItem(value: 'torch', child: Text('Taschenlampe')),
              const DropdownMenuItem(value: 'camera', child: Text('Kamera')),
              const DropdownMenuItem(value: 'none', child: Text('Keiner')),
              for (final app in apps)
                DropdownMenuItem(
                  value: app.key,
                  child: Text(app.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              onChanged(v);
              _save();
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _settings;
    final custom = s.lockWallpaperPath != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sperrbildschirm'),
        actions: [if (s.lockEnabled) TextButton(onPressed: () => Native.call('showLock'), child: const Text('Testen'))],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 380,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: MediaQuery.sizeOf(context).aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: FittedBox(
                      child: SizedBox.fromSize(
                        size: MediaQuery.sizeOf(context),
                        child: LockPreview(state: _state),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Hintergrund', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _WallpaperPicker(
                  custom: s.lockWallpaperPath,
                  selected: custom ? -1 : (s.lockWallpaper ?? -2),
                  onPreset: (i) {
                    s
                      ..lockWallpaper = i
                      ..lockWallpaperPath = null;
                    _save();
                  },
                  onCustom: (path) {
                    s
                      ..lockWallpaper = null
                      ..lockWallpaperPath = path;
                    _save();
                  },
                ),
                TextButton(
                  onPressed: () {
                    s
                      ..lockWallpaper = null
                      ..lockWallpaperPath = null;
                    _save();
                  },
                  child: const Text('Wie Home-Bildschirm'),
                ),
                const SizedBox(height: 8),
                Text('Farbe', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final c in _lockColors)
                      GestureDetector(
                        onTap: () {
                          s.lockColor = c;
                          _save();
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: s.lockColor == c ? Colors.white : Colors.transparent, width: 3),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Schrift', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in lockFonts.entries)
                      ChoiceChip(
                        label: Text(e.value, style: TextStyle(fontFamily: e.key == 'inter' ? 'Inter' : e.key)),
                        selected: s.lockFont == e.key,
                        onSelected: (_) {
                          s.lockFont = e.key;
                          _save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: _state,
                  builder: (_, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tiefeneffekt'),
                    subtitle: Text(
                      !s.lockDepth
                          ? 'Das Motiv des Bildes tritt vor die Uhr'
                          : s.lockDepthKey == null
                          ? 'Motiv wird erkannt …'
                          : s.lockDepthPath == null
                          ? 'In diesem Bild wurde kein Motiv erkannt'
                          : 'Das Motiv steht vor der Uhr',
                    ),
                    value: s.lockDepth,
                    onChanged: (v) {
                      s.lockDepth = v;
                      _save();
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mit Fokus „Nicht stören“'),
                  subtitle: const Text('Schaltet Nicht stören ein, solange dieser Hintergrund aktiv ist'),
                  value: s.lockFocus,
                  onChanged: (v) {
                    s.lockFocus = v;
                    _save();
                    Native.call('doNotDisturb', v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Glas-Uhr'),
                  subtitle: const Text('Durchscheinende Ziffern mit Lichtkante, wie Liquid Glass'),
                  value: s.lockGlass,
                  onChanged: (v) {
                    s.lockGlass = v;
                    _save();
                  },
                ),
                Text('Größe der Uhr', style: theme.textTheme.titleMedium),
                Slider(
                  value: s.lockSize,
                  min: 0.7,
                  max: 1.3,
                  onChanged: (v) {
                    s.lockSize = v;
                    _save();
                  },
                ),
                Text('Höhe der Ziffern', style: theme.textTheme.titleMedium),
                Slider(
                  value: s.lockStretch,
                  min: 1,
                  max: 1.8,
                  onChanged: (v) {
                    s.lockStretch = v;
                    _save();
                  },
                ),
                Text('Neben dem Datum', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in const {'none': 'Nichts', 'weather': 'Wetter', 'battery': 'Akku', 'event': 'Nächster Termin'}.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: s.lockInline == e.key,
                        onSelected: (_) {
                          s.lockInline = e.key;
                          _save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Mitteilungen anzeigen als', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in const {'count': 'Anzahl', 'stack': 'Stapel', 'list': 'Liste'}.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: s.lockNotify == e.key,
                        onSelected: (_) {
                          s.lockNotify = e.key;
                          _save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Filter', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in lockFilters.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: s.lockFilter == e.key,
                        onSelected: (_) {
                          s.lockFilter = e.key;
                          _save();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Schriftstärke der Uhr', style: theme.textTheme.titleMedium),
                Slider(
                  value: s.lockWeight,
                  min: 100,
                  max: 800,
                  divisions: 7,
                  onChanged: (v) {
                    s.lockWeight = v;
                    _save();
                  },
                ),
                Text('Schnellzugriffe', style: theme.textTheme.titleMedium),
                _shortcut('Links', s.lockLeft, (v) => s.lockLeft = v),
                _shortcut('Rechts', s.lockRight, (v) => s.lockRight = v),
                const SizedBox(height: 20),
                Text('Widgets (bis zu 3)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in lockWidgetLabels.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: s.lockWidgets.contains(e.key),
                        onSelected: (on) {
                          if (on && s.lockWidgets.length >= 3) return;
                          on ? s.lockWidgets.add(e.key) : s.lockWidgets.remove(e.key);
                          _save();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once after installing: the home screen is ready behind it, this is only what
/// Android lets nobody but the user switch on.
class ReadySheet extends StatelessWidget {
  const ReadySheet({super.key, required this.state});
  final AppState state;

  Widget _row(Ios p, String title, String key, IconData icon, Color color) {
    final done = state.permissions[key] == true;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: p(7)),
      child: Row(
        children: [
          Container(
            width: p(30),
            height: p(30),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(p(7))),
            child: Icon(icon, color: Colors.white, size: p(19)),
          ),
          SizedBox(width: p(12)),
          Expanded(child: Text(title, style: sf(p(16)))),
          done
              ? Icon(CupertinoIcons.checkmark_alt, color: const Color(0xFF34C759), size: p(22))
              : GestureDetector(
                  onTap: () => Native.call(key == 'home' ? 'requestHome' : 'openPermission', key == 'home' ? null : key),
                  child: Text('Erlauben', style: sf(p(16), weight: 600, color: const Color(0xFF0A84FF))),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Ios.of(context);
    return Backdrop(
      dim: 0.25,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: p(28)),
          child: Glass(
            radius: p(34),
            tint: 0.16,
            dark: true,
            child: GestureDetector(
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.fromLTRB(p(20), p(22), p(20), p(10)),
                child: ListenableBuilder(
                  listenable: state,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fast fertig', style: sf(p(22), weight: 700)),
                      SizedBox(height: p(4)),
                      Text('Diese Schalter darf nur du selbst umlegen.', style: sf(p(14), color: Colors.white.withValues(alpha: 0.7))),
                      SizedBox(height: p(10)),
                      _row(p, 'Als Startbildschirm', 'home', Icons.home_rounded, const Color(0xFF0A84FF)),
                      _row(p, 'Mitteilungen', 'notifications', CupertinoIcons.bell_fill, const Color(0xFFFF3B30)),
                      _row(p, 'Sperrbildschirm', 'overlay', CupertinoIcons.lock_fill, const Color(0xFF5E5CE6)),
                      _row(p, 'Wetter am Standort', 'location', Icons.near_me_rounded, const Color(0xFF34C759)),
                      _row(p, 'Termine', 'calendar', Icons.calendar_month_rounded, const Color(0xFFFF9500)),
                      SizedBox(height: p(6)),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            final ready = state.permissions['notifications'] == true && state.permissions['overlay'] == true;
                            if (ready) {
                              state.settings.lockEnabled = true;
                              Native.call('setLockEnabled', true);
                              state.commit();
                            }
                            Navigator.of(context).pop();
                          },
                          child: Text('Fertig', style: sf(p(17), weight: 600, color: const Color(0xFF0A84FF))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
