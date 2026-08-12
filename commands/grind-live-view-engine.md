> Retired Workflow-tool engine, kept as the back-out until the first paid runs of the `grind-live-view` agent-functor workflow pass (see HANDOFF.md). The live `/grind-live-view` command is `commands/grind-live-view.md`. Delete this file when the paid runs pass.

You are the orchestrator of a comprehensive Phoenix LiveView quality audit AND remediation. Every category must be dispatched. The outputs are: a ranked findings report at `docs/audits/grind-live-view-<YYYY-MM-DD>.md`, a remediation TODO at `docs/audits/grind-live-view-<YYYY-MM-DD>-todo.md`, and a working tree where EVERY finding has been addressed by fix subagents — no exceptions, no deferrals. The workflow moves from audit to remediation automatically; do not stop for confirmation between phases. Nothing is committed; the user reviews the dirty tree.

Before launching the Workflow, run `pwd` in the Bash tool to capture the current working directory. Pass that path as `args: { root: "<result>" }`. Do not research the codebase yourself first — the agents do that work.

Key project facts:
- LiveViews live in `lib/operation_web/live/`
- Components live in `lib/operation_web/components/`
- PubSub topics are centralized in `lib/operation/topics.ex`
- `OperationWeb.Ids` module provides stable DOM IDs
- Paradox codegen under `.dox/lib/` — do not audit generated code
- OTP app: `operation` / `OperationWeb`

Launch this Workflow script verbatim:

```javascript
export const meta = {
  name: 'grind-live-view',
  description: 'Fan-out LiveView quality audit across 11 parallel agents, synthesize ranked findings report, then plan and remediate every finding',
  phases: [
    { title: 'Audit' },
    { title: 'Synthesize' },
    { title: 'Plan', detail: 'build remediation TODO from all findings, double-check completeness' },
    { title: 'Fix', detail: 'one fix agent per disjoint file bucket — every item, no exceptions' },
    { title: 'Verify', detail: 'adversarially verify each fix, repair stragglers, gate on compile + tests' },
  ],
}

const ROOT = args && args.root ? args.root : '.'

const CSS_HARDENING = `
You are auditing COMPONENT CSS HARDENING in a Phoenix LiveView project at ${ROOT}.

The problem: passing raw CSS class strings through components makes them fragile. Any caller can override
visual contracts, global renames break silently, and Storybook fails when class attrs have defaults.

BEST PRACTICES:
- Never declare \`attr :class, :string, default: ""\` — storybook calls components without injecting defaults,
  so the default never renders. Instead: \`attr :rest, :global, include: ~w(class)\` and use \`{@rest}\`
  on the root element to propagate caller-provided classes.
- Every function component should declare ALL accepted attrs with types and \`required: true\` where mandatory.
  Undeclared attrs silently pass through or are silently dropped, both hiding bugs.
- Variant props should use \`values:\` validation: \`attr :size, :string, values: ~w(sm md lg)\`
- Avoid string interpolation of conditional classes in templates (creates hard-to-trace logic).
  Instead: a helper function that returns a class list, or a Paradox-generated CSS illuminate block.

Search patterns:
  grep -rn 'attr :class' ${ROOT}/lib --include="*.ex" 2>/dev/null
  grep -rn 'class={.*@class' ${ROOT}/lib --include="*.ex" 2>/dev/null | head -60
  grep -rn '@rest' ${ROOT}/lib --include="*.ex" 2>/dev/null | head -40
  grep -rn 'def.*assigns.*do' ${ROOT}/lib/operation_web/components --include="*.ex" 2>/dev/null | head -40
  grep -rn 'attr :' ${ROOT}/lib/operation_web/components --include="*.ex" 2>/dev/null | head -80

For each component, check:
1. Does it accept a \`class\` attr with a default string? → BAD, should use \`:rest\`
2. Are all accepted assigns declared with \`attr\`? → Undeclared = invisible bugs
3. Are variant/type attrs validated with \`values:\`?
4. Is class logic complex string interpolation in the template? → Extract to helper

Return JSON:
[{
  "file": "lib/operation_web/components/...",
  "line": 42,
  "component": "MyComponent",
  "issue": "class_default|undeclared_attr|no_values_validation|complex_template_class",
  "description": "...",
  "fix": "... elixir code showing corrected attr declaration or :rest usage ...",
  "value": "high|medium"
}]
`

