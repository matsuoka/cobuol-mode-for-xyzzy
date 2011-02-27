;;; -*- Mode: Lisp; Package: EDITOR -*-
;;;
;;;
;
; cobuol-mode
;
; MATSUOKA Hiroshi

(provide "cobuol-mode")

(in-package "editor")
(export '(
          cobuol-mode
          cobuol-expand-copy
          cobuol-fold-copy
          *cobuol-mode-keyword-file*
          *cobuol-keyword-hash-table*
          *cobuol-mode-comment-column*
          *cobuol-mode-numbering-start*
          *cobuol-mode-numbering-rate*
          *cobuol-mode-comment-char*
          *cobuol-mode-variable-start-pattern*
          *cobuol-mode-variable-end-pattern*
          *cobuol-mode-label-start-pattern*
          *cobuol-mode-label-end-pattern*
          *cobuol-mode-section-pattern*
          *cobuol-mode-copy-pattern*
          *cobuol-mode-copy-suffix-regexp*
          *cobuol-mode-copy-expand-start*
          *cobuol-mode-copy-expand-end*
          *cobuol-mode-hook*
          *cobuol-mode-copy-temp-buffer*
          *cobuol-mode-copy-foreground-color*
          *cobuol-mode-copy-background-color*
          ))

(defvar *cobuol-mode-comment-column* (- 7 1))
(defvar *cobuol-mode-numbering-start* 1000)
(defvar *cobuol-mode-numbering-rate* 100)
(defvar *cobuol-mode-comment-char* #\*)
(defvar *cobuol-mode-variable-start-pattern* "[ 　\t]*[0-9]+[ 　\t]+")
(defvar *cobuol-mode-variable-end-pattern* "[ 　\t\n.]")
(defvar *cobuol-mode-label-start-pattern* "")
(defvar *cobuol-mode-label-end-pattern* "[ 　\t\n.]")
(defvar *cobuol-mode-section-pattern* "\\([^ 　\t]*\\)[ 　\t]+SECTION[ 　\t\n.]")
(defvar *cobuol-mode-copy-pattern* "[ 　\t]*COPY[ 　\t]+\\([^ 　\t\n.]+\\)[ 　\t\n.]")
(defvar *cobuol-mode-copy-suffix-regexp* "\\.\\(cbl\\|cob\\)$")
(defvar *cobuol-mode-copy-expand-start* ">>=== cobuol-mode added ===>>")
(defvar *cobuol-mode-copy-expand-end* "<<=== cobuol-mode added ===<<")
(defvar *cobuol-mode-copy-temp-buffer* "*Cobuol:Tmp*")
(defvar *cobuol-mode-copy-foreground-color* 15)
(defvar *cobuol-mode-copy-background-color* nil)

(defvar *cobuol-completion-list* nil)
(defvar *cobuol-mode-hook* nil)
(defvar *cobuol-mode-keyword-hash-table* nil)
(defvar *cobuol-mode-keyword-file* "COBOL")
(defvar *cobuol-mode-syntax-table* nil)

(defvar *cobuol-mode-copy-temp-path-map* nil)
(defvar *cobuol-mode-saved-stacks* nil)

(unless *cobuol-mode-syntax-table*
  (setq *cobuol-mode-syntax-table* (make-syntax-table))
  (do ((x #x21 (1+ x)))((>= x #x7f))
    (let ((c (code-char x)))
      (unless (alphanumericp c)
        (set-syntax-punctuation *cobuol-mode-syntax-table* c))))
  (set-syntax-word *cobuol-mode-syntax-table* #\-)
  (set-syntax-string *cobuol-mode-syntax-table* #\")
  (set-syntax-string *cobuol-mode-syntax-table* #\')
  (set-syntax-match *cobuol-mode-syntax-table* #\( #\))
  (set-syntax-symbol *cobuol-mode-syntax-table* #\/)
  (set-syntax-comment-column *cobuol-mode-syntax-table* *cobuol-mode-comment-column*)
  (set-syntax-end-comment *cobuol-mode-syntax-table* #\LFD nil t)
  (set-syntax-option *cobuol-mode-syntax-table* *syntax-option-column-comment-char*)
  (set-syntax-start-column-comment *cobuol-mode-syntax-table* *cobuol-mode-comment-char*))

(defvar *cobuol-mode-map* nil)
(set-extended-key-translate-table exkey-C-tab #\F24)
;(unless *cobuol-mode-map*
  (setf *cobuol-mode-map* (make-sparse-keymap))
  (define-key *cobuol-mode-map* #\M-TAB 'cobuol-completion)
  (define-key *cobuol-mode-map* #\TAB 'cobuol-tab)
  (define-key *cobuol-mode-map* #\F24 'cobuol-indent)
  (define-key *cobuol-mode-map* '(#\C-c #\.) 'cobuol-comment-line)
  (define-key *cobuol-mode-map* '(#\C-c #\,) 'cobuol-decomment-line)
  (define-key *cobuol-mode-map* '(#\C-c #\=) 'cobuol-numbering)
  (define-key *cobuol-mode-map* '(#\C-c #\-) 'cobuol-denumbering)
  (define-key *cobuol-mode-map* '(#\C-c #\:) 'cobuol-comment-region)
  (define-key *cobuol-mode-map* '(#\C-c #\;) 'cobuol-decomment-region)
  (define-key *cobuol-mode-map* '(#\C-c #\LFD) 'cobuol-push-stack-jump)
  (define-key *cobuol-mode-map* '(#\C-c #\C-h) 'cobuol-pop-stack-jump)
  (define-key *cobuol-mode-map* '(#\C-c #\[) 'cobuol-section-jump-backward)
  (define-key *cobuol-mode-map* '(#\C-c #\]) 'cobuol-section-jump-forward)
  (define-key *cobuol-mode-map* '(#\C-c #\>) 'cobuol-expand-copy)
  (define-key *cobuol-mode-map* '(#\C-c #\<) 'cobuol-fold-copy)
  (define-key *cobuol-mode-map* '(#\C-c #\RET) 'cobuol-save-current-stack)  
  (define-key *cobuol-mode-map* '(#\C-c #\g) 'cobuol-jump-save-stack)
  (define-key *cobuol-mode-map* '(#\C-c #\s) 'cobuol-push-stack-search-current-word)
;  )

; save current position and stack
(defun cobuol-save-current-stack()
  (interactive)
  (when (get-buffer-file-name)
    (when (null *cobuol-mode-saved-stacks*)
      (setf *cobuol-mode-saved-stacks* (make-hash-table :test 'equal)))
    (let ((key (format nil "~A;~A"
                       (concat (pathname-name (get-buffer-file-name)) "."
                               (pathname-type (get-buffer-file-name)))
                       (current-line-number))))
      (setf (gethash key *cobuol-mode-saved-stacks*)
            (list (get-buffer-file-name)
                  (point)
                  (copy-list direct-jump-stack)))
      (message "save stack: ~A" key))))

; jump to saved stack
(defun cobuol-jump-save-stack ()
  (interactive)
  (let ((keys))
    (maphash #'(lambda (x y) (push x keys))
             *cobuol-mode-saved-stacks*)
    (let ((selected (completing-read
                     "Goto Stack: "
                     keys
                     :default nil
                     :history nil
                     :must-match t)))
      (when (and selected
                 (gethash selected *cobuol-mode-saved-stacks*))
        (let ((l (gethash selected *cobuol-mode-saved-stacks*)))
          (when
              (not 
               (path-equal
                (nth 0 l) (get-buffer-file-name)))
            (find-file (nth 0 l))
            (cobuol-mode))
          (goto-char (nth 1 l))
          (setf direct-jump-stack (nth 2 l)))
        (remhash selected *cobuol-mode-saved-stacks*)))))

; fold-copy
(defun cobuol-fold-copy ()
  (interactive)
  (save-excursion
    (goto-line 0)
    (while (scan-buffer
            *cobuol-mode-copy-expand-start*
            :no-dup t :case-fold t :regexp t)
      (delete-region
       (progn (goto-bol) (point))
       (progn (next-line) (goto-bol) (point)))
      (cobuol-decomment-line)
      (goto-eol)
      (set-mark-command)
      (let ((nest-count 1)
            (expand-regexp
             (concat "\\(" (regexp-quote *cobuol-mode-copy-expand-start*)
                     "\\|" (regexp-quote *cobuol-mode-copy-expand-end*) "\\)")))
             
        (while (and (> nest-count 0)
                    (scan-buffer expand-regexp :no-dup t :regexp t))
          (if (equal (match-string 1) *cobuol-mode-copy-expand-start*)
              (setf nest-count (+ nest-count 1))
            (setf nest-count (- nest-count 1))))
        (when (= nest-count 0)
          (goto-eol)
          (delete-region (mark) (point)))))))

; expand-copy
(defun cobuol-expand-copy (directory)
  (interactive "DDirectory: " :default0 "")
  (let ((copy-suffix-regexp
         (compile-regexp *cobuol-mode-copy-suffix-regexp* t)))
    (setf *cobuol-mode-copy-temp-path-map* (make-hash-table :test 'equal))
    (save-excursion
      (goto-char (point-min))
      (while (scan-buffer
              (concat (cobuol-search-line-prefix-regexp)
                      *cobuol-mode-copy-pattern*)
              :no-dup t :case-fold t :regexp t)
        (cobuol-find-copy-to-temp-buffer directory
                                         (match-string 1)
                                         copy-suffix-regexp)
        (when (> (buffer-size *cobuol-mode-copy-temp-buffer*) 0)
          (goto-column 0)
          (open-line)
          (dotimes (i *cobuol-mode-comment-column*)
            (insert " "))
          (insert *cobuol-mode-comment-char*)
          (insert	*cobuol-mode-copy-expand-start*)
          (next-line)
          (cobuol-comment-line)
          (goto-eol)
          (open-line)
          (next-line)
          (dotimes (i *cobuol-mode-comment-column*)
            (insert " "))
          (insert *cobuol-mode-comment-char*)
          (insert	*cobuol-mode-copy-expand-end*)
          (goto-bol)
          (open-line)
          (insert-buffer *cobuol-mode-copy-temp-buffer*)
          (set-text-attribute
           (point) (+ (point) (buffer-size *cobuol-mode-copy-temp-buffer*))
           'cobuol-mode-added
           :foreground *cobuol-mode-copy-foreground-color*
           :background *cobuol-mode-copy-background-color*
           :extend t))
        (delete-buffer *cobuol-mode-copy-temp-buffer*)))
    (setf *cobuol-mode-copy-temp-path-map* nil)))

(defun cobuol-find-copy-to-temp-buffer (dir id suffix-regexp)
  (message "searching... ~A" id)
  (save-window-excursion
    (with-output-to-temp-buffer (*cobuol-mode-copy-temp-buffer*))
    (if (and
         (gethash id *cobuol-mode-copy-temp-path-map*)
         (file-exist-p (gethash id *cobuol-mode-copy-temp-path-map*)))
        (progn
          (message "~A" (gethash id *cobuol-mode-copy-temp-path-map*))
          (insert-file (gethash id *cobuol-mode-copy-temp-path-map*)))
      (cobuol-find-recursive
       dir
       #'(lambda (x)
           (do-events)
           (if (string-match suffix-regexp x)
               (progn
                 (setf (gethash
                        (pathname-name x)
                        *cobuol-mode-copy-temp-path-map*) x)
                 t)
             nil))
         #'(lambda (x)
             (when (equal (string-downcase (pathname-name x))
                          (string-downcase id))
               (message "~A" x)
               (insert-file x)))))))

(defun cobuol-find-recursive (dir filter proc)
  (let* ((dir (append-trail-slash dir))
         (targets
          (mapcar #'(lambda (x) (concat dir x))
                  (directory dir))))
    (catch 'find-done
      (dolist (x targets t)
        (cond
         ((file-directory-p x)
          (cobuol-find-recursive x filter proc))
         ((funcall filter x)
          (funcall proc x))
         (t nil))))))

; section jump foward
(defun cobuol-section-jump-forward ()
  (interactive)
  (cobuol-section-jump nil))

; section jump backward
(defun cobuol-section-jump-backward ()
  (interactive)
  (cobuol-section-jump t))

; section jump
(defun cobuol-section-jump (reverse)
  (interactive)
  (let ((goto))
    (goto-column 0)
    (when (scan-buffer
           (concat (cobuol-search-line-prefix-regexp)
                   *cobuol-mode-section-pattern*)
           :case-fold t :reverse reverse :regexp t :no-dup t)
      (setf goto (point)))
    (if goto
        (progn
          (goto-char goto)
          (goto-column *cobuol-mode-comment-column*)
          (match-string 1))
      nil)))

; pop stack jump
(defun cobuol-pop-stack-jump ()
  (interactive)
  (let ((goto (pop direct-jump-stack)))
    (when (not (null goto))
      (goto-char goto))))

; push stack search current word
(defun cobuol-push-stack-search-current-word ()
  (interactive)
  (let* ((pattern "[ 　\t\n.]")
         (goto nil)
         (linenumber (current-line-number))
         (word
          (string-trim
           ":, 　\t\n"
           (save-excursion
             (buffer-substring
              (progn (scan-buffer pattern :reverse t :tail t :regexp t) (point))
              (progn (scan-buffer pattern :reverse nil :tail nil :regexp t) (point)))))))
    (when (not (equal word ""))
      (save-excursion
        (when (and (scan-buffer word :no-dup t)
                   (not (eq linenumber (current-line-number))))
          (setf goto (point)))))
    (when goto
      (push (point) direct-jump-stack)
      (goto-char goto)
      (goto-column *cobuol-mode-comment-column*))))


; push stack jump
(defun cobuol-push-stack-jump ()
  (interactive)
  (let* ((pattern "[ 　\t\n.]")
         (goto nil)
         (word
          (string-trim
           ":, 　\t\n"
           (save-excursion
             (buffer-substring
              (progn (scan-buffer pattern :reverse t :tail t :regexp t) (point))
              (progn (scan-buffer pattern :reverse nil :tail nil :regexp t) (point)))))))
    (when (not (equal word ""))
      (setf goto (save-excursion (cobuol-search-direct-jump word))))
    (when goto
      (push (point) direct-jump-stack)
      (goto-char goto)
      (goto-column *cobuol-mode-comment-column*))))

(defun cobuol-search-direct-jump (word)
  (interactive)
  (let* ((prefix (cobuol-search-line-prefix-regexp))
         (variable
          (concat
           *cobuol-mode-variable-start-pattern*
           word
           *cobuol-mode-variable-end-pattern*))
         (label
          (concat
           *cobuol-mode-label-start-pattern*
           word
           *cobuol-mode-label-end-pattern*))
         (goto nil))
    (goto-char (point-min))
    (when (scan-buffer (concat prefix variable) :regexp t)
      (setf goto (point)))
    (goto-char (point-min))
    (when (scan-buffer (concat prefix label) :regexp t)
      (setf goto (point)))
    goto))

(defun cobuol-search-line-prefix-regexp ()
  (let ((prefix "^"))
    (dotimes (i *cobuol-mode-comment-column*)
      (setf prefix (concat prefix ".")))
    (setf prefix (concat prefix "[^" (string *cobuol-mode-comment-char*) "]"))
    prefix))

; decomment region
(defun cobuol-decomment-region ()
  (interactive)
  (save-excursion
    (do ((max (progn
                (goto-char (region-end))
                (current-line-number)))
         (line (progn
                 (goto-char (region-beginning))
                 (current-line-number)) (1+ line)))
        ((> line max) t)
      (when (eq (goto-column *cobuol-mode-comment-column*)
                *cobuol-mode-comment-column*)
        (when (not (eolp))
          (delete-char))
        (insert " "))
      (next-line))))

; comment region
(defun cobuol-comment-region ()
  (interactive)
  (save-excursion
    (do ((max (progn
                (goto-char (region-end))
                (current-line-number)))
         (line (progn
                 (goto-char (region-beginning))
                 (current-line-number)) (1+ line)))
        ((> line max) t)
      (when (eq (goto-column *cobuol-mode-comment-column*)
                *cobuol-mode-comment-column*)
        (when (not (eolp))
          (delete-char))
        (insert *cobuol-mode-comment-char*))
      (next-line))))

; decomment line
(defun cobuol-decomment-line ()
  (interactive)
  (save-excursion
    (when (eq (goto-column *cobuol-mode-comment-column*)
              *cobuol-mode-comment-column*)
      (when (not (eolp))
        (delete-char))
      (insert " "))))

; comment line
(defun cobuol-comment-line ()
  (interactive)
  (save-excursion
    (when (eq (goto-column *cobuol-mode-comment-column*)
              *cobuol-mode-comment-column*)
      (when (not (eolp))
        (delete-char))
      (insert *cobuol-mode-comment-char*))))

; denumbering
(defun cobuol-denumbering ()
  (interactive)
  (save-excursion
    (goto-line 0)
    (do ((max (buffer-lines))
         (line 0 (1+ line)))
        ((> line max) t)
      (when (eq
             (goto-column *cobuol-mode-comment-column*)
             *cobuol-mode-comment-column*)
        (goto-bol)
        (delete-char (- *cobuol-mode-comment-column* 0))
        (insert " " (- *cobuol-mode-comment-column* 0)))
      (next-line))))

; numbering
(defun cobuol-numbering ()
  (interactive)
  (save-excursion
    (goto-line 0)
    (do ((max (buffer-lines))
         (line 0 (1+ line)))
        ((> line max) t)
      (when (eq
             (goto-column *cobuol-mode-comment-column*)
             *cobuol-mode-comment-column*)
        (goto-bol)
        (delete-char (- *cobuol-mode-comment-column* 0))
        (insert
         (format nil "~V,'0D"
                 (- *cobuol-mode-comment-column* 0)
                 (+ (* line *cobuol-mode-numbering-rate*) *cobuol-mode-numbering-start*))))
      (delete-trailing-spaces)
      (next-line))))

; indent
(defun cobuol-indent ()
  (interactive)
  (cond
   ((< (current-column) *cobuol-mode-comment-column*)
    (indent-to *cobuol-mode-comment-column*))
   ((eq (current-column) *cobuol-mode-comment-column*)
    (indent-to (+ *cobuol-mode-comment-column* 1)))
   (t
    (let (
          (goto
           (+ *cobuol-mode-comment-column* 1
              (* *tab-columns*
                 (ceiling
                  (/	(- (current-column) *cobuol-mode-comment-column*) *tab-columns*))))))
      (indent-to goto)))))

; tab
(defun cobuol-tab ()
  (interactive)
  (cond
   ((< (current-column) *cobuol-mode-comment-column*)
    (when (not
           (eq
            (goto-column *cobuol-mode-comment-column*)
            *cobuol-mode-comment-column*))
      (indent-to *cobuol-mode-comment-column*)))
   ((eq (current-column) *cobuol-mode-comment-column*)
    (when (not
           (eq
            (goto-column (+ *cobuol-mode-comment-column* 1))
            (+ *cobuol-mode-comment-column* 1)))
      (indent-to (+ *cobuol-mode-comment-column* 1))))
   (t
    (let ((goto
           (+ *cobuol-mode-comment-column* 1
              (* *tab-columns*
                 (ceiling
                  (/	(- (current-column) *cobuol-mode-comment-column*) *tab-columns*))))))
      (when (not (eq (goto-column goto) goto))
        (when (not (eq (goto-column (+ goto 1)) (+ goto 1)))
          (indent-to goto)))))))

; completion
(defun cobuol-completion ()
  (interactive)
  (or *cobuol-completion-list*
      (setf *cobuol-completion-list*
            (make-list-from-keyword-table *cobuol-mode-keyword-hash-table*))
      (return-from cobuol-completion nil))
  (let ((opoint (point)))
    (when (skip-syntax-spec-backward "w_")
      (let ((from (point)))
        (goto-char opoint)
        (do-completion from opoint :list *cobuol-completion-list*)))))

; cobuol-mode
(defun cobuol-mode ()
  (interactive)
  (kill-all-local-variables)
  (setq mode-name "cobuol")
  (setq buffer-mode 'cobuol-mode)
  (make-local-variable 'indent-tabs-mode)
  (setf indent-tabs-mode nil)
  (use-keymap *cobuol-mode-map*)
  (use-syntax-table *cobuol-mode-syntax-table*)
  (and *cobuol-mode-keyword-file*
       (null *cobuol-mode-keyword-hash-table*)
       (setq *cobuol-mode-keyword-hash-table*
             (load-keyword-file *cobuol-mode-keyword-file* t)))
  (when *cobuol-mode-keyword-hash-table*
    (make-local-variable 'keyword-hash-table)
    (setq keyword-hash-table *cobuol-mode-keyword-hash-table*))
  (make-local-variable 'direct-jump-stack)
  (setf direct-jump-stack nil)
  (run-hooks '*cobuol-mode-hook*))

