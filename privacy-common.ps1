# SPDX-License-Identifier: MIT
# Shared allowlists and local file helpers. No network or app dependencies.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Audit references and the reason for every field are in README.md.
# [] means an array of that schema. Number fields cannot contain objects/text.
$Schemas = @{
    export = [ordered]@{
        wizard_info = 'wizard'; tvalue = 'number'
        runes = 'rune[]'; unit_list = 'unit[]'; unit_storage_normal_list = 'unit[]'
        artifacts = 'artifact[]'; rune_lock_list = 'lock[]'
        world_arena_rune_equip_list = 'rta-rune[]'
        world_arena_artifact_equip_list = 'rta-artifact[]'
        rune_craft_item_list = 'material[]'; deck_list = 'deck[]'
        wizard_skill_list = 'skill-levels'; guild = 'guild'
    }
    wizard = [ordered]@{
        wizard_id = 'integer'
        wizard_mana = 'integer'; wizard_crystal = 'integer'; wizard_energy = 'integer'
    }
    rune = [ordered]@{
        rune_id = 'integer'; occupied_id = 'integer'; set_id = 'integer'
        slot_no = 'integer'; class = 'integer'; rank = 'integer'; extra = 'integer'
        upgrade_curr = 'integer'; pri_eff = 'main-effect'; prefix_eff = 'main-effect'
        sec_eff = 'rune-effect[]'
    }
    unit = [ordered]@{
        unit_id = 'integer'; unit_master_id = 'integer'
        runes = 'rune[]'; artifacts = 'artifact[]'
    }
    artifact = [ordered]@{
        rid = 'integer'; occupied_id = 'integer'; type = 'integer'
        attribute = 'integer'; unit_style = 'integer'; level = 'integer'
        rank = 'integer'; natural_rank = 'integer'
        pri_effect = 'main-effect'; sec_effects = 'artifact-effect[]'
    }
    lock = [ordered]@{ rune_id = 'integer'; lock_type = 'integer' }
    'rta-rune' = [ordered]@{ rune_id = 'integer'; occupied_id = 'integer' }
    'rta-artifact' = [ordered]@{ artifact_id = 'integer'; occupied_id = 'integer' }
    material = [ordered]@{
        craft_item_id = 'integer'; craft_type = 'integer'
        craft_type_id = 'integer'; amount = 'integer'
    }
    deck = [ordered]@{
        deck_type = 'integer'; deck_seq = 'integer'; leader_unit_id = 'integer'
        unit_id_list = 'integer[]'; equip = 'deck-equipment[]'
    }
    'deck-equipment' = [ordered]@{ unit_id = 'integer'; rune_id_list = 'integer[]' }
    guild = [ordered]@{ guild_info = 'guild-info' }
    'guild-info' = [ordered]@{ skill_info = 'guild-skills' }
    'guild-skills' = [ordered]@{
        '1001' = 'guild-stats'; '2001' = 'guild-stats'
        '3001' = 'guild-stats'; '4001' = 'guild-stats'
    }
    'guild-stats' = [ordered]@{ '1' = 'number'; '2' = 'number'; '3' = 'number' }
}

function Get-JsonProperty($Value, [string]$Name) {
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $property = $Value.PSObject.Properties[$Name]
        # JSON field names are case-sensitive; PowerShell lookup is not.
        if ($null -ne $property -and $property.Name -ceq $Name) { return $property }
    }
    return $null
}

function Copy-Number($Value, [string]$Rule, [string]$Location) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $pattern = if ($Rule -eq 'integer') { '^-?[0-9]+$' } else { '^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$' }
        if ($Value -cnotmatch $pattern) { throw "Numero invalido em $Location." }
        return $Value
    }
    if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and
        $Value -isnot [int64] -and $Value -isnot [decimal] -and $Value -isnot [double]) {
        throw "Esperado um numero em $Location. Nenhum arquivo foi alterado."
    }
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        throw "Numero nao finito em $Location."
    }
    if ($Rule -eq 'integer' -and ([decimal]$Value % 1 -ne 0 -or
        ($Value -is [double] -and [Math]::Abs($Value) -gt 9007199254740991))) {
        throw "Inteiro invalido ou sem precisao suficiente em $Location."
    }
    return $Value
}