const COMPONENTIZE = `
You are auditing for COMPONENTIZATION OPPORTUNITIES in a Phoenix LiveView project at ${ROOT}.

Rule: if a pattern of markup + logic appears 3+ times across LiveView templates or components,
it should become a named function component (or LiveComponent if it needs local state/events).

WHAT TO LOOK FOR:
1. Repeated markup structures: cards, status badges, user avatars, action menus, empty-state panels,
   loading skeletons, breadcrumbs, page headers with titles + actions
2. Repeated event-handler patterns (same handle_event logic in multiple LiveViews)
3. Repeated form field groups that always appear together
4. Repeated conditional display logic (e.g. "show X if admin" appearing in 3+ places)
5. LiveViews that exceed ~300 lines of template — a sign of undertested, hard-to-maintain markup
6. \`live_component\` invocations that inline large blocks of assigns — candidate for wrapper component

Search strategies:
  wc -l ${ROOT}/lib/operation_web/live/**/*.ex 2>/dev/null | sort -rn | head -20
  grep -rn 'class=".*border.*rounded.*p-' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -oP 'class="[^"]{20,}"' | sort | uniq -c | sort -rn | head -30
  grep -rn '<.button\|<.input\|<.select' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -oP '<\.[a-z_]+' | sort | uniq -c | sort -rn | head -20
  grep -rn 'def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -oP '"[a-z_]+"' | sort | uniq -c | sort -rn | head -20

For each opportunity, identify: what the component would be called, what props it would take, and
which files:lines it would replace.

Return JSON:
[{
  "proposed_component": "StatusBadge",
  "occurrences": [{"file": "lib/...", "line": 42}, ...],
  "count": 5,
  "props": ["status: :string, values: ~w(pending running succeeded failed)"],
  "sketch": "... heex template ...",
  "value": "high|medium"
}]
`

const LIVENESS = `
You are auditing for LIVENESS GAPS in a Phoenix LiveView project at ${ROOT}.

A liveness gap is where the page shows data that can become stale because there is no
PubSub subscription, no stream, and no polling keeping it up-to-date. The user has to
refresh to see new data.

PATTERNS TO FIND:
1. Data loaded in \`mount\` with NO corresponding \`handle_info\` that refreshes it on change
2. Lists of database records with no stream and no subscription topic
3. Counters or aggregates (counts, sums) loaded once with no live update
4. Status fields (user online, pipeline state, session phase) shown without a subscription
5. Forms that reflect remote state (another user editing the same record) with no sync
6. \`assign_async\` calls with no retry or refresh mechanism on failure

Search:
  grep -rn 'def mount' ${ROOT}/lib/operation_web/live --include="*.ex" -A 30 2>/dev/null | grep -v "PubSub\|subscribe\|start_async\|assign_async\|connected?" | head -100
  grep -rn 'Repo.all\|Repo.get\|DB.all\|DB.get' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -v "handle_info\|start_async\|assign_async" | head -60
  grep -rn 'def mount' ${ROOT}/lib/operation_web/live --include="*.ex" -l 2>/dev/null | xargs grep -L "subscribe\|start_async" 2>/dev/null

For each gap, identify:
- What data goes stale?
- What PubSub topic would broadcast the change? (check lib/operation/topics.ex)
- What does the \`handle_info\` handler need to do?

Return JSON:
[{
  "file": "lib/operation_web/live/...",
  "line": 42,
  "stale_data": "repo.fork_count",
  "trigger": "what user action or background event causes it to change",
  "fix": "subscribe to 'repos:<id>' and handle {:repo_updated, repo} by re-assigning",
  "value": "high|medium"
}]
`

const RERENDER = `
You are auditing for UNNECESSARY RE-RENDERS in a Phoenix LiveView project at ${ROOT}.

Re-render anti-patterns — each one causes wasted diffs, wasted patches, and slower UIs:

1. UNCONDITIONAL ASSIGN: assigning the same value again in handle_info/handle_event without
   checking if it changed. Every assign triggers a diff pass.
   Pattern: find handle_info blocks that assign without first comparing to existing assigns.

2. FULL LIST REPLACE instead of stream: reassigning a whole list when only one item changed.
   Look for: assigns of lists in handle_info that could be stream_insert/stream_delete.

3. PASSING PARENT ASSIGNS INTO COMPONENTS UNNECESSARILY: a component re-renders any time its
   assigns change. If you pass @current_user into every component but only 2 use the name field,
   split it into per-component props.

4. MISSING update/2 SHORT-CIRCUIT in LiveComponents: if update/2 doesn't guard against
   identity-equal assigns, the component re-renders even when nothing changed.

5. TIMER TICKS that update assigns unconditionally:
   \`Process.send_after(self(), :tick, 1000)\` that assigns new timestamps on every tick,
   even when nothing visible changed.

6. handle_info THAT DOES NOT GUARD ON RELEVANCE: handling a broad topic event and re-assigning
   regardless of whether this socket cares about the specific event (e.g. reloading all repos
   when any repo changes, even repos this user doesn't have in their current view).

Search:
  grep -rn 'def handle_info\|def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" -A 10 2>/dev/null | grep "assign(socket\|assign(" | head -80
  grep -rn 'def update' ${ROOT}/lib/operation_web/live --include="*.ex" -A 15 2>/dev/null | head -80
  grep -rn 'Process.send_after.*:tick\|send_after.*:refresh\|send_after.*:poll' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null

For each finding, describe the anti-pattern, the current code, and the optimized version.

Return JSON:
[{
  "file": "lib/operation_web/live/...",
  "function": "handle_info/2",
  "line": 42,
  "anti_pattern": "unconditional_assign|full_list_replace|unnecessary_component_prop|missing_update_guard|unconditional_tick|irrelevant_broadcast_handling",
  "current_code": "...",
  "optimized_code": "...",
  "estimated_render_savings": "high|medium|low",
  "value": "high|medium"
}]
`

