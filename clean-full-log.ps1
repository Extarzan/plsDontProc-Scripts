# SPDX-License-Identifier: MIT
# Standalone, offline FullLogger follower. Ctrl+C stops updates to its COPY.
[CmdletBinding()]
param(
    [string]$InputPath = $env:PLSDONTPROC_LOG_INPUT,
    [string]$IdentityPath,
    [string]$OutputPath,
    [switch]$Resume,
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
using System.IO;
using System.Text;
using System.Collections.Generic;
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
    // Scan bytes in buffered native code. Do not deserialize months of unrelated
    // account history in PowerShell just to reach the current login snapshot.
    sealed class Lines : IDisposable {
        readonly FileStream stream;
        readonly byte[] buffer = new byte[65536];
        readonly UTF8Encoding encoding = new UTF8Encoding(false, true);
        int index, count;
        public long Position;
        public Lines(string path, long offset) {
            stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            bool partial = false;
            if (offset > 0) { stream.Position = offset - 1; partial = stream.ReadByte() != 10; }
            stream.Position = Position = offset;
            if (partial) { string ignored; Read(out ignored, false); }
        }
        public bool Read(out string line, bool decode = true) {
            line = null;
            using (var bytes = new MemoryStream()) {
                while (true) {
                    if (index == count) {
                        count = stream.Read(buffer, 0, buffer.Length); index = 0;
                        if (count == 0) return false; // Incomplete final line is retried later.
                    }
                    int newline = Array.IndexOf(buffer, (byte)10, index, count - index);
                    int take = newline < 0 ? count - index : newline - index;
                    bytes.Write(buffer, index, take); index += take; Position += take;
                    if (bytes.Length > 128L * 1024 * 1024) throw new IOException("Log line too large.");
                    if (newline >= 0) {
                        index++; Position++;
                        if (!decode) return true;
                        byte[] value = bytes.ToArray();
                        int length = value.Length;
                        if (length > 0 && value[length - 1] == 13) length--;
                        line = encoding.GetString(value, 0, length);
                        return true;
                    }
                }
            }
        }
        public void Dispose() { stream.Dispose(); }
    }
    public static long[] LoginOffsets(string path, long start, long end) {
        var offsets = new List<long>();
        using (var lines = new Lines(path, start)) {
            string line;
            while (lines.Position < end) {
                long offset = lines.Position;
                if (!lines.Read(out line)) break;
                if (line.StartsWith("API Command: HubUserLogin ", StringComparison.Ordinal) ||
                    line.StartsWith("API Command: GuestLogin ", StringComparison.Ordinal)) offsets.Add(offset);
            }
        }
        return offsets.ToArray();
    }
    public static string[] Record(string path, long offset) {
        var result = new string[5];
        using (var lines = new Lines(path, offset)) {
            for (int i = 0; i < result.Length; i++) if (!lines.Read(out result[i])) return null;
        }
        return result;
    }
}
'@

function Find-PrivateLogStart([string]$Path, $Identity) {
    $length = (Get-Item -LiteralPath $Path).Length
    $window = 8MB; $end = $length
    while ($end -gt 0) {
        $start = [Math]::Max(0L, $length - $window)
        $candidates = [PrivacyLogFile]::LoginOffsets($Path, $start, $end)
        for ($index = $candidates.Length - 1; $index -ge 0; $index--) {
            try {
                $rows = [PrivacyLogFile]::Record($Path, $candidates[$index])
                if ($null -eq $rows -or $rows[1].Trim() -cne 'Request:' -or $rows[3].Trim() -cne 'Response:') { continue }
                $req = ConvertFrom-Json -InputObject $rows[2]
                $resp = ConvertFrom-Json -InputObject $rows[4]
                $runes = Get-JsonProperty $resp 'runes'; $units = Get-JsonProperty $resp 'unit_list'
                $command = Get-JsonProperty $req 'command'
                if ($null -eq $command -or $command.Value -cnotin @('HubUserLogin','GuestLogin') -or
                    $null -eq $runes -or $runes.Value -isnot [array] -or
                    $null -eq $units -or $units.Value -isnot [array]) { continue }
                # Use the same account checks and allowlists as normal filtering.
                if ($null -ne (Convert-PrivateLogEvent $req $resp $Identity)) {
                    return [long]$candidates[$index]
                }
            } catch { } # Try an earlier complete snapshot; never print raw content.
        }
        $end = $start; $window = [Math]::Min($length, $window * 2L)
    }
    return 0L
}

