# Description

`whereiseveryone.command-line-args` is a Common Lisp system for automatically generating command line interfaces (CLIs). Turn your Common Lisp function into a command which you can use from the command line. Do so without thinking about organizing command line options, traversing command line arguments, or generating a help message.

By writing just a few declarations, you can get command line options, positional arguments, variadic parameters, and a help message.

With just a tiny bit of code, you can get subcommands nested however deeply you want (see the `subcommand-case` macro).

Every command is generated with help options (`-h`, `--help`) and a help subcommand `help`. The help text is largely populated by the docstring for the command; it also uses information about subcommands and flags.

Project page can be found [here](https://git.sr.ht/~whereiseveryone/command-line-args).

# Example

This example shows an imaginary and abbreviated version of how one might define a typical Unix `ls` command. It shows how to declare parsers, declare alternative flag, and variadic arguments. The keyword arguments become command line options.

```lisp
;; Assume you have a pakcage local nickname of cli for whereiseveryone.command-line-args (like the whereiseveryone.command-line-args.user package).
;; Assume you are using cl-annot and have already enabled the reader.
@cli:command
(defun ls (&optional (files (list (uiop:getcwd)))
           &key all author list reverse recursive size human-readable
             ignore (width 0) (tabsize 8))
  (declare
   ;; make files variadic
   (cli:parser (list merge-pathnames) files)
   ;; parse these as Boolean options
   (cli:parser cli:parse-boolean
               all author list reverse recursive size human-readable)
   ;; parse `ignore' as a regular expression
   (cli:parser ppcre:parse-string ignore)
   ;; parse these as integers
   (cli:parser parse-integer width tabsize)
   ;; use -R for `recursive` instead of the already taken -r
   (cli:flag #\R recursive)
   ;; use -T for `tabsize` instead of the default -t
   (cli:flag #\T tabsize))
  "List information about the FILES (the current directory by default).

   FILES: The directories to have their information listed.

   ALL: Do not ignore entries starting with \".\".

   AUTHOR: With LIST, print the author of each file.

   LIST: Use a long listing format.

   REVERSE: Reverse order while sorting.

   RECURSIVE: List subdirectories recursively.

   SIZE: Print the allocated size of each file in blocks.

   HUMAN-READABLE: With LIST and SIZE, print sizes like 1K 234M 2G etc.

   IGNORE: Do not list implied entries matching shell pattern.

   WIDTH: Set output width. 0 means no limit.

   TABSIZE: Set the tabstops for the long listing format. Default is 8."
  ...)
```

A sample usage might look like:

```sh
$ ls -Ral --tabsize 10 --ignore '\.\..*' dir1 dir2
```

Here is what the help looks like. We are working on improving it based on the docstring.

```sh
$ ls --help
Usage: ls [OPTIONS...] [--] [FILES...]
List information about the FILES (the current directory by default).

Arguments:
  FILES     The directories to have their information listed.

Options:
  -a, --all                  Do not ignore entries starting with ".".
      --author               With LIST, print the author of each file.
  -l, --list                 Use a long listing format.
  -r, --reverse              Reverse order while sorting.
  -R, --recursive            List subdirectories recursively.
  -s, --size                 Print the allocated size of each file in blocks.
  -h, --human-readable       With LIST and SIZE, print sizes like 1K 234M 2G
                             etc.
  -i, --ignore               Do not list implied entries matching shell pattern.
  -w, --width                Set output width. 0 means no limit.
  -T, --tabsize              Set the tabstops for the long listing format.
                             Default is 8.
```

See a further example in `examples/` and `t.lisp`.

For the docstring to be parsed correctly, use the docstring format described by https://git.sr.ht/~charje/documentation.

# Todo

- macroexpand defun to support other macros that support defun

# Contributing

Send patches to ~whereiseveryone/command-line-args@lists.sr.ht

 [charje](https://git.sr.ht/~charje) or [jgart](https://git.sr.ht/~jgart/) can review patches and merge them.

[Reach out](https://web.libera.chat/gamja/#whereiseveryone) if you would like to discuss the project.
