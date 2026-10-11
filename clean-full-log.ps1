# SPDX-License-Identifier: MIT
# Standalone, offline FullLogger follower. Ctrl+C stops updates to its COPY.
[CmdletBinding()]
param(
    [string]$InputPath = $env:PLSDONTPROC_LOG_INPUT,
    [string]$IdentityPath,
    [string]$OutputPath,
    [switch]$Once,
    [switch]$NonInteractive,
    [ValidateRange(100,60000)][int]$PollMilliseconds = 1000
)
. "$PSScriptRoot\privacy-common.ps1"

# A file ID distinguishes replacement from append, even if timestamps/size match.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class PrivacyLogFile {
    [StructLayout(LayoutKind.Sequential)] struct Info {
        public uint attributes; public System.Runtime.InteropServices.ComTypes.FILETIME creation, access, write;
        public uint volume, sizeHigh, sizeLow, links, indexHigh, indexLow;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
    public static string Id(SafeFileHandle handle) {
        Info info;
        if (!GetFileInformationByHandle(handle, out info)) throw new System.ComponentModel.Win32Exception();
        return info.volume + ":" + info.indexHigh + ":" + info.indexLow;
    }
}
'@

$writer = $null
try {
    if (-not $InputPath) {
        if ($NonInteractive) { throw 'Provide -InputPath.' }
        $InputPath = Select-PrivacyFile 'Choose the ORIGINAL FullLogger file' 'FullLogger (*.txt)|*.txt'
        if (-not $InputPath) { exit 0 }
    }
    if (-not $IdentityPath) {
        if ($NonInteractive) { throw 'Provide -IdentityPath from the JSON helper.' }
        $IdentityPath = Select-PrivacyFile 'Choose the private identity created by the JSON helper' 'Private identity (*.identity.json)|*.identity.json'
        if (-not $IdentityPath) { exit 0 }
    }
    $identity = Read-PrivacyIdentity $IdentityPath
    $source = Get-Item -LiteralPath $InputPath -Force
    if ($source -isnot [IO.FileInfo] -or $source.Extension -ine '.txt') { throw 'Choose a FullLogger .txt file.' }
    $InputPath = $source.FullName
    if (-not $OutputPath) {
        $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($IdentityPath))
        $OutputPath = Join-Path $folder 'plsdontproc-full_log.txt'
        $suffix = 2
        while (Test-Path -LiteralPath $OutputPath) {
            $OutputPath = Join-Path $folder "plsdontproc-full_log-$suffix.txt"; $suffix++
        }
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    if ($OutputPath -ieq $InputPath -or [IO.Path]::GetExtension($OutputPath) -ine '.txt') { throw 'Choose a different .txt output path.' }
    # Existing files are never overwritten, including the original and symlinks.
    $output = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $writer = [IO.StreamWriter]::new($output, $utf8)
    $writer.AutoFlush = $true
    $writer.WriteLine('# plsDontProc filtered FullLogger copy - contains only the fictitious account')
    Write-Host "Filtered log: $OutputPath"
    Write-Host 'Select ONLY this copy in the app. Keep this window open while playing. Ctrl+C stops filtering.'
    Write-Host 'The original is read locally, never changed or sent online.'
    $position = 0L; $fileId = $null; $prefix = ''; $prefixLength = 0
    $decoder = $utf8.GetDecoder(); $pending = ''; $record = [Collections.Generic.List[string]]::new()
    $buffer = New-Object byte[] 65536; $chars = New-Object char[] 65536
    $waiting = $false; $written = 0; $skipped = 0
    do {
        $inputStream = $null
        try {
            $inputStream = [IO.File]::Open($InputPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        } catch [IO.IOException] {
            if ($Once) { throw 'The original log is unavailable.' }
            if (-not $waiting) { Write-Host 'Waiting for the original log to become available...'; $waiting = $true }
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }
        try {
            $waiting = $false
            $currentId = [PrivacyLogFile]::Id($inputStream.SafeFileHandle)
            $head = New-Object byte[] $prefixLength
            $readHead = $inputStream.Read($head, 0, $head.Length)
            $changedPrefix = $prefixLength -gt 0 -and ([Convert]::ToBase64String($head) -cne $prefix -or $readHead -ne $prefixLength)
            if ($null -ne $fileId -and ($currentId -cne $fileId -or $inputStream.Length -lt $position -or $changedPrefix)) {
                $position = 0L; $pending = ''; $record.Clear(); $decoder.Reset(); $prefixLength = 0
                # A malformed empty record makes the app wait for a fresh login
                # instead of silently assuming a gap-free history after rotation.
                $writer.Write("API Command: FilterReset - filtered`r`nRequest:`r`nnull`r`nResponse:`r`nnull`r`n`r`n")
                Write-Host 'Original log was replaced or truncated. Waiting for a new login snapshot in the log.'
            }
            $fileId = $currentId
            if ($prefixLength -eq 0 -and $inputStream.Length -gt 0) {
                $prefixLength = [int][Math]::Min(256, $inputStream.Length)
                $head = New-Object byte[] $prefixLength; $inputStream.Position = 0
                $null = $inputStream.Read($head, 0, $head.Length); $prefix = [Convert]::ToBase64String($head)
            }
            $inputStream.Position = $position
            # Bound each poll; resume at the exact byte offset without losing UTF-8 fragments.
            $budget = 8MB
            while ($budget -gt 0 -and ($count = $inputStream.Read($buffer, 0, [Math]::Min($buffer.Length, $budget))) -gt 0) {
                $budget -= $count; $position = $inputStream.Position
                $n = $decoder.GetChars($buffer, 0, $count, $chars, 0, $false)
                $pending += [string]::new($chars, 0, $n)
                $lines = $pending.Split([char]10)
                $pending = $lines[$lines.Length - 1]
                for ($i = 0; $i -lt $lines.Length - 1; $i++) {
                    $line = $lines[$i].TrimEnd([char]13)
                    if ($line.StartsWith('API Command: ')) { $record.Clear(); $record.Add('header'); continue }
                    if ($record.Count -eq 0) { continue }
                    $record.Add($line)
                    if ($record.Count -eq 5) {
                        try {
                            if ($record[1].Trim() -cne 'Request:' -or $record[3].Trim() -cne 'Response:') { throw 'Incomplete pair' }
                            $requestData = ConvertFrom-Json -InputObject $record[2]
                            $responseData = ConvertFrom-Json -InputObject $record[4]
                            $safe = Convert-PrivateLogEvent $requestData $responseData $identity
                            if ($null -ne $safe) { $writer.Write($safe); $written++ }
                        } catch {
                            # Never echo parser errors, headers or original JSON.
                            $skipped++
                            $writer.Write("API Command: FilterReset - filtered`r`nRequest:`r`nnull`r`nResponse:`r`nnull`r`n`r`n")
                        }
                        $record.Clear()
                    }
                }
                if ($pending.Length -gt 128MB) { throw 'An incomplete log line exceeds the size limit.' }
            }
            $caughtUp = $inputStream.Position -ge $inputStream.Length
        } finally { $inputStream.Dispose() }
        if ($Once -and $caughtUp) { break }
        if ($caughtUp) { Start-Sleep -Milliseconds $PollMilliseconds }
    } while ($true)
    Write-Host "Complete. Filtered events: $written. Invalid records skipped: $skipped."
} catch {
    Write-Host 'The log helper stopped. Check file paths, permissions and the private identity; originals were not changed.' -ForegroundColor Red
    exit 1
} finally { if ($null -ne $writer) { $writer.Dispose() } }
