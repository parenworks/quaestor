(in-package #:quaestor)

;;; McCLIM application frame definition for Quaestor.

;;; --- Colour Palette (Dark Mode) ---

(defparameter *colour-bg-main* (make-rgb-color 0.11 0.12 0.14))
(defparameter *colour-bg-header* (make-rgb-color 0.15 0.16 0.19))
(defparameter *colour-bg-accent* (make-rgb-color 0.13 0.14 0.17))
(defparameter *colour-bg-stripe* (make-rgb-color 0.16 0.17 0.21))
(defparameter *colour-fg-default* (make-rgb-color 0.85 0.87 0.90))
(defparameter *colour-positive* (make-rgb-color 0.30 0.78 0.40))
(defparameter *colour-negative* (make-rgb-color 0.95 0.35 0.35))
(defparameter *colour-neutral* (make-rgb-color 0.70 0.72 0.75))
(defparameter *colour-muted* (make-rgb-color 0.50 0.52 0.56))
(defparameter *colour-heading* (make-rgb-color 0.65 0.75 0.90))
(defparameter *colour-asset* (make-rgb-color 0.30 0.78 0.50))
(defparameter *colour-liability* (make-rgb-color 0.95 0.45 0.45))
(defparameter *colour-income* (make-rgb-color 0.40 0.70 0.95))
(defparameter *colour-expense* (make-rgb-color 0.95 0.60 0.25))
(defparameter *colour-equity* (make-rgb-color 0.70 0.55 0.85))

;;; --- Sub-command tables ---

(define-command-table quaestor-file-commands)
(define-command-table quaestor-edit-commands)
(define-command-table quaestor-view-commands)
(define-command-table quaestor-report-commands)

(make-command-table 'quaestor-menu-bar
                    :errorp nil
                    :menu '(("File" :menu quaestor-file-commands)
                            ("Edit" :menu quaestor-edit-commands)
                            ("View" :menu quaestor-view-commands)
                            ("Reports" :menu quaestor-report-commands)))

;;; --- Expand/Collapse State ---

(defvar *expanded-accounts* (make-hash-table :test 'equal)
  "Hash table tracking which account paths are expanded in the tree.")

(defun account-expanded-p (account)
  (gethash (account-full-path account) *expanded-accounts* nil))

(defun toggle-account-expanded (account)
  (let ((path (account-full-path account)))
    (if (gethash path *expanded-accounts*)
        (remhash path *expanded-accounts*)
        (setf (gethash path *expanded-accounts*) t))))

;;; --- Application Frame ---

(define-application-frame quaestor ()
  ((ledger :initform nil :accessor frame-ledger)
   (selected-account :initform nil :accessor frame-selected-account)
   (selected-transaction :initform nil :accessor frame-selected-transaction)
   (editing-transaction :initform nil :accessor frame-editing-transaction)
   (detail-mode :initform :dashboard :accessor frame-detail-mode)
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
                 :min-width 200
                 :foreground *colour-fg-default*
                 :background *colour-bg-accent*)
   (transaction-list :application
                     :display-function 'display-transaction-list
                     :scroll-bars :vertical
                     :incremental-redisplay t
                     :foreground *colour-fg-default*
                     :background *colour-bg-main*)
   (detail :application
            :display-function 'display-detail
            :scroll-bars :vertical
            :foreground *colour-fg-default*
            :background *colour-bg-main*)
   (status :application
            :display-function 'display-status-bar
            :scroll-bars nil
            :height 25
            :max-height 25
            :foreground *colour-fg-default*
            :background *colour-bg-header*)
   (interactor :interactor
               :height 80
               :min-height 60
               :foreground *colour-fg-default*
               :background *colour-bg-header*))
  (:layouts
   (default
    (vertically ()
      (horizontally ()
        (1/4 account-tree)
        (3/4 (vertically ()
               (1/2 transaction-list)
               (1/2 detail))))
      status
      interactor)))
  (:menu-bar quaestor-menu-bar)
  (:command-table (quaestor
                   :inherit-from (quaestor-file-commands
                                  quaestor-edit-commands
                                  quaestor-view-commands
                                  quaestor-report-commands))))

;;; --- Helpers ---

(defun account-type-colour (acct-type)
  "Return an ink colour for the given account type keyword."
  (ecase acct-type
    (:asset *colour-asset*)
    (:liability *colour-liability*)
    (:equity *colour-equity*)
    (:income *colour-income*)
    (:expense *colour-expense*)
    (:unknown *colour-neutral*)))

(defun amount-ink (quantity)
  "Return an ink colour based on sign of quantity."
  (cond ((plusp quantity) *colour-positive*)
        ((minusp quantity) *colour-negative*)
        (t *colour-neutral*)))