function Copy-Effect($Value, [string]$Rule, [string]$Location) {
    if ($Value -isnot [array]) { throw "Esperada uma lista em $Location." }
    $length = if ($Rule -eq 'main-effect') { 2 } elseif ($Rule -eq 'rune-effect') { 4 } else { 5 }
    # Artifact position 3 is unused; position 4 is the conversion count.
    # Remove position 3 if it is last, otherwise use a zero to retain indexes.
    if ($Rule -eq 'artifact-effect' -and $Value.Count -eq 4) { $length = 3 }
    $result = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt [Math]::Min($length, $Value.Count); $index++) {
        if ($Rule -eq 'artifact-effect' -and $index -eq 3) { $result.Add(0) }
        else { $result.Add((Copy-Number $Value[$index] 'number' "$Location[$index]")) }
    }
    return ,$result.ToArray()
}

function Copy-SkillLevels($Value, [string]$Location) {
    $result = [ordered]@{}
    $entries = @()
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $entries = @($Value.PSObject.Properties | ForEach-Object {
            @{ Key = $_.Name; Value = $_.Value }
        })
    } elseif ($Value -is [array]) {
        $entries = @($Value | ForEach-Object { @{ Key = $null; Value = $_ } })
    } else { throw "Esperada uma lista de habilidades em $Location." }
    foreach ($entry in $entries) {
        $item = $entry.Value
        $id = $entry.Key
        $level = $item
        if ($item -is [System.Management.Automation.PSCustomObject]) {
            $idField = Get-JsonProperty $item 'skill_id'
            if ($null -ne $idField) { $id = $idField.Value }
            $levelField = Get-JsonProperty $item 'level'
            if ($null -eq $levelField) { $levelField = Get-JsonProperty $item 'skill_level' }
            $level = if ($null -ne $levelField) { $levelField.Value } else { 0 }
        } elseif ($null -eq $entry.Key) { continue }
        # 1..20 are used by bonuses / the maxed-skills indicator. No other keys.
        if ([string]$id -cmatch '^([1-9]|1[0-9]|20)$') {
            $result[[string]$id] = Copy-Number $level 'integer' "$Location.$id"
        }
    }
    return $result
}

function Copy-Allowed($Value, [string]$Rule, [string]$Location) {
    if ($null -eq $Value) { return $null }
    if ($Rule.EndsWith('[]')) {
        $itemRule = $Rule.Substring(0, $Rule.Length - 2)
        $items = $Value
        # The app also accepts a single record for these three SWEX fields.
        if ($itemRule -in @('deck', 'deck-equipment', 'rta-rune') -and
            $Value -is [System.Management.Automation.PSCustomObject]) { $items = @($Value) }
        if ($items -isnot [array]) { throw "Esperada uma lista em $Location." }
        $result = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $items.Count; $index++) {
            $result.Add((Copy-Allowed $items[$index] $itemRule "$Location[$index]"))
        }
        return ,$result.ToArray()
    }
    if ($Rule -in @('integer', 'number')) { return Copy-Number $Value $Rule $Location }
    if ($Rule -eq 'changed-item') {
        $type = Get-JsonProperty $Value 'type'
        $info = Get-JsonProperty $Value 'info'
        if ($null -eq $type -or $null -eq $info) { return $null }
        $schema = if ($type.Value -eq 8) { 'rune' } elseif ($type.Value -eq 73) { 'artifact' }
                  elseif ($null -ne (Get-JsonProperty $info.Value 'craft_item_id')) { 'material' } else { $null }
        if (-not $schema) { return $null }
        return [ordered]@{type=(Copy-Number $type.Value 'integer' "$Location.type"); info=(Copy-Allowed $info.Value $schema "$Location.info")}
    }
    if ($Rule -in @('main-effect', 'rune-effect', 'artifact-effect')) {
        return ,(Copy-Effect $Value $Rule $Location)
    }
    if ($Rule -eq 'skill-levels') { return Copy-SkillLevels $Value $Location }
    if (-not $Schemas.ContainsKey($Rule)) { throw 'Regra interna desconhecida.' }
    if ($Value -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Esperado um objeto em $Location."
    }
    $result = [ordered]@{}
    foreach ($field in $Schemas[$Rule].GetEnumerator()) {
        $property = Get-JsonProperty $Value $field.Key
        if ($null -eq $property) { continue }
        # Only one artifact-family selector is actually used for each type.
        if ($Rule -eq 'artifact' -and $field.Key -in @('attribute', 'unit_style')) {
            $typeField = Get-JsonProperty $Value 'type'
            $kind = if ($null -ne $typeField) { [string]$typeField.Value } else { '' }
            if (($field.Key -eq 'attribute' -and $kind -ne '1') -or
                ($field.Key -eq 'unit_style' -and $kind -ne '2')) { continue }
        }
        $result[$field.Key] = Copy-Allowed $property.Value $field.Value "$Location.$($field.Key)"
    }
    return $result
}

