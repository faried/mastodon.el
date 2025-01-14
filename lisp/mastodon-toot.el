;;; mastodon-toot.el --- Minor mode for sending Mastodon toots  -*- lexical-binding: t -*-

;; Copyright (C) 2017-2019 Johnson Denen
;; Author: Johnson Denen <johnson.denen@gmail.com>
;; Version: 0.9.0
;; Homepage: https://github.com/jdenen/mastodon.el
;; Package-Requires: ((emacs "24.4"))

;; This file is not part of GNU Emacs.

;; This file is part of mastodon.el.

;; mastodon.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; mastodon.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with mastodon.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; mastodon-toot.el supports POSTing status data to Mastodon.

;;; Code:

(defvar mastodon-instance-url)

(autoload 'mastodon-auth--user-acct "mastodon-auth")
(autoload 'mastodon-http--api "mastodon-http")
(autoload 'mastodon-http--post "mastodon-http")
(autoload 'mastodon-http--triage "mastodon-http")
(autoload 'mastodon-tl--as-string "mastodon-tl")
(autoload 'mastodon-tl--clean-tabs-and-nl "mastodon-tl")
(autoload 'mastodon-tl--field "mastodon-tl")
(autoload 'mastodon-tl--find-property-range "mastodon-tl")
(autoload 'mastodon-tl--goto-next-toot "mastodon-tl")
(autoload 'mastodon-tl--property "mastodon-tl")
(autoload 'mastodon-tl--find-property-range "mastodon-tl")
(autoload 'mastodon-toot "mastodon")

(defgroup mastodon-toot nil
  "Tooting in Mastodon."
  :prefix "mastodon-toot-"
  :group 'mastodon)

(defcustom mastodon-toot--default-visibility "public"
  "The default visibility for new toots.

Must be one of \"public\", \"unlisted\", \"private\", or \"direct\"."
  :group 'mastodon-toot
  :type '(choice ("public"
                  "unlisted"
                  "private"
                  "direct")))

(defvar mastodon-toot--content-warning nil
  "A flag whether the toot should be marked with a content warning.")
(make-variable-buffer-local 'mastodon-toot--content-warning)

(defvar mastodon-toot--content-nsfw nil
  "A flag indicating whether the toot should be marked as NSFW.")
(make-variable-buffer-local 'mastodon-toot--content-nsfw)

(defvar mastodon-toot--visibility "public"
  "A string indicating the visibility of the toot being composed.

Valid values are \"direct\", \"private\", \"unlisted\", and \"public\".")
(make-variable-buffer-local 'mastodon-toot--visibility)

(defvar mastodon-toot--reply-to-id nil
  "Buffer-local variable to hold the id of the toot being replied to.")
(make-variable-buffer-local 'mastodon-toot--reply-to-id)

(defvar mastodon-toot-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'mastodon-toot--send)
    (define-key map (kbd "C-c C-k") #'mastodon-toot--cancel)
    (define-key map (kbd "C-c C-w") #'mastodon-toot--toggle-warning)
    ;;(define-key map (kbd "C-c C-n") #'mastodon-toot--toggle-nsfw)
    (define-key map (kbd "C-c C-v") #'mastodon-toot--change-visibility)
    map)
  "Keymap for `mastodon-toot'.")

(defun mastodon-toot--action-success (marker byline-region remove)
  "Insert/remove the text MARKER with 'success face in byline.

BYLINE-REGION is a cons of start and end pos of the byline to be
modified.
Remove MARKER if REMOVE is non-nil, otherwise add it."
  (let ((inhibit-read-only t)
        (bol (car byline-region))
        (eol (cdr byline-region)))
    (save-excursion
      (when remove
        (goto-char bol)
        (beginning-of-line) ;; The marker is not part of the byline
        (if (search-forward (format "(%s) " marker) eol t)
            (replace-match "")
          (message "Oops: could not find marker '(%s)'" marker)))
      (unless remove
        (goto-char bol)
        (insert (format "(%s) "
                        (propertize marker 'face 'success)))))))

(defun mastodon-toot--action (action callback)
  "Take ACTION on toot at point, then execute CALLBACK."
  (let* ((id (mastodon-tl--property 'base-toot-id))
         (url (mastodon-http--api (concat "statuses/"
                                         (mastodon-tl--as-string id)
                                         "/"
                                         action))))
    (let ((response (mastodon-http--post url nil nil)))
      (mastodon-http--triage response callback))))

(defun mastodon-toot--toggle-boost ()
  "Boost/unboost toot at `point'."
  (interactive)
  (let* ((has-id (mastodon-tl--property 'base-toot-id))
         (byline-region (when has-id
                          (mastodon-tl--find-property-range 'byline (point))))
         (id (when byline-region
               (mastodon-tl--as-string (mastodon-tl--property 'base-toot-id))))
         (boosted (when byline-region
                    (get-text-property (car byline-region) 'boosted-p)))
         (action (if boosted "unreblog" "reblog"))
         (msg (if boosted "unboosted" "boosted"))
         (remove (when boosted t)))
    (if byline-region
        (mastodon-toot--action action
                               (lambda ()
                                 (let ((inhibit-read-only t))
                                   (add-text-properties (car byline-region)
                                                        (cdr byline-region)
                                                        (list 'boosted-p
                                                              (not boosted)))
                                   (mastodon-toot--action-success
                                    "B" byline-region remove))
                                 (message (format "%s #%s" msg id))))
      (message "Nothing to boost here?!?"))))

(defun mastodon-toot--toggle-favourite ()
  "Favourite/unfavourite toot at `point'."
  (interactive)
  (let* ((has-id (mastodon-tl--property 'base-toot-id))
         (byline-region (when has-id
                          (mastodon-tl--find-property-range 'byline (point))))
         (id (when byline-region
               (mastodon-tl--as-string (mastodon-tl--property 'base-toot-id))))
         (faved (when byline-region
                  (get-text-property (car byline-region) 'favourited-p)))
         (action (if faved "unfavourite" "favourite"))
         (remove (when faved t)))
    (if byline-region
        (mastodon-toot--action action
                               (lambda ()
                                 (let ((inhibit-read-only t))
                                   (add-text-properties (car byline-region)
                                                        (cdr byline-region)
                                                        (list 'favourited-p
                                                              (not faved)))
                                   (mastodon-toot--action-success
                                    "F" byline-region remove))
                                 (message (format "%s #%s" action id))))
      (message "Nothing to favorite here?!?"))))

(defun mastodon-toot--kill ()
  "Kill `mastodon-toot-mode' buffer and window."
  (kill-buffer-and-window))

(defun mastodon-toot--cancel ()
  "Kill new-toot buffer/window. Does not POST content to Mastodon."
  (interactive)
  (mastodon-toot--kill))

(defun mastodon-toot--remove-docs ()
  "Get the body of a toot from the current compose buffer."
  (let ((header-region (mastodon-tl--find-property-range 'toot-post-header
                                                         (point-min))))
    (buffer-substring (cdr header-region) (point-max))))

(defun mastodon-toot--set-visibility (visibility)
  "Sets the visiblity of the next toot"
  (interactive
   (list (completing-read "Visiblity: " '("public"
                                          "unlisted"
                                          "private"
                                          "direct"))))
  (setq mastodon-toot--visibility visibility)
  (message "Visibility set to %s" visibility))

(defun mastodon-toot--send ()
  "Kill new-toot buffer/window and POST contents to the Mastodon instance."
  (interactive)
  (let* ((toot (mastodon-toot--remove-docs))
         (empty-toot-p (string= "" (mastodon-tl--clean-tabs-and-nl toot)))
         (endpoint (mastodon-http--api "statuses"))
         (spoiler (when (and (not empty-toot-p)
                             mastodon-toot--content-warning)
                    (read-string "Warning: ")))
         (args `(("status" . ,toot)
                 ("in_reply_to_id" . ,mastodon-toot--reply-to-id)
                 ("visibility" . ,mastodon-toot--visibility)
                 ("sensitive" . ,(when mastodon-toot--content-nsfw
                                   (symbol-name t)))
                 ("visibility" . ,mastodon-toot--visibility)
                 ("spoiler_text" . ,spoiler))))
    (if empty-toot-p
        (message "Empty toot. Cowardly refusing to post this.")
      (mastodon-toot--kill)
      (let ((response (mastodon-http--post endpoint args nil)))
        (mastodon-http--triage response
                               (lambda () (message "Toot toot!")))))))

(defun mastodon-toot--process-local (acct)
  "Adds domain to local ACCT and replaces the curent user name with \"\".

Mastodon requires the full user@domain, even in the case of local accts.
eg. \"user\" -> \"user@local.social \" (when local.social is the domain of the
mastodon-instance-url).
eg. \"yourusername\" -> \"\"
eg. \"feduser@fed.social\" -> \"feduser@fed.social\" "
  (cond ((string-match-p "@" acct) (concat "@" acct " ")) ; federated acct
        ((string= (mastodon-auth--user-acct) acct) "") ; your acct
        (t (concat "@" acct "@" ; local acct
                   (cadr (split-string mastodon-instance-url "/" t)) " "))))

(defun mastodon-toot--mentions (status)
  "Extract mentions from STATUS and process them into a string."
  (interactive)
  (let ((mentions (cdr (assoc 'mentions status))))
    (mapconcat (lambda(x) (mastodon-toot--process-local
                           (cdr (assoc 'acct x))))
               ;; reverse does not work on vectors in 24.5
               (reverse (append mentions nil))
               "")))

(defun mastodon-toot--reply ()
  "Reply to toot at `point'."
  (interactive)
  (let* ((toot (mastodon-tl--property 'toot-json))
         (id (mastodon-tl--as-string (mastodon-tl--field 'id toot)))
         (account (mastodon-tl--field 'account toot))
         (user (cdr (assoc 'acct account)))
         (mentions (mastodon-toot--mentions toot)))
    (mastodon-toot (when user (concat (mastodon-toot--process-local user)
                                      mentions))
                   id)))

(defun mastodon-toot--toggle-warning ()
  "Toggle `mastodon-toot--content-warning'."
  (interactive)
  (setq mastodon-toot--content-warning
        (not mastodon-toot--content-warning))
  (mastodon-toot--update-status-fields))

(defun mastodon-toot--toggle-nsfw ()
  "Toggle `mastodon-toot--content-nsfw'."
  ;; This only makes sense once we have attachments.
  (interactive)
  (setq mastodon-toot--content-nsfw
        (not mastodon-toot--content-nsfw))
  (mastodon-toot--update-status-fields))

(defun mastodon-toot--change-visibility ()
  "Change the current visibility to the next valid value."
  (interactive)
  (setq mastodon-toot--visibility
        (cond ((string= mastodon-toot--visibility "public")
               "unlisted")
              ((string= mastodon-toot--visibility "unlisted")
               "private")
              ((string= mastodon-toot--visibility "private")
               "direct")
              (t
               "public")))
  (mastodon-toot--update-status-fields))

;; we'll need to revisit this if the binds get
;; more diverse than two-chord bindings
(defun mastodon-toot--get-mode-kbinds ()
  "Get a list of the keybindings in the mastodon-toot-mode."
  (let* ((binds (copy-tree mastodon-toot-mode-map))
         (prefix (car (cadr binds)))
         (bindings (remove nil (mapcar (lambda (i) (if (listp i) i))
                                       (cadr binds)))))
    (mapcar (lambda (b)
              (setf (car b) (vector prefix (car b)))
              b)
            bindings)))

(defun mastodon-toot--format-kbind-command (cmd)
  "Format CMD to be more readable.
e.g. mastodon-toot--send -> Send."
  (let* ((str (symbol-name cmd))
         (re "--\\(.*\\)$")
         (str2 (save-match-data
                 (string-match re str)
                 (match-string 1 str))))
    (capitalize (replace-regexp-in-string "-" " " str2))))

(defun mastodon-toot--format-kbind (kbind)
  "Format a single keybinding, KBIND, for display in documentation."
  (let ((key (help-key-description (car kbind) nil))
        (command (mastodon-toot--format-kbind-command (cdr kbind))))
    (format "\t%s - %s" key command)))

(defun mastodon-toot--format-kbinds (kbinds)
  "Format a list keybindings, KBINDS, for display in documentation."
  (mapconcat 'identity (cons "" (mapcar #'mastodon-toot--format-kbind kbinds))
               "\n"))

(defun mastodon-toot--make-mode-docs ()
  "Create formatted documentation text for the mastodon-toot-mode."
  (let ((kbinds (mastodon-toot--get-mode-kbinds)))
    (concat
     " Compose a new toot here. The following keybindings are available:"
     (mastodon-toot--format-kbinds kbinds))))

(defun mastodon-toot--display-docs-and-status-fields ()
  "Insert propertized text with documentation about mastodon-toot mode and the
status fields which will get updated based on the status of NSFW, content
warning flags etc."
  (let ((divider
         "|=================================================================|"))
    (insert
     (propertize
      (concat
       divider "\n"
       (mastodon-toot--make-mode-docs) "\n"
       divider "\n"
       " "
       (propertize "Count"
                   'toot-post-counter t)
       " ⋅ "
       (propertize "Visibility"
                   'toot-post-visibility t)
       " ⋅ "
       (propertize "CW"
                   'toot-post-cw-flag t)
       ;; " "
       ;; (propertize "NSFW"
       ;;             'toot-post-nsfw-flag t)
       "\n"
       divider
       (propertize "\n"
                   'rear-nonsticky t))
      'face 'font-lock-comment-face
      'read-only "Edit your message below."
      'toot-post-header t))))

(defun mastodon-toot--setup-as-reply (reply-to-user reply-to-id)
  "If REPLY-TO-USER is provided, inject their handle into the message.
If REPLY-TO-ID is provided, set the MASTODON-TOOT--REPLY-TO-ID var."
  (when reply-to-user
    (insert (format "%s " reply-to-user))
    (setq mastodon-toot--reply-to-id reply-to-id)))

(defun mastodon-toot--update-status-fields (&rest args)
  "Update the status fields in the header based on the current state."
  (let ((inhibit-read-only t)
        (header-region (mastodon-tl--find-property-range 'toot-post-header
                                                         (point-min)))
        (count-region (mastodon-tl--find-property-range 'toot-post-counter
                                                        (point-min)))
        (visibility-region (mastodon-tl--find-property-range
                            'toot-post-visibility (point-min)))
        ;; (nsfw-region (mastodon-tl--find-property-range 'toot-post-nsfw-flag
        ;;                                                (point-min)))
        (cw-region (mastodon-tl--find-property-range 'toot-post-cw-flag
                                                     (point-min)))
        )
    (add-text-properties (car count-region) (cdr count-region)
                         (list 'display
                               (format "%s characters in message"
                                       (- (point-max) (cdr header-region)))))
    (add-text-properties (car visibility-region) (cdr visibility-region)
                         (list 'display
                               (format "Visibility: %s"
                                       mastodon-toot--visibility)))
    ;; (add-text-properties (car nsfw-region) (cdr nsfw-region)
    ;;                      (list 'invisible (not mastodon-toot--content-nsfw)
    ;;                            'face 'mastodon-cw-face))
    (add-text-properties (car cw-region) (cdr cw-region)
                         (list 'invisible (not mastodon-toot--content-warning)
                               'face 'mastodon-cw-face))))

(defun mastodon-toot--compose-buffer (reply-to-user reply-to-id)
  "Create a new buffer to capture text for a new toot.
If REPLY-TO-USER is provided, inject their handle into the message.
If REPLY-TO-ID is provided, set the MASTODON-TOOT--REPLY-TO-ID var."
  (let* ((buffer-exists (get-buffer "*new toot*"))
         (buffer (or buffer-exists (get-buffer-create "*new toot*")))
         (inhibit-read-only t))
    (switch-to-buffer-other-window buffer)
    (when (not buffer-exists)
      (mastodon-toot--display-docs-and-status-fields)
      (mastodon-toot--setup-as-reply reply-to-user reply-to-id))
    (make-local-variable 'after-change-functions)
    (push #'mastodon-toot--update-status-fields after-change-functions)
    (mastodon-toot--update-status-fields)
    (mastodon-toot-mode t)))

(define-minor-mode mastodon-toot-mode
  "Minor mode to capture Mastodon toots."
  :group 'mastodon-toot
  :keymap mastodon-toot-mode-map
  :global nil)

(provide 'mastodon-toot)
;;; mastodon-toot.el ends here
