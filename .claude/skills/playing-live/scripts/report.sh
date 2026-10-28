#!/usr/bin/env bash
# Brings back what the client's own Lua sees of a login: the player's state and the errors the
# addons raised, which the client's log file does not record. It installs the GenesisReport addon
# on the PC before the client starts and collects the report it saves.
#
#   report.sh install [--with-broken]  writes the GenesisReport addon to the PC's Addons folder, with
#                                      the names of the addons the PC has installed, and deletes any
#                                      old report; --with-broken also installs GenesisBroken, an addon
#                                      that fails on load, for the check that errors come back
#   report.sh collect <folder>         copies the report back into <folder>, converts it to
#                                      <folder>/report.json and prints it; refuses a report older
#                                      than the client that client.sh recorded
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
# with a recursive search since the account part of its path may be empty. collect compares its
# write time with the start time in client.pid, which client.sh start records: a report from before
# it belongs to an earlier session. report_xml.py does the conversion.
set -euo pipefail

usage() { sed -n '6,13p' "$0" >&2; exit 2; }

command=${1:-}
with_broken=0
case "$command" in
  install)
    [ $# -eq 1 ] || { [ $# -eq 2 ] && [ "$2" = --with-broken ]; } || usage
    if [ $# -eq 2 ]; then with_broken=1; fi ;;
  collect) [ $# -eq 2 ] || usage ;;
  remove) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

tool=report
. "$(dirname "$0")/pc.sh"

# PowerShell on the PC: $base is the client's per-user folder, and Refuse-When-Running stops the run
# when any WildStar64 process runs.
ps_common='$base = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "NCSOFT\WildStar"
function Refuse-When-Running {
  if (Get-Process WildStar64 -ErrorAction SilentlyContinue) {
    throw "a WildStar64 process runs on the PC; the person may be playing, so nothing was changed"
  }
}'

# Runs the PowerShell text $1 on the PC after ps_common, and leaves its output in $out. A run that
# fails ends the script with its message.
pc_ps() {
  local status=0
  out=$(on_pc_ps "try {
$ps_common
$1
} catch {
  'error: ' + (\$_.Exception.Message -replace '\s+', ' ')
  exit 1
}") || status=$?
  case "$out" in
    error:*) echo "report: ${out#error: }" >&2; exit 1 ;;
  esac
  [ "$status" -eq 0 ] || { echo "report: the PC's PowerShell failed (status $status)" >&2; exit 1; }
}

# The PowerShell list of the addon folders this script puts on the PC.
all_folders="'GenesisReport', 'GenesisBroken'"

case "$command" in
  install)
    pc_ps 'Refuse-When-Running
