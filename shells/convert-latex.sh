#!/bin/bash
# =============================================================================
# convert-latex.sh
#
# Converts LaTeX blog posts (multi-file projects) to Hugo-compatible HTML
# using LaTeXML (latexml + latexmlpost).
#
# Expected source structure:
#   latex-src/                   ← batch source dir (overridable)
#       my-article/              ← one subfolder = one LaTeX project
#           my-article.tex       ← preferred entry point (folder name + .tex)
#           main.tex             ← fallback entry point (if <folder>.tex absent)
#           images/              ← images referenced in the document (optional)
#           sections/intro.tex   ← included files (optional)
#           refs.bib             ← bibliography (optional)
#           ...
#       another-article/
#           another-article.tex
#           ...
#
# Entry-point resolution (per project):
#   1. <folder-name>.tex  — checked first (e.g. my-article/my-article.tex)
#   2. main.tex           — fallback if the above does not exist
#   A warning is printed if both files are present; <folder-name>.tex wins.
#
# Workflow per project:
#   1. Wipes and recreates html_temp/ inside the project folder.
#      latexml / latexmlpost output their files there:
#        html_temp/<stem>.xml   ← LaTeXML intermediate XML
#        html_temp/<stem>.html  ← post-processed HTML5
#   2. Runs latexml  : LaTeX → LaTeXML XML
#   3. Runs latexmlpost : LaTeXML XML → HTML5 (with MathML)
#   4. Assembles Hugo front matter from two sources:
#        \title{}, \date{}, \author{} — extracted from the LaTeX preamble
#        draft:, tags:               — read from the comment block (see below)
#   4b. (--pdf only) Compiles PDF with XeLaTeX via latexmk; copies to static/pdf/
#       and adds pdf: "/pdf/<slug>.pdf" to the front matter.
#   5. Extracts <article class="ltx_document"> body; strips img dimensions
#   6. Ensures LaTeXML CSS files are in static/css/ (copied once)
#   7. Writes final HTML to content/posts/<slug>/index.html (Hugo leaf bundle)
#   8. Copies resource subdirectories (e.g. images/) into the leaf bundle
#
# Front matter sources:
#
#   LaTeX preamble (intrinsic document metadata — also typeset in the PDF):
#     \title{My Post Title}
#     \author{Steven Liu}       ← optional; omit or leave empty to use global author
#     \date{2026-05-22}
#
#   Comment block at the top of the .tex file (publishing metadata only):
#     % ---
#     % draft: false
#     % tags: ["math", "research"]
#     % ---
#
# Usage:
#   ./convert-latex.sh                        # batch on latex-src/ (default)
#   ./convert-latex.sh -b [DIR]               # batch: scan all subfolders of DIR
#   ./convert-latex.sh --batch [DIR]
#   ./convert-latex.sh -s <PROJECT_DIR>       # single: convert one LaTeX project folder
#   ./convert-latex.sh --single <PROJECT_DIR>
#   ./convert-latex.sh -p                     # also compile PDF with XeLaTeX
#   ./convert-latex.sh --pdf
# =============================================================================

# --- Output and static directories (relative to repo root) ---
OUT_DIR="content/posts"
STATIC_CSS_DIR="static/css"

# --- Custom class path (relative to repo root) ---
# latexml --path points here so it finds pensee.cls.ltxml (and any future
# custom class bindings) without requiring a system-wide TeX install.
CLASSES_DIR="latex/lib"

# --- LaTeXML CSS source (Homebrew install) ---
LATEXML_CSS_SRC="$(perl -MFile::ShareDir=dist_dir -e \
    'eval { print dist_dir("LaTeXML") } or print "/opt/homebrew/Cellar/latexml/0.8.8_4/libexec/lib/perl5/LaTeXML/resources"' \
    2>/dev/null)/CSS"
# Fallback: locate via latexml itself
if [[ ! -d "$LATEXML_CSS_SRC" ]]; then
    LATEXML_CSS_SRC="$(dirname "$(dirname "$(command -v latexml 2>/dev/null)")")/lib/perl5/LaTeXML/resources/CSS"
