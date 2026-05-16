(in-package #:quaestor)

;;; CLIM commands for the Quaestor application frame.

;;; --- File Commands ---

(define-command (com-open-file :command-table quaestor-file-commands :name "Open File" :menu t
                                        :keystroke (#\o :control))
    ((path 'pathname :prompt "Ledger file"))
  (handler-case
      (let ((ledger (parse-ledger-file (namestring path))))
        (setf (slot-value *application-frame* 'ledger) ledger)
        (setf (slot-value *application-frame* 'status-message)
              (format nil "Opened ~A (~D transactions)"
                      (file-namestring path)
                      (length (ledger-transactions ledger)))))
    (ledger-file-error (c)
      (setf (slot-value *application-frame* 'status-message)
            (format nil "Error: ~A" c)))))

(define-command (com-save :command-table quaestor-file-commands :name "Save" :menu t
                                   :keystroke (#\s :control))
    ()
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (handler-case
        (progn
          (write-ledger-file ledger)
          (setf (slot-value *application-frame* 'status-message)
                (format nil "Saved to ~A" (ledger-file-path ledger))))
      (error (c)
        (setf (slot-value *application-frame* 'status-message)
              (format nil "Save failed: ~A" c))))))

(define-command (com-quit :command-table quaestor-file-commands :name "Quit" :menu t
                                   :keystroke (#\q :control))
    ()
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (when (ledger-modified-p ledger)
      ;; TODO: prompt to save
      nil))
  (frame-exit *application-frame*))

;;; --- Transaction Commands ---

(define-command (com-add-transaction :command-table quaestor-edit-commands :name "Add Transaction" :menu t
                                              :keystroke (#\n :control))
    ()
  (let ((frame *application-frame*))
    (setf (slot-value frame 'editing-transaction)
          (make-instance 'transaction
                         :date (local-time:today)
                         :state :cleared
                         :payee ""
                         :postings (list
                                    (make-instance 'posting :account-path "")
                                    (make-instance 'posting :account-path ""))))
    (setf (slot-value frame 'detail-mode) :edit)))

(define-command (com-edit-transaction :command-table quaestor-edit-commands :name "Edit Transaction")
    ((tx 'transaction-presentation :gesture :select))
  (let ((frame *application-frame*))
    (setf (slot-value frame 'editing-transaction) tx)
    (setf (slot-value frame 'selected-transaction) tx)
    (setf (slot-value frame 'detail-mode) :edit)))

(define-command (com-delete-transaction :command-table quaestor-edit-commands :name "Delete Transaction")
    ((tx 'transaction-presentation :gesture :delete))
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (remove-transaction ledger tx)
    (setf (slot-value *application-frame* 'status-message)
          (format nil "Deleted: ~A ~A"
                  (format-date (transaction-date tx))
                  (transaction-payee tx)))))

(define-command (com-save-transaction :command-table quaestor-edit-commands :name "Save Transaction")
    ()
  (let* ((frame *application-frame*)
         (tx (slot-value frame 'editing-transaction))
         (ledger (slot-value frame 'ledger)))
    (when (and tx ledger)
      (handler-case
          (progn
            (validate-transaction tx)
            (unless (member tx (ledger-transactions ledger) :test #'eq)
              (add-transaction ledger tx))
            (setf (slot-value frame 'detail-mode) :view)
            (setf (slot-value frame 'status-message) "Transaction saved"))
        (validation-error (c)
          (setf (slot-value frame 'status-message)
                (format nil "Invalid: ~A" c)))))))

;;; --- Account Commands ---

(define-command (com-select-account :command-table quaestor-view-commands :name "Select Account")
    ((acct 'account-presentation :gesture :select))
  (setf (slot-value *application-frame* 'selected-account) acct)
  (setf (slot-value *application-frame* 'status-message)
        (format nil "Filtering: ~A" (account-full-path acct))))

(define-command (com-clear-filter :command-table quaestor-view-commands :name "Show All" :menu t)
    ()
  (setf (slot-value *application-frame* 'selected-account) nil)
  (setf (slot-value *application-frame* 'status-message) "Showing all transactions"))

(define-command (com-add-account :command-table quaestor-edit-commands :name "Add Account" :menu t)
    ((path 'string :prompt "Account path (e.g. Expenses:Food:Bar)")
     (note 'string :prompt "Note (optional)" :default nil))
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (ensure-account ledger path :note note)
    (setf (slot-value *application-frame* 'status-message)
          (format nil "Added account: ~A" path))))

;;; --- Date Range / Month Filter Commands ---

(define-command (com-filter-month :command-table quaestor-view-commands :name "Filter by Month" :menu t)
    ((year 'integer :prompt "Year (e.g. 2026)")
     (month 'integer :prompt "Month (1-12)"))
  (let ((frame *application-frame*))
    (setf (slot-value frame 'filter-month) month)
    (setf (slot-value frame 'filter-year) year)
    (setf (slot-value frame 'filter-from) nil)
    (setf (slot-value frame 'filter-to) nil)
    (setf (slot-value frame 'status-message)
          (format nil "Showing ~A ~D"
                  (aref #("" "January" "February" "March" "April" "May" "June"
                          "July" "August" "September" "October" "November" "December")
                        month)
                  year))))

(define-command (com-filter-date-range :command-table quaestor-view-commands :name "Filter by Date Range" :menu t)
    ((from-str 'string :prompt "From date (YYYY/MM/DD)")
     (to-str 'string :prompt "To date (YYYY/MM/DD)"))
  (let ((frame *application-frame*))
    (setf (slot-value frame 'filter-from) (parse-date-string from-str))
    (setf (slot-value frame 'filter-to) (parse-date-string to-str))
    (setf (slot-value frame 'filter-month) nil)
    (setf (slot-value frame 'filter-year) nil)
    (setf (slot-value frame 'status-message)
          (format nil "Showing ~A to ~A" from-str to-str))))

(define-command (com-clear-date-filter :command-table quaestor-view-commands :name "Clear Date Filter" :menu t)
    ()
  (let ((frame *application-frame*))
    (setf (slot-value frame 'filter-month) nil)
    (setf (slot-value frame 'filter-year) nil)
    (setf (slot-value frame 'filter-from) nil)
    (setf (slot-value frame 'filter-to) nil)
    (setf (slot-value frame 'status-message) "Showing all dates")))

;;; --- Quick Entry Commands ---

(define-command (com-add-expense :command-table quaestor-edit-commands :name "Add Expense" :menu t)
    ((date-str 'string :prompt "Date (YYYY/MM/DD)")
     (payee 'string :prompt "Payee")
     (amount-str 'string :prompt "Amount (e.g. 49.99)")
     (expense-account 'string :prompt "Expense account (e.g. Expenses:Food:Bar)")
     (source-account 'string :prompt "Source account" :default "Assets:Revolut:Current"))
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (let* ((amt (parse-amount-string amount-str))
           (tx (make-instance 'transaction
                              :date (parse-date-string date-str)
                              :state :cleared
                              :payee payee
                              :postings (list
                                         (make-instance 'posting
                                                        :account-path expense-account
                                                        :amount amt)
                                         (make-instance 'posting
                                                        :account-path source-account)))))
      (validate-transaction tx)
      (add-transaction ledger tx)
      (setf (slot-value *application-frame* 'status-message)
            (format nil "Added expense: ~A ~A" payee (format-amount amt))))))

(define-command (com-add-income :command-table quaestor-edit-commands :name "Add Income/Deposit" :menu t)
    ((date-str 'string :prompt "Date (YYYY/MM/DD)")
     (payee 'string :prompt "Source/Payee")
     (amount-str 'string :prompt "Amount (e.g. 2500.00)")
     (dest-account 'string :prompt "Deposit account" :default "Assets:Revolut:Current")
     (income-account 'string :prompt "Income account" :default "Income:Salary"))
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (let* ((amt (parse-amount-string amount-str))
           (tx (make-instance 'transaction
                              :date (parse-date-string date-str)
                              :state :cleared
                              :payee payee
                              :postings (list
                                         (make-instance 'posting
                                                        :account-path dest-account
                                                        :amount amt)
                                         (make-instance 'posting
                                                        :account-path income-account)))))
      (validate-transaction tx)
      (add-transaction ledger tx)
      (setf (slot-value *application-frame* 'status-message)
            (format nil "Added income: ~A ~A" payee (format-amount amt))))))

(define-command (com-add-transfer :command-table quaestor-edit-commands :name "Add Transfer" :menu t)
    ((date-str 'string :prompt "Date (YYYY/MM/DD)")
     (payee 'string :prompt "Description")
     (amount-str 'string :prompt "Amount")
     (from-account 'string :prompt "From account")
     (to-account 'string :prompt "To account"))
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (let* ((amt (parse-amount-string amount-str))
           (tx (make-instance 'transaction
                              :date (parse-date-string date-str)
                              :state :cleared
                              :payee payee
                              :postings (list
                                         (make-instance 'posting
                                                        :account-path to-account
                                                        :amount amt)
                                         (make-instance 'posting
                                                        :account-path from-account)))))
      (validate-transaction tx)
      (add-transaction ledger tx)
      (setf (slot-value *application-frame* 'status-message)
            (format nil "Added transfer: ~A" payee)))))

;;; --- Report Commands ---

(define-command (com-balance-report :command-table quaestor-report-commands :name "Balance Report" :menu t)
    ()
  (when-let (ledger (slot-value *application-frame* 'ledger))
    (setf (slot-value *application-frame* 'report-data)
          (balance-report ledger))
    (setf (slot-value *application-frame* 'detail-mode) :report)))

(define-command (com-register-report :command-table quaestor-report-commands :name "Register Report" :menu t)
    ()
  (let ((frame *application-frame*))
    (when-let (ledger (slot-value frame 'ledger))
      (let ((account (when-let (acct (slot-value frame 'selected-account))
                       (account-full-path acct))))
        (setf (slot-value frame 'report-data)
              (register-report ledger :account account))
        (setf (slot-value frame 'detail-mode) :report)))))

(define-command (com-monthly-summary :command-table quaestor-report-commands :name "Monthly Summary" :menu t)
    ((year 'integer :prompt "Year")
     (month 'integer :prompt "Month (1-12)"))
  (let ((frame *application-frame*))
    (when-let (ledger (slot-value frame 'ledger))
      (multiple-value-bind (from to) (month-date-range year month)
        (let* ((txs (filter-transactions ledger :from from :to to))
               (income (make-instance 'amount :quantity 0))
               (expenses (make-instance 'amount :quantity 0)))
          (dolist (tx txs)
            (dolist (posting (transaction-postings tx))
              (when (posting-amount posting)
                (let ((path (posting-account-path posting)))
                  (cond ((starts-with-subseq "Income" path)
                         (setf income (amount-add income (posting-amount posting))))
                        ((starts-with-subseq "Expenses" path)
                         (setf expenses (amount-add expenses (posting-amount posting)))))))))
          (setf (slot-value frame 'status-message)
                (format nil "~A ~D: Income ~A | Expenses ~A | Net ~A"
                        (aref #("" "Jan" "Feb" "Mar" "Apr" "May" "Jun"
                                "Jul" "Aug" "Sep" "Oct" "Nov" "Dec") month)
                        year
                        (format-amount income)
                        (format-amount expenses)
                        (format-amount (amount-add income expenses)))))))))
