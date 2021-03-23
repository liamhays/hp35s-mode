;;; hp35s-mode.el --- major mode for editing HP 35s programs

;; Copyright (C) 2020 Liam Hays

;; Author: Liam Hays <liamrhays@gmail.com>
;; Created: August 2020
;; Version: 1.4
;; Keywords: languages

;;; Change Log:
;; v1.0 - initial release
;; v1.1 - fixed many issues, added memory usage counter
;; v1.1.1 - improved code overall
;; v1.1.2 - added check for label equality between GTO/XEQ and higher LBL.
;; v1.2 - added standard export feature
;; v1.3 - added current program line print feature and updated jump with line number indexer.
;; v1.4 - added goto program line feature

;;; Code:
(defvar hp35s-mode-hook nil)

;; hp35s-find-line-with-lbl-instruction
(defvar hp35s-label-search-failed nil)

;; hp35s-jump-to-goto-line
(defvar hp35s-line-to-goto nil)
(defvar hp35s-current-line-split nil)
(defvar hp35s-label-on-goto-line nil)
    ;; stores the last line to use in hp35s-return-from-goto-line
(defvar hp35s-last-buffer-line 0)
(defvar hp35s-last-program-line 0)
    ;; used only (with hp35s-last-program-line) to print out
    ;; a helpful message in hp35s-return-from-goto-line
(defvar hp35s-last-buffer-label nil)

;; hp35s-measure-mem-usage
(defvar hp35s-buffer-mem-usage 0)

;; hp35s-export-to
(defvar hp35s-export-line-counter 1)
(defvar hp35s-export-label nil)
(defvar hp35s-export-final-text nil)