function Write-NewJson([string]$SourcePath, [string]$Destination, [byte[]]$Bytes, [string]$FakeName) {
    $automatic = [string]::IsNullOrWhiteSpace($Destination)
    $folder = [System.IO.Path]::GetDirectoryName($SourcePath)
    if ($automatic) {
        if ([string]::IsNullOrWhiteSpace($FakeName)) { throw 'Provide the fictitious name for the copy.' }
        # Only the filename is sanitized; the chosen identity stays unchanged in JSON.
        $stem = $FakeName.Trim() -replace '[<>:"/\\|?*\x00-\x1f]', '_'
        $stem += '_clean_copy'
        if ($stem -match '^(CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])\.') { $stem = '_' + $stem }
    }
    $counter = 1
    while ($true) {
        if ($automatic) {
            $name = if ($counter -eq 1) { "$stem.json" } else { "$stem-$counter.json" }
            $Destination = [System.IO.Path]::Combine($folder, $name)
        }
        $Destination = [System.IO.Path]::GetFullPath($Destination)
        if ([System.IO.Path]::GetExtension($Destination) -ine '.json') {
            throw 'O arquivo de saida precisa ter a extensao .json.'
        }
        if ($Destination -ieq $SourcePath -or [System.IO.File]::Exists($Destination) -or
            [System.IO.Directory]::Exists($Destination)) {
            if ($automatic) { $counter++; continue }
            throw 'O destino ja existe ou e o arquivo original. Escolha outro nome.'
        }
        $stream = $null
        try {
            # CreateNew refuses overwrites, including a destination created after the check.
            $stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            if ($automatic -and [System.IO.File]::Exists($Destination)) { $counter++; continue }
            throw
        }
        try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush() }
        catch {
            $stream.Dispose()
            # Only remove the incomplete NEW file owned by this invocation.
            [System.IO.File]::Delete($Destination)
            throw
        } finally { $stream.Dispose() }
        return $Destination
    }
}

