# Troubleshooting

## Logs

- **WinPE:** `X:\OSDCloud\Logs\OSDCloudEUC-*.log` (+ Transcript). Ausgangspunkt für die
  Bootstrap-/Deployment-Phase.
- **Ziel-Windows (SetupComplete):** `C:\OSDCloud\Logs\SetupComplete-*.log`.
- **OSDCloud selbst:** `C:\OSDCloud\Logs` bzw. die vom OSD-Modul erzeugten Logs.

Log-Level und -Ziel werden in `config/global.json → Logging` gesteuert (`Level`, `DebugMode`,
`Target`, `EnableTranscript`). Für die Diagnose `DebugMode` bzw. `Level = "Debug"` setzen.

## Häufige Probleme

### Cmdlet nicht gefunden (z. B. Invoke-OSDCloud)

```
Invoke-OSDCloud … ist nicht verfügbar.
```
→ OSD-Modul fehlt oder ist zu alt. Auf dem Build-Host `Install-Module OSD -Force` und
`.\src\Test-OSDCloudPrerequisites.ps1` ausführen. Die Prereq-Prüfung listet jedes erwartete
Cmdlet mit Fundort/Version.

### Konfiguration lädt nicht aus GitHub

- **AllowedHosts:** Host muss in `global.json → Security.AllowedHosts` stehen und **HTTPS**
  sein. Sonst: `Host '…' steht nicht in der AllowedHosts-Liste`.
- **Netzwerk:** In WinPE `Initialize-Network.ps1` prüft Konnektivität. Ohne IP/DNS greift der
  Fallback auf die lokale Kopie – im Log erscheint `Offline: verwende lokal eingebettete Konfiguration`.
- **Privates Repo:** `OSDCLOUD_GITHUB_TOKEN` gesetzt? Ohne Token → 404 auf Raw-URLs.
- **Timeout/Retry:** `Network.TimeoutSeconds`/`RetryCount` erhöhen.

### Schema-Validierung schlägt fehl

```
global.json entspricht nicht dem Schema (global.schema.json).
```
→ Lokal mit ajv prüfen (siehe `.github/workflows/validate-json.yml`) oder in PowerShell 7:
`Test-Json -Json (gc config/global.json -raw) -Schema (gc config/schema/global.schema.json -raw)`.
In WinPE (PS 5.1) wird nur Wohlgeformtheit geprüft – Schemafehler fallen dort ggf. erst in CI auf.

### USB bootet nicht

- UEFI-Bootreihenfolge prüfen; bei reinem UEFI Legacy/CSM deaktivieren.
- Secure Boot: OSDCloud-WinPE ist signiert; bei Problemen temporär Secure Boot prüfen.
- Stick mit `-Mode New` neu erstellen, falls die WinPE-Partition beschädigt ist.

### PXE bootet nicht / Menü erscheint nicht

- `${boot-url}` in `boot.ipxe` **und** `ipxe-menu.ipxe` korrekt?
- Liegen `wimboot`, `boot/BCD`, `boot/boot.sdi`, `sources/boot.wim` am HTTP-Server?
- DHCP-Architektur-Weiche (UEFI vs. Legacy) korrekt? Siehe `pxe/examples/`.
- In der iPXE-Shell manuell testen: `chain http://…/boot.ipxe`.

### Disk-Wipe-Abbruch

Die Bestätigungsphrase (Standard `WIPE`, `security.json → DiskWipe.ConfirmationPhrase`) muss
**exakt** (Groß-/Kleinschreibung) eingegeben werden. Im Zero-Touch-Modus mit
`SkipDiskWipeConfirmation`/`-Force` entfällt die Abfrage.

### Post-Install-Schritte laufen nicht

- Liegt `C:\Windows\Setup\Scripts\SetupComplete.cmd` (+ `.ps1`) vor? Wird von
  `Start-OSDCloudDeployment.ps1` (`Stage-OSDCloudPostInstall`) bereitgestellt.
- Existiert `C:\OSDCloud\Scripts\DeploymentContext.json`? Ohne Kontext werden Schritte übersprungen.
- SetupComplete läuft mit `ErrorActionPreference = Continue` – Fehler einzelner Schritte
  stehen im `SetupComplete-*.log`, brechen aber die Kette nicht ab.

## Diagnose-Kommandos (WinPE)

```powershell
# Netz
ipconfig /all
Test-OSDCloudConnectivity -TargetHosts 'raw.githubusercontent.com'

# Konfiguration testweise laden
Import-Module X:\OSDCloud\src\modules\OSDCloud.Config.psm1
Get-OSDCloudConfig -LocalConfigRoot X:\OSDCloud\config -UseLocalGlobal
```
