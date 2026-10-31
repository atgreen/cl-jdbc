# Charles' Docstring Parser

This docstring parser is opinionated and easy to customize.

## Opinionate

A docstring has 3 parts:
- synopsis
- parameter descriptions
- further description


A docstring is made of sections (think paragraphs). Each section is separated by 2 consecutive `#\newline`s.


Parameters of a function, macro, or generic function Should be written in all uppercase. References to other lisp symbols should be written in `...' style quotes.


In the source code, the first character of each section should be aligned with the first character after the starting quote of the docstring.


Each parameter description should be its own section where the section starts with the parameter name (all uppercase) followed by a `#\colon` and a `#\space`. It is of course permitted for the parameters to show up in the synopsis, other parameter descriptions, and the further description.

A docstring might omit the parameter descriptions or the further description if they are not needed.

Example:
```lisp
(defun docstring-example (first second)
  "Just serve as an example of how a docstring should look.
   
   FIRST: Who knows what happens with this argument. The ... could be anything.
   
   SECOND: Really, it could be whatever you can imagine. I wonder if it has
   something to do with the `first' and `second' functions.
   
   In case you couldn't tell already, This function is just to serve as an
   example of how a docstring should look. It doesn't really do anything, and it
   probably never will."
  ...)
```
### Parsing

You can parse such a docstring using `(parse 'full "blah blah")`.

Once you have it parsed you can use the `synopsis`, `parameter-description`, and `descriptions` functions to get at the parts of the docstring.

If you only need a part of a docstring, you can just parse that part. For example, if you only need the synopsis, you can do `(synopsis (parse 'synopsis "blah blah"))`.


## Customize

What, you don't like my totally arbitrary docstring format? That is okay you can define your own.

A docstirng parser is a mixin class where the `initialize-instance :after` method parsed the docstring (`remains`) until it is satisfied. You can easily define such a parser using `define-docstring-parser`. You can even use `parse-section` and `do-sections` if you please; they operate on sections as defined previously.

Once you have all your individual parsers, you can combine them using `defdocstring`.
