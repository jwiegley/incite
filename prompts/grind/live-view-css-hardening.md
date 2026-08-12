You are auditing Phoenix function components for **CSS and attribute
hardening**. A component that takes raw class strings has no visual contract:
any caller can override it, a global rename breaks it in silence, and a
component gallery that renders it without the caller's defaults renders it
wrong.

Audit every function component for these four.

1. **A `class` attr with a string default.** `attr :class, :string, default:
   ""` never renders its default in a gallery that calls the component bare.
   The pattern that holds up is `attr :rest, :global, include: ~w(class)` with
   `{@rest}` spread on the root element, so caller classes propagate without
   becoming part of the contract.
2. **Undeclared assigns.** Every assign a component accepts must be declared
   with `attr`, typed, and marked `required: true` where the component is
   wrong without it. An undeclared assign passes through or drops in silence,
   and both hide bugs.
3. **Variant props without `values:`.** A prop that selects among a closed set
   — a size, a tone, a state — declares the set: `attr :size, :string,
   values: ~w(sm md lg)`. Without it, a typo at one call site renders the
   default styling and no error anywhere.
4. **Conditional class logic interpolated in the template.** A string built
   from nested conditionals inside `class={...}` is logic nobody can trace or
   test. Extract it to a helper function that returns a class list.

For each finding, report the component, the file and line, which of the four
it is, and the corrected declaration or helper as code — the exact `attr` line
or the extracted function, not a description of one.

A component whose class passthrough is deliberate and documented at the call
sites is not finding material for the passthrough alone; check its other
attrs and move on. Say which components you cleared.
