;;; consult-org.el --- Consult commands for org-mode -*- lexical-binding: t -*-

;; Copyright (C) 2021-2025 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides a `completing-read' interface for Org mode navigation.
;; This is an extra package, to allow lazy loading of Org.

;;; Code:

(require 'consult)
(require 'org)

(defvar consult-org--history nil)

(defun consult-org--narrow ()
  "Narrowing configuration for `consult-org' commands."
  (let ((todo-kws
         (seq-filter
          (lambda (x) (<= ?a (car x) ?z))
          (mapcar (lambda (s)
                    (pcase-let ((`(,a ,b) (split-string s "(")))
                      (cons (downcase (string-to-char (or b a))) a)))
                  (apply #'append (mapcar #'cdr org-todo-keywords))))))
    (list :predicate
          (lambda (cand)
            (pcase-let ((`(,level ,todo ,prio . ,_)
                         (get-text-property 0 'consult-org--heading cand)))
              (cond
               ((<= ?1 consult--narrow ?9) (<= level (- consult--narrow ?0)))
               ((<= ?A consult--narrow ?Z) (eq prio consult--narrow))
               (t (equal todo (alist-get consult--narrow todo-kws))))))
          :keys
          (nconc (mapcar (lambda (c) (cons c (format "Level %c" c)))
                         (number-sequence ?1 ?9))
                 (mapcar (lambda (c) (cons c (format "Priority %c" c)))
                         (number-sequence (max ?A org-highest-priority)
                                          (min ?Z org-lowest-priority)))
                 todo-kws))))

(defun consult-org--headings (prefix match scope &rest skip)
  "Return a list of Org heading candidates.

If PREFIX is non-nil, prefix the candidates with the buffer name.
MATCH, SCOPE and SKIP are as in `org-map-entries'."
  (let (buffer (idx 0))
    (apply
     #'org-map-entries
     (lambda ()
       ;; Reset the cache when the buffer changes, since `org-get-outline-path' uses the cache
       (unless (eq buffer (buffer-name))
         (setq buffer (buffer-name)
               org-outline-path-cache nil))
       (pcase-let* ((`(_ ,level ,todo ,prio ,_hl ,tags) (org-heading-components))
                    (tags (if org-use-tag-inheritance
                              (when-let ((tags (org-get-tags)))
                                (concat ":" (string-join tags ":") ":"))
                            tags))
                    (cand (org-format-outline-path
                           (org-get-outline-path 'with-self 'use-cache)
                           most-positive-fixnum)))
         (when todo
           (put-text-property 0 (length todo) 'face (org-get-todo-face todo) todo))
         (when tags
           (put-text-property 0 (length tags) 'face 'org-tag tags))
         (setq cand (concat (and prefix buffer) (and prefix " ") cand (and tags " ")
                            tags (consult--tofu-encode idx)))
         (cl-incf idx)
         (add-text-properties 0 1
                              `(org-marker ,(point-marker)
                                consult-org--heading (,level ,todo ,prio . ,buffer))
                              cand)
         cand))
     match scope skip)))

(defun consult-org--annotate (cand)
  "Annotate CAND for `consult-org-heading'."
  (pcase-let ((`(,_level ,todo ,prio . ,_)
               (get-text-property 0 'consult-org--heading cand)))
    (consult--annotate-align
     cand
     (concat todo
             (and prio (format #(" [#%c]" 1 6 (face org-priority)) prio))))))

(defun consult-org--group (cand transform)
  "Return title for CAND or TRANSFORM the candidate."
  (pcase-let ((`(,_level ,_todo ,_prio . ,buffer)
               (get-text-property 0 'consult-org--heading cand)))
    (if transform (substring cand (1+ (length buffer))) buffer)))

;;;###autoload
(defun consult-org-heading (&optional match scope)
  "Jump to an Org heading.

MATCH and SCOPE are as in `org-map-entries' and determine which
entries are offered.  By default, all entries of the current
buffer are offered."
  (interactive (unless (derived-mode-p #'org-mode)
                 (user-error "Must be called from an Org buffer")))
  (let ((prefix (not (memq scope '(nil tree region region-start-level file)))))
    (consult--read
     (consult--slow-operation "Collecting headings..."
       (or (consult-org--headings prefix match scope)
           (user-error "No headings")))
     :prompt "Go to heading: "
     :category 'org-heading
     :sort nil
     :require-match t
     :history '(:input consult-org--history)
     :narrow (consult-org--narrow)
     :state (consult--jump-state)
     :annotate #'consult-org--annotate
     :group (and prefix #'consult-org--group)
     :lookup (apply-partially #'consult--lookup-prop 'org-marker))))

;;;###autoload
(defun consult-org-agenda (&optional match)
  "Jump to an Org agenda heading.

By default, all agenda entries are offered.  MATCH is as in
`org-map-entries' and can used to refine this."
  (interactive)
  (unless org-agenda-files
    (user-error "No agenda files"))
  (consult-org-heading match 'agenda))

(provide 'consult-org)
;;; consult-org.el ends here
