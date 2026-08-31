# Sicherheitsrichtlinie

## Melden von Sicherheitslücken

Sicherheitsrelevante Probleme bitte **nicht** über öffentliche Issues melden.
Verwende stattdessen die private Sicherheitsmeldung von GitHub
("Security" → "Report a vulnerability") im Repository `kurdem/OSDCloudEUC`.

Wir bestätigen den Eingang in der Regel innerhalb von 5 Werktagen.

## Sicherheitskonzept (Kurzfassung)

OSDCloudEUC lädt Deployment-Konfigurationen aus dem Netzwerk und führt privilegierte
Aktionen (Datenträger löschen, Betriebssystem installieren) aus. Folgende Schutzmechanismen
sind implementiert; Details siehe [`docs/Security-Concept.md`](docs/Security-Concept.md).

- **AllowedHosts-Enforcement:** Downloads sind nur von den in `config/global.json`
  (`Security.AllowedHosts`) hinterlegten Hosts und ausschließlich über HTTPS erlaubt
  (`Assert-OSDCloudAllowedHost`).
- **Schema-Validierung:** Jede geladene JSON-Datei wird vor Verwendung gegen ein
  JSON-Schema geprüft (soweit `Test-Json -Schema` verfügbar; sonst Wohlgeformtheitsprüfung).
- **Hash-Prüfung (optional):** Bei `Security.ValidateHashes = true` können heruntergeladene
  Dateien gegen ein SHA256-Manifest geprüft werden (`Test-OSDCloudHash`).
- **Signaturprüfung (optional):** Bei `Security.RequireSignedScripts = true` müssen
  PowerShell-Skripte Authenticode-signiert sein (`Test-OSDCloudSignature`).
- **Bestätigung vor Disk-Wipe:** Vor dem Löschen der Zieldisk ist die Eingabe einer
  Bestätigungsphrase erforderlich (`Confirm-OSDCloudDiskWipe`), außer im ausdrücklich
  aktivierten Zero-Touch-Modus.
- **Keine Secrets im Repository:** Domänen-/Entra-Anmeldedaten werden niemals im
  Repository gespeichert. Domain Join fragt Credentials interaktiv ab oder nutzt
  `djoin.exe`-Provisioning; Entra Join erfolgt über OOBE/Autopilot.

## Umgang mit privaten Repositories

Für private Konfigurations-Repositories wird ein GitHub-Token benötigt. Dieses wird
**nicht** im Repository abgelegt, sondern zur Laufzeit über die Umgebungsvariable
`OSDCLOUD_GITHUB_TOKEN` bereitgestellt (siehe `docs/GitHub-Configuration.md`).

## Unterstützte Versionen

| Version | Unterstützt |
|---------|-------------|
| 1.0.x   | ✅          |
