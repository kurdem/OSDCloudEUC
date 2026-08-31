# USB-Deployment

Anleitung zum Erstellen und Nutzen eines bootfähigen OSDCloud-USB-Sticks.

## Voraussetzungen

- Windows-Build-Host mit Windows ADK und `OSD`-Modul (`Install-Module OSD -Force`)
- USB-Stick ≥ 16 GB (wird formatiert – **alle Daten gehen verloren**)
- Vorheriger Build des Workspace (`Build-OSDCloudMedia.ps1`) oder ein vorhandener Workspace

## Neuen USB-Stick erstellen

```powershell
# 1. Workspace/Template + WinPE erzeugen (falls noch nicht geschehen)
.\src\Build-OSDCloudMedia.ps1 -WorkspacePath C:\OSDCloud\Workspace

# 2. USB erstellen (nutzt New-OSDCloudUSB aus dem OSD-Modul)
.\src\Update-OSDCloudMedia.ps1 -Mode New -WorkspacePath C:\OSDCloud\Workspace
```

`New-OSDCloudUSB` legt zwei Partitionen an:

- **WinPE** (FAT32, bootfähig) – das angepasste OSDCloud-WinPE
- **OSDCloud** (NTFS) – Datenpartition; hierhin kopiert `Update-OSDCloudMedia.ps1`
  die aktuelle Konfiguration (`config/`, `profiles/`, `src/`, `scripts/`) als lokalen Fallback.

## Vorhandenen USB aktualisieren

```powershell
.\src\Update-OSDCloudMedia.ps1 -Mode Update
```

Aktualisiert das WinPE (`Update-OSDCloudUSB`) und die eingebettete Konfiguration, ohne den
Stick neu zu partitionieren.

## Ablauf am Client

1. Vom USB booten (ggf. Secure Boot beachten – OSDCloud-WinPE ist signiert).
2. WinPE startet `Startnet.ps1` → Netz → GitHub-Bootstrap.
3. Bei Online-Verbindung wird die aktuelle Konfiguration aus GitHub geladen; offline greift
   der Fallback auf die USB-Kopie.
4. Menü erscheint (oder Zero-Touch startet automatisch).

## Konfiguration nur lokal verwenden

Wenn der Client bewusst **ohne** GitHub arbeiten soll, in `config/global.json` vor dem
USB-Update `Network.FallbackMode` auf `LocalConfig` belassen; ist keiner der AllowedHosts
erreichbar, wird automatisch die USB-Konfiguration verwendet. Alternativ das WinPE-Menü mit
`-UseLocalConfig` starten.

## Troubleshooting

- **USB bootet nicht:** Im UEFI die Bootreihenfolge prüfen; bei reinem UEFI ggf. Legacy/CSM
  deaktivieren. Der Stick muss als FAT32/WinPE-Partition erkannt werden.
- **Konfiguration veraltet:** `-Mode Update` erneut ausführen; die Datenpartition wird überschrieben.
- Weiteres in [Troubleshooting.md](Troubleshooting.md).
