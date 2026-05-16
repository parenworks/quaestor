(in-package #:quaestor)

;;; MOP extensions for Quaestor.
;;; Provides an auditable metaclass that tracks modification times on instances,
;;; and a dirty-tracking mixin for change detection.

(defclass auditable-class (standard-class)
  ()
  (:documentation "Metaclass that adds automatic modification tracking to instances."))

(defmethod validate-superclass ((class auditable-class) (super standard-class))
  t)

(defclass auditable-object ()
  ((%created-at :initform (get-universal-time)
                :reader object-created-at)
   (%modified-at :initform (get-universal-time)
                 :accessor object-modified-at))
  (:metaclass auditable-class)
  (:documentation "Base class for objects that track creation and modification times."))

(defmethod (setf slot-value-using-class) :after
    (new-value (class auditable-class) (object auditable-object) slot)
  "Automatically update modification timestamp when any user slot is written."
  (let ((slot-name (slot-definition-name slot)))
    (unless (member slot-name '(%created-at %modified-at))
      (setf (slot-value object '%modified-at) (get-universal-time)))))

;;; Dirty-tracking mixin for detecting unsaved changes.

(defclass dirty-tracking-mixin ()
  ((%dirty-p :initform nil :accessor object-dirty-p)
   (%snapshot :initform nil :accessor object-snapshot))
  (:documentation "Mixin that tracks whether an object has been modified since last save."))

(defgeneric snapshot (object)
  (:documentation "Take a snapshot of the object's current state for dirty comparison."))

(defgeneric dirty-p (object)
  (:documentation "Return T if the object has been modified since last snapshot."))

(defmethod snapshot ((object dirty-tracking-mixin))
  "Default snapshot stores a plist of all user-visible slot values."
  (let ((slots (class-slots (class-of object))))
    (setf (object-snapshot object)
          (loop for slot in slots
                for name = (slot-definition-name slot)
                unless (member name '(%dirty-p %snapshot %created-at %modified-at))
                  when (slot-boundp object name)
                    collect (cons name (slot-value object name))))))

(defmethod dirty-p ((object dirty-tracking-mixin))
  "Compare current slot values against the stored snapshot."
  (let ((snap (object-snapshot object))
        (slots (class-slots (class-of object))))
    (if (null snap)
        (object-dirty-p object)
        (loop for slot in slots
              for name = (slot-definition-name slot)
              unless (member name '(%dirty-p %snapshot %created-at %modified-at))
                thereis (let ((current (and (slot-boundp object name)
                                           (slot-value object name)))
                              (saved (cdr (assoc name snap))))
                          (not (equal current saved)))))))