fi

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Usage ---
usage() {
    echo "Usage:"
    echo "  $(basename "$0")                        # batch on latex/pensee/ (default)"
    echo "  $(basename "$0") -b [DIR]               # batch: scan all subfolders of DIR"
    echo "  $(basename "$0") --batch [DIR]"
    echo "  $(basename "$0") -s <PROJECT_DIR>       # single: one LaTeX project folder"
    echo "  $(basename "$0") --single <PROJECT_DIR>"
}

# --- Argument parsing ---
MODE="batch"
TARGET=""
SKIP_FONT_UPDATE=0
PDF_FLAG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--single)
            MODE="single"
            shift
            ;;
        -b|--batch)
            MODE="batch"
            shift
            ;;
        -F|--skip-font-update)
            SKIP_FONT_UPDATE=1
            shift
            ;;
        -p|--pdf)
            PDF_FLAG=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error:${NC} Unknown option '$1'"
            usage
            exit 1
            ;;
        *)
            if [[ -n "$TARGET" ]]; then
                echo -e "${RED}Error:${NC} Unexpected argument '$1'"
                usage
                exit 1
            fi
            TARGET="$1"
            shift
            ;;
    esac
done

# --- Apply defaults and validate ---
if [[ "$MODE" == "single" ]]; then
    if [[ -z "$TARGET" ]]; then
        echo -e "${RED}Error:${NC} --single requires a project directory."
        usage
        exit 1
    fi
    if [[ ! -d "$TARGET" ]]; then
        echo -e "${RED}Error:${NC} Project directory '$TARGET' not found."
        exit 1
    fi
else
    TARGET="${TARGET:-latex/pensee}"
    if [[ ! -d "$TARGET" ]]; then
        echo -e "${RED}Error:${NC} Source directory '$TARGET' not found."
        exit 1
    fi
fi

# --- Python helper: extract article body and fix <img> attributes ---
#
# 1. Extracts <article class="ltx_document">...</article> — the self-contained
#    article content generated by latexmlpost, without the surrounding page
#    scaffolding (ltx_page_main, ltx_page_footer with the LaTeXML logo, etc.).
# 2. Strips height="..." / height='...' from ALL <img> tags — prevents
#    square-image distortion when CSS sets width but the height attribute
#    overrides the natural aspect ratio.
# 3. Strips width="..." / width='...' from <img> tags inside <figure> elements
#    — lets figures scale to full content width, matching \textwidth intent.
FIX_BODY_PY=$(mktemp /tmp/fix_body_XXXXXX.py)
PREPROCESS_TEX_PY=$(mktemp /tmp/preprocess_tex_XXXXXX.py)
trap 'rm -f "$FIX_BODY_PY" "$PREPROCESS_TEX_PY"' EXIT

cat > "$FIX_BODY_PY" << 'PYEOF'
import re, sys

def strip_attr(tag, attr):
    return re.sub(
        r'\s*' + attr + r'\s*=\s*(?:"[^"]*"|\'[^\']*\')',
        '', tag, flags=re.IGNORECASE)

html = sys.stdin.read()

# Step 1: extract <article class="ltx_document ...">...</article>
# Use \b word-boundary match on the class name so it works when LaTeXML
# adds extra classes alongside ltx_document (e.g. ltx_authors_1line).
m = re.search(
    r'<article\b[^>]*\bltx_document\b[^>]*>.*?</article>',
    html, flags=re.IGNORECASE | re.DOTALL)
if m:
    html = m.group(0)

# Step 2: strip the LaTeXML-generated title block.
# LaTeXML automatically renders \title{}, \author{}, and \date{} into the
# document even without \maketitle. In a Hugo blog these are redundant —
# PaperMod already displays the title and date from the YAML front matter.
# We remove the specific elements LaTeXML generates for them:
#   <h1 class="ltx_title ltx_title_document">...</h1>   ← from \title{}
#   <div class="ltx_authors">...</div>                   ← from \author{}
#   <div class="ltx_dates">...</div>                     ← from \date{}
for pattern in [
    r'<h1\b[^>]*\bltx_title_document\b[^>]*>.*?</h1>',
    r'<div\b[^>]*\bltx_authors\b[^>]*>.*?</div>',
    r'<div\b[^>]*\bltx_dates\b[^>]*>.*?</div>',
]:
    html = re.sub(pattern, '', html, flags=re.IGNORECASE | re.DOTALL)

