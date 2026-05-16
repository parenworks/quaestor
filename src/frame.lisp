(in-package #:quaestor)

;;; McCLIM application frame definition for Quaestor.

(define-application-frame quaestor ()
  ((ledger :initform nil :accessor frame-ledger)
   (selected-account :initform nil :accessor frame-selected-account)
   (selected-transaction :initform nil :accessor frame-selected-transaction)
   (editing-transaction :initform nil :accessor frame-editing-transaction)
   (detail-mode :initform :view :accessor frame-detail-mode)
   (report-data :initform nil :accessor frame-report-data)
   (status-message :initform "Ready" :accessor frame-status-message)
   ;; Date filtering
   (filter-month :initform nil :accessor frame-filter-month)
   (filter-year :initform nil :accessor frame-filter-year)
   (filter-from :initform nil :accessor frame-filter-from)
   (filter-to :initform nil :accessor frame-filter-to))
  (:panes
   (account-tree :application
                 :display-function 'display-account-tree
                 :scroll-bars :vertical
                 :width 250
                 :min-width 200)
   (transaction-list :application
                     :display-function 'display-transaction-list
                     :scroll-bars :vertical
                     :incremental-redisplay t)
   (detail :application
            :display-function 'display-detail
            :scroll-bars :vertical)
   (status :application
            :display-function 'display-status-bar
            :scroll-bars nil
            :height 25
            :max-height 25)
   (interactor :interactor
               :height 30
               :max-height 30))
  (:layouts
   (default
    (vertically ()
      (horizontally ()
        (1/4 account-tree)
        (3/4 (vertically ()
               (2/3 transaction-list)
               (1/3 detail))))
      status
      interactor)))
  (:menu-bar t)
  (:command-table (quaestor
                   :inherit-from (quaestor-file-commands
                                  quaestor-edit-commands
                                  quaestor-view-commands
                                  quaestor-report-commands))))

;;; --- Command Tables ---

(define-command-table quaestor-file-commands
  :menu (("Open" :command com-open-file)
         ("Save" :command com-save)
         ("Quit" :command com-quit)))

(define-command-table quaestor-edit-commands
  :menu (("Add Transaction" :command com-add-transaction)
         ("Add Expense" :command com-add-expense)
         ("Add Income/Deposit" :command com-add-income)
         ("Add Transfer" :command com-add-transfer)
         ("Add Account" :command com-add-account)))

(define-command-table quaestor-view-commands
  :menu (("Show All" :command com-clear-filter)
         ("Filter by Month" :command com-filter-month)
         ("Filter by Date Range" :command com-filter-date-range)
         ("Clear Date Filter" :command com-clear-date-filter)))

(define-command-table quaestor-report-commands
  :menu (("Balance" :command com-balance-report)
         ("Register" :command com-register-report)
         ("Monthly Summary" :command com-monthly-summary)))

;;; --- Display Functions ---

(defun display-account-tree (frame pane)
  "Display the hierarchical account tree in the left pane."
  (when-let (ledger (frame-ledger frame))
    (let ((root-accounts (remove-if #'account-parent
                                    (hash-table-values (ledger-accounts ledger)))))
      (setf root-accounts (sort root-accounts #'string< :key #'account-full-path))
      (dolist (account root-accounts)
        (display-account-node account pane 0)))))

(defun display-account-node (account pane depth)
  "Recursively display an account and its children with indentation."
  (with-output-as-presentation (pane account 'account-presentation)
    (formatting-row (pane)
      (formatting-cell (pane)
        (format pane "~A~A" (make-string (* depth 2) :initial-element #\Space)
                (account-name account)))))
  (terpri pane)
  (let ((children (sort (copy-list (account-children account))
                        #'string< :key #'account-name)))
    (dolist (child children)
      (display-account-node child pane (1+ depth)))))

(defun display-transaction-list (frame pane)
  "Display filtered transactions in the main list pane."
  (when-let (ledger (frame-ledger frame))
    (let* ((selected-account (frame-selected-account frame))
           (account-path (when selected-account
                           (account-full-path selected-account)))
           (transactions (filter-transactions ledger
                                             :account account-path
                                             :month (frame-filter-month frame)
                                             :year (frame-filter-year frame)
                                             :from (frame-filter-from frame)
                                             :to (frame-filter-to frame))))
      ;; Show most recent first
      (let ((sorted (sort (copy-list transactions) #'local-time:timestamp>
                          :key #'transaction-date)))
        (formatting-table (pane)
          ;; Header
          (formatting-row (pane)
            (formatting-cell (pane) (with-text-face (pane :bold) (write-string "Date" pane)))
            (formatting-cell (pane) (with-text-face (pane :bold) (write-string " " pane)))
            (formatting-cell (pane) (with-text-face (pane :bold) (write-string "Payee" pane)))
            (formatting-cell (pane) (with-text-face (pane :bold) (write-string "Amount" pane))))
          ;; Rows
          (dolist (tx sorted)
            (with-output-as-presentation (pane tx 'transaction-presentation)
              (formatting-row (pane)
                (formatting-cell (pane)
                  (format pane "~A" (format-date (transaction-date tx))))
                (formatting-cell (pane)
                  (format pane "~A" (ecase (transaction-state tx)
                                      (:cleared "*") (:pending "!") (:unmarked " "))))
                (formatting-cell (pane)
                  (format pane "~A" (transaction-payee tx)))
                (formatting-cell (pane)
                  (let ((primary-posting (first (transaction-postings tx))))
                    (when (and primary-posting (posting-amount primary-posting))
                      (present (posting-amount primary-posting)
                               'amount-presentation :stream pane))))))))))))

(defun display-detail (frame pane)
  "Display transaction detail or entry form in the bottom pane."
  (ecase (frame-detail-mode frame)
    (:view (display-transaction-detail frame pane))
    (:edit (display-transaction-edit frame pane))
    (:report (display-report frame pane))))

(defun display-transaction-detail (frame pane)
  "Show the selected transaction's full detail."
  (when-let (tx (frame-selected-transaction frame))
    (with-text-face (pane :bold)
      (format pane "~A ~A ~A~%"
              (format-date (transaction-date tx))
              (ecase (transaction-state tx)
                (:cleared "*") (:pending "!") (:unmarked ""))
              (transaction-payee tx)))
    (when (transaction-comment tx)
      (with-drawing-options (pane :ink +dark-gray+)
        (format pane "  ; ~A~%" (transaction-comment tx))))
    (terpri pane)
    (dolist (posting (transaction-postings tx))
      (format pane "    ~A" (posting-account-path posting))
      (when (posting-amount posting)
        (format pane "~40T")
        (present (posting-amount posting) 'amount-presentation :stream pane))
      (terpri pane))))

(defun display-transaction-edit (frame pane)
  "Show the transaction entry/edit form."
  (declare (ignore frame))
  (format pane "  [Transaction editing form - Phase 3]~%")
  (format pane "  Use the interactor to enter transaction details.~%"))

(defun display-report (frame pane)
  "Display report data."
  (when-let (data (frame-report-data frame))
    (formatting-table (pane)
      (dolist (entry data)
        (formatting-row (pane)
          (if (consp entry)
              ;; Balance report entry: (path . amount)
              (progn
                (formatting-cell (pane) (format pane "~A" (car entry)))
                (formatting-cell (pane)
                  (present (cdr entry) 'amount-presentation :stream pane)))
              ;; Register report entry: list
              (dolist (item entry)
                (formatting-cell (pane)
                  (format pane "~A" item)))))))))

(defun display-status-bar (frame pane)
  "Display the status bar with balance and message."
  (let ((ledger (frame-ledger frame)))
    (format pane " ~A~40T~A~70T~A"
            (frame-status-message frame)
            (if ledger
                (if (ledger-modified-p ledger) "[Modified]" "[Clean]")
                "")
            (if ledger
                (format nil "~D transactions" (length (ledger-transactions ledger)))
                "No file loaded"))))
