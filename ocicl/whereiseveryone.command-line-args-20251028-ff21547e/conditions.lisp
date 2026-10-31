;;;; conditions.lisp

(in-package whereiseveryone.command-line-args)

(define-condition command-line-condition () ()
  (:documentation
   "The parent conditio for the `whereiseveryone.command-line-args' system."))

(define-condition rest-used-for-variadic (command-line-condition warning)
  ((parameter-name
    :reader parameter-name
    :initarg :parameter-name
    :type symbol
    :documentation
    "The name of the `&rest' parameter.")
   (parser-name
    :reader parser-name
    :initarg :parser-name
    :type (or cons symbol)
    :documentation
    "The parser declared for the `&rest' parameter."))
  (:report
   (lambda (c out)
     (format out "&rest used for variadic. Declare the list parser on the last required or &optional parameter to get variadic args: ~%~A"
             `(declare
               (parser (list
                        ,(if (and (listp (parser-name c))
                                  (eq (first (parser-name c)) 'list))
                             (second (parser-name c))
                             (parser-name c)))
                       ,(parameter-name c))))))
  (:documentation
   "This is when `&rest' is used in the `command' macro. There is no
    sane way to map the Common Lisp concept of `&rest' to the shell
    concept of variadic arguments. This is because the Common Lisp
    `&rest' includes the keyword arguments."))

(define-condition wrong-number-of-args (command-line-condition error)
  ((number-of-args-supplied
    :reader number-of-args-supplied
    :initarg :supplied
    :type integer
    :documentation
    "The number of arguments supplied by the user of the command line
     tool at run time.")
   (minimum-number-of-args
    :reader minimum-number-of-args
    :initarg :min
    :type integer
    :documentation
    "The minimum number of positional arguments that this command can take.")
   (maximum-number-of-args
    :reader maximum-number-of-args
    :initarg :max
    :initform nil
    :type (or null integer)
    :documentation
    "The maximum number of positional arguments that this command can
     take. `nil' indicates that there is no maximum and the command
     can take any number of positional arguments greater or equal to
     the `minimum-number-of-args'."))
  (:report
   (lambda (c out)
     (format out "You supplied ~A args but the command requires "
             (number-of-args-supplied c))
     (cond
       ((not (maximum-number-of-args c))
        (format out "at least"))
       ((= (minimum-number-of-args c)
           (maximum-number-of-args c))
        (format out "exactly"))
       (t (format out "between ~A and"
                  (minimum-number-of-args c))))
     (format out " ~A arg~:p.~%"
             (or (maximum-number-of-args c)
                 (minimum-number-of-args c)))
     (when (zerop (maximum-number-of-args c))
       (format out "Did you mean to give some options instead?~%"))
     (format out "See --help for the possible arguments.~%")))
  (:documentation
   "This is when the user of the command line provided too few or too
    many arguments for this command to handle."))

(define-condition invalid-flag (command-line-condition error)
  ((flag
    :reader flag
    :initarg :flag
    :type string
    :documentation
    "The flag that the user of the command line provided."))
  (:report
   (lambda (c out)
     (format out "You provided the `~A' option which is not a valid option for this command.~%"
             (flag c))
     (format out "See --help for the possible options.~%")))
  (:documentation
   "This is when a user of the command line tried to provide a
    command line option that this command has not been defined to
    handle."))

(define-condition invalid-combined-short-flag (invalid-flag)
  ((combined-flag
    :reader combined-flag
    :initarg :combined-flag
    :type string
    :documentation
    "The combined short flag the contains the invalid flag."))
  (:report
   (lambda (c out)
     (format out "You used `~A' in a combined short option `~A', but it is not a boolean option.~%"
             (flag c)
             (combined-flag c))
     (format out "See --help for the possible short options.~%")))
  (:documentation
   "This is when the user of the command line provides an invalid flag
    that in the form of a combined short flag: (-abcd) where a, b, c,
    and d are all different arguments and one of them is not valid for
    this command."))

(define-condition invalid-variadic-parser (command-line-condition error)
  ((parameter
    :reader param
    :initarg :param
    :type symbol
    :documentation
    "The parameter that was declared as variadic but cannot be for
     whatever reason.")
   (bad-parser
    :reader parser
    :initarg :parser
    :type (or cons symbol)
    :documentation
    "The declared parser for `parameter'."))
  (:report
   (lambda (c out)
     (format
      out
      "Only the last positional argument can be variadic.~%~
       You have `~A' being parsed with `~A' which is not a valid parser for a non-variadic parameter.~%"
      (param c)
      (parser c))))
  (:documentation
   "This is when the programmer declares variadic parser for a
    parameter which cannot be variadic due to its position in the
    lambda-list."))

(define-condition keyword-argument-too-short (command-line-condition style-warning)
  ((arg
    :reader arg
    :initarg :supplied
    :type keyword
    :documentation
    "The keyword argument defined as part of the lambda-list."))
  (:report
   (lambda (c out)
     (format out "The keyword argument supplied is too short: ~A.~%"
             (arg c))))
  (:documentation
   "This is when the programmer defines a function with a keyword
    parameter whos argument is too short. Very short keyword arguments
    get confusing when it comes to short options versus long options."))

(define-condition invalid-subcommand (command-line-condition error)
  ((subcommand
    :reader subcommand
    :initarg :subcommand
    :type string
    :documentation
    "The user supplied subcommand that does not match any of the
     subcommands that this command is designed to handle."))
  (:report
   (lambda (c out)
     (format out "`~A' is not a valid subcommand.~%"
             (subcommand c))
     (format t "See --help to see the possible subcommands.~%")))
  (:documentation
   "This is when the user of the command line provides a subcommand
    that doesn't match any of the subcommands."))
