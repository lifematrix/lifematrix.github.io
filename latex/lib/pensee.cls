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
%   \blogdate{2026-05-25}
%   \blogtags{math, physics, notes}
%
% Blog front matter (for Hugo) is still read from the leading comment block:
%   % ---
%   % title: "..."
%   % date: ...
%   % draft: false
%   % tags: [...]
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

% -----------------------------------------------------------------------------
% Blog metadata commands
%
% \blogdate{YYYY-MM-DD} : sets the document date (rendered in PDF title block)
% \blogtags{tag1, tag2} : purely metadata — silently ignored in PDF output;
%                         available for future script extraction or LaTeXML use
% -----------------------------------------------------------------------------
\newcommand{\blogdate}[1]{\date{#1}}
\newcommand{\blogtags}[1]{}     % no-op in PDF

%------------------------------------------------------------------------------
% some common formatting commands
%------------------------------------------------------------------------------

\newcommand{\textred}[1]{\textcolor{red}{#1}}
\newcommand{\textblue}[1]{\textcolor{blue}{#1}}
\newcommand{\textgreen}[1]{\textcolor{green}{#1}}
\newcommand{\blankline}[0]{\vskip \baselineskip}

% Lightweight standalone essay heading — non-run-in, unnumbered.
% Inspired by the rubric headings of medieval manuscripts: a brief title
% that names the section without imposing a formal hierarchy.
% Usage: \rubric{A quiet observation}
\newcommand{\rubric}[1]{%
    \vspace{0.6em}%
    {\noindent\normalsize\bfseries\itshape #1}%
    \vspace{0.2em}\par\noindent\ignorespaces
}
