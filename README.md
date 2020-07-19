# ShowNice
Show data more nicely in the Julia REPL

## Motivation

Julia has a very sophisticated infrastructure for displaying data, but I find its output in the REPL ... unsatisfying.  Too often, typing `show(x)` either returns too little information, or too much information in a lengthy, near-incomprehensible string.

## Guiding Principles

`show(x)` should show a salient textual representation or overview of `x`.
Such a representation should indicate the type of `x`, its structure, and the data that comprises it.

- Specialized formatting may be used to implicitly indicate the type of `x`, e.g. `[ ]`
  indicates an array, `( )` indicates a tuple, etc.
- The structure of `x` is shown up to some reasonable depth. The amount of detail shown
 	may decrease with nesting depth.
- Large containers may be summarized by their initial and final elements.

## Design

Their are different contexts:
- for non-types:  Top level, element of a composite, parameter of a type (if a simple type)
- for types: 		Top level, type info for a value, parameter of a type

This is all handled through two context parameters:
- :depth - An integer denoting the level of structural nesting.  Defaults to 0.
- :max_depth - The maximum depth of structure to show.
- :show_typeinfo (bool) - Whether or not to show type info

<!-- There are four main use cases:
- Provide a user with a meaningful, visually appealing, and easily understandable textual representation or summary of a given Julia value.
- Produce a concise textual representation of a value for non-Julian targets, e.g. for a
- Produce a parseable string that is equivalent to the given value. -->


<!-- `print(x)` should produce a textual representation of `x` with

 This may involve Julia-specific annotation and formatting.  It does not generally yield a valid Julia expression for constructing `x`.  Type information is generally shown, except when the context or formatting indicates the type.

 `repr(x)` should return a string representation of `x` that constructs `x`. -->
