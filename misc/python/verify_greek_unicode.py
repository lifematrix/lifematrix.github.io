"""
verify_greek_unicode.py
=======================
Verifies that the Unicode characters displayed in the "Letter" column of the
Greek letters table in complete_list_greek_letters_in_latex.tex match the
code points declared in the "Upper-case" and "Lower-case" columns via
\\symbol{"XXXX} (U+XXXX) notation.

Only rows where a column uses \\symbol{"XXXX} are checked — rows with
LaTeX-defined symbols (\\Gamma, \\Delta, etc.) are skipped.

Usage
-----
Run from the project root:

    python misc/python/verify_greek_unicode.py

Or pass a custom path to the .tex file:

    python misc/python/verify_greek_unicode.py path/to/file.tex

Expected output
---------------
A table showing each verified entry with ✓ (pass) or ✗ MISMATCH (fail),
followed by an overall summary line.
"""

import re
import sys

# ── Default file path (relative to project root) ───────────────────────────────
DEFAULT_TEX_FILE = (
    "latex/pensee/complete_list_greek_letters_in_latex/"
    "complete_list_greek_letters_in_latex.tex"
)


# ── Parsers ────────────────────────────────────────────────────────────────────

def extract_rows(text):
    """Split table body into rows by \\ at brace depth 0.

    \\ inside \\makecell{} is at depth > 0 and is correctly skipped.
    """
    rows, cur, depth, i = [], [], 0, 0
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1; cur.append(c)
        elif c == "}":
            depth -= 1; cur.append(c)
        elif c == "\\" and i + 1 < len(text) and text[i+1] == "\\" and depth == 0:
            row = "".join(cur).strip()
            if row:
                rows.append(row)
            cur = []; i += 2; continue
        else:
            cur.append(c)
        i += 1
    return rows


def split_cells(row):
    """Split a LaTeX table row into cells by & at brace depth 0."""
    cells, cur, depth = [], [], 0
    for c in row:
        if c == "{":
            depth += 1; cur.append(c)
        elif c == "}":
            depth -= 1; cur.append(c)
        elif c == "&" and depth == 0:
            cells.append("".join(cur).strip()); cur = []
        else:
            cur.append(c)
    if cur:
        cells.append("".join(cur).strip())
    return cells


def load_data_rows(tex_file):
    """Read the .tex file and return list of dicts with table row data."""
    with open(tex_file, encoding="utf-8") as f:
        content = f.read()

    m = re.search(
        r"\\begin\{tabular\}\{[^}]+\}(.*?)\\end\{tabular\}",
        content, re.DOTALL
    )
    assert m, "Could not find \\begin{tabular}...\\end{tabular}"
    table_body = m.group(1)

    # Remove \hline tokens — they sit between rows and pollute row parsing
    table_body_clean = re.sub(r"\\hline\b", "", table_body)

    data_rows = []
    for row in extract_rows(table_body_clean):
        row = row.strip()
        if re.match(r"^\d+\s*&", row):
            cells = split_cells(row)
            if len(cells) >= 5:
                data_rows.append({
                    "no":     cells[0].strip(),
                    "letter": cells[1].strip(),
                    "upper":  cells[2].strip(),
                    "lower":  cells[3].strip(),
                    "name":   cells[4].strip(),
                })
    return data_rows


# ── Helpers ────────────────────────────────────────────────────────────────────

def unicode_chars_in_cell(cell):
    """Non-whitespace chars after stripping $...$ math and invisible commands."""
    plain = re.sub(r"\$[^$]*\$", "", cell)
    plain = re.sub(r"\\null\b", "", plain).strip()
    return [c for c in plain if not c.isspace()]


def parse_symbol_hex(cell):
    """Return uppercase hex string from \\symbol{\"XXXX}, or None."""
    m = re.search(r'\\symbol\{"([0-9A-Fa-f]+)\}', cell)
    return m.group(1).upper() if m else None


# ── Main verification ──────────────────────────────────────────────────────────

def verify(tex_file):
    data_rows = load_data_rows(tex_file)
    print(f"Parsed {len(data_rows)} data rows.\n")

    HDR = (
        f"{'No':<4} {'Row No of Table':<16} {'Name':<10} "
        f"{'Col':<8} {'Char':>6}  {'Letter U+':<12} {'symbol U+':<12} {'Match'}"
    )
    SEP = "─" * len(HDR)
    print(HDR)
    print(SEP)

    all_pass = True
    idx = 0

    for row in data_rows:
        no, letter, upper, lower, name = (
            row["no"], row["letter"], row["upper"], row["lower"], row["name"]
        )
        letter_chars = unicode_chars_in_cell(letter)

        # Check Upper-case column
        upper_hex = parse_symbol_hex(upper)
        if upper_hex:
            idx += 1
            char = letter_chars[0] if letter_chars else None
            if char is None:
                print(f"{idx:<4} {no:<16} {name:<10} {'UPPER':<8} {'?':>6}  {'?':<12} {upper_hex:<12} ✗ no char")
                all_pass = False
            else:
                actual = f"{ord(char):04X}"
                ok = actual == upper_hex
                all_pass = all_pass and ok
                mark = "✓" if ok else "✗ MISMATCH"
                print(f"{idx:<4} {no:<16} {name:<10} {'UPPER':<8} {repr(char):>6}  {actual:<12} {upper_hex:<12} {mark}")

        # Check Lower-case column (only Omicron has \\symbol here)
        lower_hex = parse_symbol_hex(lower)
        if lower_hex:
            idx += 1
            # Omicron Letter cell is "Ο ο" — second char is lowercase
            char = letter_chars[1] if len(letter_chars) >= 2 else None
            if char is None:
                print(f"{idx:<4} {no:<16} {name:<10} {'LOWER':<8} {'?':>6}  {'?':<12} {lower_hex:<12} ✗ no char")
                all_pass = False
            else:
                actual = f"{ord(char):04X}"
                ok = actual == lower_hex
                all_pass = all_pass and ok
                mark = "✓" if ok else "✗ MISMATCH"
                print(f"{idx:<4} {no:<16} {name:<10} {'LOWER':<8} {repr(char):>6}  {actual:<12} {lower_hex:<12} {mark}")

    print(SEP)
    print(
        "\n✓ All Unicode values verified correctly!" if all_pass
        else "\n✗ Some mismatches found — check rows marked ✗"
    )
    return all_pass


if __name__ == "__main__":
    tex_file = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_TEX_FILE
    success = verify(tex_file)
    sys.exit(0 if success else 1)
