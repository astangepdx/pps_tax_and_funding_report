# docgen — markdown to PDF specifications

docgen builds a multi-section technical specification from markdown source files kept under revision control. It produces a PDF with a cover page, a table of contents, a list of tables and a list of figures (each only when the document has some), auto-numbered sections, headers and footers with page numbers and the confidentiality notice, figures rendered from Mermaid and WaveDrom sources, and a version-history page at the end. Alongside the PDF it writes the whole document as one markdown file for other consumers such as DV.

The pipeline is pandoc → XeLaTeX. Everything in this directory is shared; each document lives in its own directory (for example `dig/design/chip/doc/`) with a three-line Makefile.

## 1. Tools

docgen needs the five tools in Table 1-1 on `PATH` (each overridable: `PANDOC`, `XELATEX`, `MMDC`, `WAVEDROM`, `RSVG_CONVERT`, `PYTHON`), and the build stops with a message naming any that is missing. `ENVIRONMENT.md` in the project root tracks the install status of these tools in each environment (WSL container, cloud chamber). On macOS, follow `SETUP_MACOS.md` in the repository root instead; it wins over this section on tool setup.

| Tool | Used for | Container version |
|---|---|---|
| `pandoc` ≥ 3.1 | markdown → LaTeX, Lua filters | 3.11 |
| `xelatex` | PDF engine | TeX Live 2018 |
| `mmdc` (mermaid-cli) | Mermaid → PDF, through Chromium | 11.x + puppeteer 24 |
| `wavedrom-cli` | WaveDrom → SVG | 3.x |
| `rsvg-convert` | SVG → PDF | librsvg 2.42 |

*Table 1-1: docgen tools.*

### 1.1 Dev container (WSL)

Installed by the `Dockerfile` (`bash env/dev.sh build` after a change; `bash env/dev.sh smoke` checks them). Chromium comes from EPEL and `puppeteer-config.json` points `mmdc` at it with `--no-sandbox`, which is required inside Docker.

### 1.2 Cadence-cloud chamber (RedHat, no root)

Tool setup is the team `docgen` module; `ENVIRONMENT.md` section 3.3 tracks tool status and holds the modulefile notes. `make` works from any chamber shell with the module loaded (outside an SGE job it re-submits itself to `interactive.q` via `qrsh -V -cwd`):

```tcsh
module use /proj/atc1a/setup/modulefiles
module load docgen
```

The module puts grid TeX Live 2025 on `PATH`, loads the Cadence-installed `pandoc/3.12`, `mermaid/12.0.0` and `wavedrom/3.2.0` modules, and sets `MMDC_PDF_FLAGS`/`MMDC_PUPPETEER_CONFIG` for mermaid-cli 12 and its own browser cache. Fonts: DejaVu is present; otherwise set `mainfont`/`sansfont`/`monofont` in `metadata.yaml` to a font `fc-list` shows (the default Cantarell ships with most Linux desktops; `abattis-cantarell-fonts` on RHEL).

## 2. Building a document

Run inside the dev container (WSL) or on a host with the tools installed (section 1):

```bash
cd dig/design/chip/doc
make            # out/chip_spec.pdf and out/chip_spec.md
make md         # out/chip_spec.md only
make tex        # out/chip_spec.tex, for LaTeX debugging
make versions   # print tool versions
make clean      # remove out/
```

From the WSL host shell, using the container pattern from `ENVIRONMENT.md`:

```bash
script -qec "bash env/dev.sh shell" /dev/null <<'END'
cd /workspace/dig/design/chip/doc && make
END
```

The build first writes `out/<DOC>.md`: every section file with its preamble removed, joined verbatim in `SECTIONS` order. It has no cover page, table of contents, version history or section numbers, and nothing in it is reformatted, so tables, diagram fences, footnotes and `[Table](#KEY)` references stay exactly as written; refer to things by their keys, not numbers. Its first line is the confidentiality notice (`NOTICE`, default `Public`), exactly as in the section files, followed by a comment naming the title, revision and source files; both are stripped again before the PDF is built. The comment also notes and relative paths in it (`img/…`, `wavedrom/…`) are relative to the document directory. pandoc then turns that file into `out/<DOC>.tex`, and docgen runs `xelatex` until LaTeX stops asking for a rerun, because table column widths and the TOC need more passes than pandoc's own PDF step makes. The build prints the number of overfull lines (text or a table wider than its column) when there are any; the details are in `out/<DOC>.log`.

Everything generated lands in the document's `out/` directory, which is gitignored (`dig/.gitignore` covers `design/*/doc/out/`).

## 3. Document layout

