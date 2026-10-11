# SPDX-License-Identifier: MIT
# Run outside plsDontProc. Only the generated JSON should be imported into it.
[CmdletBinding()]
param(
    [string]$InputPath = $env:PLSDONTPROC_CLEANER_INPUT,
    [string]$OutputPath,
    [string]$FakeName = $env:PLSDONTPROC_PRIVATE_NAME,
    [string]$FakeId = $env:PLSDONTPROC_PRIVATE_ID,
    [string]$IdentityPath,
    [switch]$NonInteractive
)
. "$PSScriptRoot\privacy-common.ps1"

try {
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        if ($NonInteractive) { throw 'Provide -InputPath.' }
        $InputPath = Select-PrivacyFile 'Choose the original SWEX JSON' 'SWEX JSON (*.json)|*.json'
        if (-not $InputPath) { exit 0 }
    }
    $source = Get-Item -LiteralPath $InputPath -Force
    if ($source -isnot [IO.FileInfo] -or $source.Extension -ine '.json' -or $source.Length -gt 128MB) {
        throw 'Choose a SWEX JSON up to 128 MB.'
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $data = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($source.FullName, $utf8)) }
    catch { throw 'Invalid JSON. No output was created.' }
    $wizard = Get-JsonProperty $data 'wizard_info'
    $runes = Get-JsonProperty $data 'runes'
    $units = Get-JsonProperty $data 'unit_list'
    if ($null -eq $wizard -or $wizard.Value -isnot [Management.Automation.PSCustomObject] -or
        $null -eq $runes -or $runes.Value -isnot [array] -or
        $null -eq $units -or $units.Value -isnot [array]) { throw 'A full SWEX export is required.' }
    $realId = Get-JsonProperty $wizard.Value 'wizard_id'
    if ($null -eq $realId) { throw 'The export has no account ID.' }
    $sourceHash = Get-AccountHash $realId.Value
    if ($IdentityPath) {
        $identity = Read-PrivacyIdentity $IdentityPath
        if ($identity.source_hash -cne $sourceHash -and [string]$realId.Value -cne [string]$identity.fake_id) {
            throw 'This identity belongs to a different account. Use its original JSON or create another identity.'
        }
    } else {
        if (-not $FakeName -or -not $FakeId) {
            if ($NonInteractive) { throw 'Provide -FakeName and -FakeId, or -IdentityPath.' }
            $choice = Show-PrivacyIdentity
            if ($null -eq $choice) { exit 0 }
            $FakeName = $choice.Name; $FakeId = $choice.Id
        }
        Test-PrivacyAlias $FakeName $FakeId
        if ((Get-AccountHash $FakeId) -ceq $sourceHash) { throw 'Choose a fictitious ID different from the real account ID.' }
        $identity = [pscustomobject]@{version=1; source_hash=$sourceHash; fake_name=$FakeName.Trim(); fake_id=[long]$FakeId}
    }
    Write-Host 'Creating a filtered copy locally. The original is never changed...'
    $clean = Copy-Allowed $data 'export' 'export'
    $clean.wizard_info['wizard_id'] = $identity.fake_id
    $clean.wizard_info['wizard_name'] = $identity.fake_name
    $bytes = $utf8.GetBytes((ConvertTo-Json -InputObject $clean -Depth 32 -Compress) + [Environment]::NewLine)
    $destination = Write-NewJson $source.FullName $OutputPath $bytes
    if (-not $IdentityPath) {
        $IdentityPath = [IO.Path]::ChangeExtension($destination, '.identity.json')
        try {
            $identityBytes = $utf8.GetBytes((ConvertTo-Json $identity -Compress))
            $null = Write-NewJson $source.FullName $IdentityPath $identityBytes
        } catch {
            [IO.File]::Delete($destination)
            throw 'Could not save the private identity. No filtered JSON was kept.'
        }
    }
    Write-Host "Filtered JSON: $destination"
    Write-Host "Private identity file for the log helper: $IdentityPath"
    Write-Host 'Import only the filtered JSON. Do not import the identity file or original export.'
    Write-Host 'Keep the identity file for future exports and the FullLogger helper. Nothing was sent online.'
    exit 0
} catch {
    Write-Host ('Could not prepare the JSON: {0}' -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
