# LM Studio Codex Starter

Dieses Projekt startet Codex gegen das aktuell in LM Studio geladene Modell.

Fuer GitHub und andere Windowsrechner ist der Ordner `install/` relevant. Er enthaelt den portablen Installer, den Gateway und die globalen CLI-Befehle.

```powershell
.\install\install.ps1
lm-studio
```

Mehr Details: [install/README.md](install/README.md)

## Start

1. LM Studio oeffnen.
2. Ein LLM laden.
3. `start-codex-lmstudio.bat` starten.

Die Batch-Datei startet bei Bedarf den LM-Studio-Server, startet den lokalen Gateway und startet danach Codex.

Systemweit geht dasselbe aus jedem Terminal, z.B. aus dem VS-Code-Terminal im aktuellen Projektordner:

```powershell
lm-studio
```

Damit arbeitet Codex im aktuellen Terminalordner.

## Desktop-App-Versuch

Der CLI-Weg ist der verlaessliche Weg. Fuer einen Desktop-App-Versuch gibt es zusaetzlich:

```powershell
lm-studio-app
```

Dieser Befehl startet den Gateway dauerhaft und oeffnet die ChatGPT/Codex Desktop App. Wenn die App bereits offen war, starte danach eine neue lokale Codex-Session. Den Gateway stoppst du mit:

```powershell
lm-studio-stop
```

## Dateien

- `start-codex-lmstudio.bat` ist der normale Starter.
- `scripts/start-codex-lmstudio.ps1` prueft LM Studio, waehlt das geladene Modell und startet Codex.
- `scripts/lmstudio-responses-gateway.js` uebersetzt Codex Responses API nach LM Studio Chat Completions.
- `.codex-home/config.toml` ist die projektlokale Codex-Konfiguration.

## Warum der Gateway noetig ist

Aktuelle Codex-Versionen erwarten einen Responses-kompatiblen Provider. Manche LM-Studio-Modelle, darunter das getestete Qwen-Modell, stolpern beim direkten Responses-Pfad ueber ihr Chat-Template. Der Gateway setzt System- und Developer-Nachrichten an den Anfang und reicht Tool-Calls an Codex zurueck.

## Mehrere geladene Modelle

Wenn mehrere LLMs in LM Studio geladen sind, fragt der Starter nach der Nummer des Modells.

## Test

Ein schneller Test aus diesem Ordner:

```powershell
cmd /c start-codex-lmstudio.bat exec --skip-git-repo-check "Reply exactly: TEST_OK"
```

Der `exec`-Modus von Codex ist restriktiver als eine interaktive Coding-Session. Fuer echte Agent-Arbeit starte einfach die Batch-Datei ohne Zusatzargumente.
