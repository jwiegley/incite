You have just committed. Before continuing, get that commit independently checked.

This is the one description of the post-commit check. `/wiggum` runs it on every
commit and `ship-feature`'s work loop fires it as a beat; both defer here rather
than restating it, so there is one copy to keep true.

## What to run

**Always call `review-lite`.** It runs six independent reviewers over the commit,
concurrently across three backends — correctness on claude-agent, fess on
claude-agent, complexity on codex, ponytail on codex, qa on opencode, haskell on
claude-agent (behind a triage leaf: it runs only when the diff touches Haskell
source or a cabal file) — ranked:

| lens | judges | a finding means |
|---|---|---|
| `correctness` | the code — does it do what it claims, on every input | it is wrong; fix it |
| `haskell` | the Haskell — types, totality, strictness, instances | the type system was left holding less than it can; fix it |
| `fess` | **your claims** — against what the diff actually shows | your account is wrong; correct the record *and* do the work you said you had done |
| `qa` | the cases nobody wrote — edge, error, scale, observability | an untested path; cover it |
| `complexity` | the shape — what a reshape would fix | structural debt; decide whether to pay it now |
| `ponytail` | the size — what deletion would fix | cut it, or say why not |

**Inside an agent-functor run, also: `fess-audit`.** Same question as the `fess`
lens, asked far wider — that lens checks one commit's claims against one diff,
while `fess-audit` audits your whole captured session. It needs no input from you:
the server supplies your transcript. Outside a run there is no capture, so it is
not available and the `fess` lens is what you have.

Do not run a heavier check on this beat. `review-heavy` (eight lenses × three
backends) and `review-audit` (84 leaves) are for a pre-PR review and a standing
audit; running either per-commit burns the turns you need for the work.

## Input — the part to get right

All `review-lite` lenses read the **same** input, so one artifact has to serve
them. A bare diff silently defeats the `fess` lens: it audits claims against
reality, and a diff on its own carries no claims. Pass:

1. **The diff** — `git show` for the commit you just made. The other lenses
   need nothing else.
2. **What you were asked to do** — the task or plan step this commit is against.
3. **What you are claiming about it** — in your own words, before the tool answers.
   "Added the guard and a regression test for it; the suite passes." That sentence
   is what `fess` checks against the diff.

Do not skip (3) because it feels redundant. An unstated claim cannot be caught
being wrong, and the lens degrades into a second opinion on style.

`fess-audit`, where available, takes nothing. Pass an `input` only to steer the
audit, such as "focus on the test claims". The `input` arrives as guidance beside
the transcript. The `input` never replaces the transcript.

## Protocol

Start the call (or both calls, concurrently). Each returns a run id immediately
without waiting. Poll `status` with each id until it is `done` (or `failed` /
`cancelled`), then read `output`. `output` is safe to call early — it reports
progress rather than blocking.

- Do NOT spawn a subagent to *run* a check.
- Do NOT assemble a context snapshot to hand over.
- Do NOT coordinate through the filesystem — no observations directory to scan,
  no report files to read, no directory polled for another agent's output.

The server already has your conversation, and a tool call is the entire protocol.
(Fixing what comes back is a different matter, and the caller decides how.)

## Acting on it

Fix every finding. If a finding is wrong, say what in the diff proves it wrong,
then continue. Do not skip a check, and do not argue a finding away without
evidence. If a check reports nothing actionable, say so in one line and move on.

**Do not audit the fix commit.** Do not run the checks in this document against a
commit whose only purpose is to fix what they raised. That loop does not converge,
and progress matters more than a perfect fixpoint.
