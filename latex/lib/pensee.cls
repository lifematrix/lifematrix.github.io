% =============================================================================
% pensee.cls — Personal Essay Class
%
% Named after Pascal's Pensées (1670): unfinished reflections and fragments,
% written freely without the structure of a formal treatise. The spirit of
% the Chinese 随笔 (suíbǐ): casual, personal, exploratory writing.
%
% Designed for dual output:
%   pdflatex / xelatex → PDF (for personal archive and sharing)
%   latexml            → HTML (for Hugo blog publication)
%
% Usage:
%   \documentclass{pensee}
%
%   \title{My Reflection on Something}
%   \author{Your Name}
%   \date{2026-05-25}
%
% Blog publishing metadata (draft flag and tags) is read from a leading
% comment block by convert-latex.sh; title, date, and author are extracted
% from the LaTeX commands above:
%   % ---
%   % draft: false
%   % tags: ["math", "physics"]
%   % ---
% =============================================================================

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{pensee}[2026/05/25 v0.1 Pensee personal essay class]

% -----------------------------------------------------------------------------
% Base class
% -----------------------------------------------------------------------------
\LoadClass[12pt, a4paper]{article}

% -----------------------------------------------------------------------------
% Core packages — bundled so individual articles stay clean
% -----------------------------------------------------------------------------
\RequirePackage{amsmath}        % equation environments, \text{}, etc.
\RequirePackage{amssymb}        % \mathbb, \mathcal, extra symbols
\RequirePackage{amsthm}         % theorem / proof environments
\RequirePackage{graphicx}       % \includegraphics
\RequirePackage{float}          % [H] figure placement
\RequirePackage{xcolor}         % \textcolor, \colorbox
\RequirePackage{hyperref}       % clickable links and refs in PDF
\RequirePackage{geometry}       % page margins

% -----------------------------------------------------------------------------
% Page geometry — comfortable reading margins
% -----------------------------------------------------------------------------
\geometry{
    a4paper,
    top    = 2.5cm,
    bottom = 2.5cm,
    left   = 3.0cm,
    right  = 3.0cm
}

% -----------------------------------------------------------------------------
% Hyperref style — subtle blue links, no garish boxes
% -----------------------------------------------------------------------------
\hypersetup{
    colorlinks = true,
    linkcolor  = blue!70!black,
    urlcolor   = blue!70!black,
    citecolor  = blue!70!black
}

% -----------------------------------------------------------------------------
% Theorem-like environments
% -----------------------------------------------------------------------------
\theoremstyle{plain}
\newtheorem{theorem}{Theorem}[section]
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{proposition}[theorem]{Proposition}
\newtheorem{corollary}[theorem]{Corollary}

\theoremstyle{definition}
\newtheorem{definition}[theorem]{Definition}
\newtheorem{example}[theorem]{Example}
\newtheorem{remark}[theorem]{Remark}

%------------------------------------------------------------------------------
% some common formatting commands
%------------------------------------------------------------------------------

\newcommand{\textred}[1]{\textcolor{red}{#1}}
\newcommand{\textblue}[1]{\textcolor{blue}{#1}}
\newcommand{\textgreen}[1]{\textcolor{green}{#1}}
\newcommand{\blankline}[0]{\vskip \baselineskip}

% Colour used for \rubric headings — matches the HTML CSS value #622E7A.
\definecolor{penseeRubric}{HTML}{622E7A}

% Lightweight standalone essay heading — non-run-in, unnumbered, centred.
% Inspired by the rubric headings of medieval manuscripts: a brief title
% that names the section without imposing a formal hierarchy.
% Usage: \rubric{A quiet observation}
\newcommand{\rubric}[1]{%
    \vspace{0.6em}\par%
    {\centering\normalsize\bfseries\itshape\textcolor{penseeRubric}{#1}\par}%
    \vspace{0.2em}\noindent\ignorespaces
}
