#!/usr/bin/env python3
"""
Generate a branded Earthly PDF from a markdown file.

Usage:
    python3 build-pdf.py --input document.md --output document.pdf

Requires: pandoc, weasyprint (pip3 install weasyprint)
"""

import argparse
import base64
import pathlib
import re
import subprocess
import sys
import tempfile

SKILL_DIR = pathlib.Path(__file__).parent

CSS = """
@page {
  size: letter;
  margin: 1in 1in 1.2in 1in;
  @bottom-center {
    content: "Earthly Technologies · earthly.dev · Confidential";
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 9px;
    color: #89B0C7;
    padding-top: 12px;
  }
  @bottom-right {
    content: "— " counter(page) " of " counter(pages) " —";
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 9px;
    color: #aaa;
    padding-top: 12px;
  }
}
body {
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-size: 11px;
  line-height: 1.55;
  color: #1a1a1a;
}
.logo { margin-bottom: 32px; }
.logo img { height: 36px; }
h1 {
  font-size: 22px; font-weight: 700; color: #111;
  margin-top: 0; margin-bottom: 6px; border-bottom: none;
}
h1 + p { margin-top: 0; }
h2 {
  font-size: 15px; font-weight: 700; color: #111;
  margin-top: 28px; margin-bottom: 10px;
  padding-bottom: 4px; border-bottom: 1.5px solid #e0e0e0;
}
h3 {
  font-size: 12px; font-weight: 600; color: #333;
  margin-top: 18px; margin-bottom: 6px;
}
p, li { font-size: 11px; color: #2a2a2a; }
em { color: #555; font-size: 10px; }
strong { font-weight: 600; }
table {
  width: 100%; border-collapse: collapse;
  margin: 10px 0 16px 0; font-size: 10.5px;
}
th {
  background-color: #f5f7fa; font-weight: 600; text-align: left;
  padding: 7px 10px; border-bottom: 2px solid #dde1e6; color: #333;
}
td {
  padding: 6px 10px; border-bottom: 1px solid #eaecef; color: #2a2a2a;
}
tr:last-child td { border-bottom: 1.5px solid #dde1e6; }
tr:last-child td strong { color: #111; }
hr { border: none; border-top: 1px solid #e8e8e8; margin: 24px 0; }
ul { padding-left: 20px; }
li { margin-bottom: 4px; }
code {
  font-family: "SF Mono", Menlo, Monaco, monospace;
  font-size: 10px; background: #f5f7fa;
  padding: 1px 4px; border-radius: 3px;
}
"""


def build_logo_tag():
    svg_path = SKILL_DIR / "earthly-lunar-logo.svg"
    if not svg_path.exists():
        print(f"Warning: logo not found at {svg_path}, skipping logo", file=sys.stderr)
        return ""
    b64 = base64.b64encode(svg_path.read_bytes()).decode()
    return f'<div class="logo"><img src="data:image/svg+xml;base64,{b64}" /></div>'


def md_to_html(md_path):
    with tempfile.NamedTemporaryFile(suffix=".html", delete=False) as tmp:
        tmp_path = tmp.name
    subprocess.run(
        ["pandoc", str(md_path), "-f", "markdown", "-t", "html5",
         "--standalone", "--metadata", "title=", "-o", tmp_path],
        check=True,
    )
    html = pathlib.Path(tmp_path).read_text()
    pathlib.Path(tmp_path).unlink()
    return html


def extract_body(html):
    match = re.search(r"<body>(.*)</body>", html, re.DOTALL)
    body = match.group(1) if match else html
    body = body.replace(
        "<p>Earthly Technologies · earthly.dev · Confidential</p>", ""
    )
    return body


def build_pdf(md_path, out_path):
    body = extract_body(md_to_html(md_path))
    logo = build_logo_tag()

    full_html = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"/><style>{CSS}</style></head>
<body>
{logo}
{body}
</body>
</html>"""

    with tempfile.NamedTemporaryFile(suffix=".html", delete=False, mode="w") as tmp:
        tmp.write(full_html)
        tmp_path = tmp.name

    subprocess.run(["weasyprint", tmp_path, str(out_path)], check=True)
    pathlib.Path(tmp_path).unlink()
    print(f"PDF written to: {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate branded Earthly PDF from markdown")
    parser.add_argument("--input", required=True, help="Path to markdown file")
    parser.add_argument("--output", required=True, help="Path for output PDF")
    args = parser.parse_args()

    md_path = pathlib.Path(args.input)
    if not md_path.exists():
        print(f"Error: {md_path} not found", file=sys.stderr)
        sys.exit(1)

    build_pdf(md_path, pathlib.Path(args.output))
