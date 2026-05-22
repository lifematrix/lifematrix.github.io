#!/bin/bash
set -e

SRC_DIR="latex-src"
OUT_DIR="content/posts"
STATIC_DIR="static/css"

mkdir -p "$OUT_DIR" "$STATIC_DIR"

for texfile in "$SRC_DIR"/*.tex; do
    basename=$(basename "$texfile" .tex)
    echo "Converting $basename..."

    # Run make4ht (modern TeX4ht frontend)
    cd "$SRC_DIR"
    make4ht -f html5+tidy "$basename.tex" "fn-in,mathml"
    cd ..

    # Extract front matter from comment lines at top of .tex
    frontmatter=$(grep -E "^% " "$texfile" | \
                  grep -A 99 "^% ---" | \
                  grep -B 99 "^% ---" | \
                  sed 's/^% //' )

    # Strip <head> and inject Hugo front matter into the HTML body
    html_body=$(sed -n '/<body/,/<\/body>/p' "$SRC_DIR/$basename.html")

    # Write final Hugo-compatible HTML content file
    cat > "$OUT_DIR/$basename.html" << EOF
$frontmatter
$html_body
EOF

    # Copy TeX4ht CSS to static folder
    cp "$SRC_DIR"/*.css "$STATIC_DIR/" 2>/dev/null || true

    echo "Done: $OUT_DIR/$basename.html"
done