;; hp35s-import-from
(defvar hp35s-import-file nil)
(defvar hp35s-import-file-as-string nil)
(defvar hp35s-import-file-as-list '())
(defvar hp35s-import-line-counter 0)
(defvar hp35s-import-line nil)
(defvar hp35s-import-length 0)

;; hp35s-verify-one-label
(defvar hp35s-labels-found 0)
(defvar hp35s-multiple-labels-found nil)

;; hp35s-message-label-line-number
(defvar hp35s-program-line-number 0)

;; hp35s-goto-program-line
(defvar hp35s-input-line-contains-label nil)
(defvar hp35s-input-program-line 0)
(defvar hp35s-goto-program-line-last-point 0)

;; hp35s-build-line-number-index
(defvar hp35s-buffer-line-index 0)
(defvar hp35s-program-line-index 0)
(defvar hp35s-line-number-index '())

;; shared
(defvar hp35s-last-point nil)
(defvar hp35s-current-line nil)
(defvar hp35s-label-line nil)
(defvar hp35s-current-label nil)

(defun hp35s-verify-one-label ()
  "Iterate over the buffer and check if more than one line is an
   LBL instruction."
  
  (setq hp35s-labels-found 0)
  (setq hp35s-multiple-labels-found nil)
  (setq hp35s-last-point (point))

  (goto-char (point-min))
  
  (while (not (eobp))
    (if (string-match
	 "^\\(LBL\\) [A-Z]$"
	 (buffer-substring-no-properties
	  (line-beginning-position)
	  (line-end-position)))

	(setq hp35s-labels-found (1+ hp35s-labels-found)))
    (forward-line 1))

  ;; now, we can see if hp35s-labels-found is more than 1.
  (if (> hp35s-labels-found 1)
      (progn
	(setq hp35s-multiple-labels-found t)
	;; it seems we have to have this here as well as below.
	(goto-char hp35s-last-point)
	(error "File has multiple labels!")))

  (goto-char hp35s-last-point))

(defun hp35s-find-point-with-lbl-instruction ()
  "Returns the point found with the first LBL instruction in the
   buffer."
  
  (goto-char (point-min))
  
  (setq hp35s-label-search-failed nil)
  
  ;; this prints out "Search for LBL failed" on error. should be
  ;; something to document.
  (unless (search-forward "LBL " nil t)
    (progn
      (message "%s"
	       "Search for LBL failed. Does this program have a label?")
      (setq hp35s-label-search-failed t))))

(defun hp35s-extract-label-name-from-point (label-point)
  "Extract and return the string with the just the single-letter
   label from the point returned by
   hp35s-find-point-with-lbl-instruction."
  
  (replace-regexp-in-string
   "^LBL " ""
   (buffer-substring-no-properties
    (line-beginning-position label-point)
    (line-end-position label-point))))

(defun hp35s-jump-to-goto-line ()
  "Jump to line specified in GTO or XEQ instruction on current
   line, checking to make sure that the instruction is complete and
   that the label the instruction specifies is underneath the first
   label found. This function also makes sure, as its first step,
   that there is only one LBL instruction in the buffer."
  
  (interactive)
  
  (setq hp35s-last-point (point))

  ;; init everything, to reset
  (setq hp35s-label-line nil)
  (setq hp35s-line-to-goto nil)
  (setq hp35s-current-line-split nil)
  (setq hp35s-label-on-goto-line nil)

  (hp35s-build-line-number-index)
  
  ;; trim newlines and split the current line by " "
  ;;
  ;; the (buffer-substring...) stuff comes from
  ;; http://ergoemacs.org/emacs/elisp_all_about_lines.html.
  ;;
  ;; get the current line and replace newlines with nothing
  ;; then, split that string by spaces
  (setq hp35s-current-line-split
	(split-string
	 (replace-regexp-in-string
	  "\n$" ""
	  (buffer-substring-no-properties
	   (line-beginning-position)
	   (line-end-position)))
	 " "))

  ;; even though the message in the (throw) doesn't print
  ;; (inhibit-message is set non-nil), the catch means this doesn't
  ;; need cl-macs or anything.
  (catch 'hp35s-label-search-failed-error
    ;; first, check if the file has more than one label
    (hp35s-verify-one-label)

    (if hp35s-multiple-labels-found
	;; don't specify a message, because the function prints one.
	(progn
	  (setq hp35s-last-buffer-line 0)
	  (throw 'hp35s-label-search-failed-error "")))
	  
    ;(message "%s" "hp35s-jump-to-goto-line")
    ;; if the current line is split into two
    (if (and
	 (eq (length hp35s-current-line-split) 2)
	 (string-match
	  "\\(GTO\\|XEQ\\) [A-Z][0-9][0-9][0-9]"
	  (concat
	   (nth 0 hp35s-current-line-split)
	   " "
	   (nth 1 hp35s-current-line-split))))
	
	;; by here, we should have a valid GTO or XEQ instruction
	(progn
	  ;; technically, this variable is holding a point until after
	  ;; the error handler.
	  (setq hp35s-label-line
		(hp35s-find-point-with-lbl-instruction))

	  (if hp35s-label-search-failed
	      ;; If hp35s-label-search-failed, then we
	      ;; failed to get a LBL line. Return and replace the
	      ;; point.
	      (progn
		(let ((inhibit-message t))
		  (setq hp35s-last-buffer-line 0)
		  (goto-char hp35s-last-point)

		  (throw 'hp35s-label-search-failed-error
			 "search failed"))))

	  ;; we have to set this to the current line, not
	  ;; line-to-goto. That should have been obvious the first
	  ;; time.
	  (setq hp35s-last-buffer-line
		(line-number-at-pos hp35s-last-point))

	  ;; extract the label specified on the line and store it to
	  ;; hp35s-label-on-goto-line
	  (setq hp35s-label-on-goto-line
		(replace-regexp-in-string
		 "[0-9][0-9][0-9]" ""
		 (nth 1 hp35s-current-line-split)))

	  (setq hp35s-current-label
		(hp35s-extract-label-name-from-point hp35s-label-line))
	  
	  ;; now, if the label in the instruction is not equal to the
	  ;; label we searched for, die.
	  (if (not
	       (string-equal hp35s-label-on-goto-line
			     hp35s-current-label))
	       (progn
		 (goto-char hp35s-last-point)
		 (setq hp35s-last-buffer-line 0)
		 (error
		  "Label in current line does not match LBL instruction above.")
		 
		 (throw 'hp35s-label-search-failed-error "")))
	  
	  ;; now we can make hp35s-label-line actually hold a line.
	  (setq hp35s-label-line
		(line-number-at-pos hp35s-label-line))

	  ;; now, we have to locate the actual line number in the
	  ;; buffer based on the assoc list from
	  ;; hp35s-build-line-number-index.
	  
	  ;; we use the car of the rassoc search because
	  ;; hp35s-build-line-number-index creates a list with the
	  ;; keys as the buffer line and the program lines as the
	  ;; value. I could reverse these and use the cdr of the assoc
	  ;; search, but then I would have to reverse
	  ;; hp35s-message-program-line-number.
	  (setq hp35s-line-to-goto
		(car (rassoc
		      (string-to-number
		       (replace-regexp-in-string
			"[A-Z]" ""
			(nth 1 hp35s-current-line-split)))
		      hp35s-line-number-index)))

	  (setq hp35s-last-buffer-label hp35s-current-label)
		  
	  (setq hp35s-last-program-line
		(cdr (assoc
		      (line-number-at-pos hp35s-last-point)
		      hp35s-line-number-index)))
	  ;(message "%s" "hp35s-line-to-goto is %d" hp35s-line-to-goto)
	  ;; yes, you're not supposed to use goto-line. But isn't
	  ;; this function interactive?
	  (with-no-warnings
	    (goto-line hp35s-line-to-goto))
	  
	  ;; print this afterward, because "Mark set" covers it
	  ;; up. we also print (nth 1 currentlinesplit), because
	  ;; "moving to line 31" when the instruction is "GTO
	  ;; Q025" is useless.
	  ;;
	  ;(print hp35s-line-to-goto)
	  (message "moving to line %s"
		   (nth 1 hp35s-current-line-split)))
	  
    ;; in the else, we should let the user know that the
    ;; current line is not usable
    (error "Current line is not a GTO or XEQ instruction."))))

(defun hp35s-return-from-goto-line ()
  "Return back to the last GTO or XEQ instruction that was used
   to jump. This isn't list-based, so you can only go back one
   level."

  (interactive)

  (message "hp35s-last-buffer-line is %d" hp35s-last-buffer-line)
  
  (if (equal hp35s-last-buffer-line 0)
      (error "Nowhere to jump back to!")
    
    (progn
      (with-no-warnings
	(goto-line hp35s-last-buffer-line))
      
      (message "moving back to line %s%03d"
	       hp35s-last-buffer-label hp35s-last-program-line)
      ;; reset for next time
      (setq hp35s-last-buffer-line 0)
      (setq hp35s-last-buffer-label nil)
      (setq hp35s-last-program-line 0))))

(defun hp35s-measure-mem-usage ()
  "Iterate over the current buffer and estimate the memory used
   by the program, based on information from Datafile about the
   calculator."
  
  (interactive)
  
  (setq hp35s-last-point (point))

  (setq hp35s-current-line nil)
  (setq hp35s-buffer-mem-usage 0)

  (goto-char (point-min))

  (while (not (eobp))
    (setq hp35s-current-line
	  (replace-regexp-in-string
	   "\n$" ""
	   (buffer-substring-no-properties
	    (line-beginning-position)
	    (line-end-position))))

    (if (or
	 ;; look for numbers
	 ;; this regex is my own creation
	 ;"^[^A-Z#\n]+[?[e0-9.-]+,*]?/?p?i?"
	 (string-match "^[^A-Z#\n]+[?[e0-9.-]+,*]?/?p?i?"
		       hp35s-current-line)
	 
	 (string-match "^pi$" hp35s-current-line))

	  (setq hp35s-buffer-mem-usage
		;; according to the 35s report by HPCC's Datafile,
		;; numbers use 35 bytes in programs regardless of
		;; their size. from what I read, they might also use
		;; 37.
		(+ hp35s-buffer-mem-usage 35)))

    ;; look for instructions
    (if (or
	 (string-match
          "^\\(?:C\\(?:F\\|L\\(?:STK\\|VARS\\|[Ex]\\)\\)\\|DSE\\|FS\\?\\|GTO\\|I\\(?:NPUT\\|SG\\)\\|PSE\\|RCL\\(?:add\\|div\\|mul\\|sub\\)?\\|S\\(?:F\\|TO\\(?:P\\|add\\|div\\|mul\\|sub\\)?\\)\\|VIEW\\|XEQ\\)"
          hp35s-current-line)
         
         (string-match
          "^\\(\\(?:%CHG\\|/c\\|1\\(?:[/0]x\\)\\|A\\(?:BS\\|COSH?\\|RG\\|SINH?\\|TANH?\\)\\|COSH?\\|E\\(?:N\\(?:Gforw\\|TER\\)\\|[+-]\\)\\|FP\\|I\\(?:NT\\(?:G\\|div\\)\\|P\\)\\|L\\(?:ASTx\\|N\\|OG\\)\\|R\\(?:ANDOM\\|EG[TXYZ]\\|MDR\\|ND\\|down\\|up\\)\\|S\\(?:EED\\|GN\\|INH?\\)\\|TANH?\\|backENG\\|chs\\|ex\\|n\\(?:[CP]r\\)\\|rootx\\|swap\\|x\\(?:!=\\(?:[0y]\\?\\)\\|2\\|<\\(?:\\(?:=[0y]\\|[0y]\\)\\?\\)\\|=\\(?:[0y]\\?\\)\\|>\\(?:\\(?:=[0y]\\|[0y]\\)\\?\\)\\|rooty\\)\\|yx\\|[!%*+/-]\\)\\)$"
          hp35s-current-line)
         
         (string-match
          "^\\(\\(LBL [A-Z]\\)\\|\\(RTN\\)\\)$"
          hp35s-current-line)
         
         (string-match
          "^\\(\\(?:FN=\\|SOLVE\\|integralFNd\\)\\)"
          hp35s-current-line)
	 
	 (string-match
          "^\\(\\(?:E\\(?:x[2y]\\|y2\\|[xy]\\)\\|s\\(?:igma[xy]\\|[xy]\\)\\|x\\(?:barw?\\|hat\\)\\|y\\(?:bar\\|hat\\)\\|[bmnr]\\)\\)$"
          hp35s-current-line)
         
         (string-match
          "^\\(\\(?:ALL\\|DEG\\|GRAD\\|RAD\\(?:IX[,.]\\)?\\|r\\(?:adixo\\(?:ff\\|n\\)\\|thetaa\\)\\|xiy\\)\\)$"
          hp35s-current-line)

	 (string-match
	  "^\\(?:ENG\\|FIX\\|SCI\\)"
	  hp35s-current-line)
	 
         (string-match
          "^\\(\\(?:AND\\|BIN\\|DEC\\|HEX\\|N\\(?:AND\\|O[RT]\\)\\|O\\(?:CT\\|R\\)\\|XOR\\)\\)$"
          hp35s-current-line)
         
         (string-match
          "^\\(\\(?:HMSto\\|to\\(?:DEG\\|HMS\\|RAD\\|cm\\|gal\\|in\\|k[gm]\\|lb\\|mile\\|[CFl]\\)\\)\\)$"
          hp35s-current-line))
	
	;; all instructions use 3 bytes
	(setq hp35s-buffer-mem-usage
	      (+ hp35s-buffer-mem-usage 3)))
    
    ;; look for equations
    (if (string-match "^EQN .*" hp35s-current-line)
	(setq hp35s-buffer-mem-usage
	      (+ hp35s-buffer-mem-usage
		 ;; subtract the four characters "EQN "
		 (- (length hp35s-current-line) 4) 3)))
    
    (forward-line 1))

  ;; return the user to where they were and print out the total
  (goto-char hp35s-last-point)
  (message "approx. memory used: %d bytes" hp35s-buffer-mem-usage))

(defun hp35s-export-to (export-file)
  "Export the current buffer to MoHPC forum style programs, with
   line numbers, and intelligently include comments and
   whitespace."
  
  (interactive "FFile to export to: ")

  (setq hp35s-last-point (point))
  
  (setq hp35s-current-line nil)
  (setq hp35s-export-final-text nil)
  (setq hp35s-export-label nil)
  (setq hp35s-export-line-counter 1)

  (catch 'hp35s-export-error
    ;; first, check for multiple labels
    (hp35s-verify-one-label)
    
    (if hp35s-multiple-labels-found
	(let ((inhibit-message t))
	  (throw 'hp35s-export-error
		 "multiple labels")))
    
    (setq hp35s-export-label (hp35s-find-point-with-lbl-instruction))
    
    (if hp35s-label-search-failed
	(progn
	  (let ((inhibit-message t))
	    (goto-char hp35s-last-point)
	    (throw 'hp35s-export-error
		   "search failed"))))

    ;; now, we can set hp35s-export-label to actually hold the label,
    ;; because the point is valid.
    (setq hp35s-export-label
	  (hp35s-extract-label-name-from-point
	   hp35s-export-label))
    
    ;; this has to be after the label finder.
    (goto-char (point-min))
  
    (while (not (eobp))
      (setq hp35s-current-line
	    (buffer-substring-no-properties
	     (line-beginning-position)
	     (line-end-position)))
      
      (if (not
	   ;; blank line handler; regex comes from
	   ;; https://stackoverflow.com/a/3012832
	   ;; ignore blank lines
	   (string-match "^\s*$"
			 hp35s-current-line))
	  
	  ;; by here, the line should be a program line, and we can
	  ;; append it to the file with the counter.
	  (progn
	    (if (string-match "^#.*" hp35s-current-line)
		(progn
		  ;; now we just send the comment through unfiltered
		  (setq hp35s-export-final-text
			(concat
			 hp35s-export-final-text
			 hp35s-current-line
			 "\n")))
	      
	      ;; otherwise, add the prefix. the increment is in the else
	      (setq hp35s-export-final-text
		    (concat
		     hp35s-export-final-text
		     hp35s-export-label
		     (format "%03d " hp35s-export-line-counter)
		     hp35s-current-line
		     "\n"))
	      
	      (setq hp35s-export-line-counter
		    (1+ hp35s-export-line-counter)))))
      
      (forward-line 1))
    (write-region hp35s-export-final-text nil export-file)
    (goto-char hp35s-last-point)))

;; from http://ergoemacs.org/emacs/elisp_read_file_content.html, and
;; modified a little by me to follow elisp convention.
(defun hp35s-get-string-from-file (file-path)
  "Return file-path's file content."
  (with-temp-buffer
    (insert-file-contents file-path)
    (buffer-string)))

(defun hp35s-filter-line-numbers (line)
  ;(message "hp35s-filter-line-numbers: line is %s" line)
  ;; filter out all line numbers
  (replace-regexp-in-string
   ;; this has to have a capturing group (maybe I should have
   ;; seen that the first time)
   "^\\([A-Z]?[0-9][0-9]?[0-9]?\s*\\)"
   ""
   line))

(defun hp35s-strip-whitespace-from-end-of-line (line)
  (car (split-string
	hp35s-import-line)))

(defun hp35s-import-from (import-file)
  "Import a MoHPC Forum style program in place, filtering it to
   match hp35s-mode syntax and style."

  (interactive "fFile to import from: ")

  (setq hp35s-import-file-as-string nil)
  (setq hp35s-import-file-as-list '())
  (setq hp35s-import-line-counter 0)
  (setq hp35s-import-line nil)
  (setq hp35s-string-counter 0)

  ;(setq import-file (read-file-name "File to import from: "))
  (setq hp35s-import-file-as-string
	(hp35s-get-string-from-file import-file))

  (setq hp35s-import-file-as-list
	(delete "" (split-string hp35s-import-file-as-string "\n")))

  (setq hp35s-import-length
	(length hp35s-import-file-as-list))

  ;; has to be <, not <=, because elisp is 1-indexed.
  (while (< hp35s-import-line-counter hp35s-import-length)
    (setq hp35s-import-line
	  (nth hp35s-import-line-counter
	       hp35s-import-file-as-list))

    ;; filter out semicolons (comments) alone on a line and keep them
    ;; there
    (if (string-match "^;.*" hp35s-import-line)
	(progn
	  (insert (concat
		   (replace-regexp-in-string
		    ";"
		    "#"
		    hp35s-import-line)
		   "\n"))
	  
	  ;; delete so that it isn't there for the next run
	  (setq hp35s-import-file-as-list
		(delete hp35s-import-line hp35s-import-file-as-list))
	  
	  ;; redefine to prevent nils and empties from coming through.
	  (setq hp35s-import-length
		(length hp35s-import-file-as-list)))

      ;;comments on ends of lines: "(?:[\s;a-z]);.+"
      
      ;; else if: semicolon on line with other stuff
      (if (string-match "^.*;.*$" hp35s-import-line)
	  (progn
	    (message "got comment on end of line")
	    (let ((comment (concat
		     "#"
		     (nth 1 (split-string
			     hp35s-import-line
			     ";"))
		     "\n")))
	      
	      (insert comment)
	      (message "end-of-line comment is %s" comment))

	    (insert (concat
		     (hp35s-filter-line-numbers
		      (nth 0 (split-string
			      hp35s-import-line
			      ";")))
		      "\n"))
	    
	    (setq hp35s-import-file-as-list
		  (delete hp35s-import-line hp35s-import-file-as-list))
	    
	    (setq hp35s-import-length
		  (length hp35s-import-file-as-list)))
	    
	;; finally, if neither of the above conditions are met.
	(setq hp35s-import-line
	      (hp35s-filter-line-numbers hp35s-import-line))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(x^2\\)" "x2"
	       hp35s-import-line))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(e^x\\)" "ex"
	       hp35s-import-line))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(10^x\\)" "10x"
	       hp35s-import-line))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(10^x\\)" "10x"
	       hp35s-import-line))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(x<>y\\)" "swap"
	       hp35s-import-line))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(+/-\\)" "chs"
	       hp35s-import-line))

	;; the ts (t's? ts'?) here mean "don't do anything to the case
	;; of the replacement, just put it there as specified"
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(STO\\)\\+" "STOadd"
	       hp35s-import-line t))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(STO\\)-" "STOsub"
	       hp35s-import-line t))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(STO\\)\\*" "STOmul"
	       hp35s-import-line t))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(STO\\)/" "STOdiv"
	       hp35s-import-line t))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(RCL\\)\\+" "RCLadd"
	       hp35s-import-line t))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(RCL\\)-" "RCLsub"
	       hp35s-import-line t))
	
	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(RCL\\)\\*" "RCLmul"
	       hp35s-import-line t))

	(setq hp35s-import-line
	      (replace-regexp-in-string
	       "\\(RCL\\)/" "RCLdiv"
	       hp35s-import-line t))
	
	(insert (concat
		 hp35s-import-line
		 "\n"))
	
	(setq hp35s-import-line-counter
	      (1+ hp35s-import-line-counter))))))
    
