# Klang zu Text — Logoentwurf

Zwei Farbvarianten derselben eigenständigen Vektorzeichnung:

Das Zeichen ist gegenüber dem ersten Entwurf um 30 Prozent vergrößert, bei unveränderter Kachel und unveränderten Farben. Es nutzt damit rund 80 Prozent der Kachelbreite.

- `sound-to-text-blue.svg`: durchgehend blau.
- `sound-to-text-blue-graphite.svg`: blaue Klangform, graue Textlinien mit einem kurzen Farbübergang.

`comparison.png` zeigt beide Entwürfe groß sowie mit 128, 64, 32 und 16 Pixeln. Die PNG-Exporte liegen zusätzlich in 1024 und 320 Pixeln vor. Der Bereich außerhalb der abgerundeten Kachel ist transparent.

Die Quellen bestehen aus fest definierten SVG-Pfaden und Verläufen. Es wurden keine SF-Symbol-Dateien, Screenshots oder KI-generierten Bildbestandteile verwendet. Die vergrößerte, ganz blaue Variante A ist als neues App-Icon übernommen. Die produktive Vektorquelle liegt unter `Sources/WhisperForMac/Resources/AppIcons/AppIcon.svg`; daraus wurden alle sieben macOS-PNG-Größen sowie `appstore.png` und `playstore.png` erzeugt.

`create-drafts.cjs` erzeugt die SVG-Quellen, PNG-Dateien und Vergleichsansicht erneut. Es benötigt Node.js und `sharp`. Wenn das Modul nicht über `require('sharp')` verfügbar ist, kann `WHISPER_SHARP_PATH` auf den absoluten Pfad des Moduls gesetzt werden.

## Lizenz

Die Logozeichnungen und Vorschaubilder in diesem Ordner sind von der MIT-Lizenz
ausgenommen. Für sie gilt die [Logo and App Icon License Exception](../../LOGO-LICENSE.md).
Der Programmcode zur Erzeugung der Grafiken bleibt unter MIT; die Logozeichnungen
selbst fallen unter die Ausnahme.
