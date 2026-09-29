#Requires -Version 5.1
<#
.SYNOPSIS
    Targeted print subsystem remediation. MODIFIES THE SYSTEM.

.DESCRIPTION
    Run Invoke-CyberWinDiag.ps1 first and read the print findings before using
    this. Nothing here runs unless you pass a switch.

.PARAMETER ClearQueue
    Stop the spooler, empty %SystemRoot%\System32\spool\PRINTERS, restart it.
    Safe and reversible (the queued jobs are lost, nothing else).

.PARAMETER DisableSnmp
    Turn off SNMP status polling on all Standard TCP/IP ports. Removes a fixed
    per-job delay when a printer is slow to answer status queries.

.PARAMETER ReplaceWsdPort
    Name of a WSD port to replace with a raw TCP/IP port. Requires -PrinterHostAddress.

.PARAMETER PrinterHostAddress
    IP address of the printer for the new raw port. Give the printer a DHCP
    reservation or static IP first.

.PARAMETER PortNumber
    Raw print port. 9100 (RAW/JetDirect) by default.

.PARAMETER RemoveGhostPrinters
    Remove non-shared printers whose names match "(Copy N)" or "(N)".

.PARAMETER EnablePrintLogging
    Enable the PrintService Operational and Admin event logs.

.EXAMPLE
    .\Fix-PrintSpooler.ps1 -ClearQueue -EnablePrintLogging

.EXAMPLE
    .\Fix-PrintSpooler.ps1 -ReplaceWsdPort 'WSD-3f2a...' -PrinterHostAddress 192.168.1.50
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $ClearQueue,
    [switch] $DisableSnmp,
    [string] $ReplaceWsdPort,
    [string] $PrinterHostAddress,
    [int]    $PortNumber = 9100,
    [switch] $RemoveGhostPrinters,
    [switch] $EnablePrintLogging
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run elevated.'
}

if (-not ($ClearQueue -or $DisableSnmp -or $ReplaceWsdPort -or
          $RemoveGhostPrinters -or $EnablePrintLogging)) {
    Get-Help $PSCommandPath -Detailed
    return
}

# --- Always show the before state -----------------------------------------
Write-Host '=== BEFORE ===' -ForegroundColor Cyan
Get-Service Spooler | Select-Object Name, Status, StartType | Format-Table -AutoSize
Get-Printer | Select-Object Name, PortName, DriverName, PrinterStatus | Format-Table -AutoSize
Get-PrinterPort | Select-Object Name, PrinterHostAddress, PortNumber, SNMPEnabled | Format-Table -AutoSize

# --- Clear the queue -------------------------------------------------------
if ($ClearQueue) {
    $spool = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
    $before = @(Get-ChildItem $spool -Force -ErrorAction SilentlyContinue).Count
    Write-Host "`nClearing spool folder ($before files)..." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($spool, 'Stop spooler, delete spool files, restart spooler')) {
        Stop-Service -Name Spooler -Force
        Start-Sleep -Seconds 2
        Remove-Item (Join-Path $spool '*') -Force -Recurse -ErrorAction SilentlyContinue
        Start-Service -Name Spooler
        Start-Sleep -Seconds 2
        Write-Host "Spooler restarted. Status: $((Get-Service Spooler).Status)" -ForegroundColor Green
    }
}

# --- Enable print logging --------------------------------------------------
if ($EnablePrintLogging) {
    Write-Host "`nEnabling PrintService event logs..." -ForegroundColor Yellow
    foreach ($log in 'Microsoft-Windows-PrintService/Operational',
                     'Microsoft-Windows-PrintService/Admin') {
        if ($PSCmdlet.ShouldProcess($log, 'Enable event log')) {
            & wevtutil.exe sl $log /e:true
            Write-Host "  enabled: $log" -ForegroundColor Green
        }
    }
    Write-Host '  Now reproduce the slow print, then re-run the collector.' -ForegroundColor DarkGray
}

