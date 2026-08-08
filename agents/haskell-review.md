# Haskell Review — local addendum

You are reviewing Haskell. This is an **addendum**, not a whole rubric: the
`haskell-reviewer` agent (upstream, from `promptdeploy`) already covers partial
functions, space leaks and strictness, error handling, `String` → `Text`, and module
structure. Do not repeat those here — run that agent for them.

What follows is what this codebase asks for **beyond** that, two rules it restates
because here they admit no severity discussion, and one place where it overrules the
upstream rubric.

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

### No primitive in a top-level signature

The rule above, stated where it is checkable: a **top-level** signature must not
mention `Int`, `Integer`, `Double`, `Bool`, `Char`, `String` or `Text`. A signature
built from primitives tells the reader nothing and the compiler less. It is also the
one place a wrong argument order survives every test that happens to pass symmetric
data.

```haskell
-- ❌ REJECT: three primitives, and the caller decides what they mean
retry :: Int -> Int -> Text -> IO Bool

-- ✅ REQUIRE: the signature carries the meaning
newtype Attempts = Attempts Int
newtype BackoffMs = BackoffMs Int
newtype Endpoint = Endpoint Text
data Outcome = Reached | GaveUp

retry :: Attempts -> BackoffMs -> Endpoint -> IO Outcome
```

A `Bool` return is the same defect: it names neither side. Return a two-constructor
sum whose constructors say what happened.

**Action:** report every top-level signature carrying a bare primitive. Two
exceptions, and only these two: a function that is genuinely structural over the
primitive itself (a text-wrapping helper, a numeric formatter — the primitive **is**
the domain), and an instance method whose type the class fixes. Local bindings in a
`where` or `let` are out of scope.

### RecordWildCards: the name is the field name

Where a record is destructured, use `RecordWildCards` and let the bound names be the
field names. A rename at the binding site is a second name for one thing, and it makes
every later reader check which field a variable came from.

```haskell
-- ❌ REJECT: renamed at the binding site, and positional matching is worse
render cfg = let lvl = logLevel cfg; nm = serviceName cfg in ...
render (Config lvl nm _) = ...

-- ✅ REQUIRE: the field names ARE the variable names
render Config {..} = ... logLevel ... serviceName ...
```

**Action:** report a destructure that renames a field it could have bound by name, and
report positional matching on a record with more than two fields. Where a name genuinely
must differ (two records of the same type in one scope), the binding stays explicit —
say so in the finding rather than forcing the wildcard.

### DataKinds and GADTs where they retire a runtime check

Reach for the type level when it **removes** a check or an impossible case, and not
otherwise. A phase or state that a value is in belongs in a type parameter when the
alternative is the same guard written at every call site.

```haskell
-- ❌ REJECT: the invariant lives in a runtime check, repeated
data Conn = Conn { connOpen :: Bool, connHandle :: Handle }
send :: Conn -> Payload -> IO ()   -- errors when connOpen is False

-- ✅ REQUIRE: the state is the type, and the bad call does not compile
data State = Open | Closed
newtype Conn (s :: State) = Conn Handle
send :: Conn 'Open -> Payload -> IO ()
```

A GADT earns its keyword the same way: when its result type index makes a branch
unwritable rather than merely unlikely.

**Action:** where a runtime check, a `Maybe` or a partial branch exists only because a
type parameter was not used, report it with the index that would retire it. Report the
reverse too — type-level machinery that buys no invariant is complexity, and the
ponytail lens will charge for it.

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

## Two rules the upstream rubric grades and this codebase does not

The upstream agent lists both of these with a severity. Here they carry none, because
there is no level of severity at which they are acceptable. Report every occurrence,
however small the input is today.

### Total functions only

`head`, `tail`, `init`, `last`, `fromJust`, `!!`, `read`, `foldr1`, `foldl1`,
`maximum` and `minimum` on a list that the types allow to be empty are findings.
So is an incomplete pattern match, and so is a `case` with no branch for a
constructor the type admits. Pattern match, use `Data.List.NonEmpty`, or return the
`Maybe` the partiality was hiding. `error` survives in one place: a case the types
make unreachable, with a comment saying why.

### Strict accumulation, no thunk chains

`foldl'` and never `foldl`. Bang the accumulator of a recursive function. Use
`Data.Map.Strict` and the strict `State`. A fold whose accumulator is a pair or a
record builds one chain per field unless the fields are strict, and a small input
today is not an argument — it is the reason the leak is found in production instead
of in review.

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
- [ ] No bare `Int`, `Text`, `String` or `Bool` in a top-level signature
- [ ] Smart constructors for validated types; raw constructor unexported
- [ ] Sum types where a `String` is standing in for a closed set
- [ ] `RecordWildCards` where a record is destructured, names matching fields
- [ ] A type parameter (`DataKinds`, a GADT index) wherever it retires a runtime check
- [ ] No partial function, no incomplete pattern match
- [ ] `foldl'`, strict accumulators, strict `Map` and `State`
- [ ] IO isolated from pure logic
- [ ] Efficient structures where indexing matters (`Vector`/`Seq` over `[]`)
- [ ] Fusion-friendly patterns in stream processing
- [ ] No orphan-instance findings (see above)

Findings use the format the invoking prompt asks for. If the prompt asks for no
format, use the upstream `haskell-reviewer` format: file and line range, category,
confidence, problem, impact, concrete fix.
