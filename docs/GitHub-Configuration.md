# GitHub-Konfiguration

Die gesamte Deployment-Steuerung liegt in JSON-Dateien im GitHub-Repository. Dieses Dokument
beschreibt Aufbau und Bezug der Konfiguration.

## Bezugsquellen

`config/global.json` → `Repository` steuert, woher geladen wird:

| Provider | Basis-URL | Hinweis |
|----------|-----------|---------|
| `GitHub` | `https://raw.githubusercontent.com/{Owner}/{Name}/{Branch|Tag}` | Standard |
| `GitHubEnterprise` | `https://{EnterpriseServerHost}/raw/{Owner}/{Name}/{ref}` | `EnterpriseServerHost` setzen |
| `WebServer` | `BaseUrlOverride` | interner HTTPS-Webserver |

Weitere relevante Felder:

- `UseRelease` / `ReleaseTag` – versionierte Konfiguration über einen Release-Tag statt Branch.
- `BaseUrlOverride` – überschreibt die berechnete Basis-URL vollständig.
- `AllowPrivateRepository` – erlaubt Token-Nutzung für private Repos.

## Öffentliche vs. private Repositories

- **Öffentlich:** kein Token nötig.
- **Privat:** Token über die Umgebungsvariable `OSDCLOUD_GITHUB_TOKEN` bereitstellen. Der
  Bootstrap (`Invoke-GitHubBootstrap.ps1`) liest sie automatisch und reicht sie an
  `Get-OSDCloudConfig`/`Resolve-OSDCloudProfile` weiter. Das Token wird **nie** im Repository
  oder in Logs gespeichert.

  ```powershell
  $env:OSDCLOUD_GITHUB_TOKEN = 'ghp_xxx'   # z. B. in einem geschützten Bootstrap-Schritt
  ```

## Fallback und Robustheit

- `Network.TimeoutSeconds`, `RetryCount`, `RetryDelaySeconds` – Timeout und exponentielles
  Backoff je Download.
- `Network.FallbackMode`:
  - `LocalConfig` – bei Fehler auf die im WinPE/USB eingebettete Konfiguration zurückgreifen.
  - `InternalWebServer` – alternative Quelle `Network.InternalWebServerUrl` nutzen.
  - `Fail` – hart abbrechen (für streng kontrollierte Umgebungen).

## Konfigurationsdateien

| Datei | Zweck |
|-------|-------|
| `global.json` | Repository, Deployment-Grundeinstellungen, Netz, Security, Logging |
| `deployments.json` | **Menüdefinition** und erlaubte Optionswerte je Feld |
| `operating-systems.json` | OS-Katalog (Name/Version/Edition/Sprache/Aktivierung) |
| `drivers.json` | Treiberstrategien + Modell-Mappings |
| `updates.json` | Update-Strategien |
| `networks.json` | Domain-/Entra-/Workgroup-Profile, DNS/Proxy |
| `security.json` | Hash-/Signatur-Policy, AllowedHosts, Disk-Wipe |
| `schema/*.json` | JSON-Schemas (Draft-07) für die Validierung |

## Profile

`profiles/*.json` beschreiben konkrete Deployments und referenzieren die Kataloge:

```jsonc
{
  "ProfileId": "Windows11-Enterprise-DE",
  "OperatingSystem": "Win11-24H2-Enterprise",   // → operating-systems.json
  "Language": "de-DE",
  "DriverStrategy": "OSDCloudDriverPack",        // → deployments.json / drivers.json
  "UpdateStrategy": "SecurityOnly",              // → deployments.json / updates.json
  "JoinType": "Workgroup",
  "ComputerName": "%SERIAL%",
  "ZeroTouch": false,
  "PostInstallScripts": [ "postinstall/Install-Drivers.ps1", "..." ]
}
```

`AllowedProfiles` in `global.json` begrenzt, welche Profile geladen werden dürfen.

## Menü anpassen (ohne Code)

Neue Optionen entstehen rein durch JSON-Änderungen in `deployments.json`:

```jsonc
"DriverStrategy": {
  "Label": "Treiberstrategie",
  "Type": "select",
  "Default": "OSDCloudDriverPack",
  "Options": [
    { "Id": "OSDCloudDriverPack", "Label": "OSDCloud DriverPack (Hersteller)", "Value": "OSDCloudDriverPack" }
    // weitere Optionen hier ergänzen
  ]
}
```

## Validierung

- Lokal/CI: `.github/workflows/validate-json.yml` prüft Wohlgeformtheit (alle Dateien) und
  Schema (`global`, `deployments`) mit ajv.
- Zur Laufzeit: `Test-OSDCloudConfigSchema` validiert jede Datei vor Verwendung
  (Schema-Modus ab PowerShell 6+, sonst Wohlgeformtheit).

## Versionierung

`ConfigVersion` in `global.json` dokumentiert die Konfigurationsversion. Für stabile
Rollouts `UseRelease = true` mit einem `ReleaseTag` verwenden, damit Clients eine
eingefrorene Konfiguration laden.
