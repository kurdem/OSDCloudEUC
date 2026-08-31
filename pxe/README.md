# PXE / iPXE Deployment

Dieser Ordner enthält die iPXE-Konfiguration, um das mit
`src/Build-OSDCloudMedia.ps1` erzeugte OSDCloud-WinPE über das Netzwerk zu booten.

## Überblick

```
Client (UEFI PXE) ──► DHCP/ProxyDHCP ──► iPXE (snponly.efi) ──► boot.ipxe
     └──► ipxe-menu.ipxe ──► wimboot ──► boot.wim (OSDCloud WinPE)
                                   └──► Startnet.ps1 ──► GitHub-Bootstrap
```

OSDCloud-WinPE wird per **wimboot** über HTTP geladen. HTTP ist gegenüber TFTP
deutlich schneller und für die mehrere hundert MB große `boot.wim` empfohlen.

## Benötigte Komponenten

| Komponente        | Zweck                                                        |
|-------------------|-------------------------------------------------------------|
| DHCP / ProxyDHCP  | Verteilt Boot-Dateinamen (Option 67) bzw. leitet auf iPXE   |
| TFTP-Server       | Liefert den initialen iPXE-Bootloader (`snponly.efi`)       |
| HTTP-Server       | Liefert `boot.ipxe`, `ipxe-menu.ipxe`, `wimboot`, `boot.wim`|
| wimboot           | iPXE-Loader für WIM-Dateien (von ipxe.org)                  |

## Dateien auf dem HTTP-Server

Lege unter der in `boot.ipxe` gesetzten `${boot-url}` (z. B.
`http://deploy.example.com/osdcloud`) folgende Struktur ab:

```
osdcloud/
├── boot.ipxe
├── ipxe-menu.ipxe
├── wimboot
├── boot/
│   ├── BCD           (aus <Workspace>\Media\boot\BCD)
│   └── boot.sdi      (aus <Workspace>\Media\boot\boot.sdi)
└── sources/
    └── boot.wim      (aus <Workspace>\Media\sources\boot.wim)
```

`BCD`, `boot.sdi` und `boot.wim` stammen aus dem OSDCloud-Workspace-`Media`-Ordner,
der von `Build-OSDCloudMedia.ps1` erzeugt wird.

## DHCP-Konfiguration

Beispiele für gängige Server findest du in `examples/`:

- `examples/dhcpd.conf.example` – ISC DHCP mit UEFI/Legacy-Weiche und iPXE-Chainload
- `examples/proxydhcp-dnsmasq.conf.example` – dnsmasq als ProxyDHCP (kein Eingriff in bestehendes DHCP)

## Ablauf anpassen

1. `${boot-url}` in `boot.ipxe` **und** `ipxe-menu.ipxe` auf deinen HTTP-Server setzen.
2. `boot.ipxe` als initiales iPXE-Skript verteilen (per DHCP Option 67 oder embedded iPXE).
3. `Build-OSDCloudMedia.ps1` ausführen und die drei Media-Dateien auf den HTTP-Server kopieren.
4. Testen: Client per PXE booten, das Menü sollte erscheinen.

## Sicherheitshinweis

`boot.wim` enthält die eingebettete Fallback-Konfiguration. Da PXE/HTTP standardmäßig
unverschlüsselt ist, sollte der Boot-Server in einem vertrauenswürdigen Deployment-VLAN
stehen. Für vertrauliche Umgebungen HTTPS-fähiges iPXE (mit eingebetteten CA-Zertifikaten)
verwenden und die AllowedHosts/Hash-Prüfung in `config/global.json` aktiviert lassen.
