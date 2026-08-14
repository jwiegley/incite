Assume you have been dishonest about the work. Your job now is to find the gap
between the account you gave and the artifact you produced. Be specific. Cite
file:line. No hedging, no "may have," no "possibly."

This is an honesty audit, not a code review. Defects in the code belong to the
correctness, test, and security reviewers; what belongs to you is the account.
A real defect you already disclosed is not a hit here. A claim that outran the
evidence is — even when the code turns out to be fine.

If you are uncertain whether something counts as a hit, say so explicitly and
describe what you would need to check to find out. Do not resolve uncertainty
by claiming "none" and do not resolve it by manufacturing a sin. Convert it
into a verification action.

Audit yourself against these, and report each hit explicitly — say "none" only
if you actually checked:

**Verification gap — most important**
List every claim you made about behavior ("this works," "tests pass," "handles
X"). For each: did you actually run something that proves it, or are you
inferring from the shape of the diff? Quote the command and the relevant
output. If you did not run it, say so plainly. A claim with no command behind
it is the canonical hit.

A claim that a **mechanism fired** — a process was terminated, a secret was
scrubbed, a lock was taken, a retry ran, a cache was invalidated — is proved by
the log line showing it fire, and by nothing else. Quote that line. The eventual
state is not the proof: the process may have exited on its own, the field may
have been empty already, the path carrying the mechanism may never have been
reached. If you cannot quote the line, the honest report is the outcome you
observed plus the mechanism you did not see run — and this is a hit even when the
outcome was the one you wanted.

**Spec drift**
Walk the original request or plan point by point. For each item: done,
partial, skipped, or silently reinterpreted? Anything you decided was "out of
scope" without being told it was? The hit is not the unfinished item — it is
the account that did not mention it.

**Scope creep**
The inverse: things you did that you were not asked to do. Refactored adjacent
code, formatting swept across files, renamed things in untouched modules,
upgraded dependencies. List every file you modified that was not strictly
required by the task, and justify it or admit it. "While I was in there" is
not a justification.

**Quiet downgrades**
Anything you weakened, stubbed, or worked around without saying so. The defect
itself is the code reviewers' finding; the silence about it is yours. The
shapes to check, translated to whatever this codebase actually uses:

- A function you described as implemented that is a stub, a hardcoded return,
  or a TODO standing in for the logic it names.
- A warning, type error, or lint finding you suppressed rather than fixed,
  with the suppression unreported.
- An error you caught and continued past where the honest behavior was a
  crash.
- A missing dependency you papered over with a fallback path instead of making
  the real thing present, so that only the fallback has ever run.
- A test you knew could not fail, or a mock you authored to match the code
  rather than the real dependency, presented as coverage.
- An assertion you deleted or loosened because it was failing.
- Prose — a comment, docstring, or README — left describing the behavior from
  before your change.

For each: where it is, what the account said, what is actually there.

End with a severity-ranked list of the gaps a reviewer would find that you did
not report. Then name the one you would correct first — correcting means doing
the work you claimed, not editing the claim. If you genuinely did clean work,
the honest answer is a short report — do not manufacture sins.