const PUBSUB = `
You are auditing for SPAMMY PUBSUB PATTERNS in a Phoenix LiveView project at ${ROOT}.

Spammy PubSub hurts UX by: thrashing the DOM with rapid updates, blocking the LiveView process
mailbox, causing visible flicker, consuming bandwidth on every connected client.

PATTERNS TO FIND:

1. HIGH-FREQUENCY BROADCASTS WITHOUT DEBOUNCE: topics that fire on every DB write, every
   metric sample, or every cursor move — with no coalescing at the subscriber.
   Look for: handle_info that does assign() with no debounce timer or coalesce check.

2. BROAD TOPIC SUBSCRIPTIONS: subscribing to a topic like "pipelines" that broadcasts for
   ALL repos, then filtering in handle_info. Each unfiltered message still wakes the process.
   Should use scoped topics like "pipelines:repo:<id>".

3. BROADCASTING FULL STRUCTS: sending entire Ecto structs on PubSub means every subscriber
   receives megabytes of data on every event. Should broadcast signal (id + event type) only;
   subscriber fetches what it needs.

4. MISSING CONNECTED? GUARD: subscribing in mount without \`connected?(socket)\` guard
   creates a dangling subscription during the static render pass.

5. SUBSCRIBER DOING EXPENSIVE WORK PER MESSAGE: a handle_info that runs a DB query or
   complex computation on EVERY broadcast message — instead of offloading to start_async.

6. PROCESS MAILBOX OVERLOAD RISK: a LiveView subscribed to N high-frequency topics with
   no backpressure — check for topics that fire >10/s with direct handle_info assigns.

Search:
  grep -rn 'PubSub.subscribe\|Topics\.' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -60
  grep -rn 'def handle_info' ${ROOT}/lib/operation_web/live --include="*.ex" -A 8 2>/dev/null | head -120
  cat ${ROOT}/lib/operation/topics.ex 2>/dev/null | head -100
  grep -rn 'connected?(socket)' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -30
  grep -rn 'PubSub.subscribe' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -L 'connected?' 2>/dev/null | head -10

Return JSON:
[{
  "file": "lib/operation_web/live/...",
  "line": 42,
  "pattern": "high_freq_no_debounce|broad_topic|full_struct_broadcast|missing_connected_guard|expensive_handle_info|mailbox_overload_risk",
  "topic": "...",
  "description": "...",
  "fix": "...",
  "value": "high|medium"
}]
`

const BEST_PRACTICES = `
You are auditing PHOENIX LIVEVIEW BEST PRACTICE VIOLATIONS in a project at ${ROOT}.

Apply each of the following checks. For each violation found, report file:line and the fix.

CHECKS:

1. ASSIGN_NEW not used for derived/expensive assigns:
   grep -rn 'assign(socket, :current_user\|assign(socket, :roles\|assign(socket, :permissions' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -20
   → Should use assign_new/3 for anything computed from session or another assign.

2. FULL SOCKET STRUCT CAPTURED IN ASYNC CLOSURE:
   grep -rn 'assign_async\|start_async' ${ROOT}/lib/operation_web/live --include="*.ex" -A 3 2>/dev/null | grep 'socket\.' | head -30
   → The closure must not reference socket.assigns.* — extract to local variables before.

3. COMPONENT RECEIVES WHOLE ASSIGNS MAP:
   grep -rn '{assigns}' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | head -20
   → Splat-passing the whole map ships everything; pass only needed fields explicitly.

4. AUTH CHECK ONLY IN MOUNT, NOT IN HANDLE_EVENT:
   grep -rn 'def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" -A 10 2>/dev/null | grep -v 'current_user\|authorized\|permitted\|can?\|role\|permission\|is_admin' | head -60
   Look for handle_event blocks that mutate data (delete, update, create) without checking
   socket.assigns.current_user authorization.

5. BLOCKING QUERY IN HANDLE_EVENT (should use start_async):
   grep -rn 'def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" -A 15 2>/dev/null | grep 'Repo\.\|DB\.\|HTTPoison\.\|:httpc\.' | head -30

6. TEMPORARY_ASSIGNS NOT USED FOR APPEND-ONLY FEEDS:
   grep -rn 'rows\|entries\|events\|feed' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep 'assign(socket' | head -20
   → Feeds that only grow should use stream or temporary_assigns to cap memory.

7. STREAM_ASYNC NOT USED FOR ASYNC-LOADED COLLECTIONS (use instead of start_async + stream reset):
   grep -rn 'start_async.*fn.*DB.all\|start_async.*fn.*Repo.all' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -10

8. :FOR WITHOUT :KEY on dynamic lists (causes index-based diffing = O(n) patch on prepend):
   grep -rn ':for={' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -v ':key=' | head -40

Return JSON:
[{
  "check": "assign_new|async_socket_capture|splat_assigns|auth_gap|blocking_handle_event|missing_temporary_assigns|missing_stream_async|for_without_key",
  "file": "lib/...",
  "line": 42,
  "description": "...",
  "fix": "... elixir/heex code ...",
  "value": "high|medium"
}]
`

