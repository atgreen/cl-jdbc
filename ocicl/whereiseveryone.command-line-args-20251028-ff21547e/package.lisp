(defpackage whereiseveryone.command-line-args
  (:use cl)
  (:local-nicknames
   (docstring charje.documentation))
  (:import-from #:trivia
                #:match
                #:guard
                #:ematch
                #:lambda-ematch)
  (:import-from #:alexandria
                #:compose
                #:when-let
                #:with-gensyms
                #:once-only
                #:parse-ordinary-lambda-list
                #:parse-body)
  (:import-from #:serapeum
                #:map-tree)
  ;; macros and functions
  (:export
   #:command
   #:subcommand-case
   #:parse-boolean)
  ;; declarations
  (:export
   #:flag
   #:parser)
  ;; conditions
  (:export
   #:command-line-condition
   #:invalid-combined-short-flag
   #:invalid-flag
   #:invalid-subcommand
   #:invalid-variadic-parser
   #:keyword-argument-too-short
   #:rest-used-for-variadic
   #:wrong-number-of-args)
  ;; condition readers
  (:export
   #:combined-flag
   #:flag
   #:maximum-number-of-args
   #:minimum-number-of-args
   #:number-of-args-supplied
   #:subcommand))

(defpackage whereiseveryone.command-line-args.user
  (:use cl)
  (:local-nicknames
   (cli whereiseveryone.command-line-args)))
