"""Converts the XML the client saves for an addon (AddonSaveData\\<addon>_<n>_<level>.xml) to JSON.

    python3 -I report_xml.py <file.xml>
    python3 -I report_xml.py --timeline <report.json> <installed_at>

The first form's JSON goes to standard output. The format is the one SaveAddonObject writes (fact 0x140185f30):
a <Document> holding one <N> per table entry; K="key" gives a string key and F="n" a number key;
T is the value's type (t table, n number, s string, b boolean); V is the value (a boolean is + or
-, text is XML-escaped); a table's entries are its own <N> children; an empty table is
<Document/>. A table whose keys are the numbers 1 to n is a JSON list; any other table is a JSON
object with its keys as text, which an empty table is too.

The second form reads the JSON of a GenesisReport timeline (the addon's timeline mode, written
by report.sh install --timeline) and prints one line per entry:

    <UTC time> game <seconds> <poll|event[ in|out]> combat <true|false> resource <n>/<max>

A value the entry lacks prints as -. It accepts the report by its own numbers, with no client
start time: bTimeline and bReported are true, the timeline holds entries, nInstalledAt is the
<installed_at> (Unix seconds on the PC) of the addon installed now, so the report is from this
install and not an earlier one, the entries' nTime never go back and none is before nInstalledAt
or after nReportedAt (the addon's os.time() at its save). Lua errors the addons raised follow as
lines starting "lua error".

Exits 1, printing nothing to standard output, on a file that is not a saved-addon document, and
on a timeline the second form does not accept (the reason on standard error).
"""

import datetime
import json
import sys
import xml.etree.ElementTree as ElementTree


def read_value(entry):
    """The Python value of one <N> element: a list, dict, number, text or boolean."""
    kind = entry.get("T")
    if kind == "t":
        return read_table(entry)
    text = entry.get("V", "")
    if kind == "b":
        if text not in ("+", "-"):
            raise ValueError(f"a boolean that is neither + nor -: {text!r}")
        return text == "+"
    if kind == "n":
        try:
            return int(text)
        except ValueError:
            return float(text)
    if kind == "s":
        return text
    raise ValueError(f"an entry of unknown type {kind!r}")


def read_table(element):
    """A table (a <Document> or a T="t" <N>) as a list when its keys are 1 to n, else a dict."""
    entries = []
    for entry in element:
        if entry.tag != "N":
            raise ValueError(f"an element <{entry.tag}> where <N> belongs")
        if entry.get("K") is not None:
            key = entry.get("K")
        elif entry.get("F") is not None:
            key = float(entry.get("F"))
            key = int(key) if key == int(key) else key
        else:
            raise ValueError("an <N> with neither K nor F")
        entries.append((key, read_value(entry)))
    keys = [key for key, _ in entries]
    if entries and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(entries) + 1)):
        return [value for _, value in sorted(entries, key=lambda entry: entry[0])]
    return {str(key): value for key, value in entries}


def convert(text):
    """The Python value of a saved-addon document's text."""
    root = ElementTree.fromstring(text)
    if root.tag != "Document":
        raise ValueError(f"the root element is <{root.tag}>, not <Document>")
    return read_table(root)


def check_timeline(report, installed_at):
    """Raises ValueError, saying why, unless the report is a timeline from the install at installed_at."""
    if not isinstance(report, dict) or report.get("bTimeline") is not True:
        raise ValueError("not a timeline report (no bTimeline = true); install with --timeline")
    if report.get("bReported") is not True:
        raise ValueError("the timeline holds no entries (no bReported = true)")
    entries = report.get("arTimeline")
    if not isinstance(entries, list) or not entries:
        raise ValueError("the timeline holds no entries")
    if report.get("nInstalledAt") != installed_at:
        raise ValueError(
            f"the timeline is from the install at Unix time {report.get('nInstalledAt')}, "
            f"not the one now on the PC ({installed_at}); it belongs to an earlier session"
        )
    reported_at = report.get("nReportedAt")
    if not isinstance(reported_at, (int, float)):
        raise ValueError("the timeline has no nReportedAt")
    previous = installed_at
    for index, entry in enumerate(entries, start=1):
        moment = entry.get("nTime") if isinstance(entry, dict) else None
        if not isinstance(moment, (int, float)):
            raise ValueError(f"entry {index} has no nTime")
        if moment < previous:
            raise ValueError(f"entry {index} is at {moment}, before {previous}")
        if moment > reported_at:
            raise ValueError(f"entry {index} is at {moment}, after the report's nReportedAt {reported_at}")
        previous = moment


def timeline_lines(report):
    """One text line per timeline entry, then one per Lua error the report holds."""
    def shown(value):
        if value is None:
            return "-"
        return str(value).lower() if isinstance(value, bool) else str(value)

    lines = []
    for entry in report["arTimeline"]:
        moment = datetime.datetime.fromtimestamp(entry["nTime"], datetime.timezone.utc)
        source = entry.get("strSource", "-")
        if source == "event":
            source += " in" if entry.get("bEventInCombat") else " out"
        lines.append(
            f"{moment:%Y-%m-%dT%H:%M:%SZ} game {shown(entry.get('nGameTime'))} {source} "
            f"combat {shown(entry.get('bInCombat'))} "
            f"resource {shown(entry.get('nResource'))}/{shown(entry.get('nMaxResource'))}"
        )
    errors = report.get("tLuaErrorEvents")
    for error in errors if isinstance(errors, list) else []:
        lines.append(f"lua error {error.get('strAddon', '-')}: {error.get('strError', '-')}")
    return lines


def main_timeline(arguments):
    try:
        installed_at = int(arguments[3])
        with open(arguments[2], encoding="utf-8") as saved:
            report = json.load(saved)
        check_timeline(report, installed_at)
        lines = timeline_lines(report)
    except (OSError, ValueError) as error:
        print(f"report_xml: {arguments[2]}: {error}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    return 0


def main(arguments):
    if len(arguments) == 4 and arguments[1] == "--timeline":
        return main_timeline(arguments)
    if len(arguments) != 2:
        print("usage: python3 -I report_xml.py <file.xml>\n"
              "       python3 -I report_xml.py --timeline <report.json> <installed_at>", file=sys.stderr)
        return 2
    try:
        with open(arguments[1], encoding="utf-8") as saved:
            report = convert(saved.read())
    except (OSError, ValueError, ElementTree.ParseError) as error:
        print(f"report_xml: {arguments[1]}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
