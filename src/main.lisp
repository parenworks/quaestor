(in-package #:quaestor)

;;; Entry point and configuration loading for Quaestor.

(defvar *default-config-path*
  (merge-pathnames ".config/quaestor/config.sexp" (user-homedir-pathname)))

(defclass configuration ()
  ((default-file :accessor config-default-file :initarg :default-file :initform nil)
   (default-commodity :accessor config-default-commodity :initarg :default-commodity
                      :initform "GBP")
   (commodity-symbol :accessor config-commodity-symbol :initarg :commodity-symbol
                     :initform "£")
   (commodity-position :accessor config-commodity-position :initarg :commodity-position
                       :initform :prefix)
   (date-format :accessor config-date-format :initarg :date-format :initform :iso)
   (alignment-column :accessor config-alignment-column :initarg :alignment-column
                     :initform 50)
   (auto-save-interval :accessor config-auto-save-interval :initarg :auto-save-interval
                       :initform 300)
   (window-width :accessor config-window-width :initarg :window-width :initform 1200)
   (window-height :accessor config-window-height :initarg :window-height :initform 800)
   (recent-files :accessor config-recent-files :initarg :recent-files :initform '()))
  (:documentation "User configuration for Quaestor."))

(defvar *config* (make-instance 'configuration))

(defgeneric load-config (&optional path)
  (:documentation "Load configuration from file, or use defaults."))

(defgeneric save-config (&optional path)
  (:documentation "Save current configuration to file."))

(defmethod load-config (&optional (path *default-config-path*))
  "Load configuration from a sexp file. Uses defaults if file does not exist."
  (if (probe-file path)
      (let ((plist (with-open-file (stream path :direction :input)
                     (read stream nil nil))))
        (when plist
          (setf *config* (make-instance 'configuration
                                        :default-file (getf plist :default-file)
                                        :default-commodity (or (getf plist :default-commodity) "GBP")
                                        :commodity-symbol (or (getf plist :commodity-symbol) "£")
                                        :commodity-position (or (getf plist :commodity-position) :prefix)
                                        :date-format (or (getf plist :date-format) :iso)
                                        :alignment-column (or (getf plist :alignment-column) 50)
                                        :auto-save-interval (getf plist :auto-save-interval 300)
                                        :window-width (or (getf plist :window-width) 1200)
                                        :window-height (or (getf plist :window-height) 800)
                                        :recent-files (getf plist :recent-files)))))
      ;; No config file - use defaults
      (setf *config* (make-instance 'configuration)))
  *config*)

(defmethod save-config (&optional (path *default-config-path*))
  "Save current configuration to file, creating directories if needed."
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (let ((*print-pretty* t)
          (*print-case* :downcase))
      (prin1 (list :default-file (config-default-file *config*)
                   :default-commodity (config-default-commodity *config*)
                   :commodity-symbol (config-commodity-symbol *config*)
                   :commodity-position (config-commodity-position *config*)
                   :date-format (config-date-format *config*)
                   :alignment-column (config-alignment-column *config*)
                   :auto-save-interval (config-auto-save-interval *config*)
                   :window-width (config-window-width *config*)
                   :window-height (config-window-height *config*)
                   :recent-files (config-recent-files *config*))
             stream)))
  path)

;;; --- Main Entry Point ---

(defun %limit-font-path ()
  "Prevent McCLIM from scanning all system TrueType fonts at startup.
   Per jackdaniel: set mcclim-truetype:*truetype-font-path* to empty
   string before port initialization."
  (let ((sym (find-symbol "*TRUETYPE-FONT-PATH*" "MCCLIM-TRUETYPE")))
    (when (and sym (boundp sym))
      (setf (symbol-value sym) "")
      t)))

(defun main (&key file)
  "Launch the Quaestor application."
  (%limit-font-path)
  (load-config)
  ;; Apply config globals
  (setf *default-commodity* (config-default-commodity *config*))
  (setf *default-commodity-symbol* (config-commodity-symbol *config*))
  (setf *default-alignment-column* (config-alignment-column *config*))
  ;; Determine which file to open
  (let* ((ledger-path (or file
                          (config-default-file *config*)))
         (ledger (when (and ledger-path (probe-file ledger-path))
                   (parse-ledger-file ledger-path)))
         (frame (make-application-frame 'quaestor
                                        :width (config-window-width *config*)
                                        :height (config-window-height *config*))))
    (when ledger
      (setf (frame-ledger frame) ledger)
      (setf (frame-status-message frame)
            (format nil "Loaded ~A (~D transactions)"
                    (file-namestring ledger-path)
                    (length (ledger-transactions ledger)))))
    (run-frame-top-level frame)))
