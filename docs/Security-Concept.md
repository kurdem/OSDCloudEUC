# Sicherheitskonzept

OSDCloudEUC lädt Konfiguration aus dem Netzwerk und führt hochprivilegierte Aktionen aus
(Datenträger löschen, Betriebssystem installieren, Domänenbeitritt). Dieses Dokument
beschreibt die Schutzmaßnahmen und ihre Grenzen.

## Bedrohungsmodell (Kurz)

| Bedrohung | Gegenmaßnahme |
|-----------|---------------|
| Manipulierte Konfiguration über gefälschten Host | HTTPS-Pflicht + AllowedHosts-Enforcement |
| Verfälschte Dateien (MITM/kompromittierter Spiegel) | optionale SHA256-Hash-Prüfung |
| Untergeschobene/verfälschte Skripte | optionale Authenticode-Signaturprüfung |
| Versehentliches/böswilliges Löschen der falschen Disk | Bestätigungsphrase vor Disk-Wipe |
| Abfluss von Anmeldedaten | keine Secrets im Repo; interaktive/Provisioning-basierte Joins |
| Schema-/Formatfehler führen zu undefiniertem Verhalten | JSON-Schema-Validierung vor Verwendung |

## Maßnahmen im Detail

### Transport & Herkunft

- **HTTPS-Pflicht:** `Assert-OSDCloudAllowedHost` lehnt jede Nicht-HTTPS-URL ab.
- **AllowedHosts:** Nur Hosts aus `global.json → Security.AllowedHosts` sind zulässig.
  Standard: `raw.githubusercontent.com`, `github.com`, `api.github.com`,
  `objects.githubusercontent.com`.

### Integrität

- **Hash-Prüfung (optional):** `Security.ValidateHashes = true`. `Test-OSDCloudHash` vergleicht
  SHA256 gegen ein Manifest (`security.json → HashValidation.ManifestFile`, Format
  `HASH  relativer/Pfad`). Der Release-Workflow erzeugt `hashes.sha256` automatisch.
- **Signaturprüfung (optional):** `Security.RequireSignedScripts = true`. `Test-OSDCloudSignature`
  verlangt eine gültige Authenticode-Signatur; optional beschränkt auf `TrustedThumbprints`.

### Schema-Validierung

Jede geladene JSON-Datei wird vor Verwendung geprüft (`Test-OSDCloudConfigSchema`). In
PowerShell 6+ per `Test-Json -Schema`; in WinPE (PS 5.1) als Wohlgeformtheitsprüfung. Die
vollständige Schema-Validierung läuft zusätzlich in CI (ajv).

### Disk-Wipe-Bestätigung

`Confirm-OSDCloudDiskWipe` verlangt die exakte Eingabe der Phrase
(`security.json → DiskWipe.ConfirmationPhrase`, Standard `WIPE`). Nur im ausdrücklich
aktivierten Zero-Touch-Modus (`SkipDiskWipeConfirmation` im Profil oder `-Force`) entfällt sie –
eine bewusste, dokumentierte Ausnahme für Labor/VM.

### Umgang mit Anmeldedaten

- **Keine Secrets im Repository.** `networks.json` enthält Domänennamen/OUs, aber keine Passwörter.
- **Domain Join:** `CredentialSource = Prompt` fragt Credentials interaktiv ab. Für
  unbeaufsichtigte Szenarien ist `djoin.exe`-Provisioning bzw. ein Provisioning-Package vorgesehen;
  `Invoke-Enrollment.ps1` nimmt **keinen** unbeaufsichtigten Join mit gespeicherten Secrets vor.
- **Entra Join:** erfolgt über OOBE/Autopilot, nicht über abgelegte Tokens.
- **Private Repos:** Token nur zur Laufzeit über `OSDCLOUD_GITHUB_TOKEN`; nie im Repo/Log.

## Grenzen

- PXE/HTTP ist ohne zusätzliche Maßnahmen unverschlüsselt – Boot-Server in einem
  vertrauenswürdigen VLAN betreiben; für hohe Anforderungen HTTPS-fähiges iPXE.
- Die in `boot.wim` eingebettete Fallback-Konfiguration ist so vertrauenswürdig wie das Image
  selbst – Medien und Build-Prozess entsprechend schützen.
- Hash-/Signaturprüfung sind optional; für Produktivumgebungen mit erhöhtem Schutzbedarf
  `ValidateHashes` (und ggf. `RequireSignedScripts`) aktivieren.

## Empfehlung für Produktivbetrieb

1. `ValidateHashes = true` und ein gepflegtes `hashes.sha256`-Manifest (Release-Artefakt).
2. Versionierte Konfiguration über `UseRelease`/`ReleaseTag` statt beweglichem Branch.
3. Zero-Touch nur mit klar definierten Profilen und in kontrollierten Netzsegmenten.
4. Regelmäßig `Test-OSDCloudPrerequisites.ps1` gegen die eingesetzte OSD-Version laufen lassen.
