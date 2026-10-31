(asdf:defsystem "charje.documentation"
  :version "0.0.0"
  :description
  "Documentation is an opinionated yet customizable docstring parsing library."
  :author "Charles Jackson <charles.b.jackson@protonmail.com>"
  :license "AGPL V3 or any later version"
  :homepage "https://git.sr.ht/~charje/documentation"
  :source-control "https://git.sr.ht/~charje/documentation"
  :depends-on
  ("alexandria")
  :in-order-to ((test-op (load-op "charje.documentation/test")))
  :components
  ((:module "src" :serial t
    :components
    ((:file "package")
     (:file "main")))))

(asdf:defsystem "charje.documentation/test"
  :components
  ((:module "test"
    :components
    ((:file "main")))))
