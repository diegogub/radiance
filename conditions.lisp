#|
 This file is a part of Radiance
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.radiance.core)

(defvar *debugger* NIL)

(define-condition radiance-error (error)
  ((message :initarg :message :initform NIL :accessor message)))

(define-condition radiance-warning (warning)
  ((message :initarg :message :initform NIL :accessor message)))

(define-condition environment-not-set (radiance-error) ()
  (:report "The application environment was not yet set but is required.
            This means you are either using Radiance for the first time or forgot to set it up properly.
            In the first case, simply use the CONTINUE restart. In the second, make sure to adjust your
            configuration and use the SET-ENVIRONMENT restart to set an explicit environment."))

(define-condition internal-error (radiance-error) ()
  (:report (lambda (c s) (format s "An internal error has ocurred.~@[ ~a~]" (message c)))))

(define-condition request-error (radiance-error)
  ((current-request :initarg :request :initform *request* :accessor current-request))
  (:report (lambda (c s) (format s "An error has ocurred while processing the request ~a.~@[ ~a~]"
                                 (current-request c) (message c)))))

(define-condition request-empty (request-error) ()
  (:report (lambda (c s) (format s "The reply body was NIL on request ~a.~@[ ~a~]"
                                 (current-request c) (message c)))))

(define-condition request-not-found (request-error) ()
  (:report (lambda (c s) (format s "There was nothing that could handle the request ~a.~@[ ~a~]"
                                 (current-request c) (message c)))))

(define-condition request-denied (request-error) ()
  (:report (lambda (c s) (format s "Access denied.~@[ ~a~]"
                                 (message c)))))

(define-condition api-error (request-error) ()
  (:report (lambda (c s) (format s "The API call to ~a failed.~@[ ~a~]"
                                 (current-request c) (message c)))))

(define-condition api-auth-error (api-error) ()
  (:report (lambda (c s) (format s "The API call to ~a was denied.~@[ ~a~]"
                                 (current-request c) (message c)))))

(define-condition api-argument-missing (api-error)
  ((argument :initarg :argument :initform (error "ARGUMENT required.") :accessor argument))
  (:report (lambda (c s) (format s "The argument ~s is required, but was not passed.~@[ ~a~]"
                                 (argument c) (message c)))))

(define-condition api-argument-invalid (api-error)
  ((argument :initarg :argument :initform (error "ARGUMENT required.") :accessor argument))
  (:report (lambda (c s) (format s "The argument ~s is not valid.~@[ ~a~]"
                                 (argument c) (message c)))))

(define-condition api-call-not-found (api-error) ()
  (:report (lambda (c s) (format s "The requested api call address could not be found.~@[ ~a~]" (message c)))))

(define-condition api-response-empty (api-error) ()
  (:report (lambda (c s) (format s "The API response was empty.~@[ ~a~]" (message c)))))

(define-condition api-unknown-format (api-error)
  ((requested-format :initarg :format :initform (error "FORMAT required.") :accessor requested-format))
  (:report (lambda (c s) (format s "The requested format ~s is not known.~@[ ~a~]"
                                 (requested-format c) (message c)))))

(define-condition database-error (radiance-error) ())

(define-condition database-warning (radiance-warning) ())

(define-condition database-connection-failed (database-error)
  ((database :initarg :database :initform (error "DATABASE required.") :accessor database))
  (:report (lambda (c s) (format s "Failed to connect to database ~a.~@[ ~a~]"
                                 (database c) (message c)))))

(define-condition database-connection-already-open (database-warning)
  ((database :initarg :database :initform (error "DATABASE required.") :accessor database))
  (:report (lambda (c s) (format s "Connection to database ~a already open.~@[ ~a~]"
                                 (database c) (message c)))))

(define-condition database-invalid-collection (database-error)
  ((collection :initarg :collection :initform (error "COLLECTION required.") :accessor collection))
  (:report (lambda (c s) (format s "No such collection ~s.~@[ ~a~]"
                                 (collection c) (message c)))))

(define-condition database-collection-already-exists (database-error)
  ((collection :initarg :collection :initform (error "COLLECTION required.") :accessor collection))
  (:report (lambda (c s) (format s "The collection ~s already exists.~@[ ~a~]"
                                 (collection c) (message c)))))

(define-condition database-invalid-field (database-error)
  ((fielddef :initarg :fielddef :initform (error "FIELD required.") :accessor fielddef))
  (:report (lambda (c s) (format s "The field declaration ~s is invalid.~@[ ~a~]"
                                 (fielddef c) (message c)))))

(define-condition data-model-not-inserted-yet (database-error)
  ((model :initarg :model :initform (error "MODEL required.") :accessor model))
  (:report (lambda (c s) (format s "The model ~s has not been inserted yet.~@[ ~a~]"
                                 (model c) (message c)))))

(define-condition user-error (radiance-error)
  ((user :initarg :user :initform (error "user required.") :accessor user)))

(define-condition user-not-found (user-error) ()
  (:report (lambda (c s) (format s "The user ~s could not been found.~@[ ~a~]"
                                 (user c) (message c)))))

(defun handle-condition (condition)
  (l:warn :radiance "Handling stray condition: ~a" condition)
  (restart-case
      (if *debugger*
          (invoke-debugger condition)
          (invoke-restart 'present-error-page))
    (present-error-page ()
      :report "Send back an appropriate error page to the client."
      (invoke-restart
       'set-data
       (typecase condition
         (request-not-found
          (setf (return-code *response*) 404)
          (data-file "html/error/404.html"))
         (request-denied
          (setf (return-code *response*) 403)
          (data-file "html/error/403.html"))
         (T
          (setf (return-code *response*) 500)
          (data-file "html/error/500.html")))))))
