"""Small static checks for the CyberWinDiagnostics GitHub Pages site."""

from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "docs"


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.local_files = []
        self.images_without_alt = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "img" and "alt" not in attrs:
            self.images_without_alt.append(attrs.get("src", "(unnamed image)"))
        if tag == "img" and attrs.get("src"):
            self.images.append(attrs["src"])
        for attribute in ("src", "href"):
            value = attrs.get(attribute, "")
            if value and not value.startswith(("https://", "http://", "#", "mailto:", "data:")):
                self.local_files.append(value.split("#", 1)[0].split("?", 1)[0])


def fail(message):
    print(f"FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


registry = json.loads((SITE / "data/themes.json").read_text(encoding="utf-8"))
families = registry["families"]
names = [name for family in families.values() for name in family]
if len(names) != 72 or len(set(names)) != 72:
    fail(f"expected 72 unique theme entries, found {len(names)}")
if set(names) != set(registry["themes"]):
    fail("theme family registry and palette registry do not contain the same names")
required_roles = {"bg", "white", "acid_green", "hot_pink", "purple", "cyan", "orange", "red", "panel", "line", "muted"}
for name, palette in registry["themes"].items():
    if set(palette) != required_roles:
        fail(f"{name} has a missing or unexpected color role")
    for role, color in palette.items():
        if not re.fullmatch(r"[0-9a-fA-F]{6}", color):
            fail(f"{name}.{role} is not a six-digit RGB hex value")

previews = list((SITE / "assets/previews").glob("*.svg"))
if len(previews) != 8:
    fail(f"expected 8 field-screen preview images, found {len(previews)}")

page = SiteParser()
page.feed((SITE / "index.html").read_text(encoding="utf-8"))
if page.images_without_alt:
    fail("images missing alt text: " + ", ".join(page.images_without_alt))
preview_refs = {Path(value).name for value in page.images if value.startswith("assets/previews/")}
if preview_refs != {item.name for item in previews}:
    fail("the eight field-screen previews are not all referenced from the page")
for asset in page.local_files:
    if not (SITE / asset).is_file():
        fail(f"referenced local site asset is missing: {asset}")
for anchor in re.findall(r'href="#([^"]+)"', (SITE / "index.html").read_text(encoding="utf-8")):
    if anchor not in page.ids:
        fail(f"in-page link has no matching target: #{anchor}")

source_html = (SITE / "index.html").read_text(encoding="utf-8")
legacy_html = source_html.replace('href="assets/', 'href="docs/assets/')
legacy_html = legacy_html.replace('src="assets/', 'src="docs/assets/')
legacy_html = legacy_html.replace('href="styles.css"', 'href="docs/styles.css"')
legacy_html = legacy_html.replace('src="app.js"', 'src="docs/app.js"')
if (ROOT / "index.html").read_text(encoding="utf-8") != legacy_html:
    fail("root Pages compatibility index is stale; regenerate it from docs/index.html")

print("PASS: 72 themes, 8 previews, accessible/local assets, and root Pages compatibility copy")
