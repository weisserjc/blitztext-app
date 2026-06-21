# Blitztext iOS (Keyboard + App)

Eine iOS-Variante von Blitztext: Whisper-Diktat aus jeder App heraus über eine eigene
Tastatur. Besteht aus der Container-App (`BlitztextiOS`) und der Tastatur-Extension
(`BlitztextKeyboard`); gemeinsamer Code liegt in `BlitztextShared`.

## Ablauf

1. Nutzer aktiviert die Blitztext-Tastatur in iOS-Einstellungen und erlaubt „Vollzugriff".
2. In einem Textfeld auf die Blitztext-Tastatur wechseln und auf **Diktieren** tippen.
3. Die Tastatur öffnet die Blitztext-App (`blitztext://record?source=keyboard`).
4. Die App nimmt **sofort** auf, transkribiert über OpenAI Whisper und legt den Text im
   geteilten Schlüsselbund bereit.
5. Der Nutzer tippt oben links auf den iOS-„‹ Zurück"-Chip und ist wieder in der Ziel-App.
6. Die Tastatur erkennt den bereitliegenden Text und fügt ihn über `textDocumentProxy` ein.

## Warum die Aufnahme in der App läuft

Getestet auf iPhone (iOS 26): Eine Keyboard-Extension bekommt auf diesem Gerät **kein
Mikrofon-Signal** – `AVAudioRecorder` nimmt stumm auf, `AVAudioEngine` scheitert mit
`kAudioUnitErr_CannotDoInCurrentContext` (über mehrere AVAudioSession-Konfigurationen),
obwohl Mikrofon-Berechtigung und Vollzugriff aktiv sind. Die Aufnahme läuft daher in der
Container-App, wo das Mikrofon zuverlässig funktioniert (AVAudioEngine + AVAudioConverter
→ 16 kHz/mono/Int16 WAV).

Einen vollautomatischen Rücksprung zu einer beliebigen Vor-App gibt es über öffentliche
iOS-APIs nicht; der iOS-„‹ Zurück"-Chip (erscheint nach einem App-zu-App-Öffnen) ist der
zuverlässige, universelle Weg und wird in der App durch einen animierten Hinweis betont.

## Modi

- **Wörtlich**: 1:1-Transkription.
- **Verbessert**: zusätzlicher LLM-Schritt (`gpt-4o-mini`) korrigiert, verbessert und
  kürzt den Text, ohne den Sinn zu ändern. Umschaltbar in Tastatur, App-Aufnahme-Screen
  und als Standard in den Einstellungen.

## Geteilter Zustand & Berechtigungen

Der Transkript- und Modus-Austausch zwischen App und Tastatur läuft über den **geteilten
Schlüsselbund** (`keychain-access-groups`), nicht über App Groups (für lokale Entwicklung
mit Personal Team nicht verfügbar). Die Tastatur liest bewusst **nicht** die
Zwischenablage, da jeder Lesezugriff die iOS-„Einsetzen erlauben?"-Abfrage auslöst (inkl.
Universal Clipboard vom Mac). Vollzugriff ist für Mikrofon (App) und Schlüsselbund nötig.

Der OpenAI-API-Key wird von der App im Schlüsselbund gespeichert und mit der Tastatur
geteilt.

## Build & Installation

Die iOS-Targets sind in `BlitztextMac/project.yml` (xcodegen) definiert. Auf ein
angeschlossenes Gerät bauen/installieren:

```
cd BlitztextMac && xcodegen generate
xcodebuild -project BlitztextMac.xcodeproj -scheme BlitztextiOS -configuration Debug \
  -destination 'platform=iOS,id=<DEVICE_ID>' -derivedDataPath /tmp/blitztext-ios-dd \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=<TEAM_ID> build
xcrun devicectl device install app --device <DEVICE_ID> \
  /tmp/blitztext-ios-dd/Build/Products/Debug-iphoneos/Blitztext.app
```

Hinweis: derivedDataPath außerhalb eines synchronisierten Ordners (z. B. `/tmp`) wählen –
Datei-Provider-Attribute lassen sonst die Code-Signatur scheitern.
