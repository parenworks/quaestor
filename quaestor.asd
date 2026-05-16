(defsystem #:quaestor
  :description "A McCLIM desktop application for managing plain-text .ledger files."
  :author "Glenn Thompson"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:mcclim
               #:local-time
               #:cl-ppcre
               #:alexandria
               #:closer-mop)
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "mop")
                             (:file "model")
                             (:file "parser")
                             (:file "writer")
                             (:file "engine")
                             (:file "presentations")
                             (:file "frame")
                             (:file "commands")
                             (:file "main")))))
