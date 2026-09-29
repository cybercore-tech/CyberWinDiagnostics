#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Microsoft refreshes the signature and definitions at this stable fwlink.
# The scanner expires ten days after download, so run this before every scan.
$downloadUri = 'https://go.microsoft.com/fwlink/?LinkId=212732'
$scannerPath = Join-Path $PSScriptRoot '..\Tools\Scanners\MSERT.exe'
$scannerPath = [System.IO.Path]::GetFullPath($scannerPath)
$tempPath = "$scannerPath.download"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUri -OutFile $tempPath -UseBasicParsing
    $signature = Get-AuthenticodeSignature -FilePath $tempPath
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw "Downloaded file did not have a valid Microsoft Authenticode signature (status: $($signature.Status))."
    }
    Move-Item -LiteralPath $tempPath -Destination $scannerPath -Force
    Write-Host "Verified current Microsoft Safety Scanner: $scannerPath"
    Write-Host 'Run it now; Microsoft says each download expires after 10 days.'
} catch {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    throw
}
