(in-package #:quaestor)

;;; CLIM Presentation types and display methods for Quaestor.

;;; --- Presentation Types ---

(define-presentation-type account-presentation ()
  :description "a ledger account")

(define-presentation-type transaction-presentation ()
  :description "a ledger transaction")

(define-presentation-type amount-presentation ()
  :description "a monetary amount")

(define-presentation-type posting-presentation ()
  :description "a transaction posting")

(define-presentation-type date-presentation ()
  :description "a date")

;;; --- Display Methods ---

(define-presentation-method present (object (type account-presentation) stream view &key)
  (let ((acct-type (account-type object)))
    (with-drawing-options (stream :ink (ecase acct-type
                                         (:asset +dark-green+)
                                         (:liability +dark-red+)
                                         (:equity +dark-blue+)
                                         (:income +dark-green+)
                                         (:expense +dark-red+)
                                         (:unknown +black+)))
      (format stream "~A" (account-name object)))))

(define-presentation-method present (object (type transaction-presentation) stream view &key)
  (let ((state-str (ecase (transaction-state object)
                     (:cleared "*")
                     (:pending "!")
                     (:unmarked " "))))
    (with-text-face (stream :bold)
      (format stream "~A" (format-date (transaction-date object))))
    (format stream " ~A " state-str)
    (format stream "~A" (transaction-payee object))))

(define-presentation-method present (object (type amount-presentation) stream view &key)
  (let* ((quantity (amount-quantity object))
         (ink (cond ((plusp quantity) +dark-green+)
                    ((minusp quantity) +dark-red+)
                    (t +black+))))
    (with-drawing-options (stream :ink ink)
      (format stream "~A" (format-amount object)))))

(define-presentation-method present (object (type posting-presentation) stream view &key)
  (format stream "  ~A" (posting-account-path object))
  (when (posting-amount object)
    (format stream "  ~A" (format-amount (posting-amount object)))))

(define-presentation-method present (object (type date-presentation) stream view &key)
  (format stream "~A" (format-date object)))

;;; --- Accept Methods (for input) ---

(define-presentation-method accept ((type account-presentation) stream view &key)
  "Accept an account by completing from known account paths."
  (let ((path (accept 'string :stream stream :prompt "Account")))
    ;; Could add completion here using the active ledger's account list
    path))

(define-presentation-method accept ((type amount-presentation) stream view &key)
  "Accept an amount in ledger format."
  (let ((str (accept 'string :stream stream :prompt "Amount")))
    (parse-amount-string str)))
