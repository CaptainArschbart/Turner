# Claude-Code-Setup für Turner

Jede Person richtet ihr eigenes Setup ein. Niemand überschreibt die Dateien eines anderen.

## Einrichten (einmal pro Person)
Im Projektordner in PowerShell ausführen, mit dem eigenen Namen:

```
powershell -ExecutionPolicy Bypass -File tools\claude-setup\setup.ps1 -Name DeinName
```

Danach Claude Code im Projektordner neu starten. Zum Prüfen Claude fragen: „Welche Subagenten hast du?“

## Was ist persönlich, was ist geteilt?

| Was | Ort | Für wen |
|---|---|---|
| Eigene Agenten | `%USERPROFILE%\.claude\agents\<name>-*.md` | nur dich |
| Eigene Regeln | `<Name>_claude.md` im Projekt | nur dich (über `CLAUDE.local.md` geladen, nicht im Git) |
| Godot-MCP | `claude mcp add --scope local …` | nur dich |
| Gemeinsame Regeln | `CLAUDE.md` | alle |
| Vorlagen und dieses Skript | `tools/claude-setup/` | alle |

Die Agenten tragen deinen Namen als Präfix, z. B. `arschi-gameplay`. Dadurch gibt es keine Namenskonflikte.

## Godot-MCP manuell hinzufügen
Falls das Skript den Befehl `claude` nicht findet:
```
claude mcp add --scope local godot -- cmd /c npx -y @coding-solo/godot-mcp
```
Dafür werden Node.js 18+ und Godot 4 benötigt. Falls Godot nicht gefunden wird, die Umgebungsvariable `GODOT_PATH` auf die Godot-.exe setzen.

## Vorlagen anpassen
Die Vorlagen liegen unter `templates/`. `{{NAME}}` und `{{PREFIX}}` werden beim Einrichten ersetzt.
Spätere Änderungen an den Vorlagen wirken sich nicht auf schon angelegte Dateien aus. Die bearbeitest du direkt.
