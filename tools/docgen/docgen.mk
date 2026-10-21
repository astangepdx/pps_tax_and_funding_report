# docgen.mk -- markdown -> PDF specification build, included by a document Makefile.
#
# A document Makefile sets DOC and SECTIONS and includes this file:
#
#   DOC      := chip_spec
#   SECTIONS := overview.md architecture.md
#   include ../../../../tools/docgen/docgen.mk
#
# See README.md next to this file for the authoring conventions and tool setup.

DOCGEN_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

ifndef DOC
$(error docgen: set DOC (output base name) before including docgen.mk)
endif
ifndef SECTIONS
$(error docgen: set SECTIONS (ordered list of section markdown files) before including docgen.mk)
endif

# clean/help are defined first; the default goal stays the build.
.DEFAULT_GOAL := all

# Output directory; also needed by the tool-free local targets below.
OUT ?= out

.PHONY: clean help
clean:
	rm -rf $(OUT)

help:
	@echo "all, pdf     build out/$(DOC).pdf (default)"
	@echo "md           combine sections into out/$(DOC).md"
	@echo "tex          write out/$(DOC).tex for LaTeX debugging"
	@echo "versions     print tool versions"
	@echo "check-tools  fail if a required tool is missing"
	@echo "clean        delete $(OUT)/"
	@echo "help         this list"

# ---- Chamber: run the build on the grid ----
# Nothing runs on the chamber login host (ENVIRONMENT.md 3.1.2). A make started
# where SGE is present (qrsh on PATH) but outside an SGE job (no JOB_ID)
# re-submits itself with the caller's environment; the rules below then run on
# the compute node. Elsewhere (dev container, compute node) this is inert.
DOCGEN_QUEUE ?= interactive.q
DOCGEN_SUBMIT :=
ifneq ($(shell command -v qrsh 2>/dev/null),)
ifeq ($(JOB_ID),)
DOCGEN_SUBMIT := 1
endif
endif

ifneq ($(DOCGEN_SUBMIT),)

# Tool-free targets (help, clean) stay local; everything else goes to the grid.
DOCGEN_GOALS := $(filter-out help clean,$(or $(MAKECMDGOALS),all))
DOCGEN_GOAL1 := $(firstword $(DOCGEN_GOALS))
ifneq ($(DOCGEN_GOALS),)
.PHONY: $(DOCGEN_GOALS)
$(DOCGEN_GOAL1):
	qrsh -q $(DOCGEN_QUEUE) -V -cwd -now no $(MAKE) $(DOCGEN_GOALS)
ifneq ($(words $(DOCGEN_GOALS)),1)
$(filter-out $(DOCGEN_GOAL1),$(DOCGEN_GOALS)): $(DOCGEN_GOAL1)
	@:
endif
endif

else  # DOCGEN_SUBMIT

