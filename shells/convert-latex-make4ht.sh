#!/bin/bash
# =============================================================================
# convert-latex.sh
#
# Converts LaTeX blog posts (multi-file projects) to Hugo-compatible HTML
# using make4ht (TeX4ht).
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
#   1. Wipes and recreates html_temp/ inside the project folder, with two
#      subfolders:
#        html_temp/output/  ← final files: .html, .css, converted images
#        html_temp/build/   ← intermediate files: .aux, .log, .dvi, .4ct, ...
#      Resource subdirectories (e.g. images/) are mirrored into html_temp/build/
#      so that make4ht can resolve relative asset paths from the build dir.
#      make4ht's -d and -B options direct files to their respective folders,
#      keeping the source folder completely clean. \input{}, \include{},
#      images, and .bib files are resolved by the LaTeX engine from the
#      project folder (where main.tex lives), so multi-file projects work
#      exactly as they would with pdflatex.
#   2. Runs make4ht to produce HTML
#   3. Extracts Hugo front matter from a comment block at the top of main.tex
#   4. Writes final HTML to content/posts/<slug>/index.html (Hugo leaf bundle)
#   5. Copies generated images from html_temp/output/ into the leaf bundle
#
# Front matter format (at the top of main.tex):
#   % ---
#   % title: "My Post Title"
#   % date: 2026-05-22
#   % draft: false
#   % tags: ["math", "research"]
#   % ---
#
# Usage:
#   ./convert-latex.sh                        # batch on latex-src/ (default)
#   ./convert-latex.sh -b [DIR]               # batch: scan all subfolders of DIR
#   ./convert-latex.sh --batch [DIR]
#   ./convert-latex.sh -s <PROJECT_DIR>       # single: convert one LaTeX project folder
#   ./convert-latex.sh --single <PROJECT_DIR>
# =============================================================================

# --- Output directories (relative to repo root) ---
OUT_DIR="content/posts"

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
    echo "  $(basename "$0")                        # batch on latex-src/ (default)"
    echo "  $(basename "$0") -b [DIR]               # batch: scan all subfolders of DIR"
    echo "  $(basename "$0") --batch [DIR]"
    echo "  $(basename "$0") -s <PROJECT_DIR>       # single: one LaTeX project folder"
    echo "  $(basename "$0") --single <PROJECT_DIR>"
}

# --- Argument parsing ---
MODE="batch"
TARGET=""

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
    TARGET="${TARGET:-latex-src}"
    if [[ ! -d "$TARGET" ]]; then
        echo -e "${RED}Error:${NC} Source directory '$TARGET' not found."
        exit 1
    fi
fi

# --- Python helper: fix <img> attributes for web display ---
# Written to a temp file using a single-quoted heredoc so no escaping
# is needed. Reused for every project, removed on exit.
#
# Two fixes applied:
#   1. Strip height="..." / height='...' from ALL <img> tags — prevents the
#      square-image distortion that occurs when CSS scales by width but the
#      hardcoded height attribute overrides the natural aspect ratio.
#   2. Strip width="..." / width='...' from <img> tags inside <figure>
#      elements — lets figures scale to full content width, mirroring the
#      \includegraphics[width=\textwidth] intent from the LaTeX source.
FIX_IMG_PY=$(mktemp /tmp/fix_img_XXXXXX.py)
trap 'rm -f "$FIX_IMG_PY"' EXIT

cat > "$FIX_IMG_PY" << 'PYEOF'
import re, sys

def strip_attr(tag, attr):
    return re.sub(
        r'\s*' + attr + r'\s*=\s*(?:"[^"]*"|\'[^\']*\')',
        '', tag, flags=re.IGNORECASE)

html = sys.stdin.read()

# Fix 1: strip height from all <img> tags
html = re.sub(
    r'<img\b[^>]*>',
    lambda m: strip_attr(m.group(0), 'height'),
    html, flags=re.IGNORECASE | re.DOTALL)

# Fix 2: strip width from <img> tags inside <figure> elements
def fix_figure(m):
    return re.sub(
        r'<img\b[^>]*>',
        lambda m: strip_attr(m.group(0), 'width'),
        m.group(0), flags=re.IGNORECASE | re.DOTALL)

