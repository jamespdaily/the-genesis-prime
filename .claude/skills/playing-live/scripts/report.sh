#!/usr/bin/env bash
# Brings back what the client's own Lua sees of a login: the player's state and the errors the
# addons raised, which the client's log file does not record.
#
#   report.sh install [--with-broken]  writes the GenesisReport addon to the PC's Addons folder, with
#                                      the names of the addons the PC has installed, and deletes any
#                                      old report; --with-broken also installs GenesisBroken, an addon
#                                      that fails on load, for the check that errors come back
#   report.sh collect <folder>         copies the report back into <folder>, converts it to
#                                      <folder>/report.json and prints it; refuses, copying nothing,
#                                      a report that is unfinished or was captured before the client
#                                      that client.sh recorded started
#   report.sh remove                   deletes both addons from the PC
#
# Needs GENESIS_PLAY_PC (user@host), read from ~/.genesis-prime/env.sh when it is there. The addon
# reloads the interface once per entry, so it is installed only for a session and removed after it.
# install and remove refuse, changing nothing, while any WildStar64 process runs: the client reads
# its addons only when the world starts (fact 0x140538fd0), and the person may be playing.
#
# The addon lives in <roaming application data>\NCSOFT\WildStar\Addons\GenesisReport (facts
# 0x1401b41f0, 0x1401b3ba0, 0x140135ad0), which the client scans for user addons. The names come from
# the Folder attribute of each Addon element of ..\Addons.xml, the file the client writes (fact
# 0x1401380c0), and are written to GenesisReportAddons.lua beside the addon, which sweeps each name's
# errors. The report is GenesisReport_0_Acct.xml under ..\AddonSaveData (fact 0x140185f30), found
# with a recursive search since the account part of its path may be empty. The client restores an
# earlier report and saves it again, so its file's write time proves nothing: collect compares the
# report's own nReportedAt (the addon's os.time(), Unix seconds) with the start time in client.pid,
# which client.sh start records, and its bReported flag (set just before the addon's reload). The
# report crosses as base64, since the PC's console would re-encode its text. report_xml.py does the
# conversion.
set -euo pipefail

usage() { sed -n '5,13p' "$0" >&2; exit 2; }

