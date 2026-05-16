;;; build.lisp - Build Quaestor into a standalone executable.
;;; Usage: sbcl --load build.lisp
;;;    or: ecl --load build.lisp

(require :asdf)

;;; Ensure quicklisp is available for dependency resolution.
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;;; Load the system and all dependencies.
(format t "~&; Loading quaestor...~%")
(asdf:load-system :quaestor)
(format t "~&; System loaded successfully.~%")

;;; Build the executable.
(defvar *output-name*
  (or (uiop:getenv "QUAESTOR_OUTPUT")
      "quaestor"))

(defvar *output-path*
  (merge-pathnames *output-name*
                   (merge-pathnames "bin/" (asdf:system-source-directory :quaestor))))

(format t "~&; Building executable: ~A~%" *output-path*)
(ensure-directories-exist *output-path*)

#+sbcl
(sb-ext:save-lisp-and-die *output-path*
                           :toplevel #'quaestor:main
                           :executable t
                           :compression t
                           :purify t)

#+ecl
(progn
  (asdf:make-build :quaestor
                   :type :program
                   :move-here *output-path*
                   :epilogue-code '(quaestor:main))
  (format t "~&; ECL build complete: ~A~%" *output-path*)
  (ext:quit 0))

#-(or sbcl ecl)
(error "Unsupported implementation. Use SBCL or ECL.")