$base
$xml = Join-Path $base "Addons.xml"
if (Test-Path $xml) {
  ([xml](Get-Content -Raw -Encoding UTF8 $xml)).Addons.Addon | ForEach-Object { $_.Folder } | Where-Object { $_ }
}'
    base=$(sed -n 1p <<< "$out")
    installed_names=$(sed 1d <<< "$out")

    # GenesisReportAddons.lua: the names the addon sweeps, each as a Lua string.
    names_file=$pc_tmp/GenesisReportAddons.lua
    wanted=(GenesisReport)
    if [ "$with_broken" -eq 1 ]; then wanted+=(GenesisBroken); fi
    count=0
    {
      echo '-- Written by report.sh install: the addons whose errors GenesisReport sweeps.'
      echo 'GenesisReportAddons ='
      echo '{'
      while IFS= read -r name; do
        name=${name//\\/\\\\}
        printf '\t"%s",\n' "${name//\"/\\\"}"
        count=$((count + 1))
      done < <(printf '%s\n' "$installed_names" "${wanted[@]}" | sed '/^$/d' | sort -u)
      echo '}'
    } > "$names_file"

    wanted_folders="'GenesisReport'"
    if [ "$with_broken" -eq 1 ]; then wanted_folders+=", 'GenesisBroken'"; fi
    pc_ps "Refuse-When-Running
\$addons = Join-Path \$base 'Addons'
foreach (\$name in $all_folders) {
  \$path = Join-Path \$addons \$name
  if (Test-Path \$path) { Remove-Item -Recurse -Force \$path }
}
foreach (\$name in $wanted_folders) { New-Item -ItemType Directory -Force (Join-Path \$addons \$name) | Out-Null }
\$saved = Join-Path \$base 'AddonSaveData'
if (Test-Path \$saved) { Get-ChildItem \$saved -Recurse -File -Filter 'GenesisReport_*.xml' | Remove-Item -Force }"

    remote=${base//\\//}/Addons
    scp -q "${options[@]}" "$pc_dir/GenesisReport/toc.xml" "$pc_dir/GenesisReport/GenesisReport.lua" "$names_file" "$GENESIS_PLAY_PC:$remote/GenesisReport/" \
      || { echo "report: could not copy the addon to the PC; run report.sh remove" >&2; exit 1; }
    if [ "$with_broken" -eq 1 ]; then
      scp -q "${options[@]}" "$pc_dir/GenesisBroken/toc.xml" "$pc_dir/GenesisBroken/GenesisBroken.lua" "$GENESIS_PLAY_PC:$remote/GenesisBroken/" \
        || { echo "report: could not copy the addon to the PC; run report.sh remove" >&2; exit 1; }
    fi

    expected="'GenesisReport\\toc.xml', 'GenesisReport\\GenesisReport.lua', 'GenesisReport\\GenesisReportAddons.lua'"
    if [ "$with_broken" -eq 1 ]; then expected+=", 'GenesisBroken\\toc.xml', 'GenesisBroken\\GenesisBroken.lua'"; fi
    pc_ps "foreach (\$file in $expected) {
  if (-not (Test-Path (Join-Path (Join-Path \$base 'Addons') \$file))) { throw \"the PC has no \$file after the copy\" }
}
'ok'"
    echo "installed ${wanted[*]} in $base\\Addons; GenesisReport sweeps $count addon names" ;;

  collect)
    folder=$2
    read_state
    pc_ps "\$started = [DateTime]::FromFileTimeUtc($started)
\$saved = Join-Path \$base 'AddonSaveData'
\$found = @()
if (Test-Path \$saved) { \$found = @(Get-ChildItem \$saved -Recurse -File -Filter 'GenesisReport_0_*.xml') }
if (\$found.Count -eq 0) { throw \"there is no GenesisReport_0_*.xml under \$saved; the addon writes it when it reloads the interface, about 10 s after the character is in\" }
if (\$found.Count -gt 1) { throw ('more than one report: ' + (\$found.FullName -join ', ')) }
\$written = \$found[0].LastWriteTimeUtc
if (\$written -lt \$started) {
  throw ('the report was written at ' + \$written.ToString('o') + ', before the client started at ' + \$started.ToString('o') + '; it belongs to an earlier session, so nothing was copied')
}
\$found[0].FullName"
    remote_file=$out
    mkdir -p "$folder"
    scp -q "${options[@]}" "$GENESIS_PLAY_PC:${remote_file//\\//}" "$folder/${remote_file##*\\}" \
      || { echo "report: could not copy $remote_file from the PC" >&2; exit 1; }
    python3 -I "$pc_dir/report_xml.py" "$folder/${remote_file##*\\}" > "$folder/report.json.tmp" \
      || { rm -f "$folder/report.json.tmp"; exit 1; }
    mv "$folder/report.json.tmp" "$folder/report.json"
    cat "$folder/report.json" ;;

  remove)
    pc_ps "Refuse-When-Running
\$addons = Join-Path \$base 'Addons'
foreach (\$name in $all_folders) {
  \$path = Join-Path \$addons \$name
  if (Test-Path \$path) {
    Remove-Item -Recurse -Force \$path
    if (Test-Path \$path) { throw \"\$path is still on the PC\" }
    \"removed \$path\"
  }
}"
    if [ -z "$out" ]; then echo "no GenesisReport or GenesisBroken addon on the PC; nothing was changed"; else echo "$out"; fi ;;
esac
