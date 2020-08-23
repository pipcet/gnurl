;; -*- lexical-binding: t -*-

(defun parse-define-peephole (expr hash &optional tag)
  (unless tag
    (setq tag 'define_peephole))
  (and (consp expr)
       (eq (car expr) tag)
       (let* ((rest (cdr expr))
	      plist)
	 (when (consp (car rest))
	   (setq plist (plist-put plist :pattern (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :condition (pop rest))))
	 (setq plist (plist-put plist :replacement (pop rest))))
	 (when (car rest)
	   (setq plist (plist-put plist :attribute (pop rest))))
	 ;; (cpcase (extract-operands (plist-get plist :template))
	 ;;   (`(,hash . ,template)
	 ;;    (setq plist (plist-put plist :template template))
	 ;;    (setq plist (plist-put plist :operands hash))))
	 plist))

(defun parse-define-peephole2 (expr hash &optional tag)
  (unless tag
    (setq tag 'define_peephole2))
  (and (consp expr)
       (eq (car expr) tag)
       (let* ((rest (cdr expr))
	      plist)
	 (when (consp (car rest))
	   (setq plist (plist-put plist :pattern (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :condition (pop rest))))
	 (when (consp (car rest))
	   (setq plist (plist-put plist :replacement (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :preparation (pop rest))))
	 ;; (cpcase (extract-operands (plist-get plist :template))
	 ;;   (`(,hash . ,template)
	 ;;    (setq plist (plist-put plist :template template))
	 ;;    (setq plist (plist-put plist :operands hash))))
	 plist)))

(defun find-cc-reference (plist)
  (catch 'return
    (dolist (cons (all-conses plist))
      (pcase cons
	(`(REG_CC . ,rest) (throw 'return t))
	(`(match_scratch :CC . ,rest) (throw 'return t))
	(`("cc" "none") (throw 'return t))))))

(defun parse-define-insn-and-split (expr hash &optional tag)
  (unless tag
    (setq tag 'define_insn_and_split))
  (and (consp expr)
       (eq (car expr) tag)
       (let* ((rest (cdr expr))
	      plist)
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :name (pop rest))))
	 (when (consp (car rest))
	   (setq plist (plist-put plist :template (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :condition (pop rest))))
	 (when (consp rest)
	   (setq plist (plist-put plist :assembler (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :split-condition (pop rest))))
	 (when (consp (car rest))
	   (setq plist (plist-put plist :replacement (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :preparation (pop rest))))
	 (when (consp rest)
	   (setq plist (plist-put plist :attribute (pop rest))))
	 ;; (cpcase (extract-operands (plist-get plist :template))
	 ;;   (`(,hash . ,template)
	 ;;    (setq plist (plist-put plist :template template))
	 ;;    (setq plist (plist-put plist :operands hash))))
	 (if (find-cc-reference plist)
	     nil
	   plist))))

(defun parse-define-insn (expr hash &optional tag)
  (unless tag
    (setq tag 'define_insn))
  (and (consp expr)
       (eq (car expr) tag)
       (let* ((rest (cdr expr))
	      plist)
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :name (pop rest))))
	 (when (consp (car rest))
	   (setq plist (plist-put plist :template (pop rest))))
	 (when (stringp (car rest))
	   (setq plist (plist-put plist :condition (pop rest))))
	 (when (consp rest)
	   (setq plist (plist-put plist :assembler (pop rest))))
	 (when (consp rest)
	   (setq plist (plist-put plist :attribute (pop rest))))
	 ;; (pcase (extract-operands (plist-get plist :template))
	 ;;   (`(,hash . ,template)
	 ;;    (setq plist (plist-put plist :template template))
	 ;;    (setq plist (plist-put plist :operands hash))))
	 (if (find-cc-reference plist)
	     nil
	   plist))))

(defun max-operand (expr)
  (cond
   ((consp expr)
    (max (max-operand (car expr))
	 (max-operand (cdr expr))))
   ((numberp expr)
    expr)
   (-1.0e+INF)))

(defun clobberify-cc-attr (ccattr n &optional force)
  (when ccattr
    (let ((attrs (split-string ccattr ",")))
      (if (or (equal attrs '("none"))
	      (equal attrs '("compare")))
	  nil
	(if (or force
		(= (length attrs) 1))
	    `(clobber (reg:CC REG_CC))
	  `(clobber (match_scratch:CC ,n,(concat "="
					     (mapconcat (lambda (str)
							  (if (equal str "none")
							      "X"
							    "c"))
							attrs
							",")))))))))

(defun resultify-cc-attr (ccattr operation)
  (when ccattr
    (let ((attrs (split-string ccattr ",")))
      (and (not (equal attrs '("none")))
	   (= (length attrs) 1)
	   (member (car attrs)
		   '("set_czn" "set_zn" "set_vzn" "set_n" "plus"))
	   `(set (reg:CCNZ REG_CC)
		 (compare:CCNZ ,operation (const_int 0)))))))

(defun add-clobbers (clobbered-insns)
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (let* ((plist (parse-define-insn form hash))
	     (ccattr (find-attr (plist-get plist :attribute) "cc"))
	     (templ (plist-get plist :template))
	     (n (1+ (max-operand templ)))
	     (clobber (clobberify-cc-attr ccattr n)))
	(when clobber
	  (let* ((vector1 (cadr templ))
		 (parallel (cadr vector1))
		 (insn (cadr parallel))
		 (ps (gethash insn hash))
		 (p0 (car ps))
		 (p1 (cdr ps))
		 (ind (save-excursion
			(goto-char p0)
			(- (current-column)
			   (length "(vector (parallel (vector")))))
	    (goto-char p1)
	    (insert "\n")
	    (insert (make-string ind ?\ ))
	    (insert (format "%S" clobber)))
	  (goto-char (car (gethash form hash)))
	  (forward-char 14)
	  (unless (looking-at-p "\\*")
	    (insert "*"))
	  (puthash templ t clobbered-insns))))))

(defun add-results ()
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (let* ((plist (parse-define-insn form hash))
	     (ccattr (find-attr (plist-get plist :attribute) "cc"))
	     (templ (plist-get plist :template))
	     (operation (caddr (cadr (cadr (cadr templ)))))
	     (result (resultify-cc-attr ccattr operation)))
	(when result
	  (let* ((oldstr (buffer-substring-no-properties
			  (car (gethash form hash))
			  (cdr (gethash form hash))))
		 (vector1 (cadr templ))
		 (parallel (cadr vector1))
		 (insn (cadr parallel))
		 (ps (gethash insn hash))
		 (p0 (car ps))
		 (p1 (cdr ps))
		 (ind (save-excursion
			(goto-char p0)
			(- (current-column)
			   (length "(vector (parallel (vector")))))
	    (goto-char p0)
	    (sit-for 0)
	    (insert (format "%S" result))
	    (insert "\n")
	    (insert (make-string ind ?\ ))
	    (goto-char (car (gethash form hash)))
	    (forward-char 14)
	    (unless (looking-at-p "\\*")
	      (insert "*"))
	    (goto-char (car (gethash form hash)))
	    (insert oldstr)
	    (when (not (equal oldstr ""))
	      (insert "\n\n"))))))))