const DOM_KEYING = `
You are auditing DOM KEYING and MORPHDOM OPTIMIZATION OPPORTUNITIES in a Phoenix LiveView project at ${ROOT}.

Proper keying tells morphdom which DOM nodes are the "same" across re-renders, enabling
surgical patching instead of destroying and recreating nodes. Missing keys = visible flicker,
lost focus state, and wasted DOM operations.

CHECKS:

1. :FOR COMPREHENSIONS WITHOUT :KEY (LiveView 1.1+ feature):
   grep -rn ':for={' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -v ':key=' | head -50
   These use index-based diffing. Prepending one item causes N DOM patches. Fix: add :key={item.id}

2. STREAM ITEMS WITHOUT STABLE IDS:
   grep -rn 'stream(' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -20
   Streams auto-generate dom_id from the struct id field. Check: do the structs have a proper :id?
   Any stream rendering items without \`id={dom_id}\` in the template.

3. MISSING phx-update="ignore" ON HOOK-MANAGED ELEMENTS:
   Any DOM element managed by a JS hook (chart, editor, terminal, custom element) that does NOT
   have phx-update="ignore" will have its content replaced by LiveView diffs on any parent re-render,
   destroying hook state.
   grep -rn 'phx-hook=' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -v 'phx-update="ignore"' | head -40
   Check if these are inside elements that could be re-rendered.

4. MISSING STABLE IDS ON KEY UI REGIONS:
   Important UI regions (forms, modals, sidebars, charts) should have stable IDs from OperationWeb.Ids
   so JS can reliably locate them. Check for raw string IDs that could collide or drift:
   grep -rn 'id="[a-z]' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -v 'Ids\.' | head -40

5. KEYING OPPORTUNITIES IN EACH/FOR OVER DYNAMIC DATA:
   List renders where order can change at runtime but no :key is provided — sort toggles,
   filtered lists, search results.

Return JSON:
[{
  "file": "lib/...",
  "line": 42,
  "issue": "for_without_key|stream_without_id|hook_without_ignore|raw_string_id|dynamic_list_no_key",
  "description": "...",
  "fix": "...",
  "value": "high|medium"
}]
`

const PAGE_LOAD = `
You are auditing PAGE LOAD TIME and DATA ACCESS PATTERNS in a Phoenix LiveView project at ${ROOT}.

Slow mount = slow TTFB = bad UX. Every blocking query in mount delays the first render.

CHECKS:

1. SYNCHRONOUS QUERIES IN MOUNT (should be async):
   grep -rn 'def mount' ${ROOT}/lib/operation_web/live --include="*.ex" -A 40 2>/dev/null | grep 'Repo\.\|DB\.\|DB\.all\|DB\.get\|Enum\.map.*Repo' | head -40
   Every query here delays the initial render. Anything not needed for the page skeleton
   should move to assign_async or start_async.

2. N+1 QUERY PATTERNS:
   Look for Enum.map calls that contain a Repo/DB query inside the iteration:
   grep -rn 'Enum.map\|Enum.each\|for.*<-' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -A 3 'Repo\.\|DB\.' | head -60
   Also look in components: update/2 with a DB call per item instead of update_many/1.
   grep -rn 'def update(%' ${ROOT}/lib/operation_web --include="*.ex" -A 10 2>/dev/null | grep 'Repo\.\|DB\.' | head -30

3. MISSING update_many/1 IN LIVE COMPONENTS RENDERED IN LISTS:
   grep -rn 'live_component' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep ':for=' | head -20
   For each: does the component module define update_many/1? Without it, N DB queries fire
   (one per component update/2 call).

4. MISSING PRELOADS (loading associations after the fact):
   grep -rn 'Repo.preload\|DB.preload' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -30
   Multiple separate preload calls that could be collapsed into a single query with join preloads.

5. MISSING SKELETON / LOADING STATE:
   LiveViews that use assign_async but don't render a loading skeleton — the user sees nothing
   until async completes. Check for assign_async without a corresponding <:loading> slot.
   grep -rn 'assign_async' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -20

6. MISSING handle_params LAZY LOADING:
   Data that is only needed when a specific live_action is active but is loaded unconditionally
   in mount. Should guard on socket.assigns.live_action.

Return JSON:
[{
  "file": "lib/...",
  "function": "mount/3 or handle_params/3",
  "line": 42,
  "issue": "sync_query|n_plus_one|missing_update_many|redundant_preloads|missing_skeleton|over_eager_mount",
  "description": "...",
  "fix": "...",
  "ttfb_impact": "high|medium|low",
  "value": "high|medium"
}]
`

