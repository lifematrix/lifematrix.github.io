#!/bin/bash
# =============================================================================
# update-fonts.sh
#
# Manages self-hosted Computer Modern font versions.
# Checks the npm registry for newer versions and downloads them.
#
# Called automatically by convert-latex.sh, or run standalone.
#
# Usage:
#   bash shells/update-fonts.sh              # check only (read-only, no download)
#   bash shells/update-fonts.sh --download   # check + download + update if newer
#   bash shells/update-fonts.sh --list       # list all installed versions
#   bash shells/update-fonts.sh --prune VER  # delete a specific old version
#
# Design:
#   - Font files live in static/fonts/npm/computer-modern/<version>/
#   - "current" is a symlink pointing to the active version folder
#   - "cmu-serif-current.css" uses absolute paths via "current/" and never
#     needs to be regenerated when the version changes
#   - Old versions are NEVER deleted automatically — use --prune explicitly
#   - Any network or download error: warns and exits 0 (non-fatal)
# =============================================================================

# --- Paths (relative to repo root) ---
FONTS_ROOT="static/fonts/npm/computer-modern"
VERSION_FILE="$FONTS_ROOT/current.version"
CURRENT_LINK="$FONTS_ROOT/current"

# --- Remote sources ---
NPM_API="https://registry.npmjs.org/computer-modern/latest"
JSDELIVR_CDN="https://cdn.jsdelivr.net/npm/computer-modern"

# --- Known CMU Serif WOFF2 files (stable naming across versions) ---
WOFF2_FILES=(
    "fonts/cmu-serif-500-roman.woff2"
    "fonts/cmu-serif-500-italic.woff2"
    "fonts/cmu-serif-700-roman.woff2"
    "fonts/cmu-serif-700-italic.woff2"
)

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Argument parsing ---
MODE="check"
PRUNE_VER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download)
            MODE="download"; shift ;;
        --list)
            MODE="list"; shift ;;
        --prune)
            MODE="prune"
            PRUNE_VER="${2:-}"
            shift; [[ -n "$PRUNE_VER" ]] && shift ;;
        -h|--help)
            echo "Usage:"
            echo "  $(basename "$0")              # check only (read-only)"
            echo "  $(basename "$0") --download   # check + download + update"
            echo "  $(basename "$0") --list       # list installed versions"
            echo "  $(basename "$0") --prune VER  # delete a specific old version"
            exit 0 ;;
        *)
            echo -e "${RED}Error:${NC} Unknown option '$1'"
            exit 1 ;;
    esac
done

# --- Helpers ---

read_current() {
    [[ -f "$VERSION_FILE" ]] && tr -d '[:space:]' < "$VERSION_FILE" || echo ""
}

# Warn and exit 0 — non-fatal, convert-latex.sh continues with existing fonts
warn_continue() {
    echo -e "  ${YELLOW}⚠  Warning${NC} : $1"
    echo -e "  ${YELLOW}→  Continuing with existing fonts (v$(read_current)).${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
}

