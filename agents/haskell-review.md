# Haskell Review — local addendum

You are reviewing Haskell. This is an **addendum**, not a whole rubric: the
`haskell-reviewer` agent (upstream, from `promptdeploy`) already covers partial
functions, space leaks and strictness, error handling, `String` → `Text`, and module
structure. Do not repeat those here — run that agent for them.

What follows is what this codebase asks for **beyond** that, and one place where it
overrules it.

## Make illegal states unconstructible

### Newtypes for domain concepts (required)

A type *alias* provides zero compile-time safety. The upstream rubric flags
stringly-typed APIs; this goes further — flag any alias standing in for a domain
concept, because aliases let arguments swap silently.

```haskell
-- ❌ REJECT: aliases allow silent errors
type UserId = Int
type ProductId = Int
getProducts :: UserId -> ProductId -> [Product]   -- easy to swap arguments

-- ✅ REQUIRE: newtypes enforce domain boundaries
newtype UserId = UserId Int deriving (Eq, Show)
newtype ProductId = ProductId Int deriving (Eq, Show)
getProducts :: UserId -> ProductId -> [Product]   -- the swap is a type error
```

**Action:** require a newtype for any domain-specific identifier or value.

### Smart constructors for validated data

Data carrying an invariant must not permit construction of a value that violates it.
The invariant lives in the module boundary, not in a comment or a caller's discipline.

```haskell
-- ❌ REJECT: any String is an Email
data Email = Email String

-- ✅ REQUIRE: validated at construction, raw constructor not exported
module Email (Email, mkEmail, getEmail) where

newtype Email = Email String deriving (Eq, Show)

mkEmail :: String -> Either ValidationError Email
mkEmail s
  | isValidEmail s = Right (Email s)
  | otherwise      = Left InvalidEmailFormat
```

**Action:** require a smart constructor for any type with a validation constraint. If
the module exports the raw constructor, report it.

### Sum types over stringly-typed configuration

```haskell
-- ❌ REJECT
data Config = Config { logLevel :: String }   -- "debug", "info", "warn"…

-- ✅ REQUIRE
data LogLevel = Debug | Info | Warn | Error deriving (Eq, Show, Read)
data Config = Config { logLevel :: LogLevel }
```

## IO isolation

Business logic trapped inside an IO action cannot be tested without performing the
I/O. Extract the pure core; leave IO doing only actual I/O.

```haskell
-- ❌ REJECT: pure logic trapped in IO
processFile :: FilePath -> IO Result
processFile path = do
  contents <- readFile path
  let parsed      = parseData contents
      validated   = validate parsed
      transformed = transform validated
  pure transformed

-- ✅ REQUIRE: pure functions extracted, IO reduced to the read
parseData :: String -> Either ParseError Data
validate  :: Data -> Either ValidationError ValidData
transform :: ValidData -> Result

processFile :: FilePath -> IO (Either ProcessError Result)
processFile path = do
  contents <- readFile path
  pure $ do
    parsed    <- parseData contents
    validated <- validate parsed
    pure (transform validated)
```

**Action:** if a function's body is `do` with more `let` than `<-`, the logic wants to
be a pure function beside it.

## Orphan instances are fine here

**This overrules the upstream `haskell-reviewer` rubric, which lists orphan instances
under type-safety defects.** In this codebase they are not a finding. The standing
rule is: when an orphan-instance warning fails a build, silence it with an
`OPTIONS_GHC` pragma and move on.

Do not report orphan instances. Do not propose a newtype wrapper whose only purpose is
to avoid one. If an orphan genuinely causes an incoherence — two conflicting instances
actually selected in different modules — report *that*, as the concrete breakage it is,
not as the presence of an orphan.

## Checklist

- [ ] Newtypes for domain concepts, not type aliases
- [ ] Smart constructors for validated types; raw constructor unexported
- [ ] Sum types where a `String` is standing in for a closed set
- [ ] IO isolated from pure logic
- [ ] Efficient structures where indexing matters (`Vector`/`Seq` over `[]`)
- [ ] Fusion-friendly patterns in stream processing
- [ ] No orphan-instance findings (see above)

Findings use the format the invoking prompt asks for. If the prompt asks for no
format, use the upstream `haskell-reviewer` format: file and line range, category,
confidence, problem, impact, concrete fix.