const AUTH_AND_SECURITY = `
You are auditing AUTHORIZATION GAPS in Phoenix LiveView event handlers in a project at ${ROOT}.

LiveView's websocket connection persists. A user whose permissions change mid-session can still
send crafted phx-click events. Every handle_event that mutates data must re-verify authorization
independently — NOT rely on what was checked in mount.

CHECKS:

1. HANDLE_EVENT WITH MUTATIONS AND NO AUTH CHECK:
   grep -rn 'def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" -A 20 2>/dev/null \
   | grep -B 5 'Repo\.\|DB\.\|insert\|update\|delete\|create\|destroy' \
   | grep -v 'current_user\|authorized\|permitted\|can?\|role\|permission\|is_admin\|gate\|owner' \
   | head -60

2. PUSH_NAVIGATE / PUSH_PATCH WITHOUT VERIFYING TARGET IS ACCESSIBLE:
   Navigation targets that are constructed from user-supplied params without access checks.
   grep -rn 'push_navigate\|push_patch' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -30

3. SOCKET ASSIGNS USED AS AUTHORIZATION SOURCE WITHOUT RE-VERIFICATION:
   Pattern: \`if socket.assigns.is_admin do ...\` in handle_event, where is_admin was set in mount.
   An admin who loses permissions mid-session still has the stale assign.
   grep -rn 'assigns.is_admin\|assigns.can_\|assigns.role\|assigns.permission' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep 'handle_event\|handle_info' | head -20

4. MISSING CSRF-EQUIVALENT FOR CUSTOM WEBSOCKET COMMANDS:
   Any handle_event that takes an "id" from client params and acts on it without verifying
   that the current user owns/has access to that id.

5. HANDLE_EVENT ACCEPTING RAW USER-SUPPLIED PATHS OR COMMANDS:
   grep -rn 'def handle_event' ${ROOT}/lib/operation_web/live --include="*.ex" -A 5 2>/dev/null | grep 'params\["path"\]\|params\["cmd"\]\|params\["url"\]' | head -20

Return JSON:
[{
  "file": "lib/...",
  "event": "handle_event \\"delete_item\\"",
  "line": 42,
  "issue": "mutation_without_auth|stale_assign_auth|missing_ownership_check|raw_path|push_unverified",
  "description": "...",
  "fix": "...",
  "severity": "critical|high|medium"
}]
`

const ASSIGN_BLOAT = `
You are auditing ASSIGN BLOAT AND MEMORY EFFICIENCY in a Phoenix LiveView project at ${ROOT}.

Every connected socket holds its assigns in memory. Large assigns mean large memory footprint,
large diffs, and large patches sent over the wire on every change.

CHECKS:

1. FULL ECTO STRUCTS STORED IN ASSIGNS:
   grep -rn 'assign(socket, :\|assign(socket,' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -v 'async\|loading\|page\|filter\|modal\|error\|flash' | head -60
   Look for assigns like :repo, :user, :group, :pipeline being set to full DB structs.
   Should project to only the fields the template uses.

2. ASSIGNS NOT NEEDED AFTER INITIAL RENDER (could be temporary):
   Append-only feed rows, search results, one-time query results — stored forever in assigns.
   grep -rn 'rows\|results\|entries\|feed\|log\|events' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep 'assign(socket' | head -30

3. DEEPLY NESTED MAPS IN ASSIGNS:
   grep -rn 'assign(socket.*%{' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep '%{.*%{' | head -20
   Nested maps make diffing expensive and the nesting often hides unnecessary structure.

4. REDUNDANT ASSIGNS (same data stored twice under different keys):
   Look for assigns like :user_id AND :user where :user contains the id — the id is duplicated.
   grep -rn 'assign(socket' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | grep -oP ':\w+' | sort | uniq -c | sort -rn | head -20

5. LARGE LOOKUP TABLES AS ASSIGNS:
   Maps like %{repo_id => pipeline} held in assigns across many socket processes.
   Each connected user gets their own copy. Could be a process dictionary or ETS cache instead.
   grep -rn 'repos_by_\|pipelines_by_\|users_by_\|map.*_by_' ${ROOT}/lib/operation_web/live --include="*.ex" 2>/dev/null | head -20

Return JSON:
[{
  "file": "lib/...",
  "assign_key": ":repo",
  "line": 42,
  "issue": "full_struct|should_be_temporary|nested_map|redundant|large_lookup_table",
  "estimated_size_per_socket": "...",
  "fix": "...",
  "value": "high|medium"
}]
`