(defun fix-peepholes (clobbered-insns)
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (let* ((plist (parse-define-peephole2 form hash)))
	(when plist
	  (let* ((templ (plist-get plist :template)))
	    (dolist (insn (cdr templ))
	      (when (gethash insn clobbered-insns)
		(error "peephole uses a clobbered insn")))))))))

(defun add-results-23 ()
  (goto-char (point-min))
  (while (let* ((hash (make-hash-table))
		(form (myread-single-form hash)))
	   (when form
	     (let ((str (buffer-substring (car (gethash form hash))
					  (cdr (gethash form hash)))))
	       (aset str 1 ?2)
	       (save-excursion
		 (goto-char (car (gethash form hash)))
		 (insert str)
		 (insert "\n\n"))
	       (aset str 1 ?3)
	       (save-excursion
		 (goto-char (car (gethash form hash)))
		 (insert str)
		 (insert "\n\n"))
	       t)))))

(defun fix-splitter ()
  (let* ((hash (make-hash-table))
	 (form (myread-single-form hash))
	 (plist (parse-define-insn-and-split form hash))
	 (new-insn-pattern (plist-get plist :replacement))
	 (nps (gethash new-insn-pattern hash))
	 (np0 (car nps))
	 (np1 (cdr nps))
	 (attributes (plist-get plist :attribute))
	 (ccattr (find-attr attributes "cc"))
	 (templ (plist-get plist :template))
	 (n (1+ (max-operand templ)))
	 (clobber (clobberify-cc-attr ccattr n t)))
    (if (not clobber)
	nil
      (let* ((vector1 (cadr new-insn-pattern))
	     (parallel (cadr vector1))
	     (insn (cadr parallel))
	     (ps (gethash insn hash))
	     (p0 (car ps))
	     (p1 (cdr ps))
	     (ind (save-excursion
		    (goto-char p0)
		    (- (current-column)
		       (length "(vector (parallel (vector")))))
	(goto-char p1)
	(sit-for 0)
	(insert "\n")
	(insert (make-string ind ?\ ))
	(insert (format "%S" clobber))
	t))))

