# Generate the translated man pages.
all-local:
	for man in $$(cd $(srcdir) && ls -d *.[158]); do \
	    po4a --no-backups --variable srcdir=$(srcdir) \
	        $(srcdir)/$$man/$$man.cfg; \
	done

# Remove the generated translations, and update the POTs/POs.
clean-local:
	for man in $$(cd $(srcdir) && ls -d *.[158]); do \
	    po4a --rm-backups --rm-translations --variable srcdir=$(srcdir) \
	        $(srcdir)/$$man/$$man.cfg; \
	done
