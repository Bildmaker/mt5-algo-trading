# GitHub-Workflow fuer den EA

## Einmalige Einrichtung

```powershell
git init
git branch -M main
git add .
git commit -m "Initial MT5 EA project structure"
git remote add origin <DEINE_GITHUB_REPO_URL>
git push -u origin main
```

Wenn das GitHub-Repository schon existiert, findest du die URL auf GitHub ueber **Code** -> **HTTPS** oder **SSH**.

## Normaler Arbeitsablauf

```powershell
git status
git switch -c feature/orb-session-rules
git add bildmaker/metatrader5/TT_ORB_2026_15M_volume
git commit -m "Add opening range session rules"
git push -u origin feature/orb-session-rules
```

Danach auf GitHub einen Pull Request von `feature/orb-session-rules` nach `main` erstellen.

## Commit-Regeln

- Ein Commit soll eine fachliche Aenderung enthalten.
- Commit-Nachrichten kurz und konkret halten.
- Backtest-Ergebnisse nur versionieren, wenn sie bewusst als Nachweis dienen.
- Generierte Dateien wie `.ex5` nicht committen.

## Branch-Vorschlag

- `main`: stabiler Stand
- `feature/...`: neue Funktionen
- `fix/...`: Fehlerbehebungen
- `research/...`: Experimente und Backtests

