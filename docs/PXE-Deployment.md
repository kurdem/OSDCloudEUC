# PXE-Deployment

Vollständige Details und Konfigurationsbeispiele liegen in [`../pxe/README.md`](../pxe/README.md)
und [`../pxe/examples/`](../pxe/examples/). Dieses Dokument fasst die Einrichtung zusammen.

## Komponenten

| Rolle | Software (Beispiele) |
|-------|----------------------|
| DHCP / ProxyDHCP | ISC DHCP, Windows DHCP, dnsmasq |
| TFTP | tftpd-hpa, dnsmasq, Windows Deployment Services |
| HTTP | nginx, Apache, IIS |
| iPXE | `snponly.efi` (UEFI), `undionly.kpxe` (Legacy), `wimboot` |

## Ablauf

```
PXE-Client ─► DHCP/ProxyDHCP ─► iPXE-Loader (TFTP) ─► boot.ipxe (HTTP)
   └─► ipxe-menu.ipxe ─► wimboot ─► boot.wim (OSDCloud-WinPE)
```

HTTP wird für `boot.wim` (mehrere hundert MB) dringend empfohlen – TFTP ist dafür zu langsam.

## Schritte

1. **WinPE bauen** und die Media-Dateien bereitstellen:
   ```powershell
   .\src\Build-OSDCloudMedia.ps1 -WorkspacePath C:\OSDCloud\Workspace
   ```
   Kopiere anschließend auf den HTTP-Server (unter `${boot-url}`):
   ```
   wimboot
   boot/BCD           (aus <Workspace>\Media\boot\BCD)
   boot/boot.sdi      (aus <Workspace>\Media\boot\boot.sdi)
   sources/boot.wim   (aus <Workspace>\Media\sources\boot.wim)
   boot.ipxe, ipxe-menu.ipxe   (aus diesem Repository, pxe/)
   ```

2. **`${boot-url}`** in `pxe/boot.ipxe` und `pxe/ipxe-menu.ipxe` auf den HTTP-Server setzen.

3. **DHCP/ProxyDHCP** konfigurieren (siehe `pxe/examples/`):
   - Bereits in iPXE → direkt `boot.ipxe` per HTTP.
   - Sonst passenden iPXE-Loader per TFTP (UEFI: `snponly.efi`, Legacy: `undionly.kpxe`).

4. **Client per PXE booten** – das OSDCloudEUC-Menü sollte erscheinen.

## Zero-Touch über PXE

Der Zero-Touch-Modus wird nicht im iPXE-Menü, sondern über die geladene Konfiguration
gesteuert: `config/global.json` → `Deployment.EnableZeroTouch = true` bzw. ein Zero-Touch-Profil
(`Windows11-Test`). So bleibt dasselbe `boot.wim` für interaktive und automatische Läufe nutzbar.

## Sicherheit

PXE/HTTP ist standardmäßig unverschlüsselt. Betreibe den Boot-Server in einem
vertrauenswürdigen Deployment-VLAN. Für höhere Anforderungen HTTPS-fähiges iPXE (mit
eingebetteten CA-Zertifikaten) verwenden und die Hash-/AllowedHosts-Prüfung aktiviert lassen.
Siehe [Security-Concept.md](Security-Concept.md).
