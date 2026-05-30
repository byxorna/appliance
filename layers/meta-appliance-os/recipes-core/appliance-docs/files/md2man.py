#!/usr/bin/env python3
"""Convert a subset of Markdown to troff (manpage) format.

Handles: headings, paragraphs, fenced code blocks, bullet/numbered lists,
tables, inline code, bold, italic, links, blockquotes, horizontal rules.

No external dependencies — stdlib only.
"""

import re
import sys
from datetime import date


def escape_troff(text):
    """Escape characters special to troff."""
    text = text.replace("\\", "\\(rs")
    text = text.replace(".", "\\&.")
    text = text.replace("'", "\\(aq")
    text = text.replace("-", "\\-")
    return text


def process_inline(text):
    """Convert inline Markdown formatting to troff."""
    # Links: [text](url) -> text <url>
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 <\2>", text)

    # Bold+italic: ***text*** or ___text___
    text = re.sub(r"\*{3}(.+?)\*{3}", r"\\fBI\1\\fR", text)

    # Bold: **text** or __text__
    text = re.sub(r"\*{2}(.+?)\*{2}", r"\\fB\1\\fR", text)
    text = re.sub(r"__(.+?)__", r"\\fB\1\\fR", text)

    # Italic: *text* or _text_ (but not mid_word_underscores)
    text = re.sub(r"(?<!\w)\*([^*]+?)\*(?!\w)", r"\\fI\1\\fR", text)

    # Inline code: `text` -> \fB text \fR
    text = re.sub(r"`([^`]+)`", r"\\fB\1\\fR", text)

    return text


def format_table(rows):
    """Format a Markdown table as plain-text columns."""
    if not rows:
        return []

    # Parse cells
    parsed = []
    for row in rows:
        cells = [c.strip() for c in row.strip("|").split("|")]
        parsed.append(cells)

    # Skip separator row (second row with ---)
    if len(parsed) > 1 and all(re.match(r"^[\s:|-]+$", c) for c in parsed[1]):
        header = parsed[0]
        data = parsed[2:]
    else:
        header = None
        data = parsed

    # Compute column widths
    all_rows = ([header] if header else []) + data
    ncols = max(len(r) for r in all_rows)
    widths = [0] * ncols
    for r in all_rows:
        for i, c in enumerate(r):
            if i < ncols:
                widths[i] = max(widths[i], len(c))

    def fmt_row(cells):
        parts = []
        for i in range(ncols):
            val = cells[i] if i < len(cells) else ""
            parts.append(val.ljust(widths[i]))
        return "  ".join(parts)

    lines = [".nf"]
    if header:
        lines.append(process_inline(fmt_row(header)))
        lines.append("  ".join(["-" * w for w in widths]))
    for r in data:
        lines.append(process_inline(fmt_row(r)))
    lines.append(".fi")
    return lines


def convert(markdown, title, section="7", source="Appliance OS"):
    """Convert Markdown string to troff manpage string."""
    lines = markdown.split("\n")
    out = []

    # Header
    today = date.today().strftime("%Y-%m-%d")
    out.append(f'.TH "{title.upper()}" "{section}" "{today}" "{source}"')

    # NAME section — required by mandb for whatis/apropos indexing.
    # Use the first heading's text as the short description.
    first_heading = title
    for raw_line in lines:
        hm = re.match(r"^#{1,2}\s+(.*)", raw_line.strip())
        if hm:
            first_heading = hm.group(1).strip()
            break
    out.append(".SH NAME")
    out.append(f"{title} \\- {first_heading}")

    i = 0
    in_code = False
    in_list = False
    table_buf = []
    paragraph_buf = []

    def flush_paragraph():
        nonlocal paragraph_buf
        if paragraph_buf:
            text = " ".join(paragraph_buf)
            out.append(process_inline(text))
            paragraph_buf = []

    def flush_table():
        nonlocal table_buf
        if table_buf:
            flush_paragraph()
            out.extend(format_table(table_buf))
            table_buf = []

    while i < len(lines):
        line = lines[i]

        # Fenced code block
        if line.strip().startswith("```"):
            if in_code:
                out.append(".fi")
                in_code = False
            else:
                flush_paragraph()
                flush_table()
                if in_list:
                    in_list = False
                out.append(".PP")
                out.append(".nf")
                in_code = True
            i += 1
            continue

        if in_code:
            out.append(escape_troff(line))
            i += 1
            continue

        stripped = line.strip()

        # Blank line
        if not stripped:
            flush_paragraph()
            flush_table()
            if in_list:
                in_list = False
            i += 1
            continue

        # Table row
        if "|" in stripped and stripped.startswith("|"):
            flush_paragraph()
            table_buf.append(stripped)
            i += 1
            continue
        else:
            flush_table()

        # Horizontal rule
        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            flush_paragraph()
            i += 1
            continue

        # Headings
        m = re.match(r"^(#{1,6})\s+(.*)", stripped)
        if m:
            flush_paragraph()
            level = len(m.group(1))
            heading_text = m.group(2).strip()
            if level <= 2:
                out.append(f'.SH "{process_inline(heading_text.upper())}"')
            else:
                out.append(f".SS {process_inline(heading_text)}")
            in_list = False
            i += 1
            continue

        # Blockquote
        if stripped.startswith(">"):
            flush_paragraph()
            quote_text = stripped.lstrip("> ").strip()
            out.append(".RS 4")
            out.append(process_inline(quote_text))
            out.append(".RE")
            i += 1
            continue

        # Numbered list item
        m = re.match(r"^(\d+)[.)]\s+(.*)", stripped)
        if m:
            flush_paragraph()
            text = m.group(2)
            out.append(f".IP {m.group(1)}. 4")
            out.append(process_inline(text))
            in_list = True
            i += 1
            continue

        # Bullet list item
        m = re.match(r"^[-*+]\s+(.*)", stripped)
        if m:
            flush_paragraph()
            text = m.group(1)
            out.append(".IP \\(bu 2")
            out.append(process_inline(text))
            in_list = True
            i += 1
            continue

        # Regular text — accumulate into paragraph
        if in_list and not line.startswith(" "):
            in_list = False

        if not paragraph_buf:
            out.append(".PP")
        paragraph_buf.append(stripped)
        i += 1

    flush_paragraph()
    flush_table()

    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.md> <manpage-name> [section]",
              file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    manpage_name = sys.argv[2]
    section = sys.argv[3] if len(sys.argv) > 3 else "7"

    with open(input_file, "r") as f:
        md = f.read()

    result = convert(md, manpage_name, section)
    sys.stdout.write(result)


if __name__ == "__main__":
    main()
