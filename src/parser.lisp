(in-package #:quaestor)

;;; Parser for .ledger format files.
;;; Reads a file into the Quaestor model, handling account directives,
;;; transactions, postings, comments, and tags.

(defvar *parse-line-number* 0)

(defgeneric parse-ledger-file (path)
  (:documentation "Parse a .ledger file and return a populated ledger instance."))

(defgeneric parse-amount-string (string)
  (:documentation "Parse an amount string like '£49.99' or '49.99 GBP' into an amount."))

;;; --- Amount parsing ---

(defmethod parse-amount-string ((string string))
  "Parse amount strings in formats: £49.99, -£49.99, 49.99 GBP, -49.99"
  (let ((trimmed (string-trim '(#\Space #\Tab) string)))
    (when (zerop (length trimmed))
      (return-from parse-amount-string nil))
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings
         "^(-?)\\s*([£$€]?)\\s*([0-9,]+\\.?[0-9]*)\\s*([A-Z]{3})?$"
         trimmed)
      (declare (ignore match))
      (when groups
        (let* ((negative-p (string= (aref groups 0) "-"))
               (symbol (aref groups 1))
               (number-str (remove #\, (aref groups 2)))
               (code (aref groups 3))
               (quantity (let ((*read-eval* nil))
                           (read-from-string number-str))))
          (when negative-p
            (setf quantity (- quantity)))
          (make-instance 'amount
                         :quantity (rationalize quantity)
                         :commodity (when (or (plusp (length symbol))
                                             code)
                                     (make-instance 'commodity
                                                    :code (or code
                                                              (cond ((string= symbol "£") "GBP")
                                                                    ((string= symbol "$") "USD")
                                                                    ((string= symbol "€") "EUR")
                                                                    (t "???")))
                                                    :symbol (when (plusp (length symbol))
                                                              symbol)))))))))

;;; --- Line classification ---

(defun blank-line-p (line)
  (every (lambda (c) (member c '(#\Space #\Tab))) line))

(defun comment-line-p (line)
  (let ((trimmed (string-trim '(#\Space #\Tab) line)))
    (and (plusp (length trimmed))
         (char= (char trimmed 0) #\;))))

(defun account-directive-p (line)
  (starts-with-subseq "account " line))

(defun transaction-header-p (line)
  "Check if a line starts with a date (YYYY/MM/DD or YYYY-MM-DD)."
  (and (>= (length line) 10)
       (cl-ppcre:scan "^\\d{4}[/-]\\d{2}[/-]\\d{2}" line)))

(defun posting-line-p (line)
  "Check if a line is indented (starts with whitespace) and not a comment-only line."
  (and (plusp (length line))
       (member (char line 0) '(#\Space #\Tab))
       (not (blank-line-p line))))

;;; --- Transaction header parsing ---

(defun parse-transaction-header (line)
  "Parse a transaction header line. Returns (values date state payee)."
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings
       "^(\\d{4}[/-]\\d{2}[/-]\\d{2})(?:=(\\d{4}[/-]\\d{2}[/-]\\d{2}))?\\s+([*!])?\\s*(.*?)\\s*$"
       line)
    (declare (ignore match))
    (when groups
      (let ((date-str (aref groups 0))
            (aux-date-str (aref groups 1))
            (state-char (aref groups 2))
            (payee (aref groups 3)))
        (values (parse-date-string date-str)
                (cond ((equal state-char "*") :cleared)
                      ((equal state-char "!") :pending)
                      (t :unmarked))
                payee
                (when aux-date-str (parse-date-string aux-date-str)))))))

(defun parse-date-string (str)
  "Parse YYYY/MM/DD or YYYY-MM-DD into a local-time timestamp."
  (let* ((normalized (substitute #\- #\/ str))
         (parts (cl-ppcre:split "-" normalized))
         (year (parse-integer (first parts)))
         (month (parse-integer (second parts)))
         (day (parse-integer (third parts))))
    (local-time:encode-timestamp 0 0 0 0 day month year)))

;;; --- Posting parsing ---

(defun parse-posting-line (line)
  "Parse a posting line. Returns a posting instance."
  (let* ((trimmed (string-trim '(#\Space #\Tab) line))
         (comment nil)
         (content trimmed))
    ;; Extract inline comment
    (when-let (pos (position #\; content))
      (setf comment (string-trim '(#\Space #\Tab) (subseq content (1+ pos))))
      (setf content (string-trim '(#\Space #\Tab) (subseq content 0 pos))))
    ;; Split into account and amount
    ;; Account ends where we find two or more spaces followed by amount, or EOL
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings "^(\\S+(?:\\S| (?! ))*)(?:\\s{2,}(.+))?$" content)
      (declare (ignore match))
      (when groups
        (let ((account-path (string-trim '(#\Space #\Tab) (aref groups 0)))
              (amount-str (aref groups 1)))
          (make-instance 'posting
                         :account-path account-path
                         :amount (when amount-str
                                   (parse-amount-string amount-str))
                         :comment comment))))))

;;; --- Main parser ---

(defmethod parse-ledger-file ((path pathname))
  (parse-ledger-file (namestring path)))

(defmethod parse-ledger-file ((path string))
  "Parse the ledger file at PATH, returning a fully populated ledger instance."
  (unless (probe-file path)
    (error 'file-error :path path :message "File does not exist"))
  (let ((ledger (make-instance 'ledger :file-path path))
        (lines (with-open-file (stream path :direction :input)
                 (loop for line = (read-line stream nil nil)
                       while line collect line)))
        (current-tx nil)
        (current-comment nil))
    (setf *parse-line-number* 0)
    (labels ((flush-transaction ()
               (when current-tx
                 (when current-comment
                   (setf (transaction-comment current-tx)
                         (format nil "~{~A~^~%~}" (nreverse current-comment))))
                 (push current-tx (ledger-transactions ledger))
                 (setf current-tx nil
                       current-comment nil)))
             (process-account-directive (line)
               (let ((path (string-trim '(#\Space #\Tab)
                                        (subseq line (length "account ")))))
                 (ensure-account ledger path)))
             (process-account-note (line account-path)
               (when-let (acct (find-account ledger account-path))
                 (let ((trimmed (string-trim '(#\Space #\Tab) line)))
                   (when (starts-with-subseq "note " trimmed)
                     (setf (account-note acct)
                           (subseq trimmed (length "note "))))))))
      (let ((last-account-path nil))
        (dolist (line lines)
          (incf *parse-line-number*)
          (cond
            ;; Blank line - flush current transaction
            ((blank-line-p line)
             (flush-transaction)
             (setf last-account-path nil))
            ;; Account directive
            ((account-directive-p line)
             (flush-transaction)
             (setf last-account-path (string-trim '(#\Space #\Tab)
                                                  (subseq line (length "account "))))
             (process-account-directive line))
            ;; Indented line following an account directive (note etc.)
            ((and last-account-path (posting-line-p line)
                  (not current-tx))
             (process-account-note line last-account-path))
            ;; Transaction header
            ((transaction-header-p line)
             (flush-transaction)
             (setf last-account-path nil)
             (multiple-value-bind (date state payee aux-date)
                 (parse-transaction-header line)
               (setf current-tx (make-instance 'transaction
                                               :date date
                                               :state state
                                               :payee payee
                                               :aux-date aux-date
                                               :line-number *parse-line-number*))))
            ;; Comment line within a transaction
            ((and current-tx (comment-line-p line))
             (push (string-trim '(#\Space #\Tab #\;) line) current-comment))
            ;; Posting line within a transaction
            ((and current-tx (posting-line-p line))
             (when-let (posting (parse-posting-line line))
               (push posting (transaction-postings current-tx))))
            ;; Top-level comment (not in a transaction)
            ((comment-line-p line)
             (setf last-account-path nil))
            ;; Anything else (includes, commodities, etc.) - store as preamble
            (t
             (setf last-account-path nil)
             (push line (ledger-preamble ledger)))))))
    ;; Flush last transaction
    (when current-tx
      (push current-tx (ledger-transactions ledger)))
    ;; Reverse to preserve file order
    (setf (ledger-transactions ledger) (nreverse (ledger-transactions ledger)))
    (setf (ledger-preamble ledger) (nreverse (ledger-preamble ledger)))
    ;; Reverse posting order within each transaction
    (dolist (tx (ledger-transactions ledger))
      (setf (transaction-postings tx) (nreverse (transaction-postings tx))))
    ;; Resolve posting account references
    (dolist (tx (ledger-transactions ledger))
      (dolist (posting (transaction-postings tx))
        (let ((path (posting-account-path posting)))
          (ensure-account ledger path)
          (setf (posting-account posting) (find-account ledger path)))))
    (setf (ledger-modified-p ledger) nil)
    ledger))