(defun add-splitters ()
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (let* ((plist (parse-define-insn form hash))
	     (attrs (plist-get plist :attribute))
	     (ccattr (find-attr (plist-get plist :attribute) "cc"))
	     (templ (plist-get plist :template))
	     (ps (gethash form hash))
	     (p0 (car ps))
	     (p9 (copy-marker (1- p0)))
	     (tps (gethash templ hash))
	     (tp0 (car tps))
	     (tp1 (cdr tps))
	     (aps (gethash attrs hash))
	     (ap0 (car aps))
	     (ap1 (cdr aps)))
	(when templ
	  (goto-char p0)
	  (sit-for 0)
	  (insert (format "(define_insn_and_split %S\n"
			  (plist-get plist :name)))
	  (insert (format "  %s\n"
			  (buffer-substring-no-properties tp0 tp1)))
	  (insert (format "  %S\n" (plist-get plist :condition)))
	  (insert (format "  %S\n" "#"))
	  (insert (format "  %S\n" "reload_completed"))
	  (insert (format "  %s\n"
			  (buffer-substring-no-properties tp0 tp1)))
	  (insert (format "  %S" ""))
	  (when attrs
	    (insert (format "\n  %s" (buffer-substring-no-properties ap0 ap1))))
	  (insert ")\n\n")
	  (goto-char (1+ p9))
	  (unless (fix-splitter)
	    (delete-region (point) p0)))))))

(defun all-conses (expr)
  (if (consp expr)
      (append (list expr)
	      (all-conses (car expr))
	      (all-conses (cdr expr)))
    nil))

(defun dupify-insns ()
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (let ((hash2 (make-hash-table :test 'equal)))
	(dolist (cons (all-conses form))
	  (pcase cons
	    (`(,(or 'match_operand 'match_scratch) ,mode ,n . ,rest)
	     (if (gethash cons hash2)
		 (progn
		   (goto-char (car (gethash cons hash)))
		   (delete-region (point)
				  (cdr (gethash cons hash)))
		   (insert (format "%S"
				   (if (numberp mode)
				       `(match_dup ,mode)
				     `(match_dup ,mode ,n)))))
	       (puthash cons t hash2)))))))))

(defun make-all-insns-parallel ()
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (pcase form
	(`(,(or 'define_insn 'define_insn_and_split) ,name (vector (parallel .  ,rest1) . ,rest2) . ,rest3)
	  )
	(`(,(or 'define_insn 'define_insn_and_split) ,name ,(and subform `(vector . ,rest1)) . ,rest2)
	 (let* ((ps (gethash subform hash))
		(p0 (car ps))
		(p1 (cdr ps)))
	   (goto-char (+ p0 8))
	   (insert "(parallel (vector ")
	   (goto-char p1)
	   (insert "))")))))))

(defun make-all-insns-serial ()
  (goto-char (point-min))
  (let* ((hash (make-hash-table))
	 (forms (myread hash)))
    (dolist (form forms)
      (pcase form
	(`(,(or 'define_insn 'define_insn_and_split)
	   ,name ,(and v `(vector (parallel . ,rest1))) . ,rest2)
	 (let* ((ps (gethash v hash))
		(p0 (car ps))
		(p1 (cdr ps)))
	   (goto-char (1- p0))
	   (delete-char (length "(vector (parallel "))
 	   (goto-char (- p1 2))
	   (delete-char 2)))))))

(defun convert-rtl-buffer ()
  (let ((clobbered-insns (make-hash-table :test 'equal)))
    (make-all-insns-parallel)
    (add-splitters)
    (add-clobbers clobbered-insns)
    (add-results)
    (fix-peepholes clobbered-insns)
    (dupify-insns)
    (make-all-insns-serial)))

(defun gnurlify (filename)
  (interactive "f")
  (with-temp-buffer
    (display-buffer (current-buffer))
    (insert-file-contents filename)
    (goto-char (point-min))
    (elispify-rtl)
    (goto-char (point-min))
    (elispify-pass-2)
    (goto-char (point-min))
    (mangle-rtl-buffer)
    (convert-rtl-buffer)
    (goto-char (point-min))
    (gnurl-to-rtl)
    (write-file (concat filename ".new"))))