;;; --- Display Functions ---

(defun display-account-tree (frame pane)
  "Display the hierarchical account tree in the left pane."
  (when-let (ledger (frame-ledger frame))
    ;; Section heading
    (with-drawing-options (pane :ink *colour-heading*)
      (with-text-face (pane :bold)
        (with-text-size (pane :large)
          (format pane "  Accounts~%"))))
    (terpri pane)
    (let ((root-accounts (remove-if #'account-parent
                                    (hash-table-values (ledger-accounts ledger)))))
      (setf root-accounts (sort root-accounts #'string< :key #'account-full-path))
      (dolist (account root-accounts)
        (display-account-node account pane 0 ledger)))))

(defun display-account-node (account pane depth ledger)
  "Recursively display an account and its children with indentation."
  (let* ((children (sort (copy-list (account-children account))
                         #'string< :key #'account-name))
         (has-children (not (null children)))
         (expanded (account-expanded-p account))
         (indent (make-string (* depth 2) :initial-element #\Space))
         (arrow (cond ((not has-children) "  ")
                      (expanded "- ")
                      (t "+ ")))
         (ink (account-type-colour (account-type account)))
         (bal (ledger-balance ledger (account-full-path account)))
         (bal-qty (amount-quantity bal)))
    (with-output-as-presentation (pane account 'account-presentation)
      (with-drawing-options (pane :ink *colour-muted*)
        (format pane "~A~A" indent arrow))
      (with-drawing-options (pane :ink ink)
        (with-text-face (pane :bold)
          (format pane "~A" (account-name account))))
      (unless (zerop bal-qty)
        (with-drawing-options (pane :ink (amount-ink bal-qty))
          (format pane "  ~A" (format-amount bal))))
      (terpri pane))
    (when (and has-children expanded)
      (dolist (child children)
        (display-account-node child pane (1+ depth) ledger)))))

(defun display-transaction-list (frame pane)
  "Display filtered transactions in the main list pane."
  (when-let (ledger (frame-ledger frame))
    ;; Section heading
    (let ((selected-account (frame-selected-account frame)))
      (with-drawing-options (pane :ink *colour-heading*)
        (with-text-face (pane :bold)
          (with-text-size (pane :large)
            (format pane "  ~A~%"
                    (if selected-account
                        (format nil "Transactions - ~A" (account-full-path selected-account))
                        "Recent Transactions")))))
      (terpri pane)
      (let* ((account-path (when selected-account
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
          (with-text-style (pane (make-text-style :fix :roman :normal))
            ;; Header
            (surrounding-output-with-border (pane :shape :rectangle
                                                  :background *colour-bg-header*
                                                  :ink +transparent-ink+
                                                  :padding 3)
              (with-drawing-options (pane :ink *colour-heading*)
                (with-text-face (pane :bold)
                  (format pane "~12A~28A~26A~10@A" "Date" "Payee" "Category" "Amount"))))
            (terpri pane)
            ;; Zebra-striped rows
            (let ((row-idx 0))
              (dolist (tx sorted)
                (let* ((primary-posting (first (transaction-postings tx)))
                       (amount (when primary-posting (posting-amount primary-posting)))
                       (category (when (second (transaction-postings tx))
                                   (posting-account-path (second (transaction-postings tx)))))
                       (bg (if (evenp row-idx) *colour-bg-main* *colour-bg-stripe*)))
                  (with-output-as-presentation (pane tx 'transaction-presentation)
                    (surrounding-output-with-border (pane :shape :rectangle
                                                          :background bg
                                                          :ink +transparent-ink+
                                                          :padding 3)
                      (with-drawing-options (pane :ink *colour-muted*)
                        (format pane "~12A" (format-date (transaction-date tx))))
                      (with-drawing-options (pane :ink *colour-fg-default*)
                        (let ((name (transaction-payee tx)))
                          (format pane "~28A" (if (> (length name) 27)
                                                   (concatenate 'string (subseq name 0 24) "...")
                                                   name))))
                      (with-drawing-options (pane :ink *colour-muted*)
                        (format pane "~26A" (or category "")))
                      (let ((amt-str (if amount (format-amount amount) "")))
                        (when amount
                          (let ((qty (amount-quantity amount)))
                            (with-drawing-options (pane :ink (amount-ink qty))
                              (with-text-face (pane :bold)
                                (format pane "~10@A" amt-str))))))))
                  (terpri pane)
                  (incf row-idx))))))))))

(defun display-detail (frame pane)
  "Display transaction detail, entry form, report, or dashboard."
  (ecase (frame-detail-mode frame)
    (:dashboard (display-dashboard frame pane))
    (:view (display-transaction-detail frame pane))
    (:edit (display-transaction-edit frame pane))
    (:report (display-report frame pane))))

;;; --- Dashboard ---

(defun display-dashboard (frame pane)
  "Show an overview: current balance, recent expenses, monthly summary."
  (when-let (ledger (frame-ledger frame))
    ;; Current Balance - prominent display
    (let* ((assets-bal (ledger-balance ledger "Assets"))
           (assets-qty (amount-quantity assets-bal)))
      (terpri pane)
      (with-drawing-options (pane :ink *colour-heading*)
        (with-text-face (pane :bold)
          (format pane "  Current Balance~%")))
      (terpri pane)
      (with-drawing-options (pane :ink (amount-ink assets-qty))
        (with-text-face (pane :bold)
          (with-text-size (pane :very-large)
            (format pane "    ~A~%" (format-amount assets-bal)))))
      (terpri pane))

    ;; This month's summary
    (let ((now (local-time:now)))
      (multiple-value-bind (from to)
          (month-date-range (local-time:timestamp-year now)
                            (local-time:timestamp-month now))
        (let ((txs (filter-transactions ledger :from from :to to))
              (income-total (make-instance 'amount :quantity 0))
              (expense-total (make-instance 'amount :quantity 0)))
          (dolist (tx txs)
            (dolist (posting (transaction-postings tx))
              (when (posting-amount posting)
                (let ((path (posting-account-path posting)))
                  (cond ((starts-with-subseq "Income" path)
                         (setf income-total (amount-add income-total (posting-amount posting))))
                        ((starts-with-subseq "Expenses" path)
                         (setf expense-total (amount-add expense-total (posting-amount posting)))))))))
          (with-drawing-options (pane :ink *colour-heading*)
            (with-text-face (pane :bold)
              (format pane "  This Month (~A ~D)~%"
                      (aref #("" "January" "February" "March" "April" "May" "June"
                              "July" "August" "September" "October" "November" "December")
                            (local-time:timestamp-month now))
                      (local-time:timestamp-year now))))
          (terpri pane)
          (formatting-table (pane :x-spacing 20)
            (formatting-row (pane)
              (formatting-cell (pane)
                (format pane "    Income"))
              (formatting-cell (pane)
                (let ((qty (amount-quantity income-total)))
                  (with-drawing-options (pane :ink (amount-ink qty))
                    (with-text-face (pane :bold)
                      (format pane "~A" (format-amount income-total)))))))
            (formatting-row (pane)
              (formatting-cell (pane)
                (format pane "    Expenses"))
              (formatting-cell (pane)
                (let ((qty (amount-quantity expense-total)))
                  (with-drawing-options (pane :ink (amount-ink qty))
                    (with-text-face (pane :bold)
                      (format pane "~A" (format-amount expense-total)))))))
            (formatting-row (pane)
              (formatting-cell (pane)
                (with-text-face (pane :bold)
                  (format pane "    Net")))
              (formatting-cell (pane)
                (let* ((net (amount-add income-total expense-total))
                       (qty (amount-quantity net)))
                  (with-drawing-options (pane :ink (amount-ink qty))
                    (with-text-face (pane :bold)
                      (format pane "~A" (format-amount net))))))))
          (terpri pane)
          (terpri pane)

          ;; Recent expenses (last 10)
          (with-drawing-options (pane :ink *colour-heading*)
            (with-text-face (pane :bold)
              (format pane "  Recent Expenses~%")))
          (terpri pane)
          (with-text-style (pane (make-text-style :fix :roman :normal))
            (let* ((expense-txs (filter-transactions ledger :account "Expenses"))
                   (recent (subseq (sort (copy-list expense-txs) #'local-time:timestamp>
                                         :key #'transaction-date)
                                   0 (min 10 (length expense-txs))))
                   (row-idx 0))
              (dolist (tx recent)
                (let* ((posting (find-if (lambda (p)
                                          (starts-with-subseq "Expenses"
                                                              (posting-account-path p)))
                                        (transaction-postings tx)))
                       (amount (when posting (posting-amount posting)))
                       (bg (if (evenp row-idx) *colour-bg-main* *colour-bg-stripe*)))
                  (with-output-as-presentation (pane tx 'transaction-presentation)
                    (surrounding-output-with-border (pane :shape :rectangle
                                                          :background bg
                                                          :ink +transparent-ink+
                                                          :padding 3)
                      (with-drawing-options (pane :ink *colour-muted*)
                        (format pane "~12A" (format-date (transaction-date tx))))
                      (with-drawing-options (pane :ink *colour-fg-default*)
                        (format pane "~20A" (transaction-payee tx)))
                      (when amount
                        (with-drawing-options (pane :ink *colour-negative*)
                          (with-text-face (pane :bold)
                            (format pane "~A" (format-amount amount)))))))
                  (terpri pane)
                  (incf row-idx))))))))))

(defun display-transaction-detail (frame pane)
  "Show the selected transaction's full detail."
  (if (null (frame-selected-transaction frame))
      (display-dashboard frame pane)
      (let ((tx (frame-selected-transaction frame)))
        (terpri pane)
        (with-drawing-options (pane :ink *colour-heading*)
          (with-text-face (pane :bold)
            (format pane "  Transaction Detail~%")))
        (terpri pane)
        (with-text-face (pane :bold)
          (format pane "  ~A ~A ~A~%"
                  (format-date (transaction-date tx))
                  (ecase (transaction-state tx)
                    (:cleared "*") (:pending "!") (:unmarked ""))
                  (transaction-payee tx)))
        (when (transaction-comment tx)
          (with-drawing-options (pane :ink *colour-muted*)
            (format pane "    ; ~A~%" (transaction-comment tx))))
        (terpri pane)
        (dolist (posting (transaction-postings tx))
          (let ((path (posting-account-path posting)))
            (format pane "    ")
            (with-drawing-options (pane :ink *colour-neutral*)
              (format pane "~A" path))
            (when (posting-amount posting)
              (let ((qty (amount-quantity (posting-amount posting))))
                (format pane "~50T")
                (with-drawing-options (pane :ink (amount-ink qty))
                  (with-text-face (pane :bold)
                    (format pane "~A" (format-amount (posting-amount posting)))))))
            (terpri pane))))))

(defun display-transaction-edit (frame pane)
  "Show the transaction entry/edit form."
  (declare (ignore frame))
  (format pane "  [Transaction editing form - Phase 3]~%")
  (format pane "  Use the interactor to enter transaction details.~%"))

(defun display-report (frame pane)
  "Display report data."
  (when-let (data (frame-report-data frame))
    ;; Report heading
    (terpri pane)
    (with-drawing-options (pane :ink *colour-heading*)
      (with-text-face (pane :bold)
        (with-text-size (pane :large)
          (format pane "  Report~%"))))
    (terpri pane)
    (with-text-style (pane (make-text-style :fix :roman :normal))
      (let ((row-idx 0))
        (dolist (entry data)
          (let ((bg (if (evenp row-idx) *colour-bg-main* *colour-bg-stripe*)))
            (surrounding-output-with-border (pane :shape :rectangle
                                                  :background bg
                                                  :ink +transparent-ink+
                                                  :padding 3)
              (cond
                ;; Balance report entry: dotted pair (path . amount)
                ((and (consp entry) (typep (cdr entry) 'amount))
                 (format pane "~40A" (car entry))
                 (let ((qty (amount-quantity (cdr entry))))
                   (with-drawing-options (pane :ink (amount-ink qty))
                     (with-text-face (pane :bold)
                       (format pane "~A" (format-amount (cdr entry)))))))
                ;; Register report entry: proper list (date payee account amount running)
                ((and (listp entry) (listp (cdr entry)))
                 (let ((date (first entry))
                       (payee (second entry))
                       (account (third entry))
                       (amount (fourth entry))
                       (running (fifth entry)))
                   (with-drawing-options (pane :ink *colour-muted*)
                     (format pane "~12A" (format-date date)))
                   (with-drawing-options (pane :ink *colour-fg-default*)
                     (format pane "~22A" payee))
                   (with-drawing-options (pane :ink *colour-muted*)
                     (format pane "~30A" account))
                   (when amount
                     (let ((qty (amount-quantity amount)))
                       (with-drawing-options (pane :ink (amount-ink qty))
                         (format pane "~12A" (format-amount amount)))))
                   (when running
                     (let ((qty (amount-quantity running)))
                       (with-drawing-options (pane :ink (amount-ink qty))
                         (with-text-face (pane :bold)
                           (format pane "~A" (format-amount running))))))))))
            (terpri pane)
            (incf row-idx)))))))

(defun display-status-bar (frame pane)
  "Display the status bar with balance and message."
  (let ((ledger (frame-ledger frame)))
    (with-drawing-options (pane :ink *colour-heading*)
      (format pane " ~A~40T~A~70T~A"
              (frame-status-message frame)
              (if ledger
                  (if (ledger-modified-p ledger) "[Modified]" "[Clean]")
                  "")
              (if ledger
                  (format nil "~D transactions" (length (ledger-transactions ledger)))
                  "No file loaded")))))