function Test-PrivateLogCopy([string]$Path, $Identity) {
    $reader = [IO.StreamReader]::new($Path, [Text.UTF8Encoding]::new($false, $true))
    try {
        if ($reader.ReadLine() -cne '# plsDontProc filtered FullLogger copy - contains only the fictitious account') { throw 'Not a filtered copy.' }
        while ($null -ne ($line = $reader.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if (-not $line.StartsWith('API Command: ') -or $reader.ReadLine().Trim() -cne 'Request:') { throw 'Invalid copy.' }
            $req = ConvertFrom-Json -InputObject $reader.ReadLine()
            if ($reader.ReadLine().Trim() -cne 'Response:') { throw 'Invalid copy.' }
            $resp = ConvertFrom-Json -InputObject $reader.ReadLine()
            if ($line -ceq 'API Command: FilterReset - filtered' -and $null -eq $req -and $null -eq $resp) { continue }
            if ([string]$req.wizard_id -cne [string]$Identity.fake_id -or
                [string]$resp.wizard_info.wizard_id -cne [string]$Identity.fake_id -or
                $req.command -cne $resp.command) { throw 'This copy belongs to another identity.' }
        }
    } finally { $reader.Dispose() }
}

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
    if ($Resume -and -not $OutputPath) { throw 'Resume requires an explicit filtered -OutputPath.' }
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
    if ($Resume) { Test-PrivateLogCopy $OutputPath $identity }
    Write-Host 'Finding the latest complete snapshot for this account in the existing log...'
    $position = Find-PrivateLogStart $InputPath $identity
    Write-Host ("Starting from byte {0:N0}; older history does not need to be filtered." -f $position)
    # By default create a new copy. Explicit resume only appends to a checked
    # filtered copy with the same fictitious identity; never overwrite a file.
    $mode = if ($Resume) { [IO.FileMode]::Append } else { [IO.FileMode]::CreateNew }
    $output = [IO.File]::Open($OutputPath, $mode, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $writer = [IO.StreamWriter]::new($output, $utf8)
    $writer.AutoFlush = $true
    if (-not $Resume) { $writer.WriteLine('# plsDontProc filtered FullLogger copy - contains only the fictitious account') }
    else { $writer.WriteLine() }
    Write-Host "Filtered log: $OutputPath"
    Write-Host 'Select ONLY this copy in the app. Keep this window open while playing. Ctrl+C stops filtering.'
    Write-Host 'The original is read locally, never changed or sent online.'
    $fileId = $null; $prefix = ''; $prefixLength = 0
    $decoder = $utf8.GetDecoder(); $pending = ''; $record = [Collections.Generic.List[string]]::new()
    $buffer = New-Object byte[] 65536; $chars = New-Object char[] 65536
    $waiting = $false; $written = 0; $skipped = 0; $reportedReady = $false
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
        if ($caughtUp -and -not $reportedReady) {
            Write-Host "Up to date. Watching for new events. Filtered events: $written. Invalid records: $skipped."
            $reportedReady = $true
        }
        if ($Once -and $caughtUp) { break }
        if ($caughtUp) { Start-Sleep -Milliseconds $PollMilliseconds }
    } while ($true)
    Write-Host "Complete. Filtered events: $written. Invalid records skipped: $skipped."
} catch {
    Write-Host 'The log helper stopped. Check file paths, permissions and the private identity; originals were not changed.' -ForegroundColor Red
    exit 1
} finally { if ($null -ne $writer) { $writer.Dispose() } }
