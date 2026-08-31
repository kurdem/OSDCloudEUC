# Treibermanagement

Treiber werden über `config/drivers.json` gesteuert und in `OSDCloud.Drivers` aufgelöst.

## Strategien

| Strategie | Quelle | Wann angewendet |
|-----------|--------|-----------------|
| `OSDCloudDriverPack` | Hersteller-DriverPack (OSDCloud lädt automatisch anhand Modell) | während WinPE |
| `MicrosoftUpdateCatalog` | Windows Update / Update Catalog | nach OOBE (via Windows Update) |
| `VendorFolder` | lokaler/Netz-Ordner mit `.inf`-Treibern | SetupComplete (`pnputil`) |
| `None` | keine Zusatztreiber | – |

## Modell-Mappings

`drivers.json → ModelMappings` überschreibt die Profil-/Menüwahl gezielt pro Hardware:

```jsonc
{
  "Manufacturer": "Dell Inc.",
  "Model": "Latitude 5450",
  "Strategy": "OSDCloudDriverPack",
  "DriverPackName": "Latitude 5450"
}
```

Auflösungslogik (`Resolve-OSDCloudDrivers`):

1. Ausgangspunkt ist die im Profil/Menü gewählte Strategie.
2. Trifft ein `ModelMappings`-Eintrag (per Hersteller + Modell-Teilstring, `*` = Platzhalter),
   überschreibt dessen `Strategy` die Wahl.
3. Unbekannte Strategien fallen sicher auf `None` zurück.

Virtuelle Maschinen sind per `"Model": "Virtual Machine"` auf `None` gemappt – VMs benötigen
in der Regel keine DriverPacks.

## Zusammenspiel mit OSDCloud

`Get-OSDCloudDriverInvokeArgs` übersetzt die aufgelöste Strategie in Ergänzungen für
`$Global:MyOSDCloud`:

| Quelle | gesetzter Schlüssel | Wirkung |
|--------|---------------------|---------|
| `DriverPack` | `DriverPackName = 'auto'` | OSDCloud wählt DriverPack anhand Hersteller/Modell |
| `MicrosoftUpdateCatalog` | `DriverPackName = 'None'` | keine DriverPacks; Treiber via Windows Update |
| `LocalFolder` | `DriverPath = <Pfad>` | Treiberordner einbinden |
| `None` | `DriverPackName = 'None'` | keine DriverPacks |

> Prüfe mit `Get-Help Invoke-OSDCloud -Full` bzw. `Test-OSDCloudPrerequisites.ps1`, welche
> Schlüssel deine installierte OSD-Version tatsächlich auswertet, und passe drivers.json
> bei Bedarf an. Es werden bewusst nur dokumentierte Mechanismen verwendet.

## Post-Install

`scripts/postinstall/Install-Drivers.ps1` führt in der SetupComplete-Phase die zur Strategie
passende Aktion aus (z. B. `pnputil /add-driver` bei `VendorFolder`).