# Step 3: strip height from all <img> tags
html = re.sub(
    r'<img\b[^>]*>',
    lambda m: strip_attr(m.group(0), 'height'),
    html, flags=re.IGNORECASE | re.DOTALL)

# Step 4: strip width from <img> tags inside <figure> elements
def fix_figure(m):
    return re.sub(
        r'<img\b[^>]*>',
        lambda m: strip_attr(m.group(0), 'width'),
        m.group(0), flags=re.IGNORECASE | re.DOTALL)

html = re.sub(
    r'<figure\b[^>]*>.*?</figure>',
    fix_figure,
    html, flags=re.IGNORECASE | re.DOTALL)

# Step 5: Collapse \makecell nested tables into <br>-separated lines.
#
# LaTeXML renders \makecell{line1 \\ line2} as a nested <table> with one
# <tr> per line.  Inside an outer <td> these nested inline-tables create
# phantom blank lines: the \n characters between <td> and <table> become
# anonymous inline boxes each ~22 px tall (line-height × font-size).
#
# Fix: replace each makecell table with its cell contents joined by <br>.
# We identify makecell tables by requiring that EVERY <td> carries the
# ltx_nopad_r class.  \makecell produces a single-column mini-table so all
# its cells have ltx_nopad_r.  The main table always has a mix — cells on
# inner columns lack it — so the check is never triggered on the outer table,
# even after its nested tables have been collapsed in an earlier pass (which
# would otherwise make it look like an "innermost" table too).
# An earlier weaker check ("ltx_nopad_r anywhere in the table") caused the
# outer table to be collapsed when @{} in the column spec added ltx_nopad_r
# to the edge-column cells.
#
# The regex matches *innermost* tables only (no nested <table> inside).
def _collapse_makecell(html_str):
    def _replacer(m):
        t = m.group(0)
        cell_attrs = re.findall(r'<td\b([^>]*)>', t, re.DOTALL)
        if not cell_attrs:
            return t
        if not all('ltx_nopad_r' in attrs for attrs in cell_attrs):
            return t          # not a single-column makecell table — leave untouched
        cells = re.findall(r'<td\b[^>]*>(.*?)</td>', t, re.DOTALL)
        return '<br>\n'.join(c.strip() for c in cells) if cells else t
    # Matches tables whose content contains no nested <table> tags.
    return re.sub(
        r'<table\b[^>]*>(?:(?!</?table\b).)*?</table>',
        _replacer, html_str, flags=re.DOTALL)

prev = None
while prev != html:
    prev = html
    html = _collapse_makecell(html)

sys.stdout.write(html)
PYEOF

# --- Python helper: pre-process .tex before feeding to LaTeXML ---
#
# Runs on a temp copy of each .tex file before latexml sees it.
# The original source is never modified.
# Add new steps here whenever LaTeXML silently drops or mishandles a
# LaTeX/XeLaTeX construct.
cat > "$PREPROCESS_TEX_PY" << 'PYEOF'
import re, sys

with open(sys.argv[1], encoding='utf-8') as f:
    tex = f.read()

# Step 1: Expand \symbol{"XXXX} to literal Unicode characters.
#
# XeLaTeX interprets \symbol{"XXXX} as "output the character at hex code
# point XXXX".  LaTeXML does not implement this command and silently drops
# it, leaving the surrounding text intact but missing the character.
# Replacing with chr(0xXXXX) before latexml runs ensures the character
# appears correctly in the HTML output.
tex = re.sub(
    r'\\symbol\{"([0-9A-Fa-f]{4,6})\}',
    lambda m: chr(int(m.group(1), 16)),
    tex)

# (Add future pre-processing steps here.)

with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(tex)
PYEOF

# --- Create output directories ---
mkdir -p "$OUT_DIR" "$STATIC_CSS_DIR"

# --- Font update check ---
# Calls update-fonts.sh to check npm for a newer Computer Modern version.
# On any network or download error it warns and continues — never fatal.
# Skip with -F / --skip-font-update for offline or CI use.
if [[ "$SKIP_FONT_UPDATE" -eq 0 ]]; then
    bash shells/update-fonts.sh --download
    echo ""