```
dig/design/<block>/doc/
  Makefile        DOC, SECTIONS, include ../../../../tools/docgen/docgen.mk
  metadata.yaml   title, revision, date, author, header/footer text, options
  history.md      version-history table
  *.md            section files, any names; order comes from SECTIONS
  img/            images referenced from the sections (png, pdf, svg)
  wavedrom/       WaveDrom JSON sources referenced from wavedrom fences
  out/            generated
```

Minimal `Makefile`:

```make
DOC      := chip_spec
SECTIONS := overview.md architecture.md
include ../../../../tools/docgen/docgen.mk
```

`SECTIONS` is the document order. Variables that can be set before the `include` or on the `make` command line: `OUT`, `METADATA`, `HISTORY`, `TOC_DEPTH` (default 3), `DOC_DEPS` (extra files that trigger a rebuild; default `img/*` and `wavedrom/*`), `STRIP_HEADING_NUMBERS=1` (drop leading "1." / "1.2" from headings in legacy sources), `PANDOC_EXTRA`, and the tool names in section 1.

## 4. Writing sections

- **Preamble is ignored.** Everything in a section file (and in `history.md`) above its first level-1 heading (`# Title`) is dropped: use it for editor notes, to-dos and comments to co-authors. A file with no level-1 heading fails the build.
- **Start every file with `Public`** on its own line, before any editor notes. It is dropped with the rest of the preamble, so the PDF is unaffected, and a section rendered or read on its own still carries the notice.
- **Several sections per file are fine.** Every `#` heading starts a new numbered section, in file order.
- **Do not number headings.** `#` → 1, `##` → 1.1, `###` → 1.1.1 are generated. Every `#` section starts on a new page while `section-newpage` is true (the default).
- **Manual page break:** a horizontal rule (a line containing only `---`). A raw `\newpage` line also works.
- **Tables:** pipe tables, with a caption line `Table: Top-level blocks.` after the table. Captions are numbered `Table 2-1` (section-major), render in bold above the table, and need no `**` in the source. Every table is drawn as a full grid (all cell borders). A table that fits on one page is kept on one page: if it would not fit in the space left, the page ends early and the table starts on the next one, together with a heading directly above it (body text above a table stays where it is). A figure directly below a heading is kept with that heading the same way. Only tables taller than a page break across pages, with the header row repeated.
- **Images:** `![Caption.](img/block.svg)` alone in a paragraph becomes a numbered figure (`Figure 2-1`) captioned with its alt text, placed where it is written rather than floated. Images and diagrams are scaled down to fit the line width and the text height less five lines, so a heading, the figure and its caption fit on one page. A `Figure:` paragraph directly after the image (see below) replaces the alt text as the caption. SVG is converted with `rsvg-convert`; PNG and PDF are used directly. Pandoc's `{width=70%}` suffix works but shows as literal text in WYSIWYG editors.
- **Diagrams** are plain `mermaid` / `wavedrom` fences, so markdown editors preview them, with the caption in a `Figure:` paragraph directly after the fence (the same shape as pandoc's `Table:` line):

  ````markdown
  ```mermaid
  graph TD
      CTRL --> TX
  ```

  Figure: Register bank hierarchy.
  ````

- **WaveDrom** sources go inline, or in a JSON file in the document directory referenced by a one-line object. A file may hold several named diagrams (a JSON object whose keys are diagram names); pick one with `key`:

  ````markdown
  ```wavedrom
  {"file": "wavedrom/chip.json", "key": "pb_read_1to1"}
  ```

  Figure: Peripheral bus read.
  ````

  A diagram without a `Figure:` paragraph is placed inline and unnumbered. Pandoc attribute syntax is still accepted (`{.mermaid caption="..." width=80% file=... key=...}`) but does not render in WYSIWYG editors. Rendered diagrams are cached in `out/diagrams/` by content hash, so only changed diagrams are re-rendered.
- **Referring to tables and figures:** give the caption a key, `Table blocks: Top-level blocks.` or `Figure regs: Register bank hierarchy.`, and write `[Table](#blocks)` or `[Figure](#regs)` in the text. The PDF shows the current number (`Table 1-1`) as a link to the table; editors show an ordinary link. Keys are letters, digits, `_` and `-`, unique within the document; the build fails if one key names both a table and a figure, and warns about a link whose target is neither a key nor a heading.
- **Highlight:** `==text==` renders with a yellow highlight (the editor convention; pandoc's `mark` extension).
- **Multi-column text:** put `<!-- columns 2 -->` (or 3) on its own line before the text and `<!-- columns end -->` after it. The PDF balances the text across that many columns; editors ignore the markers. Only text and lists can go inside: a table or figure between the markers stops the build, so close the columns before it.
- **Cross references to headings:** `[Overview](#overview)` links to a heading by its pandoc identifier (lower-cased heading text, spaces as hyphens).
- Follow `.claude/skills/doc-formatting/SKILL.md` for everything else (variables, units, formula blocks).

## 5. Metadata, cover page, headers and footers

Table 5-1 lists the `metadata.yaml` keys (defaults in `defaults.yaml`; a document overrides any of them).

| Key | Purpose | Default |
|---|---|---|
| `title`, `subtitle` | Cover page; `title` is also the default right header | — |
| `revision`, `date` | Cover-page block; taken from the newest row of `history.md`, not from `metadata.yaml` | — |
| `company` | Cover page | Public |
| `header-left`, `header-center`, `header-right` | Page header from page 2 on | `header-right` = title |
| `footer-left`, `footer-center`, `footer-right` | Page footer from page 2 on; cover shows only `footer-center` | `footer-left` = page number, `footer-center` = Public |
| `section-newpage` | Every `#` section starts a new page | true |
| `align-left` | Body text and lists flush left with an uneven right margin instead of justified; table cells are unaffected | false (justified) |
| `mainfont`, `sansfont`, `monofont` | XeLaTeX fonts (any font installed on the host) | Cantarell / Cantarell / DejaVu Sans Mono |
| `diagram-font-size` | Nominal text size in mermaid and WaveDrom diagrams, which use `mainfont`; the diagram is then scaled to fit the page | 11pt |
| `fallbackfont` | Font for Greek letters and arrows, which the main font may lack | DejaVu Sans |
| `table-header-color` | Header-row shading for every table, hex RGB; remove the key for none | DDEBF7 (light blue) |
| `fontsize`, `papersize`, `geometry` | Page setup | 11pt, letter, margin=1in |
| `colorlinks`, `linkcolor`, `urlcolor` | Link colouring | true, NavyBlue |

*Table 5-1: metadata keys.*

Write `{page}` anywhere in a header or footer slot to place the page number (`footer-right: "Page {page}"`). The cover page is page 1 with its number hidden; numbering continues from 2.

`history.md` is `Public`, then a pipe table under a plain `# Version History` heading (made unnumbered and kept out of the TOC by `filters/history.lua`) whose first column is the revision. It is placed on its own page after the last section. List the newest version first: the cover page prints the Rev and Date of the table's first row (found by column name), and the build fails if the table is missing or its first row has no revision. The planned release flow (a `release` target, Claude-written change lists, compaction of older entries) is recorded in the editor notes of the chip spec's `history.md`.

## 6. Files in this directory

Table 6-1 lists the files in this directory.

| File | Role |
|---|---|
| `docgen.mk` | Build rules, included by every document Makefile |
| `defaults.yaml` | Default metadata (company, confidentiality text, fonts, page setup) |
| `template/spec.latex` | pandoc LaTeX template: pandoc 3.11 `default.latex` plus the blocks marked `docgen:` (cover page, fancyhdr styles, section-major table/figure counters, section page breaks) |
| `filters/headers.lua` | Expands `{page}` in header/footer metadata |
| `filters/pagebreak.lua` | Horizontal rule → page break |
| `filters/history.lua` | Makes the version-history heading unnumbered and unlisted |
| `filters/diagrams.lua` | Renders mermaid/wavedrom fences to cached PDFs; `Figure:`/`Table:` captions with keys; rewrites `[Table](#key)` links to numbered references |
| `filters/images.lua` | Resolves image paths against `img/` and converts SVG images to PDF |
| `filters/fallback.lua` | Sets Greek letters and arrows in `fallbackfont` |
| `filters/columns.lua` | `<!-- columns N -->` … `<!-- columns end -->` → multi-column text |
| `filters/tables.lua` | Typesets every table as a full-grid longtable |
| `filters/strip_heading_numbers.lua` | Optional: removes manual heading numbers from legacy sources |
| `bin/strip_preamble.py` | Drops text above the first `#` heading of each section file |
| `bin/combine_sections.py` | Writes `out/<DOC>.md` from the section files |
| `bin/history_meta.py` | Writes the newest history row's revision and date as metadata for the cover page |
| `puppeteer-config.json` | Chromium launch options for `mmdc` |

*Table 6-1: docgen files.*

## 7. Troubleshooting

- `File 'x.sty' not found`: a TeX Live package is missing; add `texlive-x` to the Dockerfile list (container) or `tlmgr install x` (chamber).
- `mmdc` fails to launch the browser: check `executablePath` in the puppeteer config and that `--no-sandbox` is present when running in Docker.
- A diagram does not update: it is cached by content hash in `out/diagrams/`, keyed on the diagram source, so `make clean` is only needed if the renderer itself changed.
- To see the LaTeX pandoc generated, `make tex` and inspect `out/<DOC>.tex`.