const TS_HOOKS = `
You are auditing for TYPESCRIPT HOOK OPPORTUNITIES TO ELIMINATE WEBSOCKET ROUND TRIPS in a
Phoenix LiveView project at ${ROOT}.

The problem: LiveView sends every interaction over the WebSocket to the server, which processes
it and sends a diff back. For minor, purely visual interactions that require NO server state,
this round trip adds 20-200ms of latency and wastes server CPU. TypeScript hooks (phx-hook)
can handle these interactions entirely client-side using handleEvent/pushEvent only when
server state is actually needed.

PATTERNS THAT SHOULD MOVE CLIENT-SIDE:

1. TOGGLE/EXPAND INTERACTIONS with no server side effect:
   - Accordion open/close where the open state is not persisted or broadcast
   - Show/hide panels, tooltips, dropdowns controlled purely by CSS class toggling
   - File diff expand/collapse that only affects display, not data loading
   grep -rn 'phx-click.*toggle\|phx-click.*expand\|phx-click.*collapse\|phx-click.*show\|phx-click.*hide' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | grep -v 'handle_event.*DB\|handle_event.*Repo' | head -40
   For each: does the handle_event do anything besides toggle a boolean in assigns?

2. PURELY VISUAL STATE that doesn't need to survive reconnect:
   - Active tab selection where URL doesn't change (no push_patch needed)
   - Hover states, focus rings, selection highlights
   - Sort order for a list that's already fully loaded client-side
   - Theme preview before save
   grep -rn 'handle_event.*"tab\|handle_event.*"select\|handle_event.*"sort' ${ROOT}/lib/operation_web/live --include="*.ex" -A 8 2>/dev/null | head -80

3. FORM VALIDATION FEEDBACK that fires on every keystroke:
   - phx-change handlers that only validate format (email regex, length check) with no DB lookup
   - These fire on every keypress, causing a round trip per character
   grep -rn 'phx-change\|phx-keyup\|phx-blur' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | head -40
   For each: does the handle_event call Repo/DB? If not, it's a client-side validation candidate.

4. COPY-TO-CLIPBOARD, DOWNLOAD, OPEN-LINK actions that need no server involvement:
   grep -rn 'phx-click.*copy\|phx-click.*download\|phx-click.*open' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | head -20

5. ANIMATION TRIGGERS sent to server and back:
   - An event that only triggers a CSS animation or class change, with no data mutation
   grep -rn 'handle_event.*"animate\|handle_event.*"flash\|handle_event.*"dismiss' ${ROOT}/lib/operation_web/live --include="*.ex" -A 5 2>/dev/null | head -40

6. EXISTING HOOKS THAT PUSH EVENTS UNNECESSARILY:
   Read ${ROOT}/assets/ts/hooks/ and ${ROOT}/assets/js/hooks/ — look for pushEvent calls
   that send data the server immediately echoes back unchanged as a handleEvent with no
   meaningful transformation. The round trip buys nothing.
   find ${ROOT}/assets -name "*.ts" -o -name "*.js" 2>/dev/null | xargs grep -l "pushEvent" 2>/dev/null | head -20

7. DEBOUNCE THAT SHOULD BE PURELY CLIENT-SIDE:
   phx-debounce is still a round trip — just a delayed one. If the debounced event's
   handle_event does no DB work and only updates display state, the whole pattern should
   be a TS hook with a local debounce and no server call at all.
   grep -rn 'phx-debounce' ${ROOT}/lib/operation_web --include="*.ex" 2>/dev/null | head -30

For each opportunity, produce:
- The current server-side handle_event code
- What purely client-side hook logic replaces it
- The phx-hook name and TypeScript implementation sketch
- Whether the hook needs to pushEvent back to server at all (e.g. only on final confirm)
- Estimate of round trips saved per user interaction

This project uses TypeScript hooks in ${ROOT}/assets/ts/hooks/. New hooks must also be
registered in the PhxHook union in domain/ui/ui.dox (project convention).

Return JSON:
[{
  "file": "lib/operation_web/live/...",
  "event": "handle_event \\"toggle_section\\"",
  "line": 42,
  "pattern": "toggle|visual_state|keystroke_validation|clipboard|animation|unnecessary_echo|debounce",
  "round_trips_per_interaction": 1,
  "server_work": "assigns a boolean — no DB",
  "hook_name": "SectionToggle",
  "hook_sketch": "... TypeScript ...",
  "still_needs_server": false,
  "still_needs_server_reason": null,
  "value": "high|medium"
}]
`