(defun hp35s-build-line-number-index ()
  "Iterate over the buffer and build an index of line numbers in
   the program to line numbers in the buffer. This is to be used
   within other functions."
  
  (setq hp35s-buffer-line-index 0)
  (setq hp35s-program-line-index 0)
  (setq hp35s-line-number-index '())
  (setq hp35s-current-line nil)
  
  (setq hp35s-last-point (point))
  
  (goto-char (point-min))
  
  (while (not (eobp))
    (setq hp35s-current-line
	  (buffer-substring-no-properties
	   (line-beginning-position)
	   (line-end-position)))
    
    (setq hp35s-buffer-line-index
	  (1+ hp35s-buffer-line-index))

    (if (not
	 (or
	  (string-match "^#.*$" hp35s-current-line)
	  (string-match "^\s*$" hp35s-current-line)))
	
	(progn
	  (setq hp35s-program-line-index (1+ hp35s-program-line-index))
	  ;; append, add-to-list doesn't work.
	  (setq hp35s-line-number-index
		;; must be buffer-line then program-line, because
		;; assoc only works on keys.
		(push
		 (cons hp35s-buffer-line-index
		       hp35s-program-line-index)
		 hp35s-line-number-index))))
    
    (forward-line 1))
  
  (goto-char hp35s-last-point))

(defun hp35s-message-program-line-number ()
  "Print out the current program line number relative to the
   first LBL for use in GTO or XEQ instructions. This is
   different than the line number in the buffer, because this
   isn't affected by comments."
  
  (interactive)

  ;; build it for use
  (hp35s-build-line-number-index)

  (setq hp35s-last-point (point))
  
  (catch 'hp35s-message-line-error
    (setq hp35s-label-line (hp35s-find-point-with-lbl-instruction))
    
    (if hp35s-label-search-failed
	(progn
	  (message "%s"
	   "Search for LBL failed. Does this program have a label?")
	  
	  (let ((inhibit-message t))
	    (goto-char hp35s-last-point)
	    (throw 'hp35s-message-line-error
		   "search failed"))))

    (setq hp35s-label-line
	  (hp35s-extract-label-name-from-point
	   hp35s-label-line))
    
    (goto-char hp35s-last-point)

    (setq hp35s-program-line-number
	  (cdr (assoc
		(line-number-at-pos (point))
		hp35s-line-number-index)))

    ;; only print if not nil.
    (if (not (equal hp35s-program-line-number nil))
	(message "on line %s%03d"
		 hp35s-label-line
		 (cdr (assoc
		       (line-number-at-pos (point))
		       hp35s-line-number-index)))
      
      ;; otherwise, print out a helpful message
      (error "Current line is blank or a comment."))))

(defun hp35s-goto-program-line (line)
  "Prompt for a line to go to and run the same checks as in other
   functions. If the letter in the line is present (it is
   optional), then it doesn't have to be capital."
  
  (interactive "sLine to go to: ")

  ;; capitalize for convience (and possibly a bit of speed)
  (setq line (upcase line))
  (setq hp35s-goto-program-line-last-point (point))
  (setq hp35s-input-line-contains-label nil)
  (hp35s-build-line-number-index)
  
  (catch 'hp35s-goto-error
    (if (not (string-match "^[A-Z]?[0-9]+" line))
	(progn
	  (error "Invalid line")
	  (throw 'hp35s-goto-error "")))

    (setq hp35s-label-line
	  (hp35s-find-point-with-lbl-instruction))

    (if hp35s-label-search-failed
	(progn
	  (error
	   "Search for LBL failed. Does this program have a label?")
	  (goto-char hp35s-goto-program-line-last-point)
	  (throw 'hp35s-goto-error "")))
    
    ;; check if the input line as a letter
    (if (string-match "[A-Z][0-9]+" line)
	(setq hp35s-input-line-contains-label t))
	
    (hp35s-verify-one-label)
    
    (if hp35s-multiple-labels-found
	;; verify-one-label has its own error mesage
	(throw 'hp35s-goto-error ""))

    (setq hp35s-current-label
	  (hp35s-extract-label-name-from-point hp35s-label-line))

    (if (and
	 hp35s-input-line-contains-label
	 (not (equal
	       (replace-regexp-in-string "[0-9]+" "" line)
	       hp35s-current-label)))
	
	(progn
	  (goto-char hp35s-goto-program-line-last-point)
	  (error "Label in file is not the same as specified label")
	  (throw 'hp35s-goto-error "")))

    (setq hp35s-input-program-line
	  (car (rassoc
		(string-to-number
		 (replace-regexp-in-string "[A-Z]" "" line))
		hp35s-line-number-index)))

    ;(message "hp35s-current-label is %s" hp35s-current-label)
    (if (equal hp35s-input-program-line nil)
	(progn
	  (goto-char hp35s-goto-program-line-last-point)
	  (error "Input line exceeds buffer length"))
      
      (with-no-warnings
	(goto-line hp35s-input-program-line))
      
      (message "moving to line %s%03d"
	       hp35s-current-label
	       (string-to-number
		(replace-regexp-in-string "[A-Z]" "" line))))))

(defvar hp35s-mode-font-lock-keywords nil
  "Font-lock keywords for hp35s-mode")

(setq hp35s-mode-font-lock-keywords
      '(
	;; this must go first
        ;; standard # for one-line comments
        ("^#.*" . font-lock-comment-face)
        ;; when flag 10 is set, equations are pretty much strings
        ("^\\(EQN\\).*$" . font-lock-string-face)
        ;; this must also be before other keywords
        ;; line numbers
        (" [A-Z][0-9][0-9][0-9]" . font-lock-function-name-face)
        ;; LBLs and RTNs are special, let's make them stand out
        ("^LBL [A-Z]$" . font-lock-function-name-face)
        ("^RTN$" . font-lock-function-name-face)
        ;; non-number-related keywords
        ("^\\(?:C\\(?:F\\|L\\(?:STK\\|VARS\\|[Ex]\\)\\)\\|DSE\\|FS\\?\\|GTO\\|I\\(?:NPUT\\|SG\\)\\|PSE\\|RCL\\(?:add\\|div\\|mul\\|sub\\)?\\|S\\(?:F\\|TO\\(?:P\\|add\\|div\\|mul\\|sub\\)?\\)\\|VIEW\\|XEQ\\)" . font-lock-keyword-face)
        ;; math keywords without arguments
        ;; note that the entire thing is wrapped in ^()$
        ("^\\(\\(?:%CHG\\|/c\\|1\\(?:[/0]x\\)\\|A\\(?:BS\\|COSH?\\|RG\\|SINH?\\|TANH?\\)\\|COSH?\\|E\\(?:N\\(?:Gforw\\|TER\\)\\|[+-]\\)\\|FP\\|I\\(?:NT\\(?:G\\|div\\)\\|P\\)\\|L\\(?:ASTx\\|N\\|OG\\)\\|R\\(?:ANDOM\\|EG[TXYZ]\\|MDR\\|ND\\|down\\|up\\)\\|S\\(?:EED\\|GN\\|INH?\\)\\|TANH?\\|backENG\\|chs\\|ex\\|n\\(?:[CP]r\\)\\|rootx\\|swap\\|x\\(?:!=\\(?:[0y]\\?\\)\\|2\\|<\\(?:\\(?:=[0y]\\|[0y]\\)\\?\\)\\|=\\(?:[0y]\\?\\)\\|>\\(?:\\(?:=[0y]\\|[0y]\\)\\?\\)\\|rooty\\)\\|yx\\|[!%*+/-]\\)\\)$" . font-lock-keyword-face)
        ;; math functions with arguments
        ;; note: anchored to beginning of line
        ("^\\(\\(?:FN=\\|SOLVE\\|integralFNd\\)\\)" . font-lock-keyword-face)
	;; special thing (yes really)
	;; anchored
	("^\\(x<>\\)" . font-lock-keyword-face)
	
        ;; stat registers
	;; also anchored
        ("^\\(\\(?:E\\(?:x[2y]\\|y2\\|[xy]\\)\\|s\\(?:igma[xy]\\|[xy]\\)\\|x\\(?:barw?\\|hat\\)\\|y\\(?:bar\\|hat\\)\\|[bmnr]\\)\\)$" . font-lock-keyword-face)
        ;; display modes
        ;; anchored
        ("^\\(\\(?:ALL\\|DEG\\|GRAD\\|RAD\\(?:IX[,.]\\)?\\|r\\(?:adixo\\(?:ff\\|n\\)\\|thetaa\\)\\|xiy\\)\\)$" . font-lock-keyword-face)
	;; display modes with argument
	;; anchored
	("^\\(?:ENG\\|FIX\\|SCI\\)" . font-lock-keyword-face)
        ;; base modes
        ;; anchored
        ("^\\(\\(?:AND\\|BIN\\|DEC\\|HEX\\|N\\(?:AND\\|O[RT]\\)\\|O\\(?:CT\\|R\\)\\|XOR\\)\\)$" . font-lock-keyword-face)
        ;; unit conversions
        ;; anchored
        ("^\\(\\(?:HMSto\\|to\\(?:DEG\\|HMS\\|RAD\\|cm\\|gal\\|in\\|k[gm]\\|lb\\|mile\\|[CFl]\\)\\)\\)$" . font-lock-keyword-face)
        ;; actual special base numbers and normal numbers, including e
        ;; and negatives. we need both this one and the lower one.
        ;; specially generated by me
        ("[e0-9.-]+[dhob]*$" . font-lock-builtin-face)
        ;; pi and i as constants (must be later, after keywords)
        ;; pi can only exist on a line by itself
        ("^pi$" . font-lock-constant-face)
        ;; i can be anywhere (theta can only be in between numbers,
        ;; though, so this solution isn't perfect.)
        ("i" . font-lock-constant-face)
        ("theta" . font-lock-constant-face)
        ;; numbers and vectors (now with fractions!)
        ("[?[e0-9.-]+,*]?/?" . font-lock-builtin-face)
        ;; variable names
        ;; I added the dollar sign at the end, it does matter
        ("\\(?: \\(?:\\(?:(\\(?:[IJ])\\)\\|[A-Z]\\)\\)\\)$" . font-lock-variable-name-face)))

;; there's no reason not to inherit this syntax table. It already has
;; whitespace and vector brackets.
(defvar hp35s-mode-syntax-table nil)
(setq hp35s-mode-syntax-table
      (make-syntax-table text-mode-syntax-table))

(defvar hp35s-mode-map nil "Keymap for `hp35s-mode`")
(setq hp35s-mode-map (make-sparse-keymap))
(define-key hp35s-mode-map (kbd "C-c C-j") 'hp35s-jump-to-goto-line)
(define-key hp35s-mode-map (kbd "C-c C-b") 'hp35s-return-from-goto-line)
(define-key hp35s-mode-map (kbd "C-c C-u") 'hp35s-measure-mem-usage)
(define-key hp35s-mode-map (kbd "C-c i")   'hp35s-import-from)
(define-key hp35s-mode-map (kbd "C-c C-e") 'hp35s-export-to)
(define-key hp35s-mode-map (kbd "C-c C-c")
  'hp35s-message-program-line-number)
(define-key hp35s-mode-map (kbd "C-c C-n") 'hp35s-goto-program-line)

(easy-menu-define hp35s-mode-menu hp35s-mode-map
  "Menu for HP 35s mode."
  '("HP 35s"
    ["Jump to line in GTO/XEQ instruction"
     hp35s-jump-to-goto-line
     :help "Go to the line specified by GTO or XEQ instruction on current line"]
    
    ["Return to last line jumped from "
     hp35s-return-from-goto-line
     :help "Return to the last line where C-c C-j was pressed"]
    
    ["Print line number of current line relative to top"
     hp35s-message-program-line-number
     :help "Print the line number of the current instruction in the program (like N004)"]

    ["Goto line in program relative to first label"
     hp35s-goto-program-line
     ;; don't really need any :help here
     ]
    
    ["--" 'ignore]
    
    ["Estimate memory usage"
     hp35s-measure-mem-usage
     :help "Iterate over buffer and estimate memory usage"]
    
    ["--" 'ignore]

    ["Import MoHPC Forum format program into buffer"
     hp35s-import-from
     :help "Import a file containing a MoHPC Forum style program and convert it to hp35s-mode style formatting"]
    
    ["Export to MoHPC Forum format (as .txt)"
     hp35s-export-to
     :help "Export the current buffer into plain text in a format like the forum or the calculator screen"]))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.hp35s\\'" . hp35s-mode))

(define-derived-mode hp35s-mode fundamental-mode
  "HP 35s"
  "Major mode for editing HP 35s programs"
  ;; define-derived-mode detects hp35s-mode-map
  (set-syntax-table hp35s-mode-syntax-table)
  ;; need to define these to make M-q work
  (setq comment-start "#")
  (setq comment-end "")
  (setq comment-start-skip "^#.*$")
  (setq font-lock-defaults '(hp35s-mode-font-lock-keywords)))

(provide 'hp35s-mode)

;; these are the regexp-opt functions I used to make most of the
;; font-lock expressions

;; (regexp-opt '("CF" "SF" "FS?" "CLSTK" "CLx" "CLVARS" "DSE"
;; 	      "CLE" "GTO" "INPUT" "ISG" "PSE" "RCL" 
;; 	      "STO" "STOP" "VIEW" "XEQ" "STOadd" "STOsub"
;;  	      "STOmul" "STOdiv" "RCLadd" "RCLsub" "RCLmul" "RCLdiv"))

;; (regexp-opt '(
;; 	      "x!=y?" "x<=y?" "x<y?" "x>y?" "x>=y?" "x=y?"
;; 	      "x!=0?" "x<=0?" "x<0?" "x>0?" "x>=0?" "x=0?"
;; 	      "Rdown" "Rup" "swap" "ARG" "SIN"
;; 	      "ASIN" "COS" "ACOS" "TAN" "ATAN" "SINH"
;; 	      "COSH" "TANH" "ASINH" "ACOSH" "ATANH" "rootx"
;; 	      "x2" "xrooty" "yx" "LOG" "LN" "1/x" "10x" "ex"
;; 	      "ENTER" "LASTx" "ABS" "RND" "ENGforw" "backENG"
;; 	      "nCr" "nPr" "/" "*" "-" "+" "E+"
;; 	      "E-" "!" "/c" "RANDOM" "SEED" "%CHG" "%" "SGN"
;; 	      "INTdiv" "RMDR" "INTG" "FP" "IP" "chs"
;; 	      "REGX" "REGY" "REGT" "REGZ"))

;; math functions that take arguments
;; (regexp-opt '(
;; 	      "integralFNd" "FN=" "SOLVE" ))

;; stat registers, all keywords
;; (regexp-opt '(
;; 	      "n" "Ex" "Ey" "Ex2" "Ey2" "Exy" ;; sums
;; 	      "xbar" "ybar" "xbarw"           ;; averages
;; 	      "sx" "sy" "sigmax" "sigmay"     ;; standard deviation
;; 	      "xhat" "yhat" "r" "m" "b"       ;; linear regression
;; 	      ))

;; display modes with arguments
;; (regexp-opt '(
;; 	      "FIX" "SCI" "ENG"))

;; display modes and trig modes
;; (regexp-opt '(
;; 	      "ALL" ;; decimal modes
;; 	      "RADIX." "RADIX,"       ;; radix
;; 	      "radixon"  "radixoff"   ;; show radix, shown
;; 	      ;; as 1,000 and 100 on calc
;; 	      "xiy" "rthetaa" ;; im display modes
;; 	      "DEG" "RAD" "GRAD" ;; trig modes
;; 	      ))

;; special bases
;; (regexp-opt '(
;; 	      "DEC" "HEX" "OCT" "BIN" ;; base modes	      
;; 	      "AND" "XOR" "OR" "NOT" "NAND" "NOR" ;; logic
;; 	      ))

;; "d" "h" "o" "b"
;; will be seperate, anchored to end of line with numbers before
;; should become "[e0-9\.\-]+[dhob]$"

;; conversion functions
;; (regexp-opt '(
;; 	      "toF" "toC" "HMSto" "toHMS" "toRAD" "toDEG"
;; 	      "tolb" "tokg" "tomile" "tokm" "toin" "tocm"
;; 	      "togal" "tol"))

;;; hp35s-mode.el ends here
