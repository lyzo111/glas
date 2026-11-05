# Glas

Launcher für Android mit der Bedienung von iOS: Home-Bildschirm mit Wackelmodus, Ordner, Dock,
App-Mediathek, Suche, Kontrollzentrum, Mitteilungen, eigene Widgets und ein gestaltbarer
Sperrbildschirm.

## Sperrbildschirm

Android lässt keine App die System-Sperre ersetzen. `LockActivity` liegt deshalb vor ihr und übergibt
beim Entsperren an die PIN- oder Fingerabdruck-Abfrage des Systems. Glas kann das Gerät nie selbst
entsperren. Gestartet wird sie von `NotificationService`, sobald das Display ausgeht.

## Nachbau von iOS

`lib/glass.dart` (`Ios`) rechnet in iOS-Punkten auf Basis von 393 × 852 pt. Ein Galaxy S24 hat dieselben
Proportionen, also stimmen Raster, Dock und Widgets dort exakt. `lib/icons.dart` zeichnet die Icons der
Systemapps, `lib/preset.dart` baut die Startseite aus dem, was installiert ist; alle übrigen Apps liegen
in der App-Mediathek. Erhöht man `presetVersion`, wird die gespeicherte Anordnung beim Update ersetzt.
`tool/wallpapers.dart` erzeugt die Hintergründe.

Das Wetter kommt von open-meteo.com. Dabei verlässt nur die auf zwei Stellen gerundete Position das Gerät.
SF Pro darf außerhalb von Apple-Plattformen nicht genutzt werden, deshalb ist Inter eingebaut.

## Schnellzugriffe, Doppeltippen, Antworten

Die Ecken des Sperrbildschirms folgen im Modus „Wie Android“ dem One-UI-Wert `lock_application_shortcut`.
Android lässt Apps ihn nur lesen; eine Auswahl in Glas ändert also nicht die Ecken der System-Sperre.
Doppeltippen braucht `ScreenOffService`, weil nur diese Bedienungshilfe den Bildschirm ausschalten kann, ohne
danach die PIN zu verlangen. Antworten läuft über die `RemoteInput`-Aktion der Mitteilung; Apps ohne diese Aktion
zeigen kein „Antworten“. Auf dem Sperrbildschirm wird der Text erst nach dem Entsperren abgeschickt.

## Home-Bildschirm

Wie in iOS lassen sich Seiten über die Punkte im Bearbeiten-Modus aus- und einblenden oder löschen
(`HomeLayout.hidden`). Links von Seite 1 liegt die Heute-Ansicht (`lib/today.dart`). Für den Perspektive-Zoom
schickt `Bridge` den Schwerkraftsensor mit 30 Hz, aber nur solange der Home-Bildschirm vorne ist.

## Systemhintergrund


Die App-Übersicht und die PIN-Abfrage gehören Android und lassen sich nicht umgestalten. Sie zeigen aber die
Hintergründe des Systems, deshalb setzt `AppState` beim Start und bei jeder Änderung die in Glas gewählten
Bilder auch als Home- und Sperrbildschirm-Hintergrund von Android. Das ersetzt die dort gewählten Bilder.

## Bauen

Flutter liegt in WSL (Kali). Quellcode nach `~/projects/glas` kopieren, dann `flutter test` und
`flutter build apk --release`. Während eines Gradle-Builds darf kein Emulator laufen.

Der Renderer steht in `AndroidManifest.xml` bewusst auf Skia: Impeller brachte den Android-15-Emulator
beim Anzeigen von Glas zum Absturz.