function Get-AccountHash($Value) {
    $number = 0L
    if ([string]$Value -cnotmatch '^[0-9]+$' -or -not [long]::TryParse([string]$Value, [ref]$number) -or $number -le 0) {
        throw 'Invalid account ID.'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$number)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-PrivacyAlias([string]$Name, [string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Trim().Length -gt 48 -or $Name -cmatch '[\x00-\x1f\x7f]') {
        throw 'Choose a fictitious name with 1 to 48 characters and no control characters.'
    }
    $number = 0L
    if ($Id -cnotmatch '^[1-9][0-9]{0,15}$' -or -not [long]::TryParse($Id, [ref]$number) -or $number -gt 9007199254740991) {
        throw 'Choose a fictitious numeric ID from 1 to 9007199254740991.'
    }
}

function Read-PrivacyIdentity([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path
        if ($item.Length -gt 4096) { throw 'Too large' }
        $value = ConvertFrom-Json ([IO.File]::ReadAllText($item.FullName, [Text.Encoding]::UTF8))
        if ($value.version -ne 1 -or $value.source_hash -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid format' }
        Test-PrivacyAlias $value.fake_name ([string]$value.fake_id)
        return $value
    } catch { throw 'Invalid private identity file. Generate it with the JSON helper first.' }
}

function Select-PrivacyFile([string]$Title, [string]$Filter) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = [Windows.Forms.OpenFileDialog]::new()
    $picker.Title = $Title; $picker.Filter = $Filter; $picker.Multiselect = $false
    try {
        if ($picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return $picker.FileName }
        return $null
    } finally { $picker.Dispose() }
}

function Show-PrivacyIdentity {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'Choose a fictitious account identity'
    $form.ClientSize = [Drawing.Size]::new(440, 230)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $fields = @()
    $labels = @('Fictitious account name (not your real name)', 'Fictitious numeric ID (reuse it for the log copy)')
    for ($i = 0; $i -lt 2; $i++) {
        $label = [Windows.Forms.Label]::new(); $label.Text = $labels[$i]
        $label.SetBounds(20, (18 + $i * 68), 400, 24)
        $field = [Windows.Forms.TextBox]::new(); $field.SetBounds(20, (44 + $i * 68), 400, 25)
        $form.Controls.Add($label); $form.Controls.Add($field); $fields += $field
    }
    $ok = [Windows.Forms.Button]::new(); $ok.Text = 'Create copy'; $ok.SetBounds(220, 182, 100, 30)
    $ok.Add_Click({
        try {
            Test-PrivacyAlias $fields[0].Text $fields[1].Text
            $form.DialogResult = [Windows.Forms.DialogResult]::OK; $form.Close()
        } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Check the identity') }
    })
    $cancel = [Windows.Forms.Button]::new(); $cancel.Text = 'Cancel'; $cancel.SetBounds(330, 182, 90, 30)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($ok); $form.Controls.Add($cancel); $form.AcceptButton = $ok; $form.CancelButton = $cancel
    try {
        if ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            return @{Name=$fields[0].Text; Id=$fields[1].Text}
        }
        return $null
    } finally { $form.Dispose() }
}

# FullLogger uses the same inventory allowlists, plus only fields consumed by
# live_events.py, drop_history.py and upgrade_history.py. Never copy raw requests.
$Schemas['request'] = [ordered]@{
    rune_id='integer'; rune_id_list='integer[]'; unit_id='integer'
    craft_item_id='integer'; craft_item_id_list='integer[]'; artifact_ids='integer[]'
    updates='occupation[]'; lock_type='integer'
}
# Only request fields actually consumed for that command. In particular,
# unit_id_list can contain battle formations or conversion objects; neither
# is needed to apply inventory changes from those commands' responses.
$LogRequestFields = @{
    SellRune=@('rune_id_list'); SellArtifacts=@('artifact_ids')
    EquipRune=@('rune_id','unit_id'); UnequipRune=@('rune_id'); EquipRuneList=@('unit_id')
    UpdateArtifactOccupation=@('updates')
    LockRune=@('rune_id','lock_type'); UnlockRune=@('rune_id','lock_type')
    AmplifyRune=@('craft_item_id'); AmplifyRune_v2=@('craft_item_id')
    ConvertRune=@('craft_item_id'); ConvertRune_v2=@('craft_item_id')
    SellRuneCraftItem=@('craft_item_id_list')
}
$Schemas['occupation'] = [ordered]@{rid='integer'; occupied_id='integer'}
$Schemas['crate'] = [ordered]@{runes='rune[]'; rune='rune'; artifacts='artifact[]'; artifact='artifact'; changestones='material[]'}
$Schemas['reward'] = [ordered]@{crate='crate'}
$Schemas['response'] = [ordered]@{}
foreach ($field in $Schemas.export.GetEnumerator()) { $Schemas.response[$field.Key] = $field.Value }
foreach ($field in ([ordered]@{
    ret_code='integer'; rune='rune'; upgrade_rune_list='rune[]'; artifact='artifact'
    changed_item_list='changed-item[]'; reward='reward'; unit_info_list='unit[]'; mob_list='unit[]'
    unit_info='unit'; remove_unit_id_list='integer[]'; unequip_rune_id_list='integer[]'
    equip_rune_id_list='integer[]'; lock_type='integer'
}).GetEnumerator()) { $Schemas.response[$field.Key] = $field.Value }

