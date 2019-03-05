;;; mastodon-discover.el --- Use Mastodon.el with discover.el  -*- lexical-binding: t -*-

;; Copyright (C) 2019 Johnson Denen
;; Author: Johnson Denen <johnson.denen@gmail.com>
;; Version: 0.8.0
;; Package-Requires: ((emacs "24.4"))
;; Homepage: https://github.com/jdenen/mastodon.el

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

;; This adds optional functionality that can be used if the dicover package
;; is present.
;;
;; See the README file for how to use this.

;;; Code:
(require 'discover)

(defun mastodon-discover--init ()
  "Plug Mastodon functionality into discover."
  (interactive)
  (discover-add-context-menu
   :bind "?"
   :mode 'mastodon-mode
   :mode-hook 'mastodon-mode-hook
   :context-menu '(mastodon
                   (description "Mastodon feed viewer")
                   (actions
                    ("Toots"
                     ("A" "Author" mastodon-profile--get-toot-author)
                     ("b" "Boost" mastodon-toot--boost)
                     ("c" "Toggle content" mastodon-tl--toggle-spoiler-text-in-toot)
                     ("f" "Favourite" mastodon-toot--favourite)
                     ("j" "Next" mastodon-tl--goto-next-toot)
                     ("k" "Prev" mastodon-tl--goto-prev-toot)
                     ("n" "Send" mastodon-toot)
                     ("r" "Reply" mastodon-toot--reply)
                     ("t" "Thread" mastodon-tl--thread)
                     ("u" "Update" mastodon-tl--update)
                     ("U" "Users" mastodon-profile--show-user))
                    ("Timelines"
                     ("F" "Federated" mastodon-tl--get-federated-timeline)
                     ("H" "Home" mastodon-tl--get-home-timeline)
                     ("L" "Local" mastodon-tl--get-local-timeline)
                     ("N" "Notifications" mastodon-notifications--get)
                     ("T" "Tag" mastodon-tl--get-tag-timeline))
                    ("Quit"
                     ("q" "Quit mastodon buffer. Leave window open." kill-this-buffer)
                     ("Q" "Quit mastodon buffer and kill window." kill-buffer-and-window))))))

(provide 'mastodon-discover)
;;; mastodon-discover.el ends here