fi

# --- Step 0: Ensure LaTeXML CSS files are in static/css/ ---
#
# LaTeXML.css (core layout, math, tables) and ltx-article.css (section
# headings, abstract, equation numbering, etc.) must be served by Hugo for
# the article to render correctly.  They are copied once to static/css/ and
# referenced via /css/<file> URLs in every generated content file.
#
# These files rarely change (they come from the installed LaTeXML version),
# so we only copy when not already present.
CSS_COPIED=0
for cssfile in LaTeXML.css ltx-article.css; do
    if [[ ! -f "$STATIC_CSS_DIR/$cssfile" ]]; then
        if [[ -f "$LATEXML_CSS_SRC/$cssfile" ]]; then
            cp "$LATEXML_CSS_SRC/$cssfile" "$STATIC_CSS_DIR/$cssfile"
            echo -e "  ${GREEN}↳ CSS${NC}        : copied '$cssfile' to '$STATIC_CSS_DIR/'"
            (( CSS_COPIED++ )) || true
        else
            echo -e "  ${YELLOW}⚠ Warning${NC}   : '$cssfile' not found at '$LATEXML_CSS_SRC/'"
            echo -e "               LaTeXML CSS may not render correctly."
        fi
    fi
done

CONVERTED=0
FAILED=0