# --- Disable SNMP polling --------------------------------------------------
if ($DisableSnmp) {
    $ports = Get-PrinterPort | Where-Object SNMPEnabled -eq $true
    if (-not $ports) {
        Write-Host "`nNo ports have SNMP enabled." -ForegroundColor DarkGray
    } else {
        Write-Host "`nDisabling SNMP on $(@($ports).Count) port(s)..." -ForegroundColor Yellow
        foreach ($p in $ports) {
            if ($PSCmdlet.ShouldProcess($p.Name, 'Disable SNMP status polling')) {
                try {
                    Set-PrinterPort -Name $p.Name -SNMPEnabled $false
                    Write-Host "  done: $($p.Name)" -ForegroundColor Green
                } catch {
                    Write-Warning "  failed on $($p.Name): $($_.Exception.Message)"
                }
            }
        }
    }
}

# --- Replace a WSD port with a raw TCP/IP port -----------------------------
if ($ReplaceWsdPort) {
    if (-not $PrinterHostAddress) {
        throw '-ReplaceWsdPort requires -PrinterHostAddress.'
    }

    Write-Host "`nTesting $PrinterHostAddress on port $PortNumber..." -ForegroundColor Yellow
    $test = Test-NetConnection -ComputerName $PrinterHostAddress -Port $PortNumber -WarningAction SilentlyContinue
    if (-not $test.TcpTestSucceeded) {
        throw "Printer at $PrinterHostAddress is not answering on port $PortNumber. Confirm the IP and that raw printing is enabled on the device."
    }
    Write-Host '  reachable.' -ForegroundColor Green

    $newPort = 'IP_' + $PrinterHostAddress
    if (-not (Get-PrinterPort -Name $newPort -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($newPort, "Create raw TCP/IP port -> ${PrinterHostAddress}:${PortNumber}")) {
            Add-PrinterPort -Name $newPort -PrinterHostAddress $PrinterHostAddress -PortNumber $PortNumber
            Write-Host "  created port $newPort" -ForegroundColor Green
        }
    } else {
        Write-Host "  port $newPort already exists, reusing it." -ForegroundColor DarkGray
    }

    $affected = Get-Printer | Where-Object PortName -eq $ReplaceWsdPort
    foreach ($pr in $affected) {
        if ($PSCmdlet.ShouldProcess($pr.Name, "Repoint from $ReplaceWsdPort to $newPort")) {
            Set-Printer -Name $pr.Name -PortName $newPort
            Write-Host "  repointed '$($pr.Name)' to $newPort" -ForegroundColor Green
        }
    }

    if (-not (Get-Printer | Where-Object PortName -eq $ReplaceWsdPort)) {
        if ($PSCmdlet.ShouldProcess($ReplaceWsdPort, 'Remove now-unused WSD port')) {
            try {
                Remove-PrinterPort -Name $ReplaceWsdPort
                Write-Host "  removed $ReplaceWsdPort" -ForegroundColor Green
            } catch {
                Write-Warning "  could not remove ${ReplaceWsdPort}: $($_.Exception.Message)"
                Write-Warning '  Restart the spooler and try again, or remove it from printmanagement.msc.'
            }
        }
    }
}

# --- Remove ghost printers -------------------------------------------------
if ($RemoveGhostPrinters) {
    $ghosts = Get-Printer | Where-Object {
        -not $_.Shared -and $_.Name -match '\(Copy \d+\)|\(\d+\)$'
    }
    if (-not $ghosts) {
        Write-Host "`nNo obvious ghost printers found." -ForegroundColor DarkGray
    } else {
        Write-Host "`nFound $(@($ghosts).Count) probable ghost printer(s):" -ForegroundColor Yellow
        $ghosts | Select-Object Name, PortName, DriverName | Format-Table -AutoSize
        foreach ($g in $ghosts) {
            if ($PSCmdlet.ShouldProcess($g.Name, 'Remove printer')) {
                try {
                    Remove-Printer -Name $g.Name
                    Write-Host "  removed '$($g.Name)'" -ForegroundColor Green
                } catch {
                    Write-Warning "  failed on '$($g.Name)': $($_.Exception.Message)"
                }
            }
        }
    }
}

# --- After state -----------------------------------------------------------
Write-Host "`n=== AFTER ===" -ForegroundColor Cyan
Get-Service Spooler | Select-Object Name, Status, StartType | Format-Table -AutoSize
Get-Printer | Select-Object Name, PortName, DriverName, PrinterStatus | Format-Table -AutoSize
Get-PrinterPort | Select-Object Name, PrinterHostAddress, PortNumber, SNMPEnabled | Format-Table -AutoSize

Write-Host 'Now print a test page and time it. Re-run the collector to capture the new state.' -ForegroundColor Cyan
