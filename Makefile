DOC      := pps_tax_report
SECTIONS := report.md
include tools/docgen/docgen.mk

# Release name; defaults to the newest revision in history.md (e.g. R3). Override with REL=.
REL ?= $(shell awk -F'|' '/^\|/ && !/\*\*/ && !/---/ { gsub(/[ \t]/, "", $$2); print $$2; exit }' history.md)
RELEASE_DOC := PPS_Tax_and_Funding_Report_$(REL)

.PHONY: release
release:
	@[ -n "$(REL)" ] || { echo "release: no revision found in history.md; set REL="; exit 1; }
	$(MAKE) clean
	$(MAKE) DOC=$(RELEASE_DOC)
	cp out/$(RELEASE_DOC).pdf releases
	perl -pi -e 's{PPS_Tax_and_Funding_Report_[^/)\s]*?\.pdf}{$(RELEASE_DOC).pdf}g if /^_See /' README.md