# =============================================================================
# MODE: list — show all installed versions
# =============================================================================
if [[ "$MODE" == "list" ]]; then
    current=$(read_current)
    echo -e "${BOLD}Installed Computer Modern versions:${NC}"
    found=0
    for dir in "$FONTS_ROOT"/*/; do
        ver=$(basename "$dir")
        # skip non-version entries (current symlink resolves to a dir too)
        [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        found=1
        if [[ "$ver" == "$current" ]]; then
            echo -e "  ${GREEN}✔ $ver${NC}  ← current"
        else
            echo -e "    $ver"
        fi
    done
    [[ $found -eq 0 ]] && echo "  (none)"
    exit 0
fi

# =============================================================================
# MODE: prune — delete a specific old version
# =============================================================================
if [[ "$MODE" == "prune" ]]; then
    if [[ -z "$PRUNE_VER" ]]; then
        echo -e "${RED}Error:${NC} --prune requires a version argument."
        echo -e "       Example: bash shells/update-fonts.sh --prune 0.1.2"
        exit 1
    fi
    current=$(read_current)
    if [[ "$PRUNE_VER" == "$current" ]]; then
        echo -e "${RED}Error:${NC} Cannot prune the active version ($current)."
        echo -e "       Upgrade first, then prune the old version."
        exit 1
    fi
    target="$FONTS_ROOT/$PRUNE_VER"
    if [[ ! -d "$target" ]]; then
        echo -e "${RED}Error:${NC} Version '$PRUNE_VER' not found at '$target'."
        exit 1
    fi
    rm -rf "$target"
    echo -e "${GREEN}✔ Pruned:${NC} $target"
    exit 0
fi

# =============================================================================
# MODE: check / update
# =============================================================================
current=$(read_current)

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} update-fonts.sh — Computer Modern${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Installed : ${CYAN}${current:-none}${NC}"

# Step 1: Query npm registry for latest version
latest=$(curl -sf --max-time 10 "$NPM_API" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" \
    2>/dev/null) || true

if [[ -z "$latest" ]]; then
    warn_continue "Cannot reach npm registry."
fi
echo -e "  Latest    : ${CYAN}$latest${NC}"

# Step 2: Compare versions
if [[ "$latest" == "$current" ]]; then
    echo -e "  ${GREEN}✔ Fonts are up to date.${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi

echo -e "  ${YELLOW}→  Update available:${NC} $current → $latest"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[[ "$MODE" == "check" ]] && exit 0   # check-only: stop here

echo ""
echo -e "${BOLD} Downloading v${latest}...${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CDN_BASE="$JSDELIVR_CDN@$latest"

# Step 3: Determine CSS filename — prefer .min.css, fall back to .css
css_src=""
for candidate in "cmu-serif.min.css" "cmu-serif.css"; do
    if curl -sf --max-time 10 --head "$CDN_BASE/$candidate" \
            -o /dev/null 2>/dev/null; then
        css_src="$candidate"
        break
    fi
done

if [[ -z "$css_src" ]]; then
    warn_continue "Cannot find CSS file for v$latest on jsDelivr."
fi
echo -e "  CSS source : ${CYAN}$css_src${NC} → saved as cmu-serif.css"

# Step 4: Download to temp directory
tmp_dir=$(mktemp -d /tmp/cmu-update-XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/fonts"

# Download CSS — normalize filename to cmu-serif.css regardless of source name
if ! curl -sf --max-time 30 -o "$tmp_dir/cmu-serif.css" \
        "$CDN_BASE/$css_src" 2>/dev/null; then
    warn_continue "Failed to download $css_src."
fi
[[ -s "$tmp_dir/cmu-serif.css" ]] || warn_continue "Downloaded CSS is empty."
echo -e "  ${GREEN}↳ CSS${NC}         : cmu-serif.css"

# Download WOFF2 files
for woff2 in "${WOFF2_FILES[@]}"; do
    fname=$(basename "$woff2")
    if ! curl -sf --max-time 30 \
            -o "$tmp_dir/$woff2" "$CDN_BASE/$woff2" 2>/dev/null; then
        warn_continue "Failed to download $fname."
    fi
    [[ -s "$tmp_dir/$woff2" ]] || warn_continue "Downloaded file '$fname' is empty."
    echo -e "  ${GREEN}↳ Font${NC}        : $fname"
done

# Step 5: Install — copy to versioned directory (old versions untouched)
new_dir="$FONTS_ROOT/$latest"
mkdir -p "$new_dir/fonts"
cp "$tmp_dir/cmu-serif.css"    "$new_dir/cmu-serif.css"
cp "$tmp_dir/fonts/"*.woff2    "$new_dir/fonts/"

echo ""

# Step 6: Update "current" symlink atomically
# -f: force (replace existing), -n: don't follow if target is a dir symlink
ln -sfn "$latest" "$CURRENT_LINK"
echo -e "  ${GREEN}✔ Symlink${NC}     : current → $latest"

# Step 7: Update version file
echo "$latest" > "$VERSION_FILE"
echo -e "  ${GREEN}✔ Version${NC}     : current.version = $latest"

# cmu-serif-current.css uses current/ paths — no update needed
echo -e "  ${GREEN}✔ CSS${NC}         : cmu-serif-current.css unchanged (paths use current/)"
echo -e "  ${CYAN}ℹ  Retained${NC}   : $FONTS_ROOT/$current/ (use --prune to remove)"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✔ Updated: $current → $latest${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${YELLOW}Note:${NC} Re-run convert-latex.sh to rebuild HTML with new fonts."