command=${1:-}
addons=(GenesisReport)
case "$command" in
  install)
    [ $# -eq 1 ] || { [ $# -eq 2 ] && [ "$2" = --with-broken ]; } || usage
    if [ $# -eq 2 ]; then addons+=(GenesisBroken); fi ;;
  collect) [ $# -eq 2 ] || usage ;;
  remove) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

tool=report
. "$(dirname "$0")/pc.sh"

# Every addon folder this script can put on the PC, which install and remove clear first.
known=(GenesisReport GenesisBroken)
ps_known=$(printf "'%s', " "${known[@]}")
ps_known=${ps_known%, }

# PowerShell on the PC: $base is the client's per-user folder, and Refuse-When-Running stops the run
# when any WildStar64 process runs.
ps_common='$base = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "NCSOFT\WildStar"
function Refuse-When-Running {
  if (Get-Process WildStar64 -ErrorAction SilentlyContinue) {
    throw "a WildStar64 process runs on the PC; the person may be playing, so nothing was changed"
  }
}'

# Runs the PowerShell text $1 on the PC after ps_common; see on_pc_ps_try.
report_ps() { on_pc_ps_try "$ps_common
$1"; }

case "$command" in
  install)
    out=$(report_ps 'Refuse-When-Running
$base
$xml = Join-Path $base "Addons.xml"
if (Test-Path $xml) {
  ([xml](Get-Content -Raw -Encoding UTF8 $xml)).Addons.Addon | ForEach-Object { $_.Folder } | Where-Object { $_ }
}')
    base=$(sed -n 1p <<< "$out")

    # The names the addon sweeps: the PC's installed addons and the ones installed here.
    names=()
    while IFS= read -r name; do
      names+=("$name")
    done < <(printf '%s\n' "$(sed 1d <<< "$out")" "${addons[@]}" | sed '/^$/d' | sort -u)

    stage=$pc_tmp/stage
    mkdir -p "$stage"
    for addon in "${addons[@]}"; do cp -R "$pc_dir/$addon" "$stage/$addon"; done
    {
      echo '-- Written by report.sh install: the addons whose errors GenesisReport sweeps.'
      echo 'GenesisReportAddons ='
      echo '{'
      for name in "${names[@]}"; do
        name=${name//\\/\\\\}
        printf '\t"%s",\n' "${name//\"/\\\"}"
      done
      echo '}'
    } > "$stage/GenesisReport/GenesisReportAddons.lua"

    # One ssh into the PC's cmd.exe: clears the old addons and the old report (del /S searches the
    # account folders), then unpacks the selected addons from the tar on standard input.
    cmd="mkdir \"$base\\Addons\" 2>NUL"
    for name in "${known[@]}"; do cmd+=" & rmdir /S /Q \"$base\\Addons\\$name\" 2>NUL"; done
    cmd+=" & del /S /Q \"$base\\AddonSaveData\\GenesisReport_*.xml\" >NUL 2>&1 & tar -xf - -C \"$base\\Addons\""
    COPYFILE_DISABLE=1 tar -cf - -C "$stage" "${addons[@]}" | ssh "${options[@]}" "$GENESIS_PLAY_PC" "$cmd" \
      || { echo "report: could not copy the addons to the PC; run report.sh remove" >&2; exit 1; }
    echo "installed ${addons[*]} in $base\\Addons; GenesisReport sweeps ${#names[@]} addon names" ;;

  collect)
    folder=$2
    read_state
    out=$(report_ps '$saved = Join-Path $base "AddonSaveData"
$found = @()
if (Test-Path $saved) { $found = @(Get-ChildItem $saved -Recurse -File -Filter "GenesisReport_0_*.xml") }
if ($found.Count -eq 0) { throw "there is no GenesisReport_0_*.xml under $saved; the addon writes it when it reloads the interface, about 10 s after the character is in" }
if ($found.Count -gt 1) { throw ("more than one report: " + ($found.FullName -join ", ")) }
$found[0].Name
[Convert]::ToBase64String([IO.File]::ReadAllBytes($found[0].FullName))')
    name=$(sed -n 1p <<< "$out")
    [[ $name =~ ^GenesisReport_0_[A-Za-z0-9_.-]*\.xml$ ]] || { echo "report: the PC named the report '$name'" >&2; exit 1; }
    xml=$pc_tmp/$name
    sed 1d <<< "$out" | base64 --decode > "$xml"
    python3 -I "$pc_dir/report_xml.py" "$xml" > "$pc_tmp/report.json"

    # The client's start as Unix seconds: a file time counts 100 ns from 1601-01-01.
    started_unix=$((started / 10000000 - 11644473600))
    read -r reported reported_at < <(python3 -I -c '
import json, sys
report = json.load(open(sys.argv[1]))
print(report.get("bReported") is True, report.get("nReportedAt", 0))' "$pc_tmp/report.json")
    if [ "$reported" != True ]; then
      echo "report: $name is unfinished (no bReported = true); the addon saves it when it reloads the interface, about 10 s after the character is in, so nothing was copied" >&2
      exit 1
    fi
    if [ "$reported_at" -lt "$started_unix" ]; then
      echo "report: $name was captured at Unix time $reported_at, before the client started at $started_unix; it belongs to an earlier session, so nothing was copied" >&2
      exit 1
    fi
    mkdir -p "$folder"
    cp "$xml" "$folder/$name"
    cp "$pc_tmp/report.json" "$folder/report.json"
    cat "$folder/report.json" ;;

  remove)
    out=$(report_ps "Refuse-When-Running
\$addons = Join-Path \$base 'Addons'
foreach (\$name in $ps_known) {
  \$path = Join-Path \$addons \$name
  if (Test-Path \$path) {
    Remove-Item -Recurse -Force \$path
    \"removed \$path\"
  }
}")
    if [ -z "$out" ]; then echo "no GenesisReport or GenesisBroken addon on the PC; nothing was changed"; else echo "$out"; fi ;;
esac
