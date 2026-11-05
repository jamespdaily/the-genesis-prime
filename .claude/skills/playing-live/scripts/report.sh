#!/usr/bin/env bash
# Brings back what the client's own Lua sees of a login: the player's state and the errors the
# addons raised, which the client's log file does not record.
#
#   report.sh install [--with-broken] [--timeline [minutes]]
#                                      writes the GenesisReport addon to the PC's Addons folder, with
#                                      the names of the addons the PC has installed, and deletes any
#                                      old report; --with-broken also installs GenesisBroken, an addon
#                                      that fails on load, for the check that errors come back;
#                                      --timeline (minutes, a whole number from 1 to 600, 20 when
#                                      left out) puts the addon in timeline mode, for a fight a
#                                      person plays by hand
#   report.sh collect [--by-hand] <folder>
#                                      copies the report back into <folder> (a name that does not
#                                      start with --), converts it to <folder>/report.json and
#                                      prints it; refuses, copying nothing,
#                                      a report that is unfinished or was captured before the client
#                                      that client.sh recorded started. --by-hand is for a timeline
#                                      session the person started, with no client.pid: it accepts the
#                                      report by its own numbers (report_xml.py --timeline: from this
#                                      install, its entries in time order), keeps the XML and
#                                      report.json in <folder>, and prints <folder>/timeline.txt,
#                                      one line per entry and an end line (when saved, the last
#                                      entry's time, whether the minutes ran out: a save made mid-fight
#                                      shows as one), in place of the JSON
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
#
# Timeline mode: install writes GenesisReportTimelineMinutes and GenesisReportInstalledAt (the PC's
# Unix time at the install, read in the same PowerShell call) into GenesisReportAddons.lua, and the
# addon records the player's combat flag and Actuators every second and at each combat event instead
# of one snapshot (the addon's header lists the entry). The client writes the file only when it runs
# the addons' OnSave (facts 0x140539640, 0x1400446d0): on a reload and when the world is torn down.
# The addon asks for a reload when the timeline is its minutes long and 30 s after a fight ends, so
# a person who plays out the fight and waits 30 s has it saved; a person's /reloadui writes it too.
# Whether closing the client's window runs OnSave is not traced, so do not rely on it. collect
# --by-hand reads GenesisReportInstalledAt back from the addon still installed on the PC and
# compares it with the report's nInstalledAt, so a report left by an earlier install is refused.
set -euo pipefail

usage() { sed -n '5,27p' "$0" >&2; exit 2; }

