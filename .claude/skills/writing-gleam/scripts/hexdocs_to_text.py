"""Converts a Gleam package's hexdocs HTML pages to text, for the saved docs.

Run it once per package, from any directory, after downloading the package's
docs into the reference folder:

    R=~/Projects/reference/gleam-1.19
    P=glance-7.0.0
    mkdir -p $R/packages/$P
    curl -sfL https://repo.hex.pm/docs/$P.tar.gz | tar -xz -C $R/packages/$P
    chmod -R u+rwX,go+rX $R/packages/$P
    python3 -I hexdocs_to_text.py $R/packages/$P $R/text/packages/$P

Each HTML page becomes a Markdown file at the same relative path. Headings,
code blocks and inline code keep their Markdown form; navigation, scripts
and styles are dropped. It uses only the standard library.
"""

import pathlib
import sys
from html.parser import HTMLParser


class PageText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skipping = 0
        self.preformatted = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "nav", "svg"):
            self.skipping += 1
        elif tag in ("h1", "h2", "h3", "h4"):
            self.parts.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag == "pre":
            self.preformatted += 1
            self.parts.append("\n```\n")
        elif tag == "code" and not self.preformatted:
            self.parts.append("`")
        elif tag in ("p", "div", "li", "tr"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "nav", "svg"):
            self.skipping = max(0, self.skipping - 1)
        elif tag == "pre":
            self.preformatted -= 1
            self.parts.append("\n```\n")
        elif tag == "code" and not self.preformatted:
            self.parts.append("`")

    def handle_data(self, data):
        if self.skipping:
            return
        if self.preformatted:
            self.parts.append(data)
        else:
            trailing = " " if data.endswith((" ", "\n")) else ""
            self.parts.append(" ".join(data.split()) + trailing)


def convert(page: pathlib.Path) -> str:
    parser = PageText()
    parser.feed(page.read_text())
    text = "\n".join(line.rstrip() for line in "".join(parser.parts).split("\n"))
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text.strip() + "\n"


def main() -> None:
    source, target = map(pathlib.Path, sys.argv[1:3])
    for page in source.rglob("*.html"):
        out = target / page.relative_to(source).with_suffix(".md")
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(convert(page))


if __name__ == "__main__":
    main()