# =============================================================================
# convert_project <project_dir>
#
# Converts a single LaTeX project folder to a Hugo leaf bundle.
# Updates the global CONVERTED / FAILED counters.
# =============================================================================
convert_project() {
    local project_dir="$1"
    local slug
    slug=$(basename "$project_dir")

    echo -e "  ${CYAN}▶ Processing${NC} : $slug"

    # ------------------------------------------------------------------
    # Resolve entry point: <slug>.tex takes priority over main.tex.
    # Warn if both exist so the user knows one is being ignored.
    # ------------------------------------------------------------------
    local slug_tex="$project_dir/${slug}.tex"
    local fallback_tex="$project_dir/main.tex"
    local main_tex stem

    if [[ -f "$slug_tex" && -f "$fallback_tex" ]]; then
        echo -e "  ${YELLOW}⚠ Warning${NC}   : Both '${slug}.tex' and 'main.tex' found — using '${slug}.tex'"
        main_tex="$slug_tex"
    elif [[ -f "$slug_tex" ]]; then
        main_tex="$slug_tex"
    elif [[ -f "$fallback_tex" ]]; then
        main_tex="$fallback_tex"
    else
        echo -e "  ${RED}✘ Failed${NC}    : No '${slug}.tex' or 'main.tex' found in '$project_dir/'"
        (( FAILED++ )) || true
        echo ""
        return
    fi

    stem=$(basename "$main_tex" .tex)

    # ------------------------------------------------------------------
    # Step 1: Prepare html_temp/ — wipe and recreate for a clean run
    # ------------------------------------------------------------------
    local temp_dir="$project_dir/html_temp"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    # ------------------------------------------------------------------
    # Step 1.5: Pre-convert .bib files to .bib.xml
    #
    # latexmlpost resolves bibliographies from .bib.xml (preferred) or
    # raw .bib (experimental).  Pre-converting is reliable and fast.
    # Converted files are placed in html_temp/ alongside the XML output.
    # The resulting --bibliography=... flags are collected in bib_args[]
    # and passed to latexmlpost in Step 3.
    # ------------------------------------------------------------------
    local bib_args=()
    while IFS= read -r -d '' bibfile; do
        local bibname
        bibname=$(basename "$bibfile" .bib)
        echo -e "  ${CYAN}↳ Bib${NC}        : converting '${bibname}.bib' → '${bibname}.bib.xml'"
        if ( cd "$project_dir" && \
             latexml --dest="html_temp/${bibname}.bib.xml" \
                     "${bibname}.bib" 2>&1 ); then
            bib_args+=("--bibliography=html_temp/${bibname}.bib.xml")
        else
            echo -e "  ${YELLOW}⚠ Warning${NC}   : Failed to convert '${bibname}.bib' — bibliography may be empty"
        fi
    done < <(find "$project_dir" -maxdepth 1 -name "*.bib" -print0)

    # ------------------------------------------------------------------
    # Step 2: Run latexml — LaTeX source → LaTeXML XML
    #
    # Run from the project directory so that latexml resolves all
    # \input{}, \include{}, image paths, and .bib files relative to the
    # project root, exactly as pdflatex would.
    #
    # --path : adds latex-src/classes/ to latexml's search path so it
    #          finds pensee.cls.ltxml (and any future custom class bindings)
    #          without a system-wide TeX install.  The path is expressed
    #          relative to the project dir (where we cd before running).
    # ------------------------------------------------------------------
    local xml_out="$temp_dir/${stem}.xml"
    local classes_abspath
    classes_abspath="$(pwd)/$CLASSES_DIR"

    # ------------------------------------------------------------------
    # Step 2 (pre): Pre-process .tex before feeding to LaTeXML
    #
    # Applies the transformations defined in PREPROCESS_TEX_PY to a temp
    # copy of the source file.  latexml receives the temp copy; the
    # original .tex is never modified.
    # ------------------------------------------------------------------
    local preproc_tex
    preproc_tex=$(mktemp /tmp/latexml_XXXXXX.tex)
    python3 "$PREPROCESS_TEX_PY" "$project_dir/${stem}.tex" "$preproc_tex"

    if ! ( cd "$project_dir" && \
           latexml --path="$classes_abspath" \
                   --dest="html_temp/${stem}.xml" "$preproc_tex" 2>&1 ); then
        rm -f "$preproc_tex"
        echo -e "  ${RED}✘ Failed${NC}    : latexml error in '$slug'"
        (( FAILED++ )) || true
        echo ""
        return
    fi
    rm -f "$preproc_tex"

    # ------------------------------------------------------------------
    # Step 3: Run latexmlpost — LaTeXML XML → HTML5 with MathML
    #
    # --format=html5       : output HTML5 (default MathML for math)
    # --pmml               : Presentation MathML (default for html5, explicit)
    # --sourcedirectory    : tells latexmlpost where the original .tex lives
    #                        so it can resolve relative graphic paths correctly
    # --dest               : output HTML file path
    # --nodefaultresources : do not embed LaTeXML CSS/JS inline — we serve
    #                        them from static/css/ instead
    # --nopresentationmathml is NOT used — we want MathML output
    # --javascript         : not used — MathJax loaded via extend_head.html
    # ------------------------------------------------------------------
    local html_out="$temp_dir/${stem}.html"

    if ! ( cd "$project_dir" && \
           latexmlpost \
               --format=html5 \
               --pmml \
               --sourcedirectory="." \
               ${bib_args[@]+"${bib_args[@]}"} \
               --dest="html_temp/${stem}.html" \
               "html_temp/${stem}.xml" 2>&1 ); then
        echo -e "  ${RED}✘ Failed${NC}    : latexmlpost error in '$slug'"
        (( FAILED++ )) || true
        echo ""
        return
    fi

    if [[ ! -f "$html_out" ]]; then
        echo -e "  ${RED}✘ Failed${NC}    : Expected '$html_out' not found."
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 4: Assemble Hugo front matter from two sources
    #
    # Source A — LaTeX preamble (before \begin{document}):
    #   \title{...}   required
    #   \date{...}    required
    #   \author{...}  optional; omitted or empty → global author from hugo.toml
    #
    # Source B — comment block at the top of the .tex file:
    #   % ---
    #   % draft: true|false
    #   % tags: [...]
    #   % ---
    # ------------------------------------------------------------------

    # 4a: Extract draft and tags from comment block
    local cm_draft cm_tags
    cm_draft=$(awk '/^% ---/{c++; next} c==1 && /^% draft:/{sub(/^% /,""); print; exit} c==2{exit}' "$main_tex")
    cm_tags=$(awk  '/^% ---/{c++; next} c==1 && /^% tags:/ {sub(/^% /,""); print; exit} c==2{exit}' "$main_tex")

    if [[ -z "$cm_draft" ]]; then
        echo -e "  ${RED}✘ Failed${NC}    : No 'draft:' found in comment block of '${stem}.tex'. Skipping."
        (( FAILED++ )) || true
        echo ""
        return
    fi
    if [[ -z "$cm_tags" ]]; then
        echo -e "  ${RED}✘ Failed${NC}    : No 'tags:' found in comment block of '${stem}.tex'. Skipping."
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 4b (--pdf only): Compile PDF with XeLaTeX via latexmk
    #
    # Runs latexmk -xelatex in a temp dir so auxiliary files never land in
    # the source tree. On success the PDF is copied to static/pdf/<slug>.pdf
    # and pdf_url is set so it appears in the Hugo front matter.
    # On failure a warning is printed and HTML conversion continues normally.
    # ------------------------------------------------------------------
    local pdf_url=""
    if [[ "$PDF_FLAG" -eq 1 ]]; then
        local pdf_tmp
        pdf_tmp=$(mktemp -d /tmp/xelatex_XXXXXX)
        echo -e "  ${CYAN}↳ PDF${NC}        : compiling with XeLaTeX…"
        # Run latexmk from inside the project directory so that relative paths
        # (e.g. images/foo.jpg referenced in \includegraphics) resolve correctly.
        # $pdf_tmp is an absolute path so -outdir still works from any cwd.
        ( cd "$project_dir" && latexmk -xelatex -interaction=nonstopmode -halt-on-error \
            -outdir="$pdf_tmp" "${stem}.tex" ) \
            > "$pdf_tmp/latexmk.log" 2>&1
        if [[ $? -eq 0 ]] && [[ -f "$pdf_tmp/${stem}.pdf" ]]; then
            mkdir -p "static/pdf"
            cp "$pdf_tmp/${stem}.pdf" "static/pdf/${slug}.pdf"
            pdf_url="/pdf/${slug}.pdf"
            echo -e "  ${GREEN}↳ PDF${NC}        : static/pdf/${slug}.pdf"
        else
            echo -e "  ${YELLOW}⚠ Warning${NC}   : XeLaTeX failed — PDF skipped (see $pdf_tmp/latexmk.log)"
        fi
        # keep temp dir on failure for diagnosis; clean up on success
        [[ -n "$pdf_url" ]] && rm -rf "$pdf_tmp"
    fi

    # 4c: Extract \title, \date, \author from preamble; assemble full YAML
    local frontmatter
    frontmatter=$(python3 - "$main_tex" "$cm_draft" "$cm_tags" "$pdf_url" <<'PYEOF'
import re, sys

tex     = open(sys.argv[1]).read()
draft   = sys.argv[2]
tags    = sys.argv[3]
pdf_url = sys.argv[4] if len(sys.argv) > 4 else ''

# Restrict extraction to the preamble (before \begin{document})
m = re.match(r'(.*?)\\begin\{document\}', tex, re.DOTALL)
preamble = m.group(1) if m else tex

def extract(cmd):
    m = re.search(r'\\' + cmd + r'\{([^}]*)\}', preamble)
    return m.group(1).strip() if m else ''

def yaml_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

title  = extract('title')
date   = extract('date')
author = extract('author')

errors = []
if not title: errors.append('\\title{}')
if not date:  errors.append('\\date{}')
if errors:
    print('MISSING: ' + ', '.join(errors), file=sys.stderr)
    sys.exit(1)

lines = [
    'title: ' + yaml_str(title),
    'date: '  + date,
    draft,
    tags,
]
if author:
    lines.append('author: ' + yaml_str(author))
if pdf_url:
    lines.append('pdf: "' + pdf_url + '"')

print('\n'.join(lines))
PYEOF
)

    if [[ $? -ne 0 ]]; then
        echo -e "  ${RED}✘ Failed${NC}    : Missing required LaTeX command(s) in preamble of '${stem}.tex'. Skipping."
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 5: Extract article body and fix image attributes
    # See the FIX_BODY_PY comment block above for details.
    # ------------------------------------------------------------------
    local html_body
    html_body=$(python3 "$FIX_BODY_PY" < "$html_out")

    # ------------------------------------------------------------------
    # Step 6: Write Hugo leaf bundle
    #
    # Output layout:
    #   content/posts/<slug>/index.html   ← the article page
    #   content/posts/<slug>/<images>     ← source asset dirs (Step 8)
    #
    # The <link> tags reference LaTeXML CSS files served from /css/ by Hugo.
    # The <style> block contains PaperMod integration overrides:
    #   - ltx_figure img: responsive images (width controlled by article layout,
    #     height scales proportionally)
    #   - ltx_page_main padding is irrelevant (that div is not emitted since
    #     we extracted only the <article> — included for safety)
    # ------------------------------------------------------------------
    local dest_dir="$OUT_DIR/$slug"
    mkdir -p "$dest_dir"

    {
        echo "---"
        echo "$frontmatter"
        echo "---"
        echo '<link rel="stylesheet" href="/css/LaTeXML.css">'
        echo '<link rel="stylesheet" href="/css/ltx-article.css">'
        echo '<!-- CMU Serif: self-hosted, always current via current/ symlink -->'
        echo '<link rel="stylesheet" href="/fonts/npm/computer-modern/cmu-serif-current.css">'
        echo '<!-- pensee-latex.css: PaperMod integration overrides for LaTeXML output -->'
        echo '<link rel="stylesheet" href="/css/pensee-latex.css">'
        echo "$html_body"
    } > "$dest_dir/index.html"

    # ------------------------------------------------------------------
    # Step 7: Copy resource subdirectories into the Hugo leaf bundle
    #
    # Copies all subdirectories from the project folder (e.g. images/,
    # figures/) so that src="images/fig.jpg" in the HTML resolves correctly
    # when Hugo serves the leaf bundle at /<slug>/.
    # html_temp/ and tmp/ are excluded (build artifacts, not assets).
    # ------------------------------------------------------------------
    local dir_count=0
    while IFS= read -r -d '' subdir; do
        cp -r "$subdir" "$dest_dir/"
        (( dir_count++ )) || true
    done < <(find "$project_dir" -mindepth 1 -maxdepth 1 \
                  -type d -not -name "html_temp" -not -name "tmp" -print0)
    [[ $dir_count -gt 0 ]] && \
        echo -e "  ${GREEN}↳ Folders${NC}    : $dir_count resource folder(s) copied to '$dest_dir/'"

    echo -e "  ${GREEN}✔ Done${NC}      : $dest_dir/index.html"
    echo -e "  ${GREEN}↳ Temp dir${NC}   : $temp_dir/"
    (( CONVERTED++ )) || true
    echo ""
}