phase('Audit')
log('Launching 11 parallel LiveView audit agents...')

const [
  cssHardening,
  componentize,
  liveness,
  rerender,
  pubsub,
  bestPractices,
  domKeying,
  pageLoad,
  authSecurity,
  assignBloat,
  tsHooks,
] = await parallel([
  () => agent(CSS_HARDENING, { label: 'css-hardening', phase: 'Audit' }),
  () => agent(COMPONENTIZE, { label: 'componentize', phase: 'Audit' }),
  () => agent(LIVENESS, { label: 'liveness-gaps', phase: 'Audit' }),
  () => agent(RERENDER, { label: 'unnecessary-rerenders', phase: 'Audit' }),
  () => agent(PUBSUB, { label: 'spammy-pubsub', phase: 'Audit' }),
  () => agent(BEST_PRACTICES, { label: 'best-practices', phase: 'Audit' }),
  () => agent(DOM_KEYING, { label: 'dom-keying', phase: 'Audit' }),
  () => agent(PAGE_LOAD, { label: 'page-load', phase: 'Audit' }),
  () => agent(AUTH_AND_SECURITY, { label: 'auth-security', phase: 'Audit' }),
  () => agent(ASSIGN_BLOAT, { label: 'assign-bloat', phase: 'Audit' }),
  () => agent(TS_HOOKS, { label: 'ts-hook-opportunities', phase: 'Audit' }),
])

phase('Synthesize')
log('Synthesizing findings into ranked report...')

const SYNTHESIZE = `
You are the synthesis agent for a Phoenix LiveView quality audit of ${ROOT}.

Run: date +%Y-%m-%d to get today's date. Write the report to:
  ${ROOT}/docs/audits/grind-live-view-<YYYY-MM-DD>.md
(create docs/audits/ if it doesn't exist).

The findings from 11 audit agents:

## CSS COMPONENT HARDENING
${JSON.stringify(cssHardening || [])}

## COMPONENTIZATION OPPORTUNITIES
${JSON.stringify(componentize || [])}

## LIVENESS GAPS
${JSON.stringify(liveness || [])}

## UNNECESSARY RE-RENDERS
${JSON.stringify(rerender || [])}

## SPAMMY PUBSUB PATTERNS
${JSON.stringify(pubsub || [])}

## BEST PRACTICE VIOLATIONS
${JSON.stringify(bestPractices || [])}

## DOM KEYING / MORPHDOM
${JSON.stringify(domKeying || [])}

## PAGE LOAD & DATA ACCESS
${JSON.stringify(pageLoad || [])}

## AUTHORIZATION & SECURITY
${JSON.stringify(authSecurity || [])}

## ASSIGN BLOAT
${JSON.stringify(assignBloat || [])}

## TYPESCRIPT HOOK OPPORTUNITIES
${JSON.stringify(tsHooks || [])}

Write the report with this exact structure:

# LiveView Grind Report

## Headline Numbers
- Total findings: X
- Critical security findings: X  
- High-value findings: X
- (one line per category with count)

## Priority Queue (Top 25 Action Items)
Ranked by: 1) Security/data-integrity risk, 2) UX impact, 3) Performance impact, 4) Fix cost.
Authorization gaps always rank above perf issues.

Each item:
### N. <short title>
**Category**: css_hardening|componentize|liveness|rerender|pubsub|best_practice|dom_keying|page_load|auth|assign_bloat|ts_hooks
**File**: path:line
**Impact**: one sentence
**Fix**: concrete code (heex or elixir snippet, not prose)
---

## Full Findings by Category
One section per category (all 11). Each finding:
- file:line
- description of what's wrong
- concrete fix (code, not "consider X")

Rules:
- Authorization findings go first within each section.
- No finding without a concrete code fix.
- Cross-reference: if a liveness gap AND a pubsub finding concern the same LiveView, note both.
- [SECURITY] prefix for auth findings.
- [PERF] prefix for render/load findings.
- Write the file to disk using the Write tool.
`

await agent(SYNTHESIZE, { label: 'synthesize', phase: 'Synthesize' })

phase('Plan')
log('Building the master remediation TODO from all findings...')

