#!/usr/bin/env python3
"""
generate-abc-standard.py — Build a bundled, offline copy of the ABC 2.2 standard.

Reads a saved copy of the abcnotation.com wiki page for the ABC 2.2 standard
(the DokuWiki HTML plus its `_media/` directory) and writes a single,
self-contained HTML file to ScoreEdit/Resources/ABCStandard.html:

  * only the wiki page body is kept (site menus, search, footer buttons and
    scripts are dropped);
  * links within the standard become in-document fragment links, other wiki
    links become absolute abcnotation.com URLs;
  * the notation images are inlined as data: URIs, so no other files need
    to be bundled;
  * a small stylesheet with light and dark variants replaces the wiki CSS;
  * in-page links to headings that were renamed on the wiki are corrected
    (see RENAMED_FRAGMENTS);
  * the source and the CC BY-NC-SA 3.0 license notice are stated at the top.

ScoreEdit/Resources is a buildable folder, so the output is bundled
automatically.

Usage:
    scripts/generate-abc-standard.py [path/to/abc:standard:v2.2.html]
    mise run get_abc_standard

The default source is ~/tmp/abc/abc:standard:v2.2.html.
"""

import base64
import html
import mimetypes
import re
import sys
from datetime import date
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = Path.home() / "tmp" / "abc" / "abc:standard:v2.2.html"
OUTPUT_FILE = REPO_ROOT / "ScoreEdit" / "Resources" / "ABCStandard.html"

PAGE_NAME = "abc:standard:v2.2"
WIKI_BASE = "https://abcnotation.com/wiki/"
SOURCE_URL = WIKI_BASE + PAGE_NAME
LICENSE_NAME = "CC Attribution-Noncommercial-Share Alike 3.0 Unported"
LICENSE_URL = "https://creativecommons.org/licenses/by-nc-sa/3.0/"

# In-page links whose target heading was renamed on the wiki without the links
# being updated (broken on abcnotation.com too, as of 2026-09-26).
RENAMED_FRAGMENTS = {
    "generating_a_concert_pitch_score": "generating_a_concert_sounding_pitch_score",
    "clefs_and_transposition": "voice_modifiers_-_clefs_and_transposition",
}

STYLESHEET = """
:root {
  color-scheme: light dark;
  --text: #1d1d1f;
  --muted: #6e6e73;
  --background: #ffffff;
  --rule: #d2d2d7;
  --code-background: #f5f5f7;
  --table-header: #f0f0f3;
  --link: #0066cc;
}
@media (prefers-color-scheme: dark) {
  :root {
    --text: #f5f5f7;
    --muted: #a1a1a6;
    --background: #1e1e1e;
    --rule: #424245;
    --code-background: #2a2a2c;
    --table-header: #303033;
    --link: #4da3ff;
  }
}
html { background: var(--background); }
body {
  margin: 0 auto;
  padding: 16px 24px 48px;
  max-width: 60em;
  font: 14px/1.5 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
  color: var(--text);
  background: var(--background);
}
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
h1, h2, h3, h4, h5 { line-height: 1.25; margin: 1.6em 0 0.5em; scroll-margin-top: 12px; }
h1 { font-size: 1.8em; }
h2 { font-size: 1.45em; border-bottom: 1px solid var(--rule); padding-bottom: 0.2em; }
h3 { font-size: 1.2em; }
h4 { font-size: 1.05em; }
hr { border: none; border-top: 1px solid var(--rule); }
code, pre { font-family: "SF Mono", Menlo, monospace; font-size: 0.92em; }
code { background: var(--code-background); padding: 0.05em 0.3em; border-radius: 4px; }
pre {
  background: var(--code-background);
  padding: 10px 12px;
  border-radius: 6px;
  overflow-x: auto;
  white-space: pre;
}
table { border-collapse: collapse; margin: 0.8em 0; }
th, td { border: 1px solid var(--rule); padding: 4px 8px; vertical-align: top; text-align: left; }
th { background: var(--table-header); }
img.media { max-width: 100%; background: #ffffff; padding: 4px; border-radius: 4px; }
.provenance {
  font-size: 0.85em;
  color: var(--muted);
  border: 1px solid var(--rule);
  border-radius: 6px;
  padding: 8px 12px;
}
.dw__toc { border: 1px solid var(--rule); border-radius: 6px; padding: 4px 16px; margin: 1em 0; }
.dw__toc h3 { margin-top: 0.6em; }
ul.toc { list-style: none; padding-left: 1.2em; }
.dw__toc > div > ul.toc { padding-left: 0; }
"""


