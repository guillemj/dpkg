## Process this file with automake to produce Makefile.in

# po4a must be the first sub-directory because it generates the translations.
SUBDIRS = C po4a de es fr hu ja pl pt_BR ru sv

.PHONY: updatepo
updatepo:
	list='$(SUBDIRS)'; for dir in $$list; do \
		$(MAKE) -C "$$dir" updatepo; \
	done
