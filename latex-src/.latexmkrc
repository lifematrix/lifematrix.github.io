# .latexmkrc — reference configuration for all latex-src projects
#
# NOTE: latexmk does NOT walk up the directory tree. This file is NOT
# read automatically. It serves as a canonical template — copy or
# symlink it into each project directory, or reference it explicitly
# with: latexmk -r ../latexmkrc
#
# For automatic use by GUI apps (Texifier, TeXShop, LaTeX Workshop),
# each project needs its own .latexmkrc. See emc2/.latexmkrc for the
# standard per-project version.

use File::Basename;

# Absolute path to latex-src/classes/, derived from this file's location.
# Using an absolute path makes it robust regardless of where latexmk is
# invoked from.
my $classes_dir = dirname(__FILE__) . '/classes';
ensure_path('TEXINPUTS', "$classes_dir//");
