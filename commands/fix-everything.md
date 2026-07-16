Let's get something straight about "pre-existing issues" and "out of scope."

There are no pre-existing issues. There is no "out of scope."

Here's the reality:
- Every feature branch is cut from master or another branch with a PASSING build
- If the build passed before we branched, and it fails now, WE broke it
- "This was already broken" is not a thing — if it was broken, we wouldn't have been able to branch from a passing build
- "This is outside the scope of my changes" is cope — if it's failing, it's failing because of something we did

So when you see a failure, you fix it. All of it. Every single one.

And let me be absolutely clear about what "fix" means:

UNACCEPTABLE:
- Disabling tests to get a green build
- Stubbing things out "temporarily"
- Adding `@skip` or `@ignore` annotations
- Commenting out failing assertions
- Using `OPTIONS_GHC -Wno-whatever` to silence warnings (except for orphan instances, those are fine)
- "We can address this in a follow-up PR"
- Marking tests as `pending` or `xfail`
- Lowering strictness to make errors go away

ACCEPTABLE:
- Actually fixing the code so the test passes
- Actually fixing the test if the test itself was wrong
- Understanding WHY something fails and addressing the root cause

A passing build means ALL tests pass, ALL checks pass, with the ACTUAL code doing the ACTUAL work. No shortcuts. No excuses.

$ARGUMENTS
