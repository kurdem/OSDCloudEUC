<#
.SYNOPSIS
    Fuehrt Domain Join, Entra Join oder Workgroup-Zuordnung durch.
.DESCRIPTION
    Wird in der SetupComplete-Phase ausgefuehrt. Liest JoinType und die zugehoerigen
    Einstellungen aus dem Deployment-Kontext (aus networks.json).

    WICHTIG (Sicherheit): Es werden KEINE Anmeldedaten im Repository gespeichert.
      - Domain: Credentials werden interaktiv abgefragt (CredentialSource=Prompt) bzw.
        ueber ein sicheres Bereitstellungsverfahren (Provisioning-Package/LAPS) geliefert.
        In vollautomatischen Szenarien wird der AD-Join bevorzugt ueber ein
        djoin.exe-Provisioning-Blob durchgefuehrt.
      - Entra: Erfolgt bevorzugt ueber OOBE/Autopilot; dieses Skript protokolliert nur
        den vorgesehenen Weg und nimmt keinen unbeaufsichtigten Join mit Secrets vor.
      - Workgroup: Kein Join erforderlich.
.PARAMETER ContextPath
    Pfad zur DeploymentContext.json.
#>
[CmdletBinding()]
param(
    [string]$ContextPath = 'C:\OSDCloud\Scripts\DeploymentContext.json'
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $ContextPath)) { Write-Host 'Kein Kontext - ueberspringe Enrollment.'; return }
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
$joinType = $context.JoinType
$networks = $context.NetworksConfig

Write-Host "Join-Typ: $joinType"

switch ($joinType) {
    'Domain' {
        $profile = $networks.JoinProfiles.Domain
        Write-Host "Ziel-Domaene: $($profile.DomainName), OU: $($profile.OUPath)"
        if ($profile.CredentialSource -eq 'Prompt') {
            # Interaktiver Modus (kein Zero-Touch): Credentials abfragen.
            try {
                $cred = Get-Credential -Message "Domain-Join-Konto fuer $($profile.DomainName)"
                $params = @{
                    DomainName = $profile.DomainName
                    Credential = $cred
                    Force      = $true
                    ErrorAction= 'Stop'
                }
                if ($profile.OUPath) { $params['OUPath'] = $profile.OUPath }
                Add-Computer @params
                Write-Host 'Domain Join erfolgreich (wirksam nach Neustart).'
            } catch {
                Write-Host "Domain Join fehlgeschlagen: $($_.Exception.Message)"
            }
        } else {
            Write-Host 'CredentialSource != Prompt: Bitte djoin.exe-Provisioning oder Provisioning-Package verwenden.'
            Write-Host 'Es werden bewusst keine gespeicherten Anmeldedaten verwendet.'
        }
    }
    'Entra' {
        $profile = $networks.JoinProfiles.Entra
        Write-Host "Entra-Join vorgesehen fuer Tenant: $($profile.TenantName) (Methode: $($profile.Method))."
        Write-Host 'Entra Join erfolgt ueber OOBE/Autopilot. Kein unbeaufsichtigter Join mit Secrets in diesem Skript.'
    }
    default {
        $wg = $networks.JoinProfiles.Workgroup.WorkgroupName
        Write-Host "Workgroup: $wg (kein Join erforderlich)."
    }
}
