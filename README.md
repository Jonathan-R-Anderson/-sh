# D-based Lisp/Haskell Interpreter Prototype

This repository contains a minimal prototype for a Lisp-style interpreter written in [D](https://dlang.org/). The project is inspired by [Axel](https://github.com/axellang/axel), which translates a Lisp dialect to Haskell. In this repository we show how D can be used to build similar tooling that targets an environment with limited system commands such as those described in the [`internetcomputer`](https://github.com/Jonathan-R-Anderson/internetcomputer) project.

The implementation is intentionally small and demonstrates how one might begin to build a cross compiler or interpreter that uses the D toolchain. The code is located in `src/interpreter.d`.

## Building

A D compiler such as `dmd` or `ldc2` is required. To cross compile for a specific target, supply the desired architecture flags to the compiler. For example:

```bash
ldc2 -mtriple=<target> src/interpreter.d -of=interpreter
```

Replace `<target>` with the appropriate triple for the operating system described in the `internetcomputer` repository.

## Usage

```
./interpreter "+ 1 2"  # prints 3
```

The interpreter now supports a broader set of commands:

- `echo` – prints its arguments
- basic arithmetic with `+`, `-`, `*`, and `/`
- variable assignment and expansion using `name=value` and `$name`
- directory commands like `cd`, `pwd`, and `ls`
- Haskell-style `for` loops, e.g. `for 1..3 echo hi`
- concurrent commands using `&`, e.g. `echo one & echo two`
- sequential commands separated by `;`

Running the interpreter with no command argument starts an interactive shell.
You can customize the prompt text using the `PS1` environment variable and its color with `PS_COLOR` (e.g. `PS_COLOR=green`). Type `exit` to leave the shell.

These examples demonstrate how additional Bash commands can be layered on top of a Haskell-inspired syntax. The goal remains to eventually cover the full Bash command set, including job control and other special operators.

## Building Pseudo Languages

A small lexer and parser framework inspired by Python's SLY is provided in
`src/dlexer.d` and `src/dparser.d`. These modules allow custom token rules and
implement a simple recursive-descent parser.

The sample program `src/example.d` evaluates arithmetic expressions using this
framework:

```bash
ldc2 src/example.d src/dlexer.d src/dparser.d -of=example
./example "1 + 2 * 3"   # prints 7
```

## Lisp Flavored Erlang Translator

The program `src/lfe.d` demonstrates how the lexer can be repurposed to build a
very small subset of [Lisp Flavored Erlang](https://lfe.io/). It parses a minimal
Lisp syntax and emits Erlang source code.

Build and run it with:

```bash
ldc2 src/lfe.d src/dlexer.d src/dparser.d -of=lfe
./lfe "(defmodule sample (export (add 2)) (defun add (x y) (+ x y)))"
```

This will print the generated Erlang code for the given expression.

## LFE REPL

A small interactive interpreter `src/lferepl.d` implements a minimal LFE-like REPL. Build it with:

```bash
ldc2 src/lferepl.d src/dlexer.d src/dparser.d -of=lferepl
./lferepl
```

Inside the REPL you can evaluate prefix expressions, assign variables and define functions:

```
lfe> (* 2 (+ 1 2 3 4 5 6))
42
lfe> (set multiplier 2)
2
lfe> (* multiplier (+ 1 2 3 4 5 6))
42
lfe> (defun double (x) (* 2 x))
0
lfe> (double 21)
42
lfe> (exit)
```

The REPL exits when `(exit)` is evaluated.

### Loading Modules

Simple modules can be loaded with `(c "file.lfe")`. Functions defined in a
`defmodule` form are stored using the `module:function` naming convention and can
be invoked after the file is compiled:

```lfe
lfe> (c "tut1.lfe")
#(module tut1)
lfe> (tut1:double 21)
42
```

