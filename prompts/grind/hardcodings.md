You are auditing a source tree for **values baked in where they should be
derived, configured, or named once**. The test for a finding is not that a
literal appears. It is that some future change breaks the literal silently.

Hunt these five.

1. **Magic numbers inline.** Column widths, indent sizes, buffer sizes,
   arbitrary limits. Grep the production tree for multi-digit numbers outside
   the test tree, then judge each one. A number that appears twice is a
   constant with no name; a number that encodes a rule is a rule with no home.
2. **Paths, file extensions, and module names that must track the target
   list.** Grep for the quoted extension of each target language. Adding a
   backend must not mean hunting string literals through the tree. Where the
   extension for a target lives in more than one place, the second place is the
   one that goes stale.
3. **Target lists and per-target dispatch tables written more than once.**
   There should be exactly one enumeration of the target languages, and every
   command, every interactive shell, every downgrade path and every spec file
   should derive from it rather than restate it. A second list is a list that
   will be short by one the day a target lands.
4. **Identifiers baked into the generated output.** Prefixes, suffixes, package
   names, header text that should come from the source specification or from a
   naming function. Generated code carrying a name nobody chose is generated
   code that collides the first time a user picks that name.
5. **Test expectations that rot.** Hardcoded counts, version strings, dates,
   absolute paths. A count is the worst of these: it goes red for the right
   reason and gets bumped without anybody reading why.

For every finding give the location, then the sentence that makes it a finding:
what change breaks this quietly. Then say where the value belongs instead —
which existing module, which existing enumeration, which derivation.

A literal with one home and one reader is not a finding. Say nothing about it.
