(in-package #:quaestor)

;;; Condition hierarchy for Quaestor errors.

(define-condition quaestor-error (error)
  ((message :initarg :message :reader quaestor-error-message))
  (:report (lambda (c s)
             (format s "Quaestor error: ~A" (quaestor-error-message c)))))

(define-condition ledger-parse-error (quaestor-error)
  ((line-number :initarg :line-number :reader parse-error-line-number)
   (line-text :initarg :line-text :reader parse-error-line-text))
  (:report (lambda (c s)
             (format s "Parse error at line ~D: ~A~%  ~A"
                     (parse-error-line-number c)
                     (quaestor-error-message c)
                     (parse-error-line-text c)))))

(define-condition validation-error (quaestor-error)
  ((transaction :initarg :transaction :reader validation-error-transaction))
  (:report (lambda (c s)
             (format s "Validation error: ~A" (quaestor-error-message c)))))

(define-condition ledger-file-error (quaestor-error)
  ((path :initarg :path :reader ledger-file-error-path))
  (:report (lambda (c s)
             (format s "File error (~A): ~A"
                     (ledger-file-error-path c)
                     (quaestor-error-message c)))))

(define-condition unbalanced-transaction (validation-error)
  ((difference :initarg :difference :reader unbalanced-transaction-difference))
  (:report (lambda (c s)
             (format s "Transaction is unbalanced by ~A"
                     (unbalanced-transaction-difference c)))))