const ALL_FINDINGS = {
  css_hardening: cssHardening || [],
  componentize: componentize || [],
  liveness: liveness || [],
  rerender: rerender || [],
  pubsub: pubsub || [],
  best_practice: bestPractices || [],
  dom_keying: domKeying || [],
  page_load: pageLoad || [],
  auth: authSecurity || [],
  assign_bloat: assignBloat || [],
  ts_hooks: tsHooks || [],
}

// ============ PLAN / FIX / VERIFY ============
// This is the same Plan/Fix/Verify engine as commands/grind-tests.md: build
// one TODO item per finding (no exceptions, no "low priority — skip", no
// deferrals — a genuine false positive still gets an item whose
// instructions say why, so the fix agent makes the final call with the
// code in front of it), run it through a 3-round adversarial
// completeness-check loop, dispatch fixers across file-disjoint buckets so
// no two concurrent agents touch the same file, run an adversarial
// verify-and-repair round, then gate on compile + tests. Run that engine
// exactly as grind-tests.md describes it — see its
// "// ============ PLAN ============" through
// "// ============ VERIFY ============" sections — against ALL_FINDINGS
// above, producing the same `plan` (with `.todo_path` and `.items`),
// `todo`, `statuses`, `blocked`, and `fixedCount` bindings used below. If
// the scheduler itself needs a fix (the completeness loop, the
// file-disjoint dispatch, the rework logic), fix it in grind-tests.md, not
// here — a copy here would just drift again.
//
// Layer these LiveView-specific rules on top of that generic engine (real
// differences from grind-tests.md, not drift):
// - TODO items carry a "severity" (critical|high|medium): critical for
//   auth/security mutations, high for value=high findings, medium
//   otherwise. Rank and dispatch by severity first — authorization gaps
//   always outrank perf/UX items, per the report's own priority rule.
// - Most LiveView findings (CSS hardening, componentization, DOM keying,
//   auth placement) aren't machine-checkable by a single shell command the
//   way an ExUnit test or a golden diff is. So items carry a self-contained
//   "instructions" field instead of separate fix/verify commands, and the
//   verify step is an adversarial agent reading the actual code (e.g.
//   confirming an auth guard really gates the mutating path and not just
//   one clause, or that a :key really landed on the dynamic :for) rather
//   than running a command.
// - id format: "<category>-<n>" (e.g. "auth-3").
// - Every fixer must additionally: run NO git commands of any kind (other
//   agents are editing sibling files concurrently; git operations race
//   their work); never edit anything under ${ROOT}/.dox/ — it is
//   generated, so a fix that genuinely needs a codegen change gets marked
//   blocked with the upstream paradox change it needs; implement new
//   TypeScript hooks in ${ROOT}/assets/ts/hooks/ AND register them in the
//   PhxHook union in the ui dox file (domain/ui/ui.dox or ui.dox — find
//   it); well-typed pure-functional Elixir/TypeScript matching surrounding
//   code, no new files or modules when an existing one fits; no TODO/FIXME
//   comments as a substitute for doing the work; no weakening tests or
//   assertions to make a fix easier.

phase('Fix')
// ... engine runs here (see above) ...
phase('Verify')
// ... engine runs here (see above) ...

log(`${fixedCount}/${todo.length} items fixed. Running final gate (compile + tests + report)...`)

const gate = await agent(`
You are the final gate for the LiveView remediation in ${ROOT}.

1. Run \`nix develop -c mix compile --warnings-as-errors\` and then \`nix develop -c mix test\`
   (fall back to bare \`mix compile\`/\`mix test\` if nix develop is unavailable). Tests run in
   seconds, not minutes. Fix any compile errors or test failures the remediation introduced —
   by correcting the remediation code, never by weakening tests or assertions. Run NO git
   commands.
2. Update the checklist at ${plan.todo_path}: check off every fixed item, and append a
   "## Remediation Results" section with a status table for all ${todo.length} items
   (id, title, status, notes) plus the final compile/test outcome.

STATUSES: ${JSON.stringify(statuses)}
BLOCKED (with reasons): ${JSON.stringify(blocked)}

Return a short plain-text summary: compile result, test result (pass/fail counts), anything
you had to fix at the gate.
`, { label: 'final-gate', phase: 'Verify' })

return {
  done: true,
  report: `${ROOT}/docs/audits/grind-live-view-<date>.md`,
  todo: plan.todo_path,
  items: todo.length,
  fixed: fixedCount,
  blocked,
  gate,
}
```

After the Workflow completes, read the generated report and todo file, run `git status --short` and `git diff --stat`, and summarize: total findings, critical security issues count, top 5 items from the priority queue, TODO item count, how many were fixed vs blocked (with the blocked reasons verbatim), the final gate's compile/test outcome, and the paths to both the report and the todo file. Do not commit — leave the dirty tree for the user to review. If any items remain blocked or the gate reported failures, list them prominently as the first thing in your summary.
