(in-package charje.documentation)

(assert
 (string= "abc. def."
          (synopsis
           (parse 'synopsis
                  "abc.
                   def."))))

(assert
 (string= "abc."
          (synopsis
           (parse 'synopsis
                  "abc.

                   def."))))

(let ((docstring (parse 'parameter-descriptions
                        "A: Something bout A.

                         B: Something bout B.")))
  (assert (string= "Something bout A."
                   (parameter-description docstring 'a)))
  (assert (string= "Something bout B."
                   (parameter-description docstring 'b))))

(let ((docstring (parse 'description
                        "Something.

                         Something else.")))
  (assert (= 2 (length (descriptions docstring)))))

(let ((docstring (parse 'full
                        "Something.")))
  (assert (= 0 (length (descriptions docstring)))))
