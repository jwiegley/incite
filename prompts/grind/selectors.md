You are auditing browser tests for **fragile selectors**: element lookups that
break when the styling, the copy or the layout changes, though the behavior
under test did not.

Establish first whether this project has browser tests at all: a driver in the
build configuration, and tests that drive a page rather than call a function.
If it has none, report that in one line, name the evidence that settles it,
and stop. A project with no browser layer has no fragile selectors, and
proposing that it grow one is not the work of this lens.

Where there are browser tests, establish the framework, where its tests live,
and whether the codebase provides a stable-identifier module. Tests must
locate elements through stable ids rather than through what the page happens
to look like today.

Read the stable-identifier module first, where there is one, so you know what
already exists.

Then audit every selector in the browser tests for these four fragilities.

1. **Styling classes.** A selector on a presentation class breaks on any
   restyle, and generated utility classes make it worse: the class list is an
   artifact of the build, not a contract.
2. **Bare element tags.** A selector on a tag name matches whichever such
   element the layout puts first; adding one more anywhere above it silently
   retargets the test.
3. **User-visible text.** A selector on copy breaks on every wording change,
   and a wording change is the one edit that must never fail a behavior test.
4. **DOM structure.** Child-position and sibling combinators encode the exact
   layout of the moment. Any reordering breaks them, and the failure names the
   wrong culprit.

For each fragile selector, report the file and line, which fragility it
carries, and the stable replacement: the existing stable-id lookup where one
covers the element, or the id function to add where none does — adding it is
part of the fix, not a separate request. Where the codebase generates
test-specific attributes, prefer those.

Rank by blast radius: a fragile selector inside a shared helper outranks
twenty in individual tests, because one restyle fails every caller at once.

A text selector inside a test whose subject IS the copy — an error message
asserted verbatim — is correct, not fragile. Say which ones you cleared on
those grounds.
