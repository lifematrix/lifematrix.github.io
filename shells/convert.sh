#!/bin/bash
# =============================================================================
# convert.sh
#
# Converts LaTeX blog posts to Hugo-compatible HTML using make4ht (TeX4ht).
#
# Workflow:
#   1. Reads .tex files from latex-src/
#   2. Converts each to HTML via make4ht (MathML output, no tidy)
#   3. Extracts Hugo front matter from comment block at top of .tex
#   4. Writes final HTML to content/posts/
#   5. Copies TeX4ht CSS to static/css/
#
# Front matter format (in your .tex file):
#   % ---
#   % title: "My Post Title"
#   % date: 2026-05-22
#   % draft: false
#   % tags: ["math", "research"]
#   % ---
#
# Usage:
#   ./convert.sh
# =============================================================================

set -e

# --- Directories ---
SRC_DIR="latex-src"
OUT_DIR="content/posts"
STATIC_DIR="static/css"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Validate source directory ---
if [[ ! -d "$SRC_DIR" ]]; then
    echo -e "${RED}Error:${NC} Source directory '$SRC_DIR' not found."
    exit 1
fi

# --- Check for .tex files ---
shopt -s nullglob
texfiles=("$SRC_DIR"/*.tex)
shopt -u nullglob

if [[ ${#texfiles[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No .tex files found in '$SRC_DIR'. Nothing to convert.${NC}"
    exit 0
fi

# --- Create output directories ---
mkdir -p "$OUT_DIR" "$STATIC_DIR"

# --- Header ---
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} convert.sh — LaTeX → Hugo HTML${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Source : ${CYAN}$SRC_DIR${NC}"
echo -e "  Output : ${CYAN}$OUT_DIR${NC}"
echo -e "  CSS    : ${CYAN}$STATIC_DIR${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CONVERTED=0
FAILED=0

for texfile in "${texfiles[@]}"; do
    filename=$(basename "$texfile" .tex)
    echo -e "  ${CYAN}Converting${NC} $filename..."

    # ------------------------------------------------------------------
    # Step 1: Run make4ht
    # -f html5        — output format: HTML5
    # fn-in           — footnotes inline
    # mathml          — convert math to MathML (rendered by MathJax)
    # Note: +tidy is intentionally excluded — tidy does not understand
    #       MathML tags and would silently discard all math content.
    # ------------------------------------------------------------------
    if ! (cd "$SRC_DIR" && make4ht -f html5 "$filename.tex" "fn-in,mathml"); then
        echo -e "  ${RED}✘ Failed${NC} : make4ht error on $filename.tex"
        ((FAILED++))
        continue
    fi

    # ------------------------------------------------------------------
    # Step 2: Extract Hugo front matter from .tex comment block
    # Expects a block at the top of the .tex file:
    #   % ---
    #   % title: "..."
    #   % date: ...
    #   % ---
    # ------------------------------------------------------------------
    frontmatter=$(awk '
        /^% ---/ { found++; next }
        found == 1 && /^% / { sub(/^% /, ""); print }
        found == 2 { exit }
    ' "$texfile")

    if [[ -z "$frontmatter" ]]; then
        echo -e "  ${YELLOW}⚠ Warning${NC} : No front matter found in $filename.tex. Skipping."
        ((FAILED++))
        continue
    fi

    # ------------------------------------------------------------------
    # Step 3: Extract <body> content from make4ht output
    # ------------------------------------------------------------------
    html_output="$SRC_DIR/$filename.html"

    if [[ ! -f "$html_output" ]]; then
        echo -e "  ${RED}✘ Failed${NC} : Expected output $html_output not found."
        ((FAILED++))
        continue
    fi

    html_body=$(sed -n '/<body/,/<\/body>/p' "$html_output")

    # ------------------------------------------------------------------
    # Step 4: Write Hugo-compatible HTML content file
    # ------------------------------------------------------------------
    {
        echo "---"
        echo "$frontmatter"
        echo "---"
        echo "$html_body"
    } > "$OUT_DIR/$filename.html"

    # ------------------------------------------------------------------
    # Step 5: Copy TeX4ht CSS to static folder
    # ------------------------------------------------------------------
    css_files=("$SRC_DIR"/*.css)
    if [[ ${#css_files[@]} -gt 0 ]]; then
        cp "${css_files[@]}" "$STATIC_DIR/" 2>/dev/null || true
    fi

    echo -e "  ${GREEN}✔ Done${NC}    : $OUT_DIR/$filename.html"
    ((CONVERTED++))
done

# --- Summary ---
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔ Converted : $CONVERTED file(s)${NC}"
[[ $FAILED -gt 0 ]] && \
    echo -e "  ${RED}✘ Failed    : $FAILED file(s)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
