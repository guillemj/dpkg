## Process this file with automake to produce Makefile.in

# C must be the first sub-directory because it contains the POT files.
SUBDIRS = C de es fr hu ja pl pt_BR ru sv

.PHONY: updatepo
updatepo:
	list='$(SUBDIRS)'; for dir in $$list; do \
		$(MAKE) -C "$$dir" updatepo; \
	done
