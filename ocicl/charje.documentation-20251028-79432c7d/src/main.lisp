(in-package charje.documentation)

(defun whitespacep (char)
  (member char
          '(#\tab #\newline #\return #\space)
          :test #'char=))

(defun skip-whitespace (position string)
  (do ((current-char (char string position)
                     (char string (incf position))))
      ((not (whitespacep current-char))))
  position)

(defun parse-section (docstring)
  "Parse a section out of DOCSTRING. Return (values section section-end).

   DOCSTRING: The raw docstring to be partially parsed.

   The first return value, section, is a string of the section. The
   second return value, section-end, is the number of characters
   parsed; it is effectively the length of the section.

   Sections are separated by two consecutive `#\newline'. A single
   `#\newline' followed by any whitespace will be reduced to a single
   `#\space' in the result."
  (if (string= "" docstring)
      (values nil 0)
      (let ((synopsis-end 0)
            (starting-position (skip-whitespace 0 docstring)))
        (values
         (with-output-to-string (synopsis)
           (do ((position starting-position next)
                (next (1+ starting-position) (1+ next)))
               ((or (and (<= (length docstring) next)
                         (setq synopsis-end next))
                    (and (char= #\newline
                                (char docstring position)
                                (char docstring next))
                         (setq synopsis-end (1+ next))))
                (unless (whitespacep (char docstring position))
                  (write-char (char docstring position) synopsis)))
             (let ((current-char (char docstring position)))
               (cond
                 ((char= #\newline current-char)
                  ;; write a space and skip whitespace
                  (write-char #\space synopsis)
                  (setq next (skip-whitespace position docstring)))
                 (t (write-char current-char synopsis))))))
         synopsis-end))))

(defmacro do-sections ((section-name docstring) &body body)
  "Parse sections in DOCSTRING until there are none left.

   SECTION-NAME: The name of the parsed section. It is lexically bound in BODY.

   DOCSTRING: The docstring object to operate on.

   BODY: Code to do something with SECTION-NAME. Usually process it
   and or store it into one of the slots of DOCSTRING.

   At the each iteration, the current section (SECTION-NAME) is
   considered consumed. If at any point you want to end parsing and
   consider the current section not consumed, simply `return'.

   This macro also updates the `remains' of DOCSTRING to no longer
   include the consumed sections.

   This macro is for parsing multiple sections at once. For parsing a
   single section, see the more primitive `parse-section'."
  (with-gensyms (remains section section-end)
    (once-only (docstring)
      `(loop
         (let ((,remains (remains ,docstring)))
           (multiple-value-bind (,section ,section-end) (parse-section ,remains)
             (if ,section
                 (let ((,section-name ,section))
                   ,@body
                   (setf (remains ,docstring) (subseq ,remains ,section-end)))
                 (return))))))))

(defclass docstring ()
  ((remains
    :accessor remains
    :initarg :docstring
    :type string)))

(defmacro define-docstring-parser (name slots &rest body)
  "Define a docstring parser mixin class for use in `parse' and `defdocstring'.

   NAME: The name of the docstring parser. NAME is also bound in the
   BODY as the docstring object.

   SLOTS: A list of slots defined exactly as if for `defclass'. Any
   methods defined by the slots will be available in BODY.

   BODY: Code to parse a docstring. The docstring to be
   parsed is in (remains NAME). It should be parsed into the SLOTS.

   This is just to reduce the boiler plate of `defclass' and
   `defmethod' for `initialize-instance'. If you need something like a
   meta class feel free to just define a class and an
   `initialize-instance' method."
  (with-gensyms (initargs)
    `(progn
       (defclass ,name (docstring)
         ,slots)
       (defmethod initialize-instance :after ((,name ,name) &rest ,initargs &key &allow-other-keys)
         (declare (ignore ,initargs))
         ,@body))))

(define-docstring-parser synopsis
    ((synopsis
      :reader synopsis
      :writer (setf raw-synopsis)
      :initform ""
      :type string))
  (let ((remains (remains synopsis)))
    (multiple-value-bind (section synopsis-end) (parse-section remains)
      (when section
        (setf (raw-synopsis synopsis) section
              (remains synopsis) (subseq remains synopsis-end))))))

(defun parameter-description-parts (section)
  (let ((colon-position (position #\colon section :test #'char=)))
    (when colon-position
      (let ((name (subseq section 0 colon-position)))
        (when (parameter-name-p name)
          (values
           name
           (let ((beginning-of-description (+ 2 colon-position)))
             (if (< beginning-of-description (length section))
                 (subseq section beginning-of-description)
                 ""))))))))

(define-docstring-parser parameter-descriptions
    ((parameters-descriptions
      :reader parameter-descriptions
      :initform (make-hash-table :test #'equal)
      :type hash-table))
  (let ((descriptions (parameter-descriptions parameter-descriptions)))
    (do-sections (section parameter-descriptions)
      (multiple-value-bind (name description) (parameter-description-parts section)
        (if name
            (setf (gethash name descriptions)
                  description)
            (return))))))

(defmethod parameter-description ((docstring parameter-descriptions) (name symbol))
  "Return the description of the symbol NAME according to DOCSTRING."
  (gethash (symbol-name name)
           (parameter-descriptions docstring)))

(defun parameter-name-p (string)
  (every (lambda (char)
           (or (upper-case-p char)
               (char= #\hyphen-minus char)))
         string))

(define-docstring-parser description
    ((description-sections
      :reader descriptions
      :writer (setf raw-descriptions)
      :initform ()
      :type list))
  (let ((description-sections ()))
    (do-sections (section description)
      (push section description-sections))
    (setf (raw-descriptions description)
          (nreverse description-sections))))

(defmacro defdocstring (name &rest parts)
  "Define a docstring parser to be used in `parse' or `defdocstring'.

   NAME: The name of class resulting class.

   PARTS: The docstring parsers in the order they should be
   parsed. This should be the same order that the sections appear in
   the docstrings.

   "
  `(defclass ,name ,(reverse parts)
     ()))

(defdocstring full
  synopsis
  parameter-descriptions
  description)

(defun parse (type docstring)
  "Parse DOCSTRING into a docstring object according to the docstring
   parser TYPE.

   TYPE: The docstring parser as defined by `defdocstring' and
   `define-docstring-parser'.

   DOCSTRING: the raw docstring to be parsed."
  (make-instance
   type
   :docstring docstring))
