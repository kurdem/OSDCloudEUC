# Architektur

## Überblick

OSDCloudEUC trennt **Steuerung** (JSON-Konfiguration + Profile in GitHub) von der
**Ausführung** (PowerShell-Module und -Skripte im WinPE). Dadurch lassen sich
Deployment-Optionen ändern, ohne Code anzufassen.

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub-Repository (kurdem/OSDCloudEUC)                              │
│  config/*.json  ·  config/schema/*.json  ·  profiles/*.json          │
└───────────────┬─────────────────────────────────────────────────────┘
                │ Raw-HTTPS (Branch/Tag/Release), AllowedHosts, Hash
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  OSDCloud-WinPE (Client)                                             │
│                                                                     │
│  Startnet.ps1                                                        │
│    ├─ OSDCloud.Logging  (Transcript + Datei)                         │
│    ├─ Initialize-Network.ps1 → OSDCloud.Network                      │
│    └─ Invoke-GitHubBootstrap.ps1 → OSDCloud.Config                   │
│          ├─ Get-OSDCloudConfig  (Download + Schema + Fallback)       │
│          ├─ Zero-Touch → Start-ZeroTouchDeployment.ps1               │
│          └─ interaktiv → Start-DeploymentMenu.ps1 → OSDCloud.Menu    │
│                                                                     │
│  Start-OSDCloudDeployment.ps1  (Orchestrator)                       │
│    ├─ OSDCloud.Hardware  (Modell, UEFI, TPM, Disks)                  │
│    ├─ OSDCloud.Drivers   (Strategie → DriverPack/Catalog/Local)      │
│    ├─ OSDCloud.Updates   (Strategie → Kategorien/Methode)            │
│    ├─ $Global:MyOSDCloud = { OSName, OSEdition, OSLanguage, ZTI, … }  │
│    └─ Invoke-OSDCloud    (OSD-Modul – wendet Windows an)             │
└───────────────┬─────────────────────────────────────────────────────┘
                │ Reboot in OOBE/Specialize
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Windows (Ziel) – SetupComplete-Phase                               │
│  SetupComplete.cmd → SetupComplete.ps1                               │
│    ├─ Install-Drivers.ps1                                            │
│    ├─ Install-Updates.ps1                                            │
│    ├─ Rename-Computer.ps1                                            │
│    └─ Invoke-Enrollment.ps1  (Domain / Entra / Workgroup)           │
└─────────────────────────────────────────────────────────────────────┘
```

## Module

| Modul | Verantwortung | Wichtige Funktionen |
|-------|---------------|---------------------|
| `OSDCloud.Logging`  | Strukturiertes Logging, Transcript | `Initialize-OSDCloudLog`, `Write-OSDCloudLog` |
| `OSDCloud.Security` | AllowedHosts, Hash, Signatur, Disk-Wipe | `Assert-OSDCloudAllowedHost`, `Test-OSDCloudHash`, `Confirm-OSDCloudDiskWipe` |
| `OSDCloud.Config`   | Laden/Validieren der Konfiguration, Profile | `Get-OSDCloudConfig`, `Resolve-OSDCloudProfile`, `Test-OSDCloudConfigSchema` |
| `OSDCloud.Network`  | WinPE-Netz, Konnektivität, DNS | `Initialize-OSDCloudNetwork`, `Test-OSDCloudConnectivity` |
| `OSDCloud.Hardware` | Hardwareerkennung, Namensauflösung | `Get-OSDCloudHardware`, `Resolve-OSDCloudComputerName` |
| `OSDCloud.Drivers`  | Treiberstrategie → Quelle | `Resolve-OSDCloudDrivers`, `Get-OSDCloudDriverInvokeArgs` |
| `OSDCloud.Updates`  | Update-Strategie → Aktion | `Resolve-OSDCloudUpdates` |
| `OSDCloud.Menu`     | Konsolenmenü aus `deployments.json` | `Show-OSDCloudMenu`, `Select-OSDCloudOption` |

## Datengetriebenes Menü

`config/deployments.json` definiert **`MainMenu`** (die Menüpunkte) und **`Fields`**
(die auswählbaren Felder inkl. erlaubter Optionswerte). `OSDCloud.Menu` rendert ausschließlich
daraus – neue Optionen erfordern nur eine JSON-Änderung, keinen Code.

## Konfigurations-Auflösung

1. `global.json` (lokal beim Bootstrapping) → Repository/Netz/Security/Fallback.
2. Bei Konnektivität: `deployments/operating-systems/drivers/updates/networks/security.json`
   per Raw-HTTPS laden, sonst Fallback auf die eingebettete Kopie.
3. Jede Datei wird vor Verwendung gegen ihr Schema (bzw. Wohlgeformtheit) validiert.
4. `Resolve-OSDCloudProfile` verbindet ein Profil mit dem OS-Katalog zu einem vollständigen
   Deployment-Objekt (inkl. `OSName/OSEdition/OSLanguage/OSActivation` für `Invoke-OSDCloud`).

## OSD-Modul vs. OSD.Workspace

OSDCloudEUC ist bewusst auf das klassische **`OSD`-Modul** ausgelegt.

| Aspekt | `OSD` (dieses Projekt) | `OSD.Workspace` (OSDWorkspace) |
|--------|------------------------|-------------------------------|
| Reife/Verbreitung | Sehr hoch, stabil, umfangreiche Doku | Neuer, kleinere Nutzerbasis |
| Installation | `Install-Module OSD` (PSGallery) | winget-basiert, zusätzliche Abhängigkeiten |
| Medienerstellung | `New-OSDCloudTemplate`/`-Workspace`, `Edit-OSDCloudWinPE`, `New-OSDCloudISO`, `New-OSDCloudUSB` | `New-OSDWorkspace`, `Build-OSDWorkspaceWinPE`, eigene Ordnerstruktur |
| Deployment | `Invoke-OSDCloud` / `Start-OSDCloud` + `$Global:MyOSDCloud` | Workspace-eigene Build-/Deploy-Pipeline |
| API-Stabilität | Etabliert | In Bewegung |

**Warum `OSD`?** Stabilität, Verbreitung und eine dokumentierte, planbare Cmdlet-Oberfläche.
Eine Migration auf `OSD.Workspace` würde `src/Build-OSDCloudMedia.ps1` und
`src/Update-OSDCloudMedia.ps1` betreffen; die datengetriebene Steuerung (config/profiles/menu)
und die Post-Install-Kette blieben unverändert wiederverwendbar.

## Kompatibilität

Alle im WinPE laufenden Skripte/Module sind **PowerShell 5.1-kompatibel**. Schema-Validierung
mit `Test-Json -Schema` steht erst ab PowerShell 6+ zur Verfügung; in WinPE greift daher die
Wohlgeformtheitsprüfung als Fallback (siehe `Test-OSDCloudConfigSchema`).
