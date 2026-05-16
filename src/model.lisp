(in-package #:quaestor)

;;; Domain model for Quaestor.
;;; All core data structures are CLOS classes with proper slot definitions.

(defvar *default-commodity* "GBP")
(defvar *default-commodity-symbol* "£")
(defvar *default-alignment-column* 50)

;;; --- Commodity ---

(defclass commodity ()
  ((code :accessor commodity-code :initarg :code
         :documentation "ISO code, e.g. GBP, USD, EUR")
   (symbol :accessor commodity-symbol :initarg :symbol :initform nil
           :documentation "Display symbol, e.g. £, $")
   (position :accessor commodity-position :initarg :position :initform :prefix
             :documentation ":prefix or :suffix for symbol placement")
   (decimal-places :accessor commodity-decimal-places :initarg :decimal-places :initform 2))
  (:documentation "Represents a currency or commodity."))

(defmethod print-object ((c commodity) stream)
  (print-unreadable-object (c stream :type t)
    (format stream "~A (~A)" (commodity-code c) (or (commodity-symbol c) "?"))))

;;; --- Amount ---

(defclass amount ()
  ((quantity :accessor amount-quantity :initarg :quantity :initform 0
             :documentation "Exact decimal quantity as a rational number.")
   (commodity :accessor amount-commodity :initarg :commodity :initform nil
              :documentation "Commodity instance, or nil for default."))
  (:documentation "A monetary amount with commodity."))

(defmethod print-object ((a amount) stream)
  (print-unreadable-object (a stream :type t)
    (let ((sym (if (amount-commodity a)
                   (or (commodity-symbol (amount-commodity a))
                       (commodity-code (amount-commodity a)))
                   *default-commodity-symbol*)))
      (format stream "~A~,2F" sym (amount-quantity a)))))

(defgeneric amount-zero-p (amount)
  (:method ((a amount)) (zerop (amount-quantity a))))

(defgeneric amount-negate (amount)
  (:method ((a amount))
    (make-instance 'amount
                   :quantity (- (amount-quantity a))
                   :commodity (amount-commodity a))))

(defgeneric amount-add (a b)
  (:method ((a amount) (b amount))
    (make-instance 'amount
                   :quantity (+ (amount-quantity a) (amount-quantity b))
                   :commodity (or (amount-commodity a) (amount-commodity b)))))

;;; --- Account ---

(deftype account-type ()
  '(member :asset :liability :equity :income :expense :unknown))

(defclass account (auditable-object dirty-tracking-mixin)
  ((name :accessor account-name :initarg :name
         :documentation "Short name of this account (leaf segment).")
   (full-path :accessor account-full-path :initarg :full-path
              :documentation "Full colon-separated path, e.g. Expenses:Food:Bar")
   (parent :accessor account-parent :initarg :parent :initform nil
           :documentation "Parent account, or nil for root.")
   (children :accessor account-children :initform '()
             :documentation "List of child accounts.")
   (note :accessor account-note :initarg :note :initform nil
         :documentation "Optional note/description from account directive.")
   (account-type :accessor account-type :initarg :account-type :initform :unknown
                 :documentation "Inferred type based on path prefix."))
  (:metaclass auditable-class)
  (:documentation "A single account in the chart of accounts."))

(defmethod initialize-instance :after ((account account) &key)
  "Infer account type from path prefix."
  (when (eq (account-type account) :unknown)
    (let ((path (account-full-path account)))
      (setf (account-type account)
            (cond ((starts-with-subseq "Assets" path) :asset)
                  ((starts-with-subseq "Liabilities" path) :liability)
                  ((starts-with-subseq "Equity" path) :equity)
                  ((starts-with-subseq "Income" path) :income)
                  ((starts-with-subseq "Expenses" path) :expense)
                  (t :unknown))))))

(defmethod print-object ((a account) stream)
  (print-unreadable-object (a stream :type t)
    (format stream "~A" (account-full-path a))))

;;; --- Posting ---

(defclass posting ()
  ((account :accessor posting-account :initarg :account
            :documentation "Account instance this posting targets.")
   (account-path :accessor posting-account-path :initarg :account-path
                 :documentation "String path of the account (for parsing before resolution).")
   (amount :accessor posting-amount :initarg :amount :initform nil
           :documentation "Amount, or nil if to be auto-balanced.")
   (comment :accessor posting-comment :initarg :comment :initform nil
            :documentation "Inline comment on this posting."))
  (:documentation "A single line within a transaction."))

(defmethod print-object ((p posting) stream)
  (print-unreadable-object (p stream :type t)
    (format stream "~A ~A"
            (or (and (slot-boundp p 'account) (account-full-path (posting-account p)))
                (posting-account-path p))
            (or (posting-amount p) "(auto)"))))

;;; --- Transaction ---

(deftype transaction-state ()
  '(member :cleared :pending :unmarked))

(defclass transaction (auditable-object dirty-tracking-mixin)
  ((date :accessor transaction-date :initarg :date
         :documentation "Primary date as a local-time timestamp.")
   (aux-date :accessor transaction-aux-date :initarg :aux-date :initform nil
             :documentation "Auxiliary/effective date, if present.")
   (state :accessor transaction-state :initarg :state :initform :cleared
          :documentation "Cleared (*), pending (!), or unmarked.")
   (payee :accessor transaction-payee :initarg :payee
          :documentation "Payee/description string.")
   (postings :accessor transaction-postings :initarg :postings :initform '()
             :documentation "List of posting instances.")
   (comment :accessor transaction-comment :initarg :comment :initform nil
            :documentation "Comment lines associated with this transaction.")
   (tags :accessor transaction-tags :initarg :tags :initform '()
         :documentation "Association list of tag key-value pairs.")
   (line-number :accessor transaction-line-number :initarg :line-number :initform nil
                :documentation "Source line number in the .ledger file."))
  (:metaclass auditable-class)
  (:documentation "A complete ledger transaction with date, payee, and postings."))

(defmethod print-object ((tx transaction) stream)
  (print-unreadable-object (tx stream :type t)
    (format stream "~A ~A ~A"
            (transaction-date tx)
            (ecase (transaction-state tx)
              (:cleared "*") (:pending "!") (:unmarked ""))
            (transaction-payee tx))))

;;; --- Ledger ---

(defclass ledger (dirty-tracking-mixin)
  ((file-path :accessor ledger-file-path :initarg :file-path :initform nil
              :documentation "Path to the .ledger file on disk.")
   (accounts :accessor ledger-accounts :initform (make-hash-table :test 'equal)
             :documentation "Hash table mapping full-path strings to account instances.")
   (transactions :accessor ledger-transactions :initform '()
                 :documentation "List of transactions in file order.")
   (commodities :accessor ledger-commodities :initform (make-hash-table :test 'equal)
                :documentation "Hash table mapping commodity codes to instances.")
   (preamble :accessor ledger-preamble :initform '()
             :documentation "Lines before the first transaction (comments, directives).")
   (modified-p :accessor ledger-modified-p :initform nil
               :documentation "Whether unsaved changes exist."))
  (:documentation "Top-level container representing an entire .ledger file."))

;;; --- Ledger operations ---

(defgeneric find-account (ledger path)
  (:documentation "Find an account by its full path string.")
  (:method ((ledger ledger) (path string))
    (gethash path (ledger-accounts ledger))))

(defgeneric ensure-account (ledger path &key note)
  (:documentation "Find or create an account and all ancestor accounts.")
  (:method ((ledger ledger) (path string) &key note)
    (or (find-account ledger path)
        (let* ((segments (cl-ppcre:split ":" path))
               (parent nil))
          (loop for i from 1 to (length segments)
                for partial-path = (format nil "~{~A~^:~}" (subseq segments 0 i))
                for existing = (find-account ledger partial-path)
                if existing
                  do (setf parent existing)
                else
                  do (let ((acct (make-instance 'account
                                               :name (nth (1- i) segments)
                                               :full-path partial-path
                                               :parent parent
                                               :note (when (= i (length segments)) note))))
                       (setf (gethash partial-path (ledger-accounts ledger)) acct)
                       (when parent
                         (push acct (account-children parent)))
                       (setf parent acct)))
          (find-account ledger path)))))

(defgeneric add-transaction (ledger transaction)
  (:documentation "Add a transaction to the ledger.")
  (:method ((ledger ledger) (tx transaction))
    (push tx (ledger-transactions ledger))
    (setf (ledger-modified-p ledger) t)
    tx))

(defgeneric remove-transaction (ledger transaction)
  (:documentation "Remove a transaction from the ledger.")
  (:method ((ledger ledger) (tx transaction))
    (setf (ledger-transactions ledger)
          (remove tx (ledger-transactions ledger) :test #'eq))
    (setf (ledger-modified-p ledger) t)))

(defgeneric account-balance (ledger account)
  (:documentation "Compute the running balance for an account across all transactions.")
  (:method ((ledger ledger) (account account))
    (let ((path (account-full-path account))
          (total (make-instance 'amount :quantity 0)))
      (dolist (tx (ledger-transactions ledger))
        (dolist (posting (transaction-postings tx))
          (when (and (posting-amount posting)
                     (or (equal (posting-account-path posting) path)
                         (starts-with-subseq path (posting-account-path posting))))
            (setf total (amount-add total (posting-amount posting))))))
      total)))

(defgeneric ledger-balance (ledger path)
  (:documentation "Compute balance for an account path including sub-accounts.")
  (:method ((ledger ledger) (path string))
    (let ((total (make-instance 'amount :quantity 0)))
      (dolist (tx (ledger-transactions ledger))
        (dolist (posting (transaction-postings tx))
          (when (and (posting-amount posting)
                     (or (equal (posting-account-path posting) path)
                         (starts-with-subseq (concatenate 'string path ":") 
                                             (posting-account-path posting))))
            (setf total (amount-add total (posting-amount posting))))))
      total)))