function Convert-PrivateLogEvent($Request, $Response, $Identity) {
    $requestCommand = Get-JsonProperty $Request 'command'
    $responseCommand = Get-JsonProperty $Response 'command'
    $resultCode = Get-JsonProperty $Response 'ret_code'
    if ($null -eq $requestCommand -or $null -eq $responseCommand -or $null -eq $resultCode -or
        $resultCode.Value -ne 0 -or $requestCommand.Value -cne $responseCommand.Value) { return $null }
    $command = [string]$requestCommand.Value
    $known = @('HubUserLogin','GuestLogin','RepurchaseRune','GetRuneList','GetArtifactList','GetRuneCraftItemList',
        'GetUnitStorageList','getUnitStorageList','SellRune','SellArtifacts','EquipRune','UnequipRune','EquipRuneList',
        'UpdateArtifactOccupation','LockRune','UnlockRune','AmplifyRune','AmplifyRune_v2','ConvertRune','ConvertRune_v2',
        'SellRuneCraftItem','UpgradeRuneList','UpgradeRune','upgradeRune','UpgradeRune_v2','upgradeRune_v2')
    if ($command -cin $known) { $publicCommand = $command }
    elseif ($command -cmatch '^(Battle|battle)[A-Za-z0-9_]+$') { $publicCommand = 'BattleDungeonResult_V2' }
    elseif ($command -cmatch '^(Equip|Unequip|Sell|Buy|Upgrade|upgrade|Amplify|Convert|Confirm|Lock|Unlock|UpdateRune|UpdateArtifact|Summon|Awaken|Evolve|LevelUp|Sacrifice)[A-Za-z0-9_]*$') {
        $publicCommand = 'UpdateRune'
    } else { return $null }
    $requestId = Get-JsonProperty $Request 'wizard_id'
    $responseWizard = Get-JsonProperty $Response 'wizard_info'
    $responseId = if ($null -ne $responseWizard) { Get-JsonProperty $responseWizard.Value 'wizard_id' } else { $null }
    if ($null -eq $requestId -and $null -eq $responseId) { return $null }
    foreach ($account in @($requestId, $responseId)) {
        if ($null -ne $account -and (Get-AccountHash $account.Value) -cne $Identity.source_hash) { return $null }
    }
    $req = [ordered]@{}
    if ($LogRequestFields.ContainsKey($publicCommand)) {
        foreach ($field in $LogRequestFields[$publicCommand]) {
            $property = Get-JsonProperty $Request $field
            if ($null -ne $property) {
                $req[$field] = Copy-Allowed $property.Value $Schemas.request[$field] "request.$field"
            }
        }
    }
    $resp = Copy-Allowed $Response 'response' 'response'
    $req['command'] = $publicCommand; $req['wizard_id'] = $Identity.fake_id
    $resp['command'] = $publicCommand
    if (-not $resp.Contains('wizard_info') -or $null -eq $resp.wizard_info) { $resp['wizard_info'] = [ordered]@{} }
    $resp.wizard_info['wizard_id'] = $Identity.fake_id; $resp.wizard_info['wizard_name'] = $Identity.fake_name
    if ($resp.Contains('changed_item_list')) { $resp.changed_item_list = @($resp.changed_item_list | Where-Object { $null -ne $_ }) }
    $requestJson = ConvertTo-Json -InputObject $req -Depth 32 -Compress
    $responseJson = ConvertTo-Json -InputObject $resp -Depth 32 -Compress
    return "API Command: $publicCommand - filtered`r`nRequest:`r`n$requestJson`r`nResponse:`r`n$responseJson`r`n`r`n"
}
