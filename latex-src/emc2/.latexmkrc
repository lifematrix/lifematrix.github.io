# .latexmkrc — project-level latexmk configuration
#
# Adds the shared classes directory to TEXINPUTS so pdflatex can find
# pensee.cls (and any future custom classes) regardless of whether the
# LaTeX app inherits the system TEXMFHOME setting.
#
# This file is read by latexmk, Texifier, TeXShop, LaTeX Workshop (VS Code /
# Cursor), and any other editor that uses latexmk as its build driver.

# ../../classes resolves to latex-src/classes/ relative to this project dir.
# The trailing // means "this directory and all subdirectories".
ensure_path('TEXINPUTS', '../../classes//');
