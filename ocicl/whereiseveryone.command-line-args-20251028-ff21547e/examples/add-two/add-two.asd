(defsystem "add-two"
  :depends-on
  ("whereiseveryone.command-line-args"
   "cl-annot")
  :components ((:file "add-two"))
  :around-compile
  "(lambda (thunk)
     (cl-annot:enable-annot-syntax)
     (funcall thunk))"
  :build-operation "program-op"
  :entry-point "add-two::add-two-command"
  :build-pathname #.(merge-pathnames #p"add-two" (uiop:getcwd)))
