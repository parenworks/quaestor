(in-package #:quaestor)

;;; Writer for .ledger format files.
;;; Serializes the model back to plain-text ledger format,
;;; preserving alignment conventions.

(defgeneric write-ledger-file (ledger &optional path)
  (:documentation "Write the ledger model to a .ledger file."))

(defgeneric format-amount (amount &optional stream)
  (:documentation "Format an amount for display in ledger format."))

(defgeneric format-transaction (transaction stream &key alignment-column)
  (:documentation "Write a single transaction to the stream in ledger format."))

(defgeneric format-account-directive (account stream)
  (:documentation "Write an account directive to the stream."))

;;; --- Amount formatting ---

(defmethod format-amount ((amount amount) &optional (stream nil))
  "Format amount as '£49.99' or '-£49.99' etc."
  (let* ((commodity (amount-commodity amount))
         (symbol (if commodity
                     (or (commodity-symbol commodity) (commodity-code commodity))
                     *default-commodity-symbol*))
         (quantity (amount-quantity amount))
         (negative-p (minusp quantity))
         (abs-quantity (abs quantity)))
    (format stream "~A~A~,2F"
            (if negative-p "-" "")
            symbol
            abs-quantity)))

;;; --- Transaction formatting ---

(defmethod format-transaction ((tx transaction) stream &key (alignment-column *default-alignment-column*))
  "Write a transaction in standard ledger format."
  ;; Header line: date [=aux-date] [state] payee
  (format stream "~A~A ~A~%"
          (format-date (transaction-date tx))
          (ecase (transaction-state tx)
            (:cleared " *")
            (:pending " !")
            (:unmarked ""))
          (transaction-payee tx))
  ;; Comment lines
  (when (transaction-comment tx)
    (dolist (line (cl-ppcre:split "\\n" (transaction-comment tx)))
      (format stream "    ; ~A~%" line)))
  ;; Postings
  (dolist (posting (transaction-postings tx))
    (let* ((account-str (posting-account-path posting))
           (amount-str (when (posting-amount posting)
                         (format-amount (posting-amount posting))))
           (padding (if amount-str
                        (max 2 (- alignment-column 4 (length account-str) (length amount-str)))
                        0)))
      (format stream "    ~A~A~A~%"
              account-str
              (if amount-str
                  (make-string padding :initial-element #\Space)
                  "")
              (or amount-str ""))
      (when (posting-comment posting)
        (format stream "    ; ~A~%" (posting-comment posting))))))

;;; --- Account directive formatting ---

(defmethod format-account-directive ((account account) stream)
  (format stream "account ~A~%" (account-full-path account))
  (when (account-note account)
    (format stream "    note ~A~%" (account-note account))))

;;; --- Date formatting ---

(defun format-date (timestamp)
  "Format a local-time timestamp as YYYY/MM/DD."
  (local-time:format-timestring nil timestamp
                                :format '((:year 4) #\/ (:month 2) #\/ (:day 2))))

;;; --- File writing ---

(defmethod write-ledger-file ((ledger ledger) &optional (path (ledger-file-path ledger)))
  "Write the entire ledger to PATH. Creates a backup first."
  (unless path
    (error 'ledger-file-error :path "" :message "No file path specified"))
  ;; Create backup
  (let ((backup-path (concatenate 'string path ".bak")))
    (when (probe-file path)
      (with-open-file (in path :direction :input)
        (with-open-file (out backup-path :direction :output :if-exists :supersede)
          (loop for line = (read-line in nil nil)
                while line do (write-line line out))))))
  ;; Write the ledger
  (with-open-file (stream path :direction :output :if-exists :supersede)
    ;; Account directives
    (let ((sorted-accounts (sort (hash-table-values (ledger-accounts ledger))
                                 #'string< :key #'account-full-path)))
      ;; Group by top-level type
      (let ((current-type nil))
        (dolist (account sorted-accounts)
          ;; Only write accounts that have a note (explicit declarations)
          (when (account-note account)
            (let ((type (account-type account)))
              (unless (eq type current-type)
                (when current-type (terpri stream))
                (setf current-type type)))
            (format-account-directive account stream)
            (terpri stream)))))
    ;; Blank line separator
    (terpri stream)
    ;; Transactions
    (dolist (tx (ledger-transactions ledger))
      (format-transaction tx stream)
      (terpri stream)))
  (setf (ledger-modified-p ledger) nil)
  path)
