;;; portage.el --- search and install Gentoo packages

;; Copyright (C) 2004  Mikael Brockman

;; Version: 1.0
;; Keywords: Gentoo, portage
;; Author: Mikael Brockman
;; Maintainer: Mikael Brockman

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
;; 02111-1307, USA.

;;; Installation:

;; (require 'portage)
;; (global-set-key (kbd "\C-c p") 'portage-search)

;;; Code:

(defgroup paludis-package nil
  "Paludis customization options.")

(defcustom paludis-elevated-user-command "sudo"
  "'sudo' or 'doas' for elevated privelages.")

(defun portage-search (&optional string)
  "Search Gentoo Portage for STRING.
If called interactively, prompt for a string to search for."
  (interactive "MSearch Portage for: ")
  (in-buffer-called "*portage*"
		    (call-process "sudo" nil t t "emerge" "search" string)
		    (goto-char (point-min))

		    (kill-line 4)

		    (portage-search-mode)
		    (outline-minor-mode)
		    (hide-other)

		    (local-set-key (kbd "s") 'show-all)
		    (local-set-key (kbd "i") 'portage-install-package-at-point)
		    (local-set-key (kbd "q") 'quit-buffer-and-window)
		    (local-set-key (kbd "<down>") 'portage-next-item)
		    (local-set-key (kbd "<up>") 'portage-previous-item)
		    (local-set-key (kbd "p") 'portage-pretend-package-at-point)))

(defun exherbo-install (&optional package &key flags)
  "Emerge PACKAGE from Exherbo Paludis.
If called interactively, prompt for a package name."
  (interactive "Resolve package: ")
  (with-temp-buffer
    (start-process "paludis install" nil
                   "st"
                   "-e"
		   "sh"
		   "-c"
                   (concat "doas cave resolve -x " package "; exec sh")
		   )
    )
  )

(defun portage-install-package-at-point ()
  "Install the Gentoo package whose header is under point."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (portage-at-start-of-package-line)
      (portage-install (match-string 1)))))

(defun portage-pretend-package-at-point ()
  "Run emerge -pv on the Gentoo package whose header is under point."
  (interactive)
  (when (portage-at-start-of-package-line)
    (portage-pretend (match-string 1))))

(defun portage-move-to-adjacent-item (direction)
  "Move to an adjacant item.
If DIRECTION is 'forward, move to the next item.  Otherwise, move to
the previous item."
  (let ((position (portage-next-item-header direction)))
    (unless (null position)
      (goto-char position)
      (hide-other)
      (recenter))))

(defun portage-next-item ()
  (interactive)
  (portage-move-to-adjacent-item 'forward))

(defun portage-previous-item ()
  (interactive)
  (portage-move-to-adjacent-item 'backward))

(defun portage-next-item-header (direction)
  "Find the character number of an adjacent item header."
  (let ((n (if (eq direction 'forward) 1 -1)))
    (save-excursion
      (catch 'x
        (forward-line n)
        (until (portage-at-item-header-p)
               (forward-line n)
               (when (= (point) (point-max))
		 (throw 'x nil)))
        (point)))))

(defun portage-at-item-header-p ()
  (looking-at "^\*"))

(require 'generic-x)

(define-generic-mode 'portage-search-mode
  nil
  nil
  '(("^\\(*\\)  \\([^\\[ \n]+\\)\\(.*\\)$"
     (1 'font-lock-string-face)
     (2 'font-lock-keyword-face)
     (3 'font-lock-warning-face))
    ("^ +\\([^:]+\\): \\(.*\\)$"
     (1 'font-lock-variable-name-face)))
  nil
  nil)



(defun portage-pretend (package)
  "Run emerge -pv PACKAGE."
  (in-buffer-called "*portage pretend*"
		    (call-process "sudo" nil t t "emerge" "-pv" package)
		    (goto-char (point-min))

		    (kill-line 4)

		    (portage-pretend-mode)

		    (make-local-variable 'portage-pretend-package)
		    (setq portage-pretend-package package)

		    (make-local-variable 'portage-use-flags)
		    (setq portage-use-flags (make-hash-table :test 'equal))

		    (local-set-key (kbd "q") 'quit-buffer-and-window)
		    (local-set-key (kbd "+") 'portage-pretend-add-use-flag)
		    (local-set-key (kbd "-") 'portage-pretend-remove-use-flag)
		    (local-set-key (kbd "\C-c\C-c") 'portage-pretend-install)))

(defun portage-pretend-install ()
  (interactive)
  (portage-install portage-pretend-package :flags portage-use-flags))

(defun portage-pretend-add-use-flag (&optional flag)
  (interactive "MEnable USE flag: ")
  (puthash flag t portage-use-flags)
  (portage-pretend-update-flag-line))

(defun portage-pretend-remove-use-flag (&optional flag)
  (interactive "MDisable USE flag: ")
  (if (gethash flag portage-use-flags nil)
      (remhash flag portage-use-flags)
    (puthash flag nil portage-use-flags))
  (portage-pretend-update-flag-line))

(defun portage-pretend-update-flag-line ()
  (save-excursion
    (goto-char (point-min))
    (when (looking-at "Enabled USE flags:")
      (kill-line 4))

    (let ((enabled-string "")
          (disabled-string ""))
      (maphash #'(lambda (flag enabled)
                   (if enabled
                       (setq enabled-string
                             (concat enabled-string " " flag))
                     (setq disabled-string
                           (concat disabled-string " -" flag))))
               portage-use-flags)
      (insert (concat "Enabled USE flags: " enabled-string "\n"))
      (insert (concat "Disabled USE flags: " disabled-string "\n")))
    (insert "\n\n")))

(defun portage-at-start-of-package-line ()
  (looking-at "^\*  \\([^ \n]+\\).*$"))

(define-generic-mode 'portage-pretend-mode
  nil
  nil
  '(("^\\(\\[.*?\\]\\) \\(.*?\\) +\\(.*?\\) +\\(.*\\)$"
     (1 'font-lock-builtin-face)
     (2 'font-lock-keyword-face)
     (3 'font-lock-constant-face)
     (4 'font-lock-type-face))
    ("^\\(USE flags\\):  "
     (1 'font-lock-keyword-face))
    ("^Enabled USE flags:" . 'font-lock-constant-face)
    ("^Disabled USE flags:" . 'font-lock-warning-face)
    ("^[^\\[].*$" . 'font-lock-variable-name-face))
  nil
  nil)



(defmacro in-buffer-called (name &rest body)
  (let ((buffer (gensym)))
    `(save-excursion
       (let ((,buffer (generate-new-buffer ,name)))
         (switch-to-buffer ,buffer)
         ,@body))))

(put 'in-buffer-called 'lisp-indent-function 1)

(defmacro until (condition &rest body)
  `(while (not ,condition)
     ,@body))

(put 'until 'lisp-indent-function 1)

(defun quit-buffer-and-window ()
  (interactive)
  (kill-buffer (current-buffer))
  (unless (one-window-p t 'this)
    (delete-window)))

(defun exherbo-url (&optional version_prepend package)
  "Return URL of paludis PACKAGE."
  (interactive)
  (get-buffer-create "Paludis show Emacs")
  (with-current-buffer "Paludis show Emacs"
    (paludis-category-package-current-file)
    (call-process "doas" nil t t "cave" "show" "-c" paludis-package)
    (sleep-for 1.40)
    (setq case-fold-search nil)
    (search-backward "Downloads" nil)
    (next-line)
    (back-to-indentation)
    (kill-line)
    (erase-buffer)
     )
    )

(defun paludis-category-package-current-file ()
  "Set `paludis-package' to 'CATEGORY/PACKAGE' of the current file."
  (interactive)
  (with-temp-buffer
    (dired-jump)
    (beginning-of-buffer)
    (search-forward "packages/")
    (push-mark)
    (forward-sexp)
    (kill-ring-save (mark) (point))
    (setq paludis-package (car kill-ring))
    )
  )

(provide 'portage)

;;; portage.el ends here.
