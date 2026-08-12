You are auditing LiveView templates for **DOM keying and patching debt**.
Keys tell the patcher which nodes are the same across renders, so it moves
them instead of destroying and rebuilding. Missing keys read as flicker, lost
focus, reset scroll, and dead hook state — bugs users feel and bug reports
never name.

Hunt these five.

1. **`:for` comprehensions without `:key`.** Index-keyed diffing turns a
   prepend into a patch of every row. Add `:key={item.id}` wherever the list
   can reorder, grow at the front, or filter.
2. **Stream items without stable DOM ids.** A stream derives DOM ids from the
   item id; check the streamed structs carry a real id and the template puts
   the stream's DOM id on each rendered element.
3. **Hook-managed elements without update-ignore.** Any element a client hook
   manages — a chart, an editor, a terminal — must carry the ignore marker,
   or a parent re-render replaces its contents and destroys the hook's state.
   Find every hook attachment and check the marker; the ones inside
   re-renderable containers are the live bugs.
4. **Raw string ids on key regions.** Forms, modals, sidebars, charts — the
   regions client code locates — need ids from the stable-id module the
   project facts name, not inline strings that can collide or drift.
5. **Reorderable renders with no key at all.** Sort toggles, filters, search
   results: anywhere order changes at runtime, the key is what keeps a row's
   DOM identity — and its focus and animation state — attached to the datum
   rather than to the position.

For each finding, report the file and line, which of the five it is, what the
user sees when it bites (flicker, lost focus, dead hook), and the fix as the
exact attribute or id change.

Rank by state at stake: a keyless list holding form inputs or hooks outranks
one holding read-only rows. A static list that never changes between renders
needs no key; say which you cleared.
