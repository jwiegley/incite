Write the plan and its instruments to disk. This leaf runs once, before any
branch exists, and everything after it reads what you write here.

## The two ledgers the plan lives in

Write `.stack-plan.md` at the repository root. It is the source of truth for the
whole operation and it must survive a total loss of context: anything a stranger
would need in order to resume goes in it. It carries the `## repository facts`
block you were told to record, then one entry per branch from the approved plan
above, in order, each with its verification checkbox.

Write `.stack-branches` beside it: the branch names alone, bottom first, one per
line, no other content. Three scripts read that file, and parsing `gt log`
instead is less reliable.

Add every path below to `.git/info/exclude`, never to `.gitignore`, because
`.gitignore` is a tracked file and this tooling belongs to your run rather than
to the repository:

```
.stack-plan.md
.stack-branches
.stack-budget
.stack-verify
.stack-bugbot
verify-stack.sh
stack-status.sh
ci-budget.sh
```

Write `.stack-budget` too: the concurrent job budget you discovered, as a bare
number alone on one line. The harness runs `ci-budget.sh` itself and that file
is how the number you found reaches it.

## Three scripts, written exactly as given

Write each one at the repository root and `chmod +x` it. The text below is the
content, not a description of it. Do not improve them, do not rename their
files, and do not change which ledger file each one reads: a harness outside
this session runs `verify-stack.sh` and `ci-budget.sh` directly and reads their
exit codes.

### `verify-stack.sh`

Verifies every branch with the local gate, in parallel. Two properties make it
affordable and it depends on both. The nix store is shared, so branch two is
branch one plus a delta: the bottom branch builds to completion first, and only
then do the rest fan out. The daemon deduplicates, so concurrent checks that
need one derivation block on a lock rather than building twice.