def extract_page_body(source: str) -> str:
    """Return the wiki page content between DokuWiki's start/stop markers."""
    match = re.search(
        r"<!-- wikipage start -->(.*?)<!-- wikipage stop -->", source, re.DOTALL
    )
    if not match:
        sys.exit("error: could not find the wiki page body in the source HTML")
    return match.group(1)


def rewrite_links(body: str) -> str:
    """Point in-page links at fragments and other wiki links at abcnotation.com."""
    page_link = re.escape(f"./{PAGE_NAME}.html")
    # "Back to top" links are href="./page.html#"
    body = re.sub(rf'href="{page_link}#"', 'href="#top"', body)
    body = re.sub(rf'href="{page_link}(#[^"]+)"', r'href="\1"', body)
    for old, new in RENAMED_FRAGMENTS.items():
        body = body.replace(f'href="#{old}"', f'href="#{new}"')
    body = re.sub(
        r'href="\./([^"#]+?)\.html(#[^"]*)?"',
        lambda m: f'href="{WIKI_BASE}{m.group(1)}{m.group(2) or ""}"',
        body,
    )
    return body


def inline_images(body: str, source_dir: Path) -> str:
    """Unwrap images from their wiki detail-page links and embed them as data: URIs."""
    body = re.sub(r'<a [^>]*class="media"[^>]*>(<img [^>]*/>)</a>', r"\1", body)

    def embed(match: re.Match) -> str:
        src = html.unescape(match.group(1))
        if src.startswith(("data:", "http:", "https:")):
            return match.group(0)
        path = source_dir / src
        if not path.is_file():
            sys.exit(f"error: image not found: {path}")
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        encoded = base64.b64encode(path.read_bytes()).decode("ascii")
        return f'src="data:{mime};base64,{encoded}"'

    return re.sub(r'src="([^"]+)"', embed, body)


def strip_wiki_noise(body: str) -> str:
    """Drop DokuWiki editing hooks and comments that have no meaning offline."""
    body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    body = re.sub(r'\s*class="sectionedit\d+"', "", body)
    body = re.sub(r"\s+sectionedit\d+", "", body)
    return body.strip()


def build_document(body: str) -> str:
    today = date.today().isoformat()
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The ABC Music Notation Standard 2.2</title>
<style>{STYLESHEET}</style>
</head>
<body id="top">
<p class="provenance">
This is an offline copy of <a href="{SOURCE_URL}">{SOURCE_URL}</a>,
reformatted for viewing within ScoreEdit (generated {today}).
The text and images are unchanged, except that {len(RENAMED_FRAGMENTS)}
cross references to renamed sections have been corrected. Except where otherwise noted, content on
the abc wiki is licensed under the
<a href="{LICENSE_URL}" rel="license">{LICENSE_NAME}</a> license.
</p>
{body}
</body>
</html>
"""


def main() -> None:
    source_path = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source_path.is_file():
        sys.exit(f"error: source not found: {source_path}")

    body = extract_page_body(source_path.read_text(encoding="utf-8"))
    body = rewrite_links(body)
    body = inline_images(body, source_path.parent)
    body = strip_wiki_noise(body)

    anchors = set(re.findall(r'\b(?:id|name)="([^"]+)"', body)) | {"top"}
    dangling = sorted(set(re.findall(r'href="#([^"]+)"', body)) - anchors)
    if dangling:
        print(f"warning: in-page links with no target: {', '.join(dangling)}", file=sys.stderr)

    OUTPUT_FILE.write_text(build_document(body), encoding="utf-8")
    print(f"Wrote {OUTPUT_FILE.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