# ---- Inputs and outputs (overridable from the document Makefile or command line) ----
METADATA ?= metadata.yaml
HISTORY  ?= history.md
TOC_DEPTH ?= 3
# Extra files the PDF depends on (images, wavedrom sources); rebuild when they change.
DOC_DEPS ?= $(wildcard img/* wavedrom/*)
# Set to 1 to strip leading "1." / "1.2" numbers from source headings (legacy docs).
STRIP_HEADING_NUMBERS ?= 0
# Extra pandoc options.
PANDOC_EXTRA ?=
# Confidentiality line written at the top of the generated markdown (stripped for the PDF).
NOTICE ?= Public

# ---- Tools ----
PANDOC       ?= pandoc
XELATEX      ?= xelatex
MMDC         ?= mmdc
WAVEDROM     ?= wavedrom-cli
RSVG_CONVERT ?= rsvg-convert
PYTHON       ?= python3
# ---- macOS (Homebrew) host settings ----
# mermaid-cli installed with npm brings its own Chrome, so no puppeteer config is needed
# (the Linux puppeteer-config.json names /usr/bin/chromium-browser, which does not exist
# here), and mermaid-cli >= 12 has no -f flag (fit is its default). Linux keeps the defaults.
ifeq ($(shell uname -s),Darwin)
MMDC_PUPPETEER_CONFIG ?=
MMDC_PDF_FLAGS ?= $(if $(filter 11.%,$(shell $(MMDC) --version 2>/dev/null)),-f,)
endif
# Puppeteer launch config for mmdc (browser path, --no-sandbox). Edit or override per host.
MMDC_PUPPETEER_CONFIG ?= $(DOCGEN_DIR)/puppeteer-config.json
# Flags mmdc needs to emit a PDF that fits the diagram. mermaid-cli 11.x: -f (--pdfFit);
# mermaid-cli 12.x removed -f (fit is the default there), so set MMDC_PDF_FLAGS= on such hosts.
MMDC_PDF_FLAGS ?= -f

TEMPLATE := $(DOCGEN_DIR)/template/spec.latex
DEFAULTS := $(DOCGEN_DIR)/defaults.yaml
FILTERS  := $(DOCGEN_DIR)/filters/headers.lua $(DOCGEN_DIR)/filters/pagebreak.lua $(DOCGEN_DIR)/filters/diagrams.lua $(DOCGEN_DIR)/filters/images.lua \
            $(DOCGEN_DIR)/filters/fallback.lua \
            $(DOCGEN_DIR)/filters/tables.lua $(DOCGEN_DIR)/filters/columns.lua
ifeq ($(STRIP_HEADING_NUMBERS),1)
FILTERS  += $(DOCGEN_DIR)/filters/strip_heading_numbers.lua
endif
SCRIPTS  := $(DOCGEN_DIR)/bin/strip_preamble.py $(DOCGEN_DIR)/bin/combine_sections.py \
            $(DOCGEN_DIR)/bin/history_meta.py

PDF      := $(OUT)/$(DOC).pdf
TEX      := $(OUT)/$(DOC).tex
# All sections joined verbatim (preambles stripped): the markdown deliverable, and the
# single input pandoc turns into the PDF.
COMBINED := $(OUT)/$(DOC).md
# COMBINED with its notice/comment preamble removed: what pandoc reads.
PANDOC_IN := $(OUT)/$(DOC).pandoc.md
HISTORY_TEX := $(OUT)/history.tex
# revision and date of the newest history row, as metadata for the cover page.
HISTORY_META := $(OUT)/history-meta.yaml

# Environment the Lua filters read.
FILTER_ENV := DOCGEN_OUT=$(OUT) DOCGEN_MMDC=$(MMDC) DOCGEN_WAVEDROM=$(WAVEDROM) \
              DOCGEN_RSVG_CONVERT=$(RSVG_CONVERT) \
              DOCGEN_PUPPETEER_CONFIG=$(MMDC_PUPPETEER_CONFIG) \
              DOCGEN_MMDC_PDF_FLAGS="$(MMDC_PDF_FLAGS)"

PANDOC_FLAGS := --from markdown+raw_tex+mark \
                --metadata-file $(DEFAULTS) --metadata-file $(METADATA) --metadata-file $(HISTORY_META) \
                --template $(TEMPLATE) \
                --number-sections --top-level-division=section \
                --toc --toc-depth=$(TOC_DEPTH) \
                $(addprefix --lua-filter ,$(FILTERS)) \
                --include-after-body $(HISTORY_TEX) \
                --resource-path=.:img \
                $(PANDOC_EXTRA)

.PHONY: all pdf tex md versions check-tools

all: pdf
pdf: $(PDF)
tex: $(TEX)
md: $(COMBINED)

# Order-only prerequisite: runs every time but never forces a rebuild by itself.
check-tools:
	@for t in "$(PANDOC)" "$(XELATEX)" "$(MMDC)" "$(WAVEDROM)" "$(RSVG_CONVERT)" "$(PYTHON)"; do \
	  command -v "$$t" >/dev/null 2>&1 || { \
	    echo "docgen: required tool '$$t' not found on PATH (see $(DOCGEN_DIR)/README.md)"; exit 1; }; \
	done
	@$(PANDOC) --version | head -1 | awk '{ split($$2, v, "."); \
	  if (v[1] < 3 || (v[1] == 3 && v[2] < 1)) { \
	    printf "docgen: pandoc %s is too old (need >= 3.1; see $(DOCGEN_DIR)/README.md)\n", $$2; exit 1 } }'

versions: | check-tools
	@$(PANDOC) --version | head -1
	@$(XELATEX) --version | head -1
	@echo "mmdc $$($(MMDC) --version)"
	@echo "wavedrom-cli $$(cd $$(dirname $$(readlink -f $$(command -v $(WAVEDROM))))/.. && node -e 'console.log(require(\"./package.json\").version)' 2>/dev/null || echo '?')"
	@$(RSVG_CONVERT) --version
	@$(PYTHON) --version

$(HISTORY_META): $(HISTORY) $(DOCGEN_DIR)/bin/history_meta.py
	@mkdir -p $(OUT)
	$(PYTHON) $(DOCGEN_DIR)/bin/history_meta.py $(HISTORY) $@

# The document as one markdown file: section preambles stripped, sections joined verbatim
# in SECTIONS order. No cover, TOC, version history or section numbers.
$(COMBINED): $(SECTIONS) $(METADATA) $(HISTORY) $(DOCGEN_DIR)/bin/combine_sections.py $(DOCGEN_DIR)/bin/strip_preamble.py $(DOCGEN_DIR)/bin/history_meta.py
	@mkdir -p $(OUT)
	$(PYTHON) $(DOCGEN_DIR)/bin/combine_sections.py --metadata $(METADATA) --history $(HISTORY) --notice "$(NOTICE)" -o $@ $(SECTIONS)

$(PANDOC_IN): $(COMBINED) $(DOCGEN_DIR)/bin/strip_preamble.py
	$(PYTHON) $(DOCGEN_DIR)/bin/strip_preamble.py $< $@

# history.md with its preamble removed.
$(OUT)/sections/%.md: %.md $(DOCGEN_DIR)/bin/strip_preamble.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(DOCGEN_DIR)/bin/strip_preamble.py $< $@

# Version history page, on its own page after the last section.
$(HISTORY_TEX): $(OUT)/sections/$(HISTORY) $(DEFAULTS) $(METADATA) $(DOCGEN_DIR)/filters/history.lua $(DOCGEN_DIR)/filters/tables.lua | check-tools
	@mkdir -p $(OUT)
	( printf '\\clearpage\n\n'; \
	  $(PANDOC) --from markdown -t latex --metadata-file $(DEFAULTS) --metadata-file $(METADATA) \
	    --lua-filter $(DOCGEN_DIR)/filters/history.lua --lua-filter $(DOCGEN_DIR)/filters/tables.lua $< ) > $@

# pandoc writes the .tex; xelatex is run here until no rerun warnings remain, because
# longtable column widths and the TOC need more passes than pandoc's own PDF step makes.
$(PDF): $(TEX)
	@rm -f $(OUT)/$(DOC).aux $(OUT)/$(DOC).toc $(OUT)/$(DOC).lot $(OUT)/$(DOC).lof $(OUT)/$(DOC).out  # stale aux files can break a changed preamble
	@for pass in 1 2 3 4 5 6; do \
	  $(XELATEX) -interaction=nonstopmode -halt-on-error -output-directory=$(OUT) $(TEX) >/dev/null 2>&1 || { \
	    echo "docgen: xelatex failed (pass $$pass); end of $(OUT)/$(DOC).log:"; tail -30 $(OUT)/$(DOC).log; exit 1; }; \
	  grep -Eq 'Warning:.*Rerun|Rerun to get' $(OUT)/$(DOC).log || break; \
	  [ $$pass -lt 6 ] || echo "docgen: warning: LaTeX still asks for a rerun after $$pass passes"; \
	done
	@n=$$(grep -c '^Overfull \\hbox' $(OUT)/$(DOC).log); \
	  [ "$$n" = 0 ] || echo "docgen: $$n overfull line(s) (text or table wider than the column); see $(OUT)/$(DOC).log"
	@echo "docgen: wrote $@"

$(TEX): $(PANDOC_IN) $(METADATA) $(DEFAULTS) $(HISTORY_META) $(HISTORY_TEX) $(TEMPLATE) $(FILTERS) $(DOC_DEPS) | check-tools
	@mkdir -p $(OUT)
	env $(FILTER_ENV) $(PANDOC) $(PANDOC_IN) $(PANDOC_FLAGS) --standalone -t latex -o $@

endif  # DOCGEN_SUBMIT