html = re.sub(
    r'<figure\b[^>]*>.*?</figure>',
    fix_figure,
    html, flags=re.IGNORECASE | re.DOTALL)

sys.stdout.write(html)
PYEOF

# --- Create output directories ---
mkdir -p "$OUT_DIR"

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
    # Step 1: Prepare the html_temp/ tree
    #
    # Wipe any previous run's artifacts first (avoids stale files from
    # an earlier version of the document being silently carried forward),
    # then create the two subfolders fresh:
    #
    #   html_temp/
    #       output/   ← make4ht -d  : .html, .css, converted images
    #       build/    ← make4ht -B  : .aux, .log, .dvi, .4ct, .lg, ...
    # ------------------------------------------------------------------
    local temp_dir="$project_dir/html_temp"
    local out_subdir="$temp_dir/output"
    local build_subdir="$temp_dir/build"

    rm -rf "$temp_dir"
    mkdir -p "$out_subdir" "$build_subdir"

    # ------------------------------------------------------------------
    # Step 1b: Mirror resource subdirectories into html_temp/build/
    #
    # make4ht's -B option redirects intermediate LaTeX output (.aux, .log,
    # .dvi, ...) to the build dir. However, when make4ht later copies
    # \includegraphics assets to the output dir, it constructs their paths
    # relative to the build dir rather than the project dir. This means a
    # reference like \includegraphics{images/fig.jpg} causes make4ht to
    # look for html_temp/build/images/fig.jpg — which doesn't exist.
    #
    # Fix: create a symlink in build/ for every subdirectory in the project
    # folder, so all relative asset paths resolve correctly from there.
    # Symlinks are used instead of copies — they are instant, use no extra
    # disk space, and always reflect the current state of the source files.
    # realpath produces absolute symlink targets, ensuring they resolve
    # correctly regardless of the current working directory.
    # ------------------------------------------------------------------
    while IFS= read -r -d '' subdir; do
        ln -s "$(realpath "$subdir")" "$build_subdir/"
    done < <(find "$project_dir" -mindepth 1 -maxdepth 1 \
                  -type d -not -name "html_temp" -print0)

    # ------------------------------------------------------------------
    # Step 2: Run make4ht from the project folder
    #
    # Running from the project folder (where main.tex lives) lets the
    # LaTeX engine resolve all \input{}, \include{}, images, and .bib
    # files naturally — exactly as pdflatex would.
    #
    # -d html_temp/output  — final output files go here
    # -B html_temp/build   — intermediate build files go here
    # -f html5             — output format: HTML5
    # fn-in                — render footnotes inline
    # mathml               — convert math to MathML (rendered by MathJax)
    #
    # Note: +tidy is intentionally excluded — tidy does not understand
    #       MathML and would silently strip all math content.
    # ------------------------------------------------------------------
    if ! ( cd "$project_dir" && \
           make4ht -f html5 \
                   -d html_temp/output \
                   -B html_temp/build \
                   "${stem}.tex" "fn-in,mathml" ); then
        echo -e "  ${RED}✘ Failed${NC}    : make4ht error in '$slug'"
        echo -e "             (see $build_subdir/${stem}.log)"
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 3: Extract Hugo front matter from main.tex comment block
    #
    # Looks for:
    #   % ---
    #   % title: "..."
    #   % date: ...
    #   % ---
    # ------------------------------------------------------------------
    local frontmatter
    frontmatter=$(awk '
        /^% ---/ { found++; next }
        found == 1 && /^% / { sub(/^% /, ""); print }
        found == 2 { exit }
    ' "$main_tex")

    if [[ -z "$frontmatter" ]]; then
        echo -e "  ${YELLOW}⚠ Warning${NC}   : No front matter found in '${stem}.tex'. Skipping."
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 4: Locate make4ht HTML output inside html_temp/output/
    # make4ht always names its output after the input file: <stem>.html
    # ------------------------------------------------------------------
    local html_output="$out_subdir/${stem}.html"

    if [[ ! -f "$html_output" ]]; then
        echo -e "  ${RED}✘ Failed${NC}    : Expected '$html_output' not found."
        (( FAILED++ )) || true
        echo ""
        return
    fi

    # ------------------------------------------------------------------
    # Step 5: Extract <body> content and fix image attributes
    # See the FIX_IMG_PY comment block above for details on both fixes.
    # ------------------------------------------------------------------
    local html_body
    html_body=$(sed -n '/<body/,/<\/body>/p' "$html_output" \
        | python3 "$FIX_IMG_PY")

    # ------------------------------------------------------------------
    # Step 6: Write Hugo leaf bundle
    #
    # Output layout:
    #   content/posts/<slug>/index.html   ← the article page
    #   content/posts/<slug>/<images>     ← generated images (Step 7)
    #
    # A Hugo leaf bundle keeps the article and all its assets together
    # in one directory, which Hugo serves under the URL /<slug>/.
    # ------------------------------------------------------------------
    local dest_dir="$OUT_DIR/$slug"
    mkdir -p "$dest_dir"

    # Inject CSS fixes for TeX4ht output:
    #   - equation tables span full width so the number reaches the right margin
    #   - figure images fill the content column (width stripped by FIX_IMG_PY)
    {
        echo "---"
        echo "$frontmatter"
        echo "---"
        echo '<style>'
        echo 'table.equation { width: 100%; }'
        echo 'table.equation td:first-child { width: 100%; text-align: center; }'
        echo 'td.eq-no { white-space: nowrap; padding-left: 1em; }'
        echo 'figure img { width: 100%; height: auto; }'
        echo 'math { font-size: 1.1em; }'
        echo 'math[display="block"] { display: block; overflow-x: auto; }'
        echo '</style>'
        echo "$html_body"
    } > "$dest_dir/index.html"

    # ------------------------------------------------------------------
    # Step 7: Copy image assets into the Hugo leaf bundle
    #
    # Two distinct sources need to be handled:
    #
    # 7a. Flat images generated by make4ht (e.g. formula images, figures
    #     converted from EPS/PDF). These land as flat files in out_subdir/
    #     and are referenced by name only in the HTML: src="main0x.png".
    #
    # 7b. Original source images referenced via subdirectory paths in the
    #     LaTeX source, e.g. \includegraphics{images/fig.jpg}. make4ht
    #     preserves these paths in the HTML (src="images/fig.jpg"), so the
    #     entire subdirectory must exist alongside index.html in the leaf
    #     bundle for Hugo to serve them correctly. Without this step the
    #     browser finds nothing at that path and renders the alt text only
    #     (TeX4ht's default alt text for images is "PIC").
    # ------------------------------------------------------------------

    # Step 7a: flat generated images from html_temp/output/
    local image_count=0
    for ext in png svg jpg jpeg gif; do
        for img in "$out_subdir"/*."$ext"; do
            if [[ -f "$img" ]]; then
                cp "$img" "$dest_dir/"
                (( image_count++ )) || true
            fi
        done
    done
    [[ $image_count -gt 0 ]] && \
        echo -e "  ${GREEN}↳ Images${NC}     : $image_count generated file(s) copied to '$dest_dir/'"

    # Step 7b: resource subdirectories from the project folder
    # (e.g. images/, figures/) — copied with their structure intact so
    # that src="images/fig.jpg" in the HTML resolves correctly under Hugo.
    local dir_count=0
    while IFS= read -r -d '' subdir; do
        cp -r "$subdir" "$dest_dir/"
        (( dir_count++ )) || true
    done < <(find "$project_dir" -mindepth 1 -maxdepth 1 \
                  -type d -not -name "html_temp" -not -name "tmp" -print0)
    [[ $dir_count -gt 0 ]] && \
        echo -e "  ${GREEN}↳ Folders${NC}    : $dir_count resource folder(s) copied to '$dest_dir/'"

    echo -e "  ${GREEN}✔ Done${NC}      : $dest_dir/index.html"
    echo -e "  ${GREEN}↳ Temp dir${NC}   : $temp_dir/{output,build}"
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

    for project_dir in "${subfolders[@]}"; do
        convert_project "$project_dir"
    done

fi

# --- Summary ---
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔ Converted : $CONVERTED project(s)${NC}"
[[ $FAILED -gt 0 ]] && \
    echo -e "  ${RED}✘ Failed    : $FAILED project(s)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
