;; debian-changelog.el --- change log maintenance for Debian-style changelogs

;; Keywords: maint

;; Copyright (C) 1996 Ian Jackson
;; Copyright (C) 1997 Klee Dienes
;; This file is part of dpkg.
;;
;; It is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; dpkg is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with your Debian installation, in /usr/doc/copyright/GPL.
;; If not, write to the Free Software Foundation, 675 Mass Ave,
;; Cambridge, MA 02139, USA.

(require 'add-log)

(defun debian-changelog-setheadervalue (re str)
  (let (a b v k
	  (lineend (save-excursion (end-of-line) (point))))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward re lineend)
      (setq a (match-beginning 1)
            b (match-end 1))
      (goto-char a)
      (delete-region a b)
      (insert str))))

(defun debian-changelog-getheadervalue (re)
  (let ((lineend (save-excursion (end-of-line) (point))))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward re lineend)
      (buffer-substring-no-properties (match-beginning 1) (match-end 1)))))

(defvar debian-changelog-mode-map nil
  "Keymap for Debian changelog major mode.")
(if debian-changelog-mode-map
    nil
  (setq debian-changelog-mode-map (make-sparse-keymap))
  (define-key debian-changelog-mode-map "\C-c\C-a" 'debian-changelog-add-entry)
  (define-key debian-changelog-mode-map "\C-c\C-f"
    'debian-changelog-finalise-last-version)
  (define-key debian-changelog-mode-map "\C-c\C-c" 'debian-changelog-finalise-and-save)
  (define-key debian-changelog-mode-map "\C-c\C-v" 'debian-changelog-add-version)
  (define-key debian-changelog-mode-map "\C-c\C-d" 'debian-changelog-distribution)
  (define-key debian-changelog-mode-map "\C-c\C-u" 'debian-changelog-urgency)
  (define-key debian-changelog-mode-map "\C-c\C-e"
    'debian-changelog-unfinalise-last-version))

(defun debian-changelog-add-entry ()
  "Add a new change entry to a debian-style changelog."
  (interactive)
  (if (eq (debian-changelog-finalised-p) t)
      (error (substitute-command-keys "most recent version has been finalised - use \\[debian-changelog-unfinalise-last-version] or \\[debian-changelog-add-version]")))
  (goto-char (point-min))
  (re-search-forward "\n --")
  (backward-char 5)
  (if (prog1 (looking-at "\n") (forward-char 1))
      nil
    (insert "\n"))
  (insert "  * ")
  (save-excursion (insert "\n")))

(defun debian-changelog-distribution (arg)
  "Delete the current distribution and prompt for a new one."
  (interactive "P")
  (let* ((curstr
	  (debian-changelog-getheadervalue ") \\(.*\\)\\;"))
	 (str (completing-read 
	       "Select distribution: "
	       '(("stable" 1)
		 ("frozen" 2)
		 ("unstable" 3) 
		 ("stable frozen unstable" 4)
		 ("stable unstable frozen" 4)
		 ("unstable stable frozen" 4)
		 ("unstable frozen stable" 4)
		 ("frozen unstable stable" 4)
		 ("frozen stable unstable" 4)
		 ("frozen unstable" 5)
		 ("unstable frozen" 5)
		 ("stable frozen" 6)
		 ("frozen stable" 6)
		 ("stable unstable" 7)
		 ("unstable stable" 7))
	       nil t nil)))
    (if (not (equal str ""))
	(debian-changelog-setheadervalue ") \\(.*\\)\\;" str))))

(defun debian-changelog-urgency (arg)
  "Delete the current urgency and prompt for a new one."
  (interactive "P")
  (let* ((urgency-regex "\\;[^\n]* urgency=\\(\\sw+\\)")
	 (curstr
	  (debian-changelog-getheadervalue urgency-regex))
	 (str (completing-read 
	       "Select urgency: "
	       '(("low" 1) ("medium" 2) ("high" 3))
	       nil t nil)))
    (if (not (equal str ""))
	(debian-changelog-setheadervalue urgency-regex str))))

(defun debian-changelog-finalised-p ()
  "Check whether the most recent debian-style changelog entry is
finalised yet (ie, has a maintainer name and email address and a
release date."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "\n\\S-" (point-max) t)
        (progn
          (if (re-search-backward "\n --" (point-min) t)
              (forward-char 4)
            (beginning-of-line)
            (insert " --\n\n")
            (backward-char 2))
          (cond
           ((looking-at "[ \n]+\\S-[^\n\t]+\\S- <[^ \t\n<>]+>  \\S-[^\t\n]+\\S-[ \t]*\n")
            t)
           ((looking-at "[ \t]*\n")
            nil)
           (t
            "finalisation line has bad format (not ` -- maintainer <email>  date')")))
      t)))

(defun debian-changelog-add-version ()
  "Add a new version section to a debian-style changelog file."
  (interactive)
  (let ((f (debian-changelog-finalised-p)))
    (and (stringp f) (error f))
    (or f (error "previous version not yet finalised")))
  (goto-char (point-min))
  (let ((headstring
         (if (looking-at "\\(\\S-+ ([^()\n\t ]*[^0-9\n\t()]\\)\\([0-9]+\\)\\()[^\n]*\\)")
             (concat (match-string 1)
                     (number-to-string (+ 1 (string-to-number (match-string 2))))
                     (match-string 3))
           (let ((pkg (read-string "Package name: "))
                 (ver (read-string "New version (including any revision): ")))
             (concat pkg " (" ver ") unstable; urgency=low")))))
    (insert headstring "\n\n  * ")
    (save-excursion
      (if (re-search-backward ") \\([^\n]*\\);[^\n]* urgency=\\(\\sw+\\)" (point-min) t)
          (progn (goto-char (match-beginning 2))
                 (delete-region (point) (match-end 2))
                 (insert "low")
		 (goto-char (match-beginning 1))
		 (delete-region (point) (match-end 1))
                 (insert "unstable"))))
    (save-excursion (insert "\n\n --\n\n"))))

(defun debian-changelog-finalise-and-save ()
  "Finalise, if necessary, and then save a debian-style changelog file."
  (interactive)
  (let ((f (debian-changelog-finalised-p)))
    (and (stringp f) (error f))
    (or f (debian-changelog-finalise-last-version)))
  (save-buffer))

(defun debian-changelog-date-string ()
  "Return RFC-822 format date string"
  (let* ((dp "822-date")
	 (cp (point))
	 (ret (call-process "822-date" nil t))
	 (np (point))
	 (out nil))
    (cond ((not (or (eq ret nil) (eq ret 0)))
	   (setq out (buffer-substring-no-properties cp np))
	   (delete-region cp np)
	   (error (concat "error from " dp ": " out)))
	  (t
	   (backward-char)
	   (or (looking-at "\n")
	       (error (concat "error from " dp ": expected newline after date string")))
	   (setq out (buffer-substring-no-properties cp (- np 1)))
	   (delete-region cp np)
	   out))))

(defun debian-changelog-finalise-last-version ()
  "Remove the `finalisation' information (maintainer's name and email
address and release date) so that new entries can be made."
  (interactive)
  (or add-log-full-name (setq add-log-full-name (user-full-name)))
  (or add-log-mailing-address (setq add-log-mailing-address user-mail-address))
  (and (debian-changelog-finalised-p) (debian-changelog-unfinalise-last-version))
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "\n --\\([ \t]*\\)")
    (delete-region (match-beginning 1) (match-end 1))
    (insert " " add-log-full-name " <" add-log-mailing-address ">  " 
	    (debian-changelog-date-string))))

(defun debian-changelog-unfinalise-last-version ()
  "Remove the `finalisation' information (maintainer's name and email
address and release date) so that new entries can be made."
  (interactive)
  (if (debian-changelog-finalised-p) nil
    (error "most recent version is not finalised"))
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "\n --")
    (let ((dels (point)))
      (end-of-line)
      (delete-region dels (point)))))