command=${1:-}
addons=(GenesisReport)
timeline_minutes=
by_hand=no
case "$command" in
  install)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --with-broken) addons+=(GenesisBroken) ;;
        --timeline)
          timeline_minutes=20
          if [ $# -gt 1 ] && [[ $2 != --* ]]; then
            { [[ $2 =~ ^[1-9][0-9]{0,2}$ ]] && [ "$2" -le 600 ]; } || usage
            timeline_minutes=$2
            shift
          fi ;;
        *) usage ;;
      esac
      shift
    done ;;
  collect)
    if [ $# -eq 3 ] && [ "$2" = --by-hand ]; then
      by_hand=yes
      set -- collect "$3"
    fi
    [ $# -eq 2 ] || usage
    # A folder that starts with -- is a flag in the wrong place (collect --by-hand with no folder).
    [[ $2 != --* ]] || usage ;;
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
[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$xml = Join-Path $base "Addons.xml"
if (Test-Path $xml) {
  ([xml](Get-Content -Raw -Encoding UTF8 $xml)).Addons.Addon | ForEach-Object { $_.Folder } | Where-Object { $_ }
}')
    base=$(sed -n 1p <<< "$out")
    installed_at=$(sed -n 2p <<< "$out")
    [[ $installed_at =~ ^[0-9]+$ ]] || { echo "report: the PC gave the time '$installed_at'" >&2; exit 1; }

    # The names the addon sweeps: the PC's installed addons and the ones installed here.
    names=()
    while IFS= read -r name; do
      names+=("$name")
    done < <(printf '%s\n' "$(sed 1,2d <<< "$out")" "${addons[@]}" | sed '/^$/d' | sort -u)

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
      if [ -n "$timeline_minutes" ]; then
        echo "GenesisReportTimelineMinutes = $timeline_minutes"
        echo "GenesisReportInstalledAt = $installed_at"
      fi
    } > "$stage/GenesisReport/GenesisReportAddons.lua"

    # One ssh into the PC's cmd.exe: clears the old addons and the old report (del /S searches the
    # account folders), then unpacks the selected addons from the tar on standard input.
    cmd="mkdir \"$base\\Addons\" 2>NUL"
    for name in "${known[@]}"; do cmd+=" & rmdir /S /Q \"$base\\Addons\\$name\" 2>NUL"; done
    cmd+=" & del /S /Q \"$base\\AddonSaveData\\GenesisReport_*.xml\" >NUL 2>&1 & tar -xf - -C \"$base\\Addons\""
    COPYFILE_DISABLE=1 tar -cf - -C "$stage" "${addons[@]}" | ssh "${options[@]}" "$GENESIS_PLAY_PC" "$cmd" \
      || { echo "report: could not copy the addons to the PC; run report.sh remove" >&2; exit 1; }
    echo "installed ${addons[*]} in $base\\Addons; GenesisReport sweeps ${#names[@]} addon names"
    if [ -n "$timeline_minutes" ]; then
      echo "GenesisReport records a timeline of $timeline_minutes minutes (installed at PC Unix time $installed_at)"
    fi ;;

  collect)
    folder=$2
    # --by-hand: the PowerShell also prints the install's time from the addon still on the PC.
    installed_ps=
    missing='the addon writes it when it reloads the interface, about 10 s after the character is in'
    if [ "$by_hand" = yes ]; then
      installed_ps='$options = Join-Path $base "Addons\GenesisReport\GenesisReportAddons.lua"
$installed = $null
if (Test-Path $options) { $installed = Select-String -Path $options -Pattern "^GenesisReportInstalledAt = (\d+)$" }
if (-not $installed) { throw "the GenesisReport on the PC has no GenesisReportInstalledAt; install it with --timeline" }
$installed.Matches[0].Groups[1].Value'
      missing='in timeline mode the client writes it on a reload (/reloadui, or 30 s after a fight ends) and when the world is torn down (camp)'
    else
      read_state
    fi
    out=$(report_ps '$saved = Join-Path $base "AddonSaveData"
$found = @()
if (Test-Path $saved) { $found = @(Get-ChildItem $saved -Recurse -File -Filter "GenesisReport_0_*.xml") }
if ($found.Count -eq 0) { throw "there is no GenesisReport_0_*.xml under $saved; '"$missing"'" }
if ($found.Count -gt 1) { throw ("more than one report: " + ($found.FullName -join ", ")) }
$found[0].Name
'"$installed_ps"'
[Convert]::ToBase64String([IO.File]::ReadAllBytes($found[0].FullName))')
    name=$(sed -n 1p <<< "$out")
    [[ $name =~ ^GenesisReport_0_[A-Za-z0-9_.-]*\.xml$ ]] || { echo "report: the PC named the report '$name'" >&2; exit 1; }
    xml=$pc_tmp/$name
    if [ "$by_hand" = yes ]; then
      pc_installed_at=$(sed -n 2p <<< "$out")
      [[ $pc_installed_at =~ ^[0-9]+$ ]] || { echo "report: the PC gave the install time '$pc_installed_at'" >&2; exit 1; }
      sed 1,2d <<< "$out" | base64 --decode > "$xml"
    else
      sed 1d <<< "$out" | base64 --decode > "$xml"
    fi
    python3 -I "$pc_dir/report_xml.py" "$xml" > "$pc_tmp/report.json"

    if [ "$by_hand" = yes ]; then
      python3 -I "$pc_dir/report_xml.py" --timeline "$pc_tmp/report.json" "$pc_installed_at" > "$pc_tmp/timeline.txt" \
        || { echo "report: $name is not accepted, so nothing was copied" >&2; exit 1; }
      mkdir -p "$folder"
      cp "$xml" "$folder/$name"
      cp "$pc_tmp/report.json" "$folder/report.json"
      cp "$pc_tmp/timeline.txt" "$folder/timeline.txt"
      cat "$folder/timeline.txt"
      exit 0
    fi

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
