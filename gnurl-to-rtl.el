;; -*- lexical-binding: t -*-

(defun gnurl-to-rtl-braced-string ()
  (let* ((p0 (point))
	 (str (read (current-buffer)))
	 (p1 (point-marker)))
    (goto-char p1)
    (while (not (looking-back "\""))
      (forward-char -1))
    (setq p1 (point-marker))
    (goto-char p0)
    (delete-char 1)
    (while (< (point) p1)
      (cond ((looking-at-p "\\\\")
	     (delete-char 1)
	     (forward-char))
	    ((looking-at-p "\\\\\"")
	     (delete-char 1)
	     (forward-char))
	    ((forward-char))))
    (goto-char (1- p1))
    (delete-char 1)))

(defun gnurl-to-rtl-string ()
  (let* ((p0 (point))
	 (str (read (current-buffer)))
	 (p1 (point-marker)))
    (goto-char p0)
    (while (< (point) p1)
      (cond ((looking-at-p "\\\\")
	     (delete-char 1)
	     (forward-char))
	    ((forward-char))))))

(defun gnurl-to-rtl ()
  (interactive)
  (let ((hash (make-hash-table))
	conses)
    (myread hash)
    (maphash (lambda (key val)
	       (push key conses))
	     hash)
    (dolist (form conses)
      (when (eq (car-safe form) 'vector)
	(save-excursion
	  (goto-char (car (gethash form hash)))
	  (delete-region (point)
			 (+ (point) (length "(vector ")))
	  (insert "["))
	(save-excursion
	  (goto-char (1- (cdr (gethash form hash))))
	  (delete-region (point) (1+ (point)))
	  (insert "]")))))
  (goto-char (point-min))
  (while (not (eobp))
    (cond ((looking-at-p ";")
	   (myread-skip-comment))
	  ((looking-at-p "[ \t\n]")
	   (myread-skip-whitespace))
	  ((looking-at-p "[][()]")
	   (forward-char))
	  ((looking-at-p "\"{")
	   (gnurl-to-rtl-braced-string))
	  ((looking-at-p "\"")
	   (gnurl-to-rtl-string))
	  ((read (current-buffer))))))
