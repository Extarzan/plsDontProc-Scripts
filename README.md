# plsDontProc Privacy Tools

plsDontProc processes your SWEX data locally. It does not upload your SWEX files
or send your account information over the internet. All account and gameplay
data it reads comes from SWEX exports and optional FullLogger files, including
obfuscated copies you choose to import. The app does not access your game account
or require the game to be installed. You can copy the files to a computer that
has never accessed the game or your account and optimize entirely offline.
Live synchronization needs updated log files. Update checks and online help or
support features use the internet without uploading your account files.

These scripts are **optional tools for obfuscating your own input files**. They
show how to remove unused fields and replace your account name and ID before
importing a JSON or log into the app. You can inspect and modify the scripts,
write your own, or edit the JSON yourself while preserving the required structure
and inventory fields. The app processes the data locally with or without them.

**The MIT license applies only to the standalone privacy scripts and their
documentation. It does not apply to the plsDontProc application, its source code
or its assets. Publishing these scripts does not make the application open source.**

[Download the complete ZIP](https://github.com/Extarzan/plsDontProc-Scripts/archive/refs/heads/main.zip),
extract it, and keep all files together. Start with **`clean-json.bat`**, then
use **`clean-full-log.bat`** if you want continuous synchronization.

Source: [JSON helper](clean-json.ps1) · [FullLogger helper](clean-full-log.ps1) ·
[Shared allowlists](privacy-common.ps1) · [MIT license — scripts only](LICENSE).

Two open-source, offline Windows tools that prepare copies **before** you give
files to plsDontProc. The originals are never modified. The tools need only
Windows PowerShell 5.1 (included in Windows 10/11), not Python or the app.
They do not contact any server, install a service or launch the application.

Keep every file from the ZIP together. Read the `.ps1` and `.bat` files with a
text editor before executing them. All tools and the common code use the MIT
license in `LICENSE`. The app's Home has **I don't trust this app**, with this
download and readable source links.

## 1. Create a filtered JSON and a fictitious identity

1. Open `clean-json.bat`, or drag a SWEX JSON onto it.
2. Select the original JSON in the script's own picker.
3. Enter a fictitious account name (1–48 characters) and a fictitious positive
   numeric ID (up to 9007199254740991, different from your real account ID).
4. Import **`<your fictitious name>_clean_copy.json`** into the app. For example,
   entering `Tarzan` creates **`Tarzan_clean_copy.json`**.

The copy is saved next to the original. Existing names receive `-2`, `-3`, etc.
(for example, `Tarzan_clean_copy-2.json`). Characters Windows does not allow in
filenames become `_` in the filename only; the name inside the JSON stays as entered.
No file is overwritten. Your fictitious name and ID replace `wizard_name` and
`wizard_id`; other occurrences of account identity are discarded by field
allowlists. The output filename does not contain the original name or ID.

The separate **`<your fictitious name>_clean_copy.identity.json`** stores the fictitious identity
and a SHA-256 fingerprint of the original account ID so the log helper can
recognize the correct account. It contains no original ID, name or source path
in plain text. Keep it private: a fingerprint is not encryption and does not
make an account ID impossible to guess. **Do not import or share this file.**
Use a different fictitious identity for each real account.

For future JSON exports, reuse the identity file with the command below. This
keeps the same account identity and RTA bindings. The helper rejects an identity
file belonging to another real account. Import the newly generated copy manually.

## 2. Keep a filtered FullLogger copy updated

1. Enable FullLogger in SWEX.
2. Open `clean-full-log.bat` (or drop the original `full_log.txt` onto it).
3. Choose the original log and the `.identity.json` created in step 1.
4. The helper creates **`plsdontproc-full_log.txt`** beside the identity file.
5. In the app, disconnect any previously selected original log, load the filtered
   JSON, and select **only the generated log copy** for Account syncing.
6. Keep the helper window open while playing. Ctrl+C or closing its window stops
   updates. The app keeps the last synchronized data.

Each helper launch creates a new file (`-2`, `-3`, etc. if needed), which must be
selected in the app. It finds the latest complete login snapshot for your account
already present in the source log, filters from there, then follows appended data
every second. This skips older history, including history from other accounts.
The window shows **Up to date. Watching for new events.** when it catches up.
No scheduled task or background service is installed. `-Once` makes a static
filtered copy and exits. The command-line `-Resume` option can keep using an
existing filtered copy with the same fictitious identity.

The script writes complete request/response pairs, never half a JSON record.
It handles UTF-8 split between writes and waits for incomplete lines. Events
from other accounts are discarded before filtering; they are never relabeled
as your account. Request and response IDs must agree when both are present.
When the source is replaced, truncated or contains a malformed event, a reset
record makes the app wait for a complete login snapshot. **You do not need to
log in again just to start the helper or enable synchronization.** An existing
snapshot and its subsequent events can establish the current inventory. Log in
again through SWEX only if the app is still waiting for a snapshot because the
available history is missing or incomplete. If no matching snapshot exists, the
helper filters all available events and continues waiting for new ones.

The helper reads the original locally; the application is given only its output.
This is a filtered inventory stream, not a complete archival copy of FullLogger.

## What remains, and why

| Retained data | Purpose |
| --- | --- |
| Fictitious account name and ID | Match JSON and log; separate saved account configurations. |
| Export/event timestamps; successful command/result markers | Keep updates ordered and reject older exports. |
| Mana, crystals, energy | Account counters. |
| Purchased rune inventory expansions (`wizard_extra_data.rune_slot`) | Rune inventory capacity: 1600 base slots plus 20 per expansion. |
| Monster species and instance IDs; equipped runes/artifacts | Builds, exact monster bindings and inventory ownership. |
| Rune IDs, owner, set, slot, stars, rarity, level and numeric effects | Equipment, scores, rankings and optimization. |
| Artifact IDs, owner, type, family, levels and numeric effects | Artifact inventory, equipment and calculations. |
| RTA equipment, rune locks, team/deck records | PVE/RTA distinctions and exclusions. |
| Craft material IDs, kinds, types and amounts | Gems and grinds. |
| Summoner skills 1–20 and relevant guild combat bonuses | Combat stat calculations. |
| Supported inventory mutations/rewards, numeric IDs for sales/equipment | Live changes, drops and upgrades. |

The account ID is replaced. **Monster and equipment IDs are preserved**, including
large integers, because changing them would break bindings and event matching.
Inventory and timestamps can still be distinctive; this is data minimization
and a fictitious account identity, not a claim of complete anonymity.

Older copies removed `wizard_extra_data`. Generate a new copy from the original
JSON with the same identity file to restore the account's rune capacity. The
original file is never overwritten.

`privacy-common.ps1` defines the allowlists used by both entry scripts. Unknown
fields are removed recursively. Session/login credentials, device identifiers,
emails, player names, friends, guild identity/members, purchases, chats, battle
details and unused metadata do not enter the copies. Historical rune rewards
and partial equipment updates use the same filters as the full JSON. The script
does not copy arbitrary request/response objects or perform global text replacement.
Unneeded fields that happen to contain the account ID are discarded, not preserved.

The log helper preserves specific commands needed by the live consumer. Other
supported battle commands are normalized to `BattleDungeonResult_V2`, and generic
supported inventory mutations to `UpdateRune`; unknown/social commands are skipped.
This prevents arbitrary strings in original command headers from reaching the copy.
New fields/features may require an explicit allowlist update before they work.

## What this does not guarantee

Filtering changes the files you choose to share; it does not sandbox a desktop
program's Windows permissions. For an enforceable restriction, run the app under
a separate Windows user without access to the original export/log folders, and
make only the filtered files readable by that user. A local program with access
to the original folder could still read it. Inspecting open-source helper scripts
does not prove everything about the application that later reads their output.

Disconnect previously selected original logs before switching. These tools do
not delete prior app imports, old snapshots or logs. The app treats a fictitious
ID as a different account, so old RTA bindings do not automatically migrate to it.
Never connect a filtered JSON to the original log, or vice versa. Keep original
exports and the identity file out of the app account's accessible folder when
using separate Windows permissions. The helpers themselves are offline; app
updates and support features can use the network.

## Command line

```powershell
# New identity; output names are chosen safely if not specified.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-json.ps1 -InputPath "C:\exports\account.json" -FakeName "Private Player" -FakeId 700001 -NonInteractive

# Another export for the same fictitious identity.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-json.ps1 -InputPath "C:\exports\account.json" -IdentityPath "C:\exports\Private Player_clean_copy.identity.json" -NonInteractive

# Continuous log copy (Ctrl+C stops it).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-full-log.ps1 -InputPath "C:\exports\full_log.txt" -IdentityPath "C:\exports\Private Player_clean_copy.identity.json" -OutputPath "C:\filtered\public-log.txt" -NonInteractive

# Restart using the same filtered copy already selected in the app.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-full-log.ps1 -InputPath "C:\exports\full_log.txt" -IdentityPath "C:\exports\Private Player_clean_copy.identity.json" -OutputPath "C:\filtered\public-log.txt" -Resume -NonInteractive
```

`-OutputPath` must name a new file with the appropriate extension in an existing
directory. Existing files and originals are refused by default. With `-Resume`,
the log helper validates the existing filtered copy and its fictitious identity,
then appends without overwriting it. Stop the previous helper before resuming.
The execution-policy option applies only to that PowerShell process; it does not change Windows settings.
Organization-managed machines may have their own script restrictions.

## Source files

- `clean-json.ps1` / `.bat`: JSON picker, fictitious identity, new export.
- `clean-full-log.ps1` / `.bat`: original log picker and continuous filtered copy.
- `privacy-common.ps1`: allowlists, identity validation, event/account selection.
- `LICENSE`: MIT license covering only these scripts and their documentation, not the app.