```bash
#!/usr/bin/env bash
# Verify a Graphite stack with `nix flake check`, in parallel.
#   ./verify-stack.sh                      # reads .stack-branches, bottom-first
#   ./verify-stack.sh --from mid-branch    # only that branch and above
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
# Per-process worktree pool. Derived from the PID, not from the repo alone: two
# runs over one checkout would otherwise share a path per branch and
# `remove --force` each other's tree mid-build, which reads as a failing check
# on a stack that is perfectly healthy.
WT_ROOT="${WT_ROOT:-$ROOT/../.stack-worktrees-$$}"
LOG_DIR="${LOG_DIR:-/tmp/stack-verify-$$}"
LEDGER="${LEDGER:-$ROOT/.stack-verify}"
NPROC="$(nproc)"
JOBS="${JOBS:-4}"                                    # concurrent flake checks
CORES="${CORES:-$(( NPROC/JOBS > 0 ? NPROC/JOBS : 1 ))}"
MAX_JOBS="${MAX_JOBS:-2}"

FROM=""
[[ "${1:-}" == "--from" ]] && { FROM="$2"; shift 2; }
if [[ $# -gt 0 ]]; then
  BRANCHES=("$@")
else
  mapfile -t BRANCHES < <(grep -v '^\s*\(#\|$\)' "${BRANCHES_FILE:-$ROOT/.stack-branches}")
fi

# --from: drop everything below. Use after a restack, which only rewrites
# SHAs at and above the edit point.
if [[ -n "$FROM" ]]; then
  for i in "${!BRANCHES[@]}"; do
    [[ "${BRANCHES[$i]}" == "$FROM" ]] && { BRANCHES=("${BRANCHES[@]:$i}"); FROM=""; break; }
  done
  [[ -n "$FROM" ]] && { echo "error: --from branch not in list" >&2; exit 2; }
fi

mkdir -p "$WT_ROOT" "$LOG_DIR"
cleanup() {
  for b in "${BRANCHES[@]}"; do
    git worktree remove --force "$WT_ROOT/${b//\//_}" 2>/dev/null || true
  done
  git worktree prune
}
trap cleanup EXIT

check() {
  local branch="$1" wt="$WT_ROOT/${1//\//_}" log="$LOG_DIR/${1//\//_}.log"
  local sha; sha="$(git rev-parse "$branch")"
  git worktree remove --force "$wt" 2>/dev/null || true
  # --detach: a branch can't be checked out in two worktrees, and we only read.
  git worktree add --detach --quiet "$wt" "$branch"
  local result=FAIL
  if (cd "$wt" && nix flake check \
        --no-update-lock-file \
        --max-jobs "$MAX_JOBS" --cores "$CORES" \
        --keep-going --print-build-logs) >"$log" 2>&1; then
    result=PASS
  fi
  # Ledger: branch, SHA verified, result, log. The SHA is what lets the status
  # table mark a result STALE once the branch moves under it.
  #
  # awk on the first FIELD, not grep on a pattern: a branch name is allowed to
  # contain `.`, `*` and `[`, and as a regex those match other branches' rows.
  ( flock 9
    awk -v b="$branch" '$1 != b' "$LEDGER" > "$LEDGER.tmp" 2>/dev/null || true
    mv -f "$LEDGER.tmp" "$LEDGER" 2>/dev/null || true
    echo "$branch $sha $result $log" >> "$LEDGER"
  ) 9>"$LEDGER.lock"
  echo "$result $branch  ($log)"
  [[ $result == PASS ]]
}
export -f check
export WT_ROOT LOG_DIR MAX_JOBS CORES LEDGER

echo "stack: ${BRANCHES[*]}"
echo "jobs=$JOBS cores=$CORES max-jobs=$MAX_JOBS logs=$LOG_DIR"

# Warm the store serially. Every branch above shares most of this closure;
# fanning out cold would build it JOBS times over.
echo "--- warming: ${BRANCHES[0]}"
check "${BRANCHES[0]}" || {
  echo "bottom branch failed; everything above is unverifiable. Fix here."; exit 1; }

[[ ${#BRANCHES[@]} -eq 1 ]] && { echo "all pass."; exit 0; }

echo "--- ${#BRANCHES[@]} branches remaining, $JOBS at a time"
status=0
printf '%s\n' "${BRANCHES[@]:1}" \
  | xargs -P "$JOBS" -I{} bash -c 'check "$@"' _ {} || status=1

if [[ $status -eq 0 ]]; then
  echo "all pass -- safe to gt submit --stack"
else
  echo "fix at the LOWEST failing branch, gt restack, then:"
  echo "  ./verify-stack.sh --from <that-branch>"
fi
exit $status
```

Where `nix flake check` fails on a worktree's `.git` file, fall back to
`nix flake check path:.` from inside the worktree. Support for worktrees in the
git fetcher has been uneven across nix versions.

Replace the `nix flake check` invocation with whatever local gate you recorded
in `.stack-plan.md`, and leave the rest of the script alone. The worktree fan-out,
the serial warm-up and the ledger are what the harness depends on.

### `ci-budget.sh`

Answers one question: may I promote right now? It fails closed, so a query it
cannot answer resolves to a hold.

```bash
#!/usr/bin/env bash
# CI budget gate. Answers exactly one question: may I promote right now?
#   ./ci-budget.sh          # print one status line; exit 0 = allowed, 1 = hold
#   ./ci-budget.sh --wait   # poll until allowed, then exit 0 (exit 2 on timeout)
# Fails CLOSED: any query it cannot answer resolves to "hold".
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
BRANCHES_FILE="${BRANCHES_FILE:-$ROOT/.stack-branches}"
# Max concurrent CI *jobs* belonging to this stack. `.stack-budget` is what the
# discovery step recorded for THIS repository; 6 is the fallback when nothing
# discovered one. Without that file the gate silently enforces a number nobody
# chose.
BUDGET="${CI_JOB_BUDGET:-$(cat "$ROOT/.stack-budget" 2>/dev/null || echo 6)}"
[[ "$BUDGET" =~ ^[0-9]+$ ]] || BUDGET=6
POLL="${POLL:-120}"              # seconds between --wait polls
MAX_WAIT="${MAX_WAIT:-1800}"     # stop waiting after this; caller decides what next

mapfile -t MINE < <(grep -v '^[[:space:]]*\(#\|$\)' "$BRANCHES_FILE" 2>/dev/null)
is_mine() { local b="$1" m; for m in "${MINE[@]}"; do [[ "$b" == "$m" ]] && return 0; done; return 1; }

assess() {
  MINE_JOBS=0; MINE_RUNS=0; OTHER_Q=0; OTHER_R=0; NOTE=""
  local raw id st br n
  if ! raw="$(gh run list --limit 100 --json databaseId,status,headBranch --jq '
        .[] | select(.status=="queued" or .status=="in_progress" or .status=="waiting"
                     or .status=="requested" or .status=="pending")
        | [.databaseId, .status, .headBranch] | @tsv' 2>/dev/null)"; then
    NOTE="run list query failed"; return 1
  fi
  while IFS=$'\t' read -r id st br; do
    [[ -z "${id:-}" ]] && continue
    if is_mine "$br"; then
      MINE_RUNS=$((MINE_RUNS+1))
      n="$(gh run view "$id" --json jobs --jq '[.jobs[]|select(.conclusion==null)]|length' 2>/dev/null)"
      [[ "$n" =~ ^[0-9]+$ ]] || { n="$BUDGET"; NOTE="job count unavailable for run $id; counted as full"; }
      MINE_JOBS=$((MINE_JOBS+n))
    elif [[ "$st" == "in_progress" ]]; then OTHER_R=$((OTHER_R+1))
    else OTHER_Q=$((OTHER_Q+1)); fi
  done <<< "$raw"
  return 0
}

report() {
  local verdict="$1"
  printf 'CI BUDGET  mine: %d run(s)/%d job(s) of %d   others: %d running, %d queued   %s%s\n' \
    "$MINE_RUNS" "$MINE_JOBS" "$BUDGET" "$OTHER_R" "$OTHER_Q" "$verdict" \
    "${NOTE:+   [$NOTE]}"
}

check() {
  if ! assess; then report "HOLD (fail-closed)"; return 1; fi
  if (( OTHER_Q > 0 )); then report "HOLD -- yielding to $OTHER_Q queued run(s) not mine"; return 1; fi
  if (( MINE_JOBS >= BUDGET )); then report "HOLD -- budget full"; return 1; fi
  report "OK -- headroom $((BUDGET-MINE_JOBS)) job(s)"; return 0
}

if [[ "${1:-}" == "--wait" ]]; then
  waited=0
  until check; do
    (( waited >= MAX_WAIT )) && { echo "budget still held after ${MAX_WAIT}s"; exit 2; }
    sleep "$POLL"; waited=$((waited+POLL))
  done
  exit 0
fi
check
```

Two behaviours are worth stating, because both look like bugs and are not. It
holds on a **queued** foreign run and not on a merely running one: somebody
queued is somebody waiting on the capacity you are holding, which is the exact
condition that blocks a colleague. And an unknown job count counts as a full
budget rather than as zero, so a gap in permissions throttles you rather than
releasing you.

### `stack-status.sh`

Prints one row per branch. Every column is a condition the stack has to meet,
so the run is over when every row is clean.

```bash
#!/usr/bin/env bash
# Status of every branch in the stack. Reads .stack-branches for order and
# .stack-verify for local nix results; queries gh for everything else.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
BRANCHES_FILE="${BRANCHES_FILE:-$ROOT/.stack-branches}"
LEDGER="${LEDGER:-$ROOT/.stack-verify}"
BUGBOT_LEDGER="${BUGBOT_LEDGER:-$ROOT/.stack-bugbot}"
TRUNK="${TRUNK:-main}"
# Review-bot account. Discover once with:
#   gh api "repos/{owner}/{repo}/pulls/<n>/comments" --jq '.[].user.login' | sort -u
BOT="${BOT:-cursor[bot]}"

mapfile -t BRANCHES < <(grep -v '^\s*\(#\|$\)' "$BRANCHES_FILE")
read -r OWNER REPO < <(gh repo view --json owner,name \
  --jq '"\(.owner.login) \(.name)"')

# Color: on for terminals, off when piped/captured (so agent-echoed tables stay
# clean text). NO_COLOR=1 forces off, FORCE_COLOR=1 forces on.
if [[ -n "${FORCE_COLOR:-}" ]] || { [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; }; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; D=""; B=""; N=""
fi

# Pad plain FIRST, then color -- ANSI codes are zero-width but printf counts
# their bytes, so coloring before padding breaks column alignment.
cell() { # cell <width> <value>
  local w="$1" v="$2" c=""
  case "$v" in
    pass|PASS|ok|clean|synced|ready)        c="$G" ;;
    FAIL|CONFLICT|RESTACK|DIVERGED)         c="$R" ;;
    running|STALE|never|unpushed|none)      c="$Y" ;;
    "ahead "*|"behind "*|\?)                c="$Y" ;;
    draft|n/a|-|no-pr)                      c="$D" ;;
    *\**|*\!*|*\?*)                         c="$Y" ;;  # stale/untriggered/partial-fail counts
    0/*)                                    c="$G" ;;  # all addressed
    */*)                                    c="$R" ;;  # open items
  esac
  printf '%s%-*s%s' "$c" "$w" "$v" "$N"
}

dcell() { # diff-size cell: right-aligned, yellow past the split threshold
  local v="$1" c=""
  [[ "$v" =~ ^[0-9]+$ ]] && (( v > 700 )) && c="$Y"
  [[ "$v" == "?" ]] && c="$Y"
  printf '%s%6s%s' "$c" "$v" "$N"
}

# --- CI budget header: rate, not just totals -----------------------------
if [[ -x "$ROOT/ci-budget.sh" ]]; then "$ROOT/ci-budget.sh" || true; echo; fi

printf "${B}%-3s %-22s %6s %-6s %-8s %-9s %-9s %-9s %-8s %-9s %-7s${N}\n" \
  '#' 'BRANCH' 'DIFF' 'STATE' 'CI' 'BUGBOT' 'COMMENTS' 'CONFLICT' 'REBASE' 'LOCAL' 'NIX'

prev="$TRUNK"; i=0
for b in "${BRANCHES[@]}"; do
  i=$((i+1))

  # --- diff size against parent -------------------------------------------
  diff=$(git diff --shortstat "$prev...$b" 2>/dev/null \
    | grep -oE '[0-9]+ (insertion|deletion)' | grep -oE '^[0-9]+' \
    | paste -sd+ - | bc 2>/dev/null); diff="${diff:-?}"

  # --- rebase currency: is the parent's tip an ancestor? -------------------
  if git merge-base --is-ancestor "$prev" "$b" 2>/dev/null; then
    rebase="ok"; else rebase="RESTACK"; fi

  # --- local vs remote ----------------------------------------------------
  if ! git rev-parse --verify -q "origin/$b" >/dev/null 2>&1; then
    localst="unpushed"
  else
    read -r ahead behind < <(git rev-list --left-right --count "$b...origin/$b" \
      | awk '{print $1, $2}')
    if   [[ $ahead -gt 0 && $behind -gt 0 ]]; then localst="DIVERGED"
    elif [[ $ahead -gt 0 ]];                 then localst="ahead $ahead"
    elif [[ $behind -gt 0 ]];                then localst="behind $behind"
    else                                          localst="synced"; fi
  fi

  # --- local nix result, staleness-checked --------------------------------
  nix="never"
  if [[ -f "$LEDGER" ]]; then
    read -r _ vsha vres _ < <(grep "^$b " "$LEDGER" | tail -1) 2>/dev/null || true
    if [[ -n "${vres:-}" ]]; then
      if [[ "$vsha" == "$(git rev-parse "$b")" ]]; then nix="$vres"
      else nix="STALE"; fi
    fi
    unset vsha vres
  fi

  # --- bugbot trigger staleness: was the last review at this SHA? ----------
  bbstale=""
  if [[ -f "$BUGBOT_LEDGER" ]]; then
    read -r _ tsha < <(grep "^$b " "$BUGBOT_LEDGER" | tail -1) 2>/dev/null || true
    if [[ -z "${tsha:-}" ]]; then bbstale="!"
    elif [[ "$tsha" != "$(git rev-parse "$b")" ]]; then bbstale="*"; fi
    unset tsha
  else
    bbstale="!"
  fi

  # --- PR-side state ------------------------------------------------------
  pr=$(gh pr list --head "$b" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [[ -z "$pr" || "$pr" == "null" ]]; then
    state="-"; ci="no-pr"; conflict="-"; bug="-"; other="-"
  else
    read -r state ci conflict < <(gh pr view "$pr" \
      --json isDraft,mergeable,statusCheckRollup --jq '
        (if .isDraft then "draft" else "ready" end) + " " +
        (if (.statusCheckRollup|length) == 0 then
           (if .isDraft then "n/a" else "none" end)
         elif any(.statusCheckRollup[]; .conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED") then "FAIL"
         elif any(.statusCheckRollup[]; .status!="COMPLETED") then "running"
         else "pass" end)
        + " " +
        (if .mergeable=="CONFLICTING" then "CONFLICT"
         elif .mergeable=="MERGEABLE" then "clean"
         else "?" end)' 2>/dev/null)
    state="${state:-?}"; ci="${ci:-?}"; conflict="${conflict:-?}"

    # Review threads carry a real resolved flag. Top-level issue comments do
    # not, so they are counted as open and tracked by hand in .stack-plan.md.
    read -r bo bt oo ot < <(gh api graphql -f query='
      query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){
        pullRequest(number:$n){
          reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login}}}}}
          comments(first:100){nodes{author{login}}}}}}' \
      -f o="$OWNER" -f r="$REPO" -F n="$pr" --jq --arg bot "$BOT" '
      .data.repository.pullRequest as $p
      | ($p.reviewThreads.nodes | map(. + {a: .comments.nodes[0].author.login})) as $t
      | [ ($t|map(select(.a==$bot and (.isResolved|not)))|length),
          ($t|map(select(.a==$bot))|length),
          ($t|map(select(.a!=$bot and (.isResolved|not)))|length)
            + ($p.comments.nodes|map(select(.author.login!=$bot))|length),
          ($t|map(select(.a!=$bot))|length)
            + ($p.comments.nodes|map(select(.author.login!=$bot))|length) ]
      | @tsv' 2>/dev/null)
    bug="${bo:-?}/${bt:-?}${bbstale}"; other="${oo:-?}/${ot:-?}"
  fi

  printf '%-3s %-22s ' "$i" "${b:0:22}"
  dcell "$diff"; printf ' '
  cell 6 "$state";    printf ' '
  cell 8 "$ci";       printf ' '
  cell 9 "$bug";      printf ' '
  cell 9 "$other";    printf ' '
  cell 9 "$conflict"; printf ' '
  cell 8 "$rebase";   printf ' '
  cell 9 "$localst";  printf ' '
  cell 7 "$nix";      printf '\n'
  prev="$b"
done

cat <<'LEGEND'
COLOR   green = done/clean | yellow = pending, stale, or needs attention
        red = broken (fix before anything else) | dim = neutral/expected
        Auto-off when piped or captured; NO_COLOR=1 / FORCE_COLOR=1 override.
CI BUDGET         concurrent jobs in flight vs CI_JOB_BUDGET, plus other
                  people's runs. HOLD = do not promote, for any reason.
STATE             draft = no CI consumed (working state) | ready = CI running
BUGBOT/COMMENTS   open/total. Top-level comments have no resolved flag on
                  GitHub -- count them open and track them in .stack-plan.md.
BUGBOT  suffix *  branch moved since last trigger -- review is stale, retrigger
BUGBOT  suffix !  never triggered on any SHA
REBASE  RESTACK   parent's tip is not an ancestor; run gt restack
LOCAL             unpushed | ahead N | behind N | DIVERGED | synced
NIX     STALE     branch moved since it was verified; re-run verify-stack.sh
CI      n/a       draft, so no CI by design -- expected, not a problem
CI      none      ready but no checks reported yet -- NOT the same as passing
LEGEND
```

Set `TRUNK` and `BOT` at the top to the values you recorded, rather than leaving
the defaults.

## How the table is read

- `?` means a query failed. Show the `?`. Never guess a value, and never drop
  the row.
- `STALE` and `none` are not passes. A local pass at the current SHA is required
  before promotion, and it still does not mean the branch survives CI.
- A branch is done when CI reports `pass` after promotion.
- `DIVERGED` on a branch you did not touch means somebody else pushed to it.
  Stop and ask.
- Open counts in the two comment columns are the review work queue. Resolve
  threads on GitHub as you address them, or the count lies to you.

Print the table after every verification run, after every submit, before and
after every triage round, at the promotion gate, and after each promotion. Do
not print it after every git operation.

Close with what you wrote and where. This leaf runs once and nothing calls it
again.
