;; 
;; /etc/emacs/site-start.d/50dpkg-dev.el
;;
;; Copyright (C) 1997, Klee Dienes <klee@mit.edu>
;; I hereby release this progam into the public domain.

(autoload 'debian-changelog-mode "debian-changelog-mode"
        "Major mode for editing Debian-style change logs." t)

; Automatically set mode for debian/changelog and debian/rules files.
(setq auto-mode-alist (cons '("/debian/changelog\\'" . debian-changelog-mode)
			    auto-mode-alist)
      interpreter-mode-alist (cons '("make" . makefile-mode)
				   interpreter-mode-alist))