# =============================================================================
# Main dispatch
# =============================================================================

if [[ "$MODE" == "single" ]]; then

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD} convert-latex.sh — LaTeX → Hugo HTML (single)${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Project  : ${CYAN}$TARGET${NC}"
    echo -e "  Output   : ${CYAN}$OUT_DIR${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    convert_project "$TARGET"

else

    # --- Collect immediate subfolders ---
    subfolders=()
    while IFS= read -r -d '' dir; do
        subfolders+=("$dir")
    done < <(find "$TARGET" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ ${#subfolders[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No project subfolders found in '$TARGET'. Nothing to convert.${NC}"
        exit 0
    fi

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD} convert-latex.sh — LaTeX → Hugo HTML (batch)${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Source   : ${CYAN}$TARGET${NC}"
    echo -e "  Output   : ${CYAN}$OUT_DIR${NC}"
    echo -e "  Projects : ${CYAN}${#subfolders[@]}${NC} subfolder(s) found"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    SKIPPED=0
    for project_dir in "${subfolders[@]}"; do
        slug=$(basename "$project_dir")
        # Skip folders with no LaTeX entry point — e.g. latex-src/classes/
        if [[ ! -f "$project_dir/${slug}.tex" && ! -f "$project_dir/main.tex" ]]; then
            echo -e "  ${YELLOW}⊘ Skipped${NC}    : $slug (no ${slug}.tex or main.tex)"
            echo ""
            (( SKIPPED++ )) || true
            continue
        fi
        convert_project "$project_dir"
    done

fi

# --- Summary ---
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔ Converted : $CONVERTED project(s)${NC}"
[[ ${SKIPPED:-0} -gt 0 ]] && \
    echo -e "  ${YELLOW}⊘ Skipped   : $SKIPPED folder(s) (no entry-point .tex)${NC}"
[[ $FAILED -gt 0 ]] && \
    echo -e "  ${RED}✘ Failed    : $FAILED project(s)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
