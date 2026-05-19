---
name: branded-pdf
description: Generate branded Earthly PDF documents from markdown. Use when creating customer-facing documents, proposals, cost analyses, executive summaries, or any document that needs to be exported as a branded PDF with the Earthly Lunar logo.
---

# Branded PDF Generation

Generate professional, branded Earthly PDF documents from markdown content.

## When to Use

Use this skill when the user asks to:
- Create a customer-facing document or proposal
- Export markdown to PDF with Earthly branding
- Generate a branded report, analysis, or summary

## Prerequisites

The build script requires `pandoc` and `weasyprint`. Install if missing:

```bash
brew install pandoc
pip3 install weasyprint
```

## How to Generate a PDF

### 1. Write the markdown document

Write the document content as a standard markdown file. Use the conventions below for consistent results.

**Document conventions:**
- End the document with `Earthly Technologies · earthly.dev · Confidential` — the build script strips this from the body and renders it as a page footer instead
- Use `---` horizontal rules between major sections
- Use standard markdown tables (they render with clean styling)
- Use `**bold**` for emphasis and `*italics*` for disclaimers or caveats
- Keep the tone professional and concise — these go to customers and prospects

**Example front matter pattern:**

```markdown
# Document Title

**Scenario**: Brief description of the context.

*Disclaimer or caveat about the document.*

---

## Summary

Body content here...

---

Earthly Technologies · earthly.dev · Confidential
```

### 2. Run the build script

```bash
python3 /path/to/earthly-agent-config/skills/branded-pdf/build-pdf.py \
  --input /path/to/document.md \
  --output /path/to/output.pdf
```

The script:
1. Converts markdown to HTML via pandoc
2. Injects the Earthly Lunar logo (dark-background compatible version bundled with this skill)
3. Applies branded CSS styling
4. Renders to PDF via weasyprint with page numbers and footer

### 3. Verify the output

Open the PDF and check:
- Logo renders correctly at the top of page 1
- Tables are readable and not clipped
- Page breaks fall in reasonable places
- Footer appears on every page

## Styling Details

The template produces:
- **Logo**: Earthly Lunar logo (colorful glyph + dark "EARTHLY" + blue "LUNAR" text) at top of page 1
- **Footer**: "Earthly Technologies · earthly.dev · Confidential" centered on every page
- **Page numbers**: "— 1 of N —" in the bottom-right corner
- **Typography**: Helvetica Neue / system sans-serif, 11px body, 22px h1, 15px h2
- **Tables**: Light header row (#f5f7fa), subtle borders, compact padding
- **Page size**: US Letter with 1-inch margins

## Customization

To adjust styling, edit the `CSS` string in `build-pdf.py`. Key variables:
- Font sizes: search for `font-size`
- Colors: search for `#` hex values
- Margins: in the `@page` rule
- Logo size: `.logo img { height: 36px; }`

## Files in This Skill

| File | Purpose |
|------|---------|
| `SKILL.md` | This guide |
| `build-pdf.py` | Build script (markdown → PDF) |
| `earthly-lunar-logo.svg` | Logo with dark text (for white backgrounds) |
