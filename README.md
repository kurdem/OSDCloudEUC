# OSDCloudEUC

**Vollautomatisierte Windows-11-Installation mit OSDCloud – zentral über GitHub gesteuert.**

OSDCloudEUC bootet Windows-Clients per **USB**, **PXE/iPXE** oder **ISO** in ein
angepasstes OSDCloud-WinPE. Nach dem Start lädt das System seine Deployment-Konfiguration
und die verfügbaren Profile aus einem GitHub-Repository und führt – interaktiv oder als
**Zero-Touch** – die Installation aus. Menüeinträge und erlaubte Optionen sind **nicht**
im PowerShell-Code hinterlegt, sondern werden vollständig über **JSON-Dateien** gesteuert.

> Architekturentscheidung: OSDCloudEUC nutzt das klassische, breit unterstützte
> **`OSD`-Modul** (David Segura). Unterschiede zur neueren `OSD.Workspace`-Architektur
> sind in [`docs/Architecture.md`](docs/Architecture.md) dokumentiert.

---

## Inhaltsverzeichnis

- [Funktionsüberblick](#funktionsüberblick)
- [Ablauf (Zielbild)](#ablauf-zielbild)
- [Repository-Struktur](#repository-struktur)
- [Voraussetzungen](#voraussetzungen)
- [Verwendete Cmdlets (Cmdlet-Matrix)](#verwendete-cmdlets-cmdlet-matrix)
- [Schnellstart](#schnellstart)
- [Konfiguration](#konfiguration)
- [Sicherheit](#sicherheit)
- [Tests & Validierung](#tests--validierung)
- [Dokumentation](#dokumentation)
- [Lizenz](#lizenz)

---

## Funktionsüberblick

- **Zentrale Steuerung über GitHub** – global.json + referenzierte Konfigurationen und Profile.
- **Datengetriebene Menüführung** – Konsolenmenü, robust in WinPE, komplett aus `deployments.json`.
- **Zero-Touch** – vollautomatisch anhand eines Profils, ohne Interaktion.
- **Bootmethoden** – USB-Stick, PXE/iPXE (wimboot über HTTP), ISO für VMs/Tests.
- **Hardwareerkennung** – Hersteller/Modell/Serie/UEFI/SecureBoot/TPM, Modell-basierte Treiberwahl.
- **Treiber- & Update-Strategien** – konfigurierbar (DriverPack, Update Catalog, lokal / alle, nur Security, Defender).
- **Domain / Entra / Workgroup** – Post-Install-Enrollment ohne gespeicherte Secrets.
- **Sicherheit** – AllowedHosts-Enforcement, HTTPS-Pflicht, optionale Hash-/Signaturprüfung, Disk-Wipe-Bestätigung.
- **Robustheit** – Timeout/Retry beim Laden, Fallback auf lokal eingebettete Konfiguration, strukturiertes Logging.

## Ablauf (Zielbild)

```
USB / PXE / ISO
   └─► OSDCloud-WinPE ─► Startnet.ps1
         ├─ Initialize-Network.ps1        (Netz, DNS, Konnektivität)
         └─ Invoke-GitHubBootstrap.ps1    (Konfiguration laden + validieren)
               ├─ Zero-Touch?  ── ja ─► Start-ZeroTouchDeployment.ps1
               │                └ nein ─► Start-DeploymentMenu.ps1  (Konsolenmenü)
               └─► Start-OSDCloudDeployment.ps1 ─► Invoke-OSDCloud (OSD-Modul)
                       └─► SetupComplete ─► Treiber ▸ Updates ▸ Rename ▸ Enrollment
```

## Repository-Struktur

```
config/       JSON-Konfiguration (global, deployments, OS, drivers, updates, networks, security) + Schemas
profiles/     Deployment-Profile (DE, EN, Test/Zero-Touch)
src/          Einstiegs-/Build-Skripte + PowerShell-Module (src/modules)
scripts/      winpe/ (Start, Netz, Bootstrap), specialize/ (SetupComplete), postinstall/ (Treiber, Updates, Rename, Enroll)
pxe/          iPXE-Boot- und Menüskripte + DHCP-Beispiele
tests/        Pester-Tests (Config, Menu, Hardware, Security)
docs/         Architektur- und Betriebsdokumentation
.github/      CI-Workflows und CODEOWNERS
```

## Voraussetzungen

| Komponente        | Zweck                                                            | Hinweis |
|-------------------|------------------------------------------------------------------|---------|
| Windows 10/11     | Build-Host für Medienerstellung                                  | Nicht für WinPE selbst |
| Windows ADK       | WinPE-Umgebung, oscdimg (ISO), DISM                              | Passende ADK-Version zur Ziel-Windows-Version |
| PowerShell 5.1    | Laufzeit in WinPE                                                | Skripte sind 5.1-kompatibel |
| PowerShell 7      | optional für CI/Build auf modernen Hosts                        | |
| `OSD`-Modul       | OSDCloud-Cmdlets (Build, USB, Deployment)                        | `Install-Module OSD -Force` |
| Pester 5.5+       | Tests                                                            | nur Entwicklungs-/CI-Host |

> **Verifikation:** Führe vor dem ersten Build [`src/Test-OSDCloudPrerequisites.ps1`](src/Test-OSDCloudPrerequisites.ps1)
> auf einer Windows-ADK-Maschine aus. Das Skript prüft OS, PowerShell, ADK, die
> Modulversionen und **jedes** in der folgenden Matrix genannte Cmdlet auf tatsächliche
> Verfügbarkeit. So werden Abweichungen deiner installierten Modulversion sofort sichtbar.

## Verwendete Cmdlets (Cmdlet-Matrix)

Alle nicht-trivialen OSDCloud-Cmdlets, die dieses Projekt aufruft, mit Herkunftsmodul und
einer geprüften Mindestversion. **Diese Matrix ist auf einer Windows-ADK-Maschine mit
`Test-OSDCloudPrerequisites.ps1` gegen deine installierte Version zu bestätigen** – die
Entwicklung erfolgte gegen die öffentlich dokumentierte Cmdlet-Oberfläche des `OSD`-Moduls,
ohne Cmdlets oder Parameter zu erfinden.

| Cmdlet                  | Modul | Geprüfte Mindestversion | Verwendung in            |
|-------------------------|-------|-------------------------|--------------------------|
| `New-OSDCloudTemplate`  | OSD   | 24.1.1                  | `Build-OSDCloudMedia.ps1`|
| `New-OSDCloudWorkspace` | OSD   | 24.1.1                  | `Build-OSDCloudMedia.ps1`|
| `Edit-OSDCloudWinPE`    | OSD   | 24.1.1                  | `Build-OSDCloudMedia.ps1`|
| `New-OSDCloudISO`       | OSD   | 24.1.1                  | `Build-OSDCloudMedia.ps1`|
| `New-OSDCloudUSB`       | OSD   | 24.1.1                  | `Update-OSDCloudMedia.ps1`|
| `Update-OSDCloudUSB`    | OSD   | 24.1.1                  | `Update-OSDCloudMedia.ps1`|
| `Invoke-OSDCloud`       | OSD   | 24.1.1                  | `Start-OSDCloudDeployment.ps1` |

Weitere verwendete Standard-Cmdlets (Bordmittel, keine OSD-Abhängigkeit):
`Get-CimInstance`, `Get-FileHash`, `Get-AuthenticodeSignature`, `Confirm-SecureBootUEFI`
(SecureBoot-Modul), `Get-Disk`/`Get-Volume`/`Get-NetIPAddress` (Storage/Net-Module),
`Rename-Computer`, `Add-Computer`, `Test-Json` (Schema-Modus erst ab PowerShell 6+).

> **Automatisierung von `Invoke-OSDCloud`:** Die Deployment-Parameter (OSName, OSEdition,
> OSLanguage, OSActivation, ZTI, DriverPack) werden über die dokumentierte Hashtable
> `$Global:MyOSDCloud` gesetzt, die `Invoke-OSDCloud` einliest. Prüfe die für deine
> OSD-Version gültigen Schlüssel/Parameter (siehe `Get-Help Invoke-OSDCloud -Full`).

## Schnellstart

### 1. Voraussetzungen prüfen (Windows + ADK)

```powershell
Install-Module OSD -Force
git clone https://github.com/kurdem/OSDCloudEUC.git
cd OSDCloudEUC
.\src\Test-OSDCloudPrerequisites.ps1
```

### 2. Konfiguration anpassen

`config/global.json` → `Repository.Owner` / `Repository.Name` / `Branch` auf dein
Konfigurations-Repository setzen (Default: `kurdem/OSDCloudEUC` @ `main`).

### 3. Medien bauen

```powershell
# ISO + WinPE erstellen
.\src\Build-OSDCloudMedia.ps1 -WorkspacePath C:\OSDCloud\Workspace

# USB-Stick erstellen bzw. aktualisieren
.\src\Update-OSDCloudMedia.ps1 -Mode New       # neuer Stick
.\src\Update-OSDCloudMedia.ps1 -Mode Update    # vorhandenen Stick aktualisieren
```

Für PXE siehe [`pxe/README.md`](pxe/README.md).

### 4. Client booten

Der Client startet ins WinPE, lädt die Konfiguration aus GitHub und zeigt das Menü
(oder läuft Zero-Touch, wenn in `global.json` aktiviert).

## Konfiguration

Details in [`docs/GitHub-Configuration.md`](docs/GitHub-Configuration.md). Kern von
`config/global.json`:

```jsonc
{
  "Repository":  { "Provider": "GitHub", "Owner": "kurdem", "Name": "OSDCloudEUC", "Branch": "main" },
  "Deployment":  { "DefaultProfile": "Windows11-Enterprise-DE", "EnableInteractiveMenu": true, "EnableZeroTouch": false },
  "Network":     { "TimeoutSeconds": 30, "RetryCount": 4, "FallbackMode": "LocalConfig" },
  "Security":    { "ValidateHashes": true, "RequireSignedScripts": false, "AllowedHosts": [ "raw.githubusercontent.com", "github.com", "api.github.com" ] }
}
```

Unterstützt werden öffentliche und private GitHub-Repos, GitHub Enterprise Server, Releases
(versionierte Konfiguration über Tags), Branch-/Tag-Auswahl, ein interner HTTPS-Webserver
als Alternativquelle sowie der Fallback auf die im WinPE eingebettete Konfiguration.

## Sicherheit

Siehe [`SECURITY.md`](SECURITY.md) und [`docs/Security-Concept.md`](docs/Security-Concept.md).
Kurz: HTTPS-Pflicht, AllowedHosts-Enforcement, Schema-Validierung, optionale Hash-/
Signaturprüfung, Disk-Wipe-Bestätigung, keine Secrets im Repository.

## Tests & Validierung

```powershell
# Pester-Tests (Config, Menu, Hardware, Security)
Invoke-Pester -Path .\tests

# Voraussetzungen/Cmdlets auf dem Build-Host prüfen
.\src\Test-OSDCloudPrerequisites.ps1
```

CI validiert bei jedem Push JSON (Wohlgeformtheit + Schema) und PowerShell
(Parse + PSScriptAnalyzer + Pester). Siehe `.github/workflows/`.

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [Architecture.md](docs/Architecture.md) | Aufbau, Datenfluss, OSD vs. OSD.Workspace |
| [USB-Deployment.md](docs/USB-Deployment.md) | USB-Stick erstellen und nutzen |
| [PXE-Deployment.md](docs/PXE-Deployment.md) | PXE/iPXE einrichten |
| [GitHub-Configuration.md](docs/GitHub-Configuration.md) | Konfigurations- und Profilsteuerung |
| [Driver-Management.md](docs/Driver-Management.md) | Treiberstrategien |
| [Update-Management.md](docs/Update-Management.md) | Windows-Update-Strategien |
| [Troubleshooting.md](docs/Troubleshooting.md) | Fehlerdiagnose |
| [Security-Concept.md](docs/Security-Concept.md) | Sicherheitskonzept |

## Lizenz

Veröffentlicht unter der [GNU General Public License v3.0](LICENSE).