(defun debian-changelog-mode ()
  "Major mode for editing Debian-style change logs.
Runs `debian-changelog-mode-hook' if it exists.

Key bindings:

\\{debian-changelog-mode-map}
Hint:  If you want to use your debian.org email address for debian/changelog
entries without using it for the rest of your email, put

    (add-hook 'debian-changelog-mode-hook 'my-debian-changelog-mode-hook)
    (defun my-debian-changelog-mode-hook ()
      (make-local-variable 'add-log-mailing-address)
      (setq add-log-mailing-address \"myname@debian.org\"))

in your ~/.emacs file.  This is better than including a local setting
for add-log-mailing-address in the changelog itself both because you
only have to set it up once and because it works in the presense of
NMUs."

  (interactive)
  (kill-all-local-variables)
  (text-mode)
  (setq major-mode 'debian-changelog-mode
	mode-name "Debian changelog"
        left-margin 2
	fill-prefix "  "
	fill-column 74)
  (use-local-map debian-changelog-mode-map)
  ;; Let each entry behave as one paragraph:
  (set (make-local-variable 'paragraph-start) "\\*")
  (set (make-local-variable 'paragraph-separate) "\\*\\|\\s-*$|\\S-")
  ;; Let each version behave as one page.
  ;; Match null string on the heading line so that the heading line
  ;; is grouped with what follows.
  (set (make-local-variable 'page-delimiter) "^\\<")
  (set (make-local-variable 'version-control) 'never)
  (run-hooks 'debian-changelog-mode-hook))

(provide 'debian-changelog)
