(defvar debian-changelog-urgencies
  '((?l."low") (?m."medium") (?h."HIGH"))
  "alist of keystrokes vs. urgency values for debian-changelog-urgency \\[debian-changelog-urgency].")

(defvar debian-changelog-distributions
  '((?s."stable") (?u."unstable") (?c."contrib") (?n."non-free") (?e."experimental"))
  "alist of keystrokes vs. distribution values for debian-changelog-distribution \\[debian-changelog-distribution].")

(defun debian-changelog-headervalue (arg re alist)
  (let (a b v k
        (lineend (save-excursion (end-of-line) (point))))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward re lineend)
      (setq a (match-beginning 1)
            b (match-end 1))
      (goto-char a)
      (if arg nil
        (message (mapconcat
                  (function (lambda (x) (format "%c:%s" (car x) (cdr x))))
                  alist " "))
        (while (not v)
          (setq k (read-char))
          (setq v (assoc k alist))))
      (delete-region a b)
      (if arg nil (insert (cdr v))))
    (if arg (goto-char a))))

(defun debian-changelog-distribution (arg)
  "Without argument, prompt for a key for a new distribution value (using
debian-changelog-distributions).  With argument, delete the current distribution
and position the cursor to type a new one."
  (interactive "P")
  (debian-changelog-headervalue
   arg
   ") \\(.*\\)\\;"
   debian-changelog-distributions))

(defun debian-changelog-urgency (arg)
  "Without argument, prompt for a key for a new urgency value (using
debian-changelog-urgencies).  With argument, delete the current urgency
and position the cursor to type a new one."
  (interactive "P")
  (debian-changelog-headervalue
   arg
   "\\;[^\n]* urgency=\\(\\sw+\\)"
   debian-changelog-urgencies))

