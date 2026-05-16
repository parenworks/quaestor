(in-package #:quaestor)

;;; Engine: business logic for transaction validation, auto-balancing,
;;; searching, filtering, and reporting.

;;; --- Validation ---

(defgeneric validate-transaction (transaction)
  (:documentation "Check that a transaction is valid. Signals conditions on failure."))

(defmethod validate-transaction ((tx transaction))
  "Validate that postings balance to zero. Auto-fill one nil-amount posting."
  (let* ((postings (transaction-postings tx))
         (nil-postings (remove-if #'posting-amount postings))
         (valued-postings (remove-if-not #'posting-amount postings)))
    ;; At most one posting may have a nil amount
    (when (> (length nil-postings) 1)
      (error 'validation-error
             :transaction tx
             :message "More than one posting without an amount"))
    ;; Compute sum of valued postings
    (let ((sum (reduce #'amount-add
                       (mapcar #'posting-amount valued-postings)
                       :initial-value (make-instance 'amount :quantity 0))))
      (cond
        ;; One nil posting: auto-balance it
        ((= (length nil-postings) 1)
         (setf (posting-amount (first nil-postings))
               (amount-negate sum)))
        ;; All postings valued: check balance
        ((not (amount-zero-p sum))
         (error 'unbalanced-transaction
                :transaction tx
                :difference sum
                :message (format nil "Transaction ~S does not balance"
                                 (transaction-payee tx))))))))

;;; --- Filtering ---

(declaim (ftype (function ((integer 1) (integer 1 12))
                          (values local-time:timestamp local-time:timestamp))
                month-date-range))
(defun month-date-range (year month)
  "Return (values from to) timestamps for the first and last instant of a given month."
  (let ((from (local-time:encode-timestamp 0 0 0 0 1 month year))
        (to (local-time:encode-timestamp 0 59 59 23
                                         (local-time:days-in-month month year)
                                         month year)))
    (values from to)))

(defgeneric filter-transactions (ledger &key account from to payee month year state)
  (:documentation "Return transactions matching the given criteria.
   MONTH and YEAR together specify a calendar month filter (overrides FROM/TO).
   STATE can be :cleared, :pending, or :unmarked."))

(defmethod filter-transactions ((ledger ledger) &key account from to payee month year state)
  "Filter transactions by account path, date range, payee, month, or state."
  (let ((txs (ledger-transactions ledger)))
    ;; Month/year overrides from/to
    (when (and month year)
      (multiple-value-bind (m-from m-to) (month-date-range year month)
        (setf from m-from
              to m-to)))
    (when account
      (setf txs (remove-if-not
                 (lambda (tx)
                   (some (lambda (p)
                           (or (equal (posting-account-path p) account)
                               (starts-with-subseq
                                (concatenate 'string account ":")
                                (posting-account-path p))))
                         (transaction-postings tx)))
                 txs)))
    (when from
      (setf txs (remove-if (lambda (tx)
                              (local-time:timestamp< (transaction-date tx) from))
                            txs)))
    (when to
      (setf txs (remove-if (lambda (tx)
                              (local-time:timestamp> (transaction-date tx) to))
                            txs)))
    (when payee
      (let ((pattern (string-downcase payee)))
        (setf txs (remove-if-not
                   (lambda (tx)
                     (search pattern (string-downcase (transaction-payee tx))))
                   txs))))
    (when state
      (setf txs (remove-if-not
                 (lambda (tx) (eq (transaction-state tx) state))
                 txs)))
    txs))

;;; --- Reporting ---

(declaim (ftype (function (ledger &key (:account (or null string))
                                      (:depth (or null (integer 1))))
                          list)
                balance-report))
(defgeneric balance-report (ledger &key account depth)
  (:documentation "Compute a balance report. Returns an alist of (path . amount)."))

(defmethod balance-report ((ledger ledger) &key account (depth nil))
  "Compute running balances for all accounts, optionally filtered and depth-limited."
  (let ((balances (make-hash-table :test 'equal)))
    ;; Accumulate from all transactions
    (dolist (tx (ledger-transactions ledger))
      (dolist (posting (transaction-postings tx))
        (when (posting-amount posting)
          (let ((path (posting-account-path posting)))
            (when (or (null account)
                      (equal path account)
                      (starts-with-subseq (concatenate 'string account ":") path))
              ;; Add to this account and all ancestors
              (let ((segments (cl-ppcre:split ":" path)))
                (loop for i from 1 to (length segments)
                      for partial = (format nil "~{~A~^:~}" (subseq segments 0 i))
                      when (or (null depth) (<= i depth))
                        do (let ((current (gethash partial balances
                                                   (make-instance 'amount :quantity 0))))
                             (setf (gethash partial balances)
                                   (amount-add current (posting-amount posting)))))))))))
    ;; Convert to sorted alist
    (let ((result '()))
      (maphash (lambda (path amount)
                 (push (cons path amount) result))
               balances)
      (sort result #'string< :key #'car))))

(declaim (ftype (function (ledger &key (:account (or null string))
                                      (:from (or null local-time:timestamp))
                                      (:to (or null local-time:timestamp)))
                          list)
                register-report))
(defgeneric register-report (ledger &key account from to)
  (:documentation "Generate a register report: list of transactions with running balance."))

(defmethod register-report ((ledger ledger) &key account from to)
  "Generate register entries: (date payee account amount running-total)."
  (let ((txs (filter-transactions ledger :account account :from from :to to))
        (running (make-instance 'amount :quantity 0))
        (entries '()))
    (dolist (tx txs)
      (dolist (posting (transaction-postings tx))
        (when (and (posting-amount posting)
                   (or (null account)
                       (equal (posting-account-path posting) account)
                       (starts-with-subseq (concatenate 'string account ":")
                                           (posting-account-path posting))))
          (setf running (amount-add running (posting-amount posting)))
          (push (list (transaction-date tx)
                      (transaction-payee tx)
                      (posting-account-path posting)
                      (posting-amount posting)
                      running)
                entries))))
    (nreverse entries)))
