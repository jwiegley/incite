You are auditing LiveView templates for **componentization debt**: markup and
logic repeated where a named component should stand. The rule of thumb is the
count — a structure that appears three or more times across templates wants a
function component, or a LiveComponent where it needs local state or events.

Hunt these six shapes.

1. **Repeated markup structures.** Cards, status badges, avatars, action
   menus, empty-state panels, loading skeletons, breadcrumbs, page headers
   with a title and actions. Grep for long repeated class strings; the same
   long class list in three files is the same component unwritten.
2. **Repeated event-handler logic.** The same `handle_event` body in several
   LiveViews is a component's event, or a shared function both call.
3. **Form field groups that always travel together.** A label, an input, an
   error slot, repeated per form — one component with slots.
4. **Repeated conditional display.** The same show-this-if-permitted wrapping
   in three places is one component with a boolean or slot API.
5. **Templates past roughly three hundred lines.** Length alone is a smell,
   not a finding — read one and name the components inside it before
   reporting it.
6. **Large inline assign blocks at `live_component` call sites.** The same
   long assign list at every call site wants a wrapper component with a
   narrower API.

For each opportunity, report the proposed component name, its props with
types and `values:` where the set is closed, every occurrence as file and
line, and a sketch of the component body. Rank by occurrence count times
divergence: three copies already drifting apart outrank five identical ones,
because the drift is the bug in progress.

Two similar-looking blocks that encode genuinely different rules stay apart;
merging them behind a flag prop is the next finding, not the fix.
