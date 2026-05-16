(defpackage #:quaestor
  (:use #:clim-lisp #:clim)
  (:import-from #:closer-mop
                #:validate-superclass
                #:slot-definition-name
                #:class-slots)
  (:import-from #:alexandria
                #:when-let
                #:if-let
                #:hash-table-values
                #:hash-table-keys
                #:starts-with-subseq
                #:ends-with-subseq)
  (:export #:main
           #:*default-config-path*
           #:*default-commodity*))
