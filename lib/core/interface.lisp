#|
  This file is a part of TyNETv5/Radiance
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :radiance)

(defun lambda-keyword-p (symbol)
  (find symbol '(&allow-other-keys &aux &body &environment &key &optional &rest &whole)))

(defun flatten-lambda-list (lambda-list)
  (mapcar #'(lambda (a) (if (listp a) (car a) a)) lambda-list))

(defun extract-lambda-vars (lambda-list)
  (remove-if #'lambda-keyword-p (flatten-lambda-list lambda-list)))

(defun extract-macro-lambda-vars (macro-lambda-list)
  (loop with varlist = ()
     for i from 0 below (length macro-lambda-list)
     for arg in macro-lambda-list
     do (when (find arg '(&key &optional &rest &body &aux))
          (return (append varlist (extract-lambda-vars (nthcdr i macro-lambda-list)))))
       (unless (lambda-keyword-p arg)
         (if (listp arg)
             (appendf varlist (extract-lambda-vars arg))
             (appendf varlist (list arg))))
     finally (return varlist)))

(defun make-key-extensible (generic-lambda-list)
  (if (or (find '&rest generic-lambda-list)
          (find '&body generic-lambda-list))
      generic-lambda-list
      (if (find '&key generic-lambda-list)
          (append generic-lambda-list '(&allow-other-keys))
          (append generic-lambda-list '(&key &allow-other-keys)))))

(defun macro-lambda-list->generic-list (macro-lambda-list)
  (loop with in-required-args = T
     for arg in macro-lambda-list
     collect (cond
               ((eql arg '&body)
                (setf in-required-args NIL)
                '&rest)
               ((or (eql arg '&rest) (eql arg '&key) (eql arg '&optional))
                (setf in-required-args NIL)
                arg)
               ((and in-required-args (listp arg))
                (gensym (format NIL "~{~a~^-~}" (extract-lambda-vars arg))))
               ((listp arg)
                (car arg))
               (T arg))))

(defun intern-list-symbols (list package)
  (loop for element in list
     collect (if (and (symbolp element) (not (keywordp element)))
                 (intern (string-upcase element) package)
                 element)))

(defmacro define-interface-component-expander (name (name-var args-var options-var &optional (interface-var (gensym "INTERFACE-NAME"))) &body body)
  "Defines a new interface component expander.
NAME         --- A symbol designating the component's type name.
NAME-VAR     --- A symbol that will be bound to the name specified in the component
                 declaration.
ARGS-VAR     --- A symbol that will be bound to the arguments list specified in the
                 component declaration.
OPTIONS-VAR  --- A symbol that will be bound to the options list specified in the
                 component declaration.
PKG-NAME-VAR --- A symbol that will be bound to the name of the interface and as
                 such to the name of the package it is declaring.
BODY         --- forms.

Do note that the component-expander expands into a macro. This is necessary to
get access to symbols in a package that may not exist at expansion of the
interface macro. To reach such a symbol anyway, create a gensym and expand into
a let that binds the gensym to a FIND-SYMBOL or INTERN call.
Another consequence of this is that in order to have a form appear in the actual
interface definition itself it needs to be doubly backquoted, as only one back-
quote will make it execute within the generated macro."
  (assert (symbolp name) () "Name has to be a symbol.")
  `(setf (gethash ,(make-keyword name) *radiance-interface-expanders*)
         #'(lambda (,name-var ,args-var ,options-var ,interface-var)
             ,@body)))

(defun get-interface-component-expander (name)
  "Returns the function-object of the component-expander, if any can be found."
  (gethash (make-keyword (string-upcase name)) *radiance-interface-expanders*))

(defun interface-component-types ()
  "Returns a list of supported component-types as their keyword names."
  (hash-table-keys *radiance-interface-expanders*))

(define-interface-component-expander class (classname slots options package-name)
    (let ((slotsgens (gensym "SLOTS"))
          (tmpgens (gensym "TEMP"))
          (pkg-class (gensym "PKG-CLASS")))
      `(let ((,pkg-class (find-symbol ,(format NIL "~a" classname) ',package-name))
             (,slotsgens (loop for ,tmpgens in ',slots
                               collect (intern-list-symbols ,tmpgens ',package-name))))
         `(defclass ,,pkg-class () ,,slotsgens ,',@(remove :type options :key #'car)))))

(define-interface-component-expander function (funcname args options package-name)
  (with-gensyms ((wholegens "WHOLE") (pkg-function "PKG-FUNCTION") (pkg-method "PKG-METHOD") (pkg-impl-var "PKG-IMPL-VAR"))
    (let* ((documentation (second (assoc :documentation options)))
           (args (make-key-extensible args))
           (argsgeneric (flatten-lambda-list args))
           (call-function (if (or (find '&rest args)) 'apply 'funcall)))
      `(let ((,pkg-function (find-symbol ,(string funcname) ',package-name))
             (,pkg-method (intern ,(format NIL "I-~a" funcname) ',package-name))
             (,pkg-impl-var (find-symbol "*IMPLEMENTATION*" ',package-name)))
         `(progn
            (defgeneric ,,pkg-method (,',(gensym "MODULE") ,@',argsgeneric))
            (defmacro ,,pkg-function (&whole ,',wholegens ,@',args)
              ,@',(when documentation (list documentation))
              (declare (ignore ,@',(extract-macro-lambda-vars args)))
              `(,',',call-function #',',,pkg-method ,',,pkg-impl-var ,@(cdr ,',wholegens))))))))

(define-interface-component-expander macro (funcname args options package-name)
  (with-gensyms ((wholegens "WHOLE") (pkg-function "PKG-FUNCTION") (pkg-method "PKG-METHOD") (pkg-impl-var "PKG-IMPL-VAR"))
    (let* ((documentation (second (assoc :documentation options)))
           (args (make-key-extensible args))
           (argsgeneric (macro-lambda-list->generic-list args))
           (call-function (if (or (find '&rest args)
                                  (find '&body args))
                              'apply 'funcall)))
      `(let ((,pkg-function (find-symbol ,(string funcname) ',package-name))
             (,pkg-method (intern ,(format NIL "I-~a" funcname) ',package-name))
             (,pkg-impl-var (find-symbol "*IMPLEMENTATION*" ',package-name)))
         `(progn
            (defgeneric ,,pkg-method (,',(gensym "MODULE") ,@',argsgeneric))
            (defmacro ,,pkg-function (&whole ,',wholegens ,@',args)
              ,@',(when documentation (list documentation))
              (declare (ignore ,@',(extract-macro-lambda-vars args)))
              (,',call-function #',,pkg-method ,,pkg-impl-var (cdr ,',wholegens))))))))

(define-interface-component-expander accessor (funcname args options package-name)
  (with-gensyms ((pkg-class "PKG-CLASS") (pkg-function "PKG-FUNCTION") (pkg-method "PKG-METHOD")
                 (valuegens "VALUE") (fieldgens "FIELD") (instancegens "INSTANCE") (identifiergens "IDENTIFIER"))
    (let ((class-name (second (assoc :CLASS options))))
      (assert class-name () "Class-name required for accessor definition.")
      ``(progn
          ,,(funcall (get-interface-component-expander :function) funcname args options package-name)
          ,(let ((,pkg-class (find-symbol ,(string-upcase class-name) ',package-name))
                 (,pkg-function (find-symbol ,(string funcname) ',package-name))
                 (,pkg-method (find-symbol ,(format NIL "I-~a" funcname) ',package-name)))
             `(progn
                (defmethod getdf ((,',instancegens ,,pkg-class) ,',fieldgens)
                  (,,pkg-function ,',instancegens ,',fieldgens))
                (defmethod (setf getdf) (,',valuegens (,',instancegens ,,pkg-class) ,',fieldgens)
                  (,,pkg-function ,',instancegens ,',fieldgens :value ,',valuegens))
                (defgeneric (setf ,,pkg-method) (,',valuegens ,',identifiergens ,',instancegens ,',fieldgens))
                (defmethod (setf ,,pkg-method) (,',valuegens ,',identifiergens (,',instancegens ,,pkg-class) ,',fieldgens)
                  (,,pkg-method ,',identifiergens ,',instancegens ,',fieldgens :value ,',valuegens))))))))

(defmacro define-interface (name &body component-declarations)
  "Define a new implementation mechanism.
NAME                 ::= PRIMARY-NICKNAME | (PRIMARY-NICKNAME NICKNAME*)
COMPONENT-DECLARATION::= (NAME PRIMARY-ARGUMENTS OPTION*)
OPTION               ::= (OPTION-NAME VALUE*)

NAME                 --- A symbol used for the component's identifier.
PRIMARY-ARGUMENTS    --- A list of arguments used to build the component.
                         Depends on the component TYPE.
OPTION-NAME          --- A keyword identifying the supplied option.
PRIMARY-NICKNAME     --- NICKNAME used to build the fully qualified package name
                         in the form ofORG.TYMOONNEXT.RADIANCE.INTERFACE.name .
NICKNAME             --- A nickname symbol for the interface package.

OPTIONS:

 - :TYPE dictates the type of component being declared, which in turn
decides what is done with the rest of the arguments. To see the possible
components, invoke (RADIANCE:INTERFACE-COMPONENT-TYPES). See 
DEFINE-INTERFACE-COMPONENT-EXPANDER for more information.

 - * Any number of additional options may be passed along, but their usage
depends on the component-expander."
  (etypecase name
    (symbol)
    (list
     (assert (not (null name)) () "Interface name cannot be NIL.")
     (mapc #'(lambda (name) (assert (symbolp name) () "Interface names have to be symbols.")) name)))
  (with-gensyms
      ((macro-name    "INTERFACE-GENERATOR")
       (pkg-impl-var  "PKG-IMPL-VAR") (pkg-impl-fun  "PKG-IMPL-FUN")
       (new-impl-gens "NEW-IMPL") (provided-gens "PROVIDED"))
    (let* ((nicknames (if (listp name) name (list name)))
           (name (if (listp name) (car name) name))
           (fqpn (intern (format NIL "ORG.TYMOONNEXT.RADIANCE.INTERFACE.~a" name) :KEYWORD)))
      `(progn
         (defpackage ,fqpn
           (:nicknames ,@(mapcar #'(lambda (name) (intern (string-upcase name) :KEYWORD)) nicknames))
           (:export ,@(append '(#:*implementation* #:implementation)
                              (mapcar #'(lambda (a) (make-symbol (string-upcase (car a)))) component-declarations))))
         (asdf:defsystem ,(intern (format nil "RADIANCE-~a" name))
           :class :interface  :interface-name ,(find-symbol (string-upcase name) :KEYWORD))
         (macrolet ((,macro-name ()
                      (let ((,pkg-impl-var (find-symbol "*IMPLEMENTATION*" ',name))
                            (,pkg-impl-fun (find-symbol "IMPLEMENTATION" ',name)))
                        `(progn
                           (defvar ,,pkg-impl-var NIL)
                           (declaim (inline ,,pkg-impl-fun))
                           (defun ,,pkg-impl-fun (&optional (,',new-impl-gens NIL ,',provided-gens))
                             (if ,',provided-gens
                                 (setf ,,pkg-impl-var ,',new-impl-gens)
                                 ,,pkg-impl-var))
                           ,,@(loop for declaration in component-declarations
                                    collect (destructuring-bind (specified-name args &rest options) declaration
                                              (let* ((component-type (or (second (assoc :type options)) :function))
                                                     (function (get-interface-component-expander component-type)))
                                                (if function
                                                    (funcall function specified-name args options name)
                                                    (error 'no-such-interface-component-error
                                                           :interface-component component-type
                                                           :interface name)))))))))
           (,macro-name))
         (find-package ',name)))))

(defmacro define-interface-method (function argslist &body body)
  "Defines a new implementation of an interface function.

BODY       :== form*
ARGSLIST   :== specialized-lambda-list | ((:module IDENTIFIER [var]) specialized-lambda-list)
FUNCTION   --- A symbol
IDENTIFIER --- The module-identifier used for the implementation.

FUNCTION should be the symbol of an interface function. If the 
requested function cannot be be found in the package, a condition
of type NO-SUCH-INTERFACE-FUNCTION-ERROR will be signalled.

This macro will attempt to automatically retrieve the module-identifier
from the current package. If you want to set this manually or bind it
to a function-local variable, provide a first argument as a list,
formed in the way specified above. Note that this will be used as a
parameter-specializer-name, so it can be either a class-symbol or an
EQL form.

If you want to manually implement an interface function to get hold
of all of the CLOS functionality, you can always define your own
method on the respective INTERFACE::I-PUBLIC-FUNCTION-NAME generic."
  (let ((pkg-method (find-symbol (format NIL "I-~a" function) (symbol-package function))))
    (if pkg-method
        (progn
          (if (and (listp (first argslist)) (eq (caar argslist) :MODULE))
              (setf (car argslist) (list (or (caddar argslist) (gensym "MODULE"))
                                         (cadar argslist)))
              (push (list (gensym "MODULE") `(eql (context-module-identifier))) argslist))
          (setf argslist (make-key-extensible argslist))
          (let ((restpos (position '&body argslist)))
            (if restpos (setf (nth restpos argslist) '&rest)))
          `(defmethod ,pkg-method ,argslist
             ,@body))
        (error 'no-such-interface-function-error :interface (package-name (symbol-package function)) :interface-function function))))

(defclass interface (asdf:system)
  ((%interface-name :initarg :interface-name :initform NIL :accessor interface-name))
  (:documentation "Base class for radiance interfaces so modules may depend on them. 
Loading a system of this class will search for an interface definition in the
radiance configuration and attempt to load it. It is not guaranteed that the 
requested interface will be properly implemented after the load of this system."))

(defmacro with-asdf-system ((interface systemvar &optional (namevar (gensym "NAME"))) &body body)
  (with-gensyms ((implementationgens "IMPLEMENTATION"))
    `(progn
       (unless *radiance-config* (load-config))       
       (let* ((,namevar (interface-name ,interface))
              (,implementationgens (config-tree :interface ,namevar)))
         (if ,implementationgens
             (let ((,systemvar (asdf:find-system ,implementationgens)))
               ,@body)
             (error 'no-interface-implementation-error :interface ,namevar))))))

;; Hack into ASDF to delegate to the chosen implementation for the interface.
(defmethod asdf::plan-action-status ((plan null) (op asdf:operation) (interface interface))
  (with-asdf-system (interface system)
    (v:debug :radiance.framework.interface "Delegating (ASDF::PLAN-ACTION-STATUS ~s ~s ~s) to ~s" plan op interface system)
    (asdf::plan-action-status plan op system)))

(defmethod asdf:needed-in-image-p ((op asdf:operation) (interface interface))
  (with-asdf-system (interface system)
    (v:debug :radiance.framework.interface "Delegating (ASDF:NEEDED-IN-IMAGE-P ~s ~s) to ~s" op interface system)
    (asdf:needed-in-image-p op system)))

(defmethod asdf::compute-action-stamp (plan (op asdf:operation) (interface interface) &key just-done)
  (with-asdf-system (interface system)
    (v:debug :radiance.framework.interface "Delegating (ASDF::COMPUTE-ACTION-STAMP ~s ~s ~s :JUST-DONE ~s) to ~s" plan op interface just-done system)
    (asdf::compute-action-stamp plan op system :just-done just-done)))

(defmethod asdf:perform ((op asdf::load-op) (interface interface))
  (with-asdf-system (interface system)
    (v:debug :radiance.framework.interface "Delegating (ASDF:PERFORM ~s ~s) to ~s" op interface system)
    (asdf:operate op system)))

;; Hook into load-op to define the implementation afterwards.
(defmethod asdf:perform :after ((op asdf:load-op) (interface interface))
  (with-asdf-system (interface system name)
    (v:debug :radiance.framework.interface "Setting ~a as implementation for ~a" system interface)
    (let ((package (find-package name)))
      (if package
          (let* ((module-spec (assoc name (implementation-map system)))
                 (module (if (consp (cdr module-spec)) (second module-spec) (cdr module-spec))))
            (if module
                (setf (symbol-value (find-symbol "*IMPLEMENTATION*" package))
                      (etypecase module
                        (function (funcall module))
                        (symbol module)
                        (standard-object module)))))
          (error 'no-such-interface-error :interface name)))))
