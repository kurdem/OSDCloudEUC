# Update-Management

Windows-Updates werden über `config/updates.json` gesteuert und in `OSDCloud.Updates`
aufgelöst. Die Ausführung erfolgt in der SetupComplete-Phase
(`scripts/postinstall/Install-Updates.ps1`).

## Strategien

| Strategie | Kategorien | Treiber | Methode |
|-----------|-----------|---------|---------|
| `AllUpdates` | Security, Critical, Definition, Driver, Feature | ja | PSWindowsUpdate |
| `SecurityOnly` | Security, Critical | nein | PSWindowsUpdate |
| `DefenderOnly` | Definition | nein | Defender-Signatur |
| `None` | – | – | keine Aktion |

## Methoden und Fallback

1. **PSWindowsUpdate** (bevorzugt): Ist das Modul auf dem Zielsystem verfügbar, werden Updates
   damit installiert (`Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot`). Bei `SecurityOnly`
   werden gezielt die Kategorien *Security Updates* und *Critical Updates* gewählt.
2. **USOClient** (Fallback): Ist PSWindowsUpdate nicht vorhanden, wird der Windows Update Agent
   über `usoclient.exe StartScan/StartDownload/StartInstall` angestoßen.
3. **Defender-Signatur:** Bei `DefenderOnly` wird `MpCmdRun.exe -SignatureUpdate` bzw.
   `Update-MpSignature` verwendet.

`updates.json → Fallback.Method` legt die Fallback-Methode fest (Standard: `USOClient`).

## Neustartverhalten

Updates werden mit `-IgnoreReboot` installiert, damit die SetupComplete-Kette (Rename,
Enrollment) zunächst weiterläuft. Ein finaler Neustart erfolgt durch die OOBE/den Nutzer bzw.
über eine nachgelagerte Policy – so werden Update-Reboots nicht mitten in der Provisionierung ausgelöst.

## Hinweise

- `PSWindowsUpdate` ist nicht Teil von Windows. Für den bevorzugten Pfad das Modul entweder
  im Image vorinstallieren oder in `Install-Updates.ps1` vor Nutzung bereitstellen
  (`Install-Module PSWindowsUpdate`), sofern Netzwerk/Policy dies erlauben. Ohne das Modul
  greift automatisch der USOClient-Fallback.
- Für reine Offline-/Golden-Image-Szenarien `None` wählen und Updates zentral über
  WSUS/Intune steuern.
