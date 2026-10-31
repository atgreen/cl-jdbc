;;;; command-line-args.lisp

(in-package whereiseveryone.command-line-args)

(declaim (declaration parser flag))

(defun parse-parser-declarations (declarations)
  "Parse all the custom parser declarations.

   DECLARATIONS: A list of all the declare forms.
   Returns a hash table where the keys are the names of the function
   parameters and the values are the names of the parser functions."
  (flet ((declare-declaration (declare-form)
           (rest declare-form))
         (declaration-specifier (declaration)
           (first declaration))
         (parser-declaration-function (parser-declaration)
           (second parser-declaration))
         (parser-declaration-parameters (parser-declaration)
           (rest (rest parser-declaration))))
    (let ((parsers (make-hash-table)))
      (dolist (declaration declarations parsers)
        (dolist (declare-form (declare-declaration declaration))
          (when (eq 'parser (declaration-specifier declare-form))
            (let ((parser-function
                    (parser-declaration-function declare-form)))
              (dolist (parameter (parser-declaration-parameters declare-form))
                (setf (gethash parameter parsers)
                      parser-function)))))))))

(defun parse-flag-declarations (declarations)
  (let ((flags (make-hash-table)))
    (dolist (declaration declarations flags)
      (dolist (declare-form (rest declaration))
        (when (eq 'flag (first declare-form))
          (let ((flag-char (second declare-form))
                (parameters (rest (rest declare-form))))
            (check-type flag-char character)
            (assert (alpha-char-p flag-char)
                    nil
                    "The flag character must be a character.")
            (assert (= 1 (length parameters))
                    nil
                    "A flag character can only be used for a single parameter.")
            (let ((parameter (first parameters)))
              (setf (gethash parameter flags)
                    flag-char))))))))

(defun flagp (thing)
  (and (stringp thing)
       (str:starts-with-p "-" thing)
       (notevery #'digit-char-p
                 (string-left-trim '(#\-) thing))))

(defun combined-short-flags-p (flag)
  (and (stringp flag)
       (str:starts-with-p "-" flag)
       (< 2 (length flag))
       (every #'alpha-char-p (str:substring 1 nil flag))))

(defun short-form-flag (flag-mapping arg-keyword parameter)
  (gethash parameter flag-mapping
           (char-downcase
            (char (symbol-name arg-keyword) 0))))

(defun flag-match-p (short-form long-form flag)
  (let ((flag-word (string-left-trim '(#\-) flag)))
    (or (string= flag-word long-form)
        (and (= 1 (length flag-word))
             (char= (char flag-word 0)
                    short-form)))))

(defun parse-boolean (arg)
  "Parse ARG as a shell Boolean. Only return `t' for non empty strings.

   ARG: The thing to be parsed. Parsing will not be attempted for non-strings."
  (and (stringp arg)
       (str:non-empty-string-p arg)))

(defmacro increment-boolean-counter (param)
  `(progn
     (setq ,param (or ,param 0))
     (incf ,param)))

(defun commandify (s)
  (intern (format nil "~A-COMMAND" (symbol-name s))))

(defun generate-keyword-args-parser (command-line-args parsers flag-overrides keyword-params)
  (with-gensyms (flag)
    `(progn
       ;; set the values from the command-line-args
       (loop
         (let ((,flag (first ,command-line-args)))
           (when (string= "--" ,flag)
             (pop ,command-line-args)
             (return))
           (unless (flagp ,flag)
             (return))
           (pop ,command-line-args)
           (cond
             ((combined-short-flags-p ,flag)
              (do ((short-flag-index 1 (1+ short-flag-index)))
                  ((= short-flag-index (length ,flag)))
                (let ((short-flag (aref ,flag short-flag-index)))
                  (cond
                    ,@(remove
                       nil
                       (mapcar
                        (lambda-ematch
                          ((list (list arg param) _ _)
                           (when (= (length (symbol-name arg)) 1)
                             (warn 'keyword-argument-too-short :supplied arg))
                           (let ((parser (gethash param parsers)))
                             (when (eq 'parse-boolean parser)
                               `((char= ,(short-form-flag flag-overrides arg param)
                                        short-flag)
                                 (increment-boolean-counter ,param))))))
                        keyword-params))
                    (t
                     (error 'invalid-combined-short-flag
                            :flag short-flag
                            :combined-flag ,flag))))))
             ,@(mapcar
                (lambda-ematch
                  ((list (list arg param) _ _)
                   `((flag-match-p
                      ,(short-form-flag flag-overrides arg param)
                      ,(str:downcase (symbol-name arg)) ,flag)
                     ,(let ((parser-function (gethash param parsers)))
                        (cond
                          ((eq 'parse-boolean parser-function)
                           `(increment-boolean-counter ,param))
                          (parser-function
                           `(setq ,param ,(generate-argument-parser command-line-args parsers param)))
                          (t `(setq ,param (pop ,command-line-args))))))))
                keyword-params)
             (t
              (error 'invalid-flag
                     :flag ,flag)))))
       ;; set the default values
       ,@(mapcar
          (lambda-ematch
            ((list (list _ param) default-value _)
             (when default-value
               `(unless ,param
                  (setq ,param ,default-value)))))
          keyword-params))))

(defun generate-check-argument-lengths (variadicp command-line-args required-params optional-params)
  (if variadicp
      `(unless (<= ,(length required-params)
                   (length ,command-line-args))
         (error 'wrong-number-of-args
                :supplied (length ,command-line-args)
                :min ,(length required-params)))
      (with-gensyms (minimum-args maximum-args)
        `(let* ((,minimum-args ,(length required-params))
                (,maximum-args
                  (+ ,minimum-args ,(length optional-params))))
           (unless (<= ,minimum-args
                       (length ,command-line-args)
                       ,maximum-args)
             (error 'wrong-number-of-args
                    :supplied (length ,command-line-args)
                    :min ,minimum-args
                    :max ,maximum-args))))))

(defun generate-argument-parser (command-line-args parsers parameter-name)
  (let ((parser-function (gethash parameter-name parsers)))
    (with-gensyms (unparsed-arg)
      `(let ((,unparsed-arg (pop ,command-line-args)))
         ,(flet ((with-helpful-error-message (parser-function body)
                   `(handler-bind
                        ((error
                           (lambda (c)
                             (declare (ignore c))
                             (format *debug-io*
                                     "Error while parsing argument for `~A'. Got ~S, which could not be parsed by `~A'."
                                     ,(str:downcase (symbol-name parameter-name))
                                     ,unparsed-arg
                                     ',parser-function))))
                      ,body)))
            (ematch parser-function
              ((guard (list 'list parser-function)
                      (and parser-function
                           (symbolp parser-function)))
               (with-helpful-error-message parser-function
                 `(loop
                    collect (,parser-function ,unparsed-arg)
                    while ,command-line-args
                    do (setq ,unparsed-arg (pop ,command-line-args)))))
              ((guard _ parser-function)
               (with-helpful-error-message parser-function
                 `(,parser-function ,unparsed-arg)))
              (_ unparsed-arg)))))))

(defun parse-required-args-let-bindings (command-line-args parsers required-params)
  (mapcar
   (lambda (param)
     `(,param ,(generate-argument-parser command-line-args parsers param)))
   required-params))

(defun parse-optional-args-let-bindings (command-line-args parsers optional-params)
  (mapcar
   (lambda-ematch
     ((list param default-value _)
      `(,param (if ,command-line-args
                   ,(generate-argument-parser command-line-args parsers param)
                   ,default-value))))
   optional-params))

(defun last-parameter (required-params optional-params)
  (or (first (first (last optional-params)))
      (first (last required-params))))

(defun check-variadic-parameter-parser (parsers required-params optional-params keyword-params)
  (let ((last-positional-parameter (last-parameter required-params optional-params)))
    (flet ((check-valid-variadic-parser (param)
             (let ((parser (gethash param parsers)))
               (unless (or (not parser)
                           (symbolp parser)
                           (eq param last-positional-parameter))
                 (error 'invalid-variadic-parser
                        :param param
                        :parser parser)))))
      (dolist (keyword-param keyword-params)
        (ematch keyword-param
          ((list (list _ param) _ _)
           (check-valid-variadic-parser param))))
      ;; make sure none of the required parameters or optional
      (dolist (required-param required-params)
        (check-valid-variadic-parser required-param))
      ;; parameters are variadic except for the last one
      (dolist (optional-param optional-params)
        (ematch optional-param
          ((list param _ _)
           (check-valid-variadic-parser param)))))))

(defvar *command-line-invocation* nil)

(defvar *command-line-args* nil)

(defmacro subcommand-case (subcommand &body subcommands)
  "Use for a command to dispatch onto another command by the first
   argument. If SUBCOMMAND matches any of the symbol-names (lowercased)
   of the CASES, call the related command.

   SUBCOMMAND: The user provided variable which selects which
   subcommand to execute. It should be the one and only positional
   argument for comamnds where `subcommand-case' is used. It should be
   raw user input and not mutated or cleaned up at all.

   SUBCOMMANDS: A list of function names all of which should be
   defined inside of a `command'.

   You may be tempted to just use your own `cond', but using using
   `subcommand-case' will ensure that documentation is generated for
   your subcommands.

   When SUBCOMMAND does not match any of SUBCOMMANDS, an
   `invalid-subcommand' is signaled. You can handle this condition to
   customize the behavior of a mismatched subcommand."
  (once-only (subcommand)
    `(cond
       ,@(mapcar
          (lambda (single-case)
            `((string= ,subcommand ,(str:downcase (symbol-name single-case)))
              (,(commandify single-case)
               *command-line-invocation*
               *command-line-args*)))
          subcommands)
       (t
        (error 'invalid-subcommand
               :subcommand subcommand)))))

(defun subcommand-cases (code)
  (map-tree (lambda-ematch
              ((list* 'subcommand-case _ cases)
               (return-from subcommand-cases cases))
              (code code))
            code)
  nil)

(defun help-time-p (command-line-args)
  (and command-line-args
       (null (rest command-line-args))
       (member (first command-line-args)
               '("-h" "--help" "help")
               :test #'string-equal)))

(defun print-paragraph (string &optional (out *standard-output*))
  (let ((*print-escape* nil))
    (format out "~/pprint-fill/"
            (str:split-omit-nulls " " string))))

(defun generate-help (flag-overrides docstring
                      subcommand-cases
                      required-params required-variadic
                      optional-params optional-variadic
                      keyword-params)
  (let ((docstring (docstring:parse 'docstring:full (or docstring "")))
        (*print-right-margin* 80))
    `(progn
       ;; executable name
       (format t "Usage: ~A" *command-line-invocation*)
       ;; options indicator
       (format
        t
        ,(with-output-to-string (*standard-output*)
           (when keyword-params
             (format t " [OPTIONS...] [--]"))
           ;; positional parameters without variadic
           (dolist (param required-params)
             (format t " ~:@(~A~)" param)
             (when (eq param required-variadic)
               (format t "...")))
           ;; optional parameters without variadic
           (when optional-params
             (format t " [")
             (let ((first-param-p t))
               (dolist (param optional-params)
                 (ematch param
                   ((list param _ _)
                    (unless first-param-p
                      (format t " ")
                      (setq first-param-p nil))
                    (format t "~:@(~A~)" param)
                    (when (eq param optional-variadic)
                      (format t "..."))))))
             (format t "]"))
           (terpri)
           ;; first section of docstring (synopsis)
           (print-paragraph (docstring:synopsis docstring))
           (terpri)
           ;; subcommands
           (when subcommand-cases
             (format t "~%Subcommands:~%")
             (dolist (subcommand subcommand-cases)
               (format t "~2T~(~A~)" subcommand)
               (when-let (docstring (documentation subcommand 'function))
                 (format t "~20T")
                 (print-paragraph
                  (docstring:synopsis
                   (docstring:parse 'docstring:synopsis docstring))))
               (terpri)))
           (terpri)
           ;; arguments
           (when (or required-params
                     optional-params)
             (format t "Arguments:~%")
             (dolist (required-param required-params)
               (format t "~2T~:@(~A~)~12T" required-param)
               (print-paragraph
                (docstring:parameter-description docstring required-param))
               (terpri))
             (dolist (optional-param optional-params)
               (ematch optional-param
                 ((list name _ _)
                  (format t "~2T~:@(~A~)~12T" name)
                  (print-paragraph
                   (docstring:parameter-description docstring name))))
               (terpri))
             (terpri))
           ;; list of options
           (when keyword-params
             (format t "Options:~%")
             (let ((short-flags (make-hash-table)))
               (dolist (param keyword-params)
                 (ematch param
                   ((list (list arg param) _ _)
                    (let* ((would-be-short-flag
                             (short-form-flag flag-overrides arg param))
                           (short-flag
                             (and (not (gethash would-be-short-flag short-flags))
                                  would-be-short-flag)))
                      (if short-flag
                          (progn
                            (format t "~2T-~A, " short-flag)
                            (setf (gethash short-flag short-flags) t))
                          (format t "~6T"))
                      (format t "--~(~A~)~24T"
                              (symbol-name arg))
                      ;; description
                      (format t "~29T")
                      (print-paragraph
                       (docstring:parameter-description docstring param))
                      (terpri)))))))
           ;; the rest of the description
           (terpri)
           (dolist (description (docstring:descriptions docstring))
             (print-paragraph description)
             (terpri)))))))

(defmacro command (defun)
  "Define a function that parses the command line arguments for and
   then calls the funciton defined by DEFUN.

   DEFUN: A typical `defun' form. It is evaluated to define the
   function as usual.

   The new function generated will be the same as the function defined
   by the DEFUN with a -command suffix. Feel free to use this for the
   entry-point of your executable or script.

   `&key' parameters become command line options. These are parsed
   first, before required parameters. Each option will have a long
   form and a short form (if it is not already taken by another
   parameter). The long form is the whole name of the parameter
   preceded by 2 hyphens. The short form is the first letter of the
   parameter preceded by a single hyphen. In either case the option
   and the actual argument are separated by a space on the command
   line. The short flag customized by using a `flag' declaration as
   follows:

   (command
    (defun custom-short-flag (&key some-option)
      (declare (flag #\o some-option))
      ...)

   That will make it so that the -o option argument is the
   `some-option' argument.

   Most keyword parameters will take an argument. Using
   `parse-boolean' as a parser for a parameter makes it not take an
   argument. If the command line option is not present the value will
   be `nil', else if it is present it will be the number of time the
   command line option appeared.

   For a variadic parameter, do not use `&rest'. Instead declare the
   parser like so:

   (command
    (defun variadic-function (variadic-param)
      (declare (parser (list parse-integer)
                       variadic-param))
      ...))

   That will a variable number of integer from the command line
   arguments. Note only the last positional argument can be
   variadic. To have a variadic parameter without any special parser
   (just plain strings) use the following parser:

   (declare (parser (list identity) variadic-parameter))."
  (ematch defun
    ((list* 'defun fn-name lambda-list body)
     (multiple-value-bind (forms declarations docstring)
         (parse-body body :documentation t)
       (declare (ignore forms))
       (let ((parsers (parse-parser-declarations declarations))
             (flag-overrides (parse-flag-declarations declarations)))
         (multiple-value-bind (required-params optional-params rest-param keyword-params)
             (parse-ordinary-lambda-list lambda-list)
           (when (and rest-param (null keyword-params))
             (warn 'rest-used-for-variadic
                   :parameter-name rest-param
                   :parser-name (gethash rest-param parsers 'identity)))
           (check-variadic-parameter-parser parsers required-params optional-params keyword-params)
           (let* ((variadic-param-p
                    (lambda (param)
                      (let ((parser (gethash param parsers)))
                        (match parser
                          ((list 'list _) t)))))
                  (required-variadic (find-if variadic-param-p required-params))
                  (optional-variadic
                    (first (find-if (compose variadic-param-p #'first)
                                    optional-params)))
                  (variadic-param (or required-variadic optional-variadic))
                  (subcommand-cases (subcommand-cases defun)))
             (with-gensyms (command-line-args)
               `(progn
                  ,defun
                  (defun ,(commandify fn-name)
                      (&optional
                         (*command-line-invocation*
                          (or *command-line-invocation*
                              (first (uiop:raw-command-line-arguments))))
                         (,command-line-args (uiop:command-line-arguments)))
                    (when (help-time-p ,command-line-args)
                      ,(generate-help flag-overrides
                                      (or docstring
                                          (documentation fn-name 'function))
                                      subcommand-cases
                                      required-params required-variadic
                                      optional-params optional-variadic
                                      keyword-params)
                      (return-from ,(commandify fn-name)))
                    (let (,@(mapcar (compose #'second #'first) keyword-params))
                      ,(generate-keyword-args-parser
                        command-line-args parsers
                        flag-overrides keyword-params)
                      ,(unless subcommand-cases
                         (generate-check-argument-lengths
                          variadic-param command-line-args
                          required-params optional-params))
                      (let* (,@(parse-required-args-let-bindings
                                 command-line-args parsers required-params)
                             ,@(parse-optional-args-let-bindings
                                 command-line-args parsers optional-params)
                             ;; for any potential subcommands
                             (*command-line-args* ,command-line-args)
                             (*command-line-invocation*
                               (format nil "~A ~A"
                                       *command-line-invocation*
                                       ,(first required-params))))
                        (,fn-name
                         ,@required-params
                         ,@(mapcar #'first optional-params)
                         ,@(apply #'append (mapcar #'first keyword-params)))))))))))))))
