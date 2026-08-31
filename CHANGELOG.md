# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
und das Projekt folgt [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

## [1.0.0] - 2026-08-31

### Hinzugefügt
- Erste Veröffentlichung von OSDCloudEUC.
- GitHub-basierte, datengetriebene Deployment-Steuerung über JSON-Konfigurationen
  (`config/`) und Profile (`profiles/`) inklusive JSON-Schemas.
- Konsolenbasierte Menüführung für WinPE (`OSDCloud.Menu`), vollständig aus
  `config/deployments.json` aufgebaut.
- PowerShell-Module: Config, Menu, Hardware, Drivers, Updates, Logging, Security, Network.
- Einstiegs- und Build-Skripte: `Start-OSDCloudDeployment`, `Start-DeploymentMenu`,
  `Start-ZeroTouchDeployment`, `Build-OSDCloudMedia`, `Update-OSDCloudMedia`,
  `Test-OSDCloudPrerequisites`.
- WinPE-Ablauf (`scripts/winpe`), SetupComplete-Phase (`scripts/specialize`) und
  Post-Install-Skripte (`scripts/postinstall`: Treiber, Updates, Rename, Enrollment).
- PXE/iPXE-Boot über wimboot inkl. DHCP-/ProxyDHCP-Beispielen.
- Pester-Tests für Konfiguration, Menü, Hardware und Sicherheit.
- CI-Workflows für PowerShell- und JSON-Validierung sowie Release.
- Dokumentation unter `docs/` (Architektur, USB, PXE, GitHub-Konfiguration,
  Treiber, Updates, Troubleshooting, Sicherheitskonzept).

[Unreleased]: https://github.com/kurdem/OSDCloudEUC/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kurdem/OSDCloudEUC/releases/tag/v1.0.0
