# Localization Contributing Guide

1. Fork the repository and create a feature branch.
2. If adding new strings, update `locales/en-US.json` first.
3. Add matching translations in `locales/fr-FR.json`.
4. Run `pwsh ./tools/validate-locales.ps1`.
5. Open a pull request with a short summary and screenshots (if UI text changed).

## Key Naming

Use `PascalCase` with section prefixes:

- `MainWindow.*`
- `Settings.*`
- `InstallQueue.*`
- `Notifications.*`
- `Dialogs.*`
