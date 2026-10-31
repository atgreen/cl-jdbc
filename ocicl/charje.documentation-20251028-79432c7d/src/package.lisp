(defpackage charje.documentation
  (:use #:cl)
  (:import-from #:alexandria
                #:once-only
                #:with-gensyms)
  (:export
   #:defdocstring
   #:define-docstring-parser
   #:description
   #:descriptions
   #:do-sections
   #:full
   #:parameter-description
   #:parameter-descriptions
   #:parse
   #:parse-section
   #:remains
   #:synopsis))
