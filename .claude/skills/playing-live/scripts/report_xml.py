"""Converts the XML the client saves for an addon (AddonSaveData\\<addon>_<n>_<level>.xml) to JSON.

    python3 -I report_xml.py <file.xml>

The JSON goes to standard output. The format is the one SaveAddonObject writes (fact 0x140185f30):
a <Document> holding one <N> per table entry; K="key" gives a string key and F="n" a number key;
T is the value's type (t table, n number, s string, b boolean); V is the value (a boolean is + or
-, text is XML-escaped); a table's entries are its own <N> children; an empty table is
<Document/>. A table whose keys are the numbers 1 to n is a JSON list; any other table is a JSON
object with its keys as text, which an empty table is too.

report.sh collect uses this on the GenesisReport addon's report. A document without the addon's
bReported flag is converted too, with a warning on standard error: the addon sets it just before
its own reload, so a document without it was written some other way.

Exits 1, printing nothing to standard output, on a file that is not a saved-addon document.
"""

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


def main(arguments):
    if len(arguments) != 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    try:
        with open(arguments[1], encoding="utf-8") as saved:
            report = convert(saved.read())
    except (OSError, ValueError, ElementTree.ParseError) as error:
        print(f"report_xml: {arguments[1]}: {error}", file=sys.stderr)
        return 1
    if not (isinstance(report, dict) and report.get("bReported") is True):
        print("report_xml: the document has no bReported = true; it was not written by the addon's own reload", file=sys.stderr)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
