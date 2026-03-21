# AIMLauncher Language Pack

This repository is the localization source for AIMLauncher.

## Goals

- Keep all user-facing strings in locale files.
- Start with `en-US` and `fr-FR`.
- Accept community pull requests for additional languages.

## Locale Files

- `locales/en-US.json`: canonical English keys.
- `locales/fr-FR.json`: French translation.

## PR Policy

- Add or update keys in `en-US.json` first.
- Keep key sets synchronized across all locale files.
- Use UTF-8 encoding.
- Do not rename existing keys unless discussed in an issue.

## Validation

Run:

`pwsh ./tools/validate-locales.ps1`

to verify key parity between English and translated files.
