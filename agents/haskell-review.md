# Haskell Review — local addendum

You are reviewing Haskell. This is an **addendum**, not a whole rubric: the
`haskell-reviewer` agent (upstream, from `promptdeploy`) already covers partial
functions, space leaks and strictness, error handling, `String` → `Text`, and module
structure. Do not repeat those here — run that agent for them.

What follows is what this codebase asks for **beyond** that, two rules it restates
because here they admit no severity discussion, and one place where it overrules the
upstream rubric.

## Make illegal states unconstructible

### No partial field accessors

A record field accessor that some constructor of its type lacks is a **partial
function**. It compiles, it type-checks, and it crashes on every constructor without
the field. `-Wpartial-fields` catches it. `{-# OPTIONS_GHC -Wno-partial-fields #-}`
is never the answer — it is a finding of its own. (A label every constructor carries
is total — the warning stays silent — and is not a finding under this rule.)

```haskell
-- ❌ REJECT: callTarget is partial, and crashes on Placeholder
data NodeRhs
  = Placeholder { placeholderTarget :: Text }
  | CallFunction { callTarget :: CallTarget, callArgs :: [Expr] }
```

Three fixes, in order of preference:

1. **Extract the multi-field constructor into its own single-constructor record**
   and nest it. Prefix the record constructor with `Mk`, so the type does not read
   as `Foo (Foo ...)`.
2. **Drop the label** where the constructor holds one field and the accessor has no
   callers. A positional constructor cannot be projected partially.
3. **Write a total function** where the field is genuinely shared across
   constructors: `ropeConfigLayout :: RopeConfig a -> Maybe RopeLayout`. It returns
   the `Maybe` that the accessor was hiding.

```haskell
-- ✅ REQUIRE: every accessor is total, because its record has one constructor
data NodeRhs = Placeholder Text | CallFunction CallFunction

data CallFunction = MkCallFunction
  { callTarget :: CallTarget
  , callArgs   :: [Expr]
  , callKwargs :: Map Keyword Expr
  }
```

**Action:** report every field label that at least one constructor of its type
lacks, and name which of the three fixes applies. Report `-Wno-partial-fields`
wherever it appears.

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

The rule bites hardest on `Map` keys and on tuples. `Map Text Expr` says nothing
about what the `Text` is; `Map Keyword Expr` says it. The wrapper costs one line and
keeps the literals working:

```haskell
newtype Keyword = Keyword Text
  deriving stock (Show, Eq, Ord)
  deriving newtype (IsString, Pretty)   -- "dtype" still works; rendering unchanged
```

Stay targeted. A newtype earns its place where a primitive loses its meaning in
transit. Wrapping an obvious single field, or every element of a list, is ceremony,
and the ponytail lens will charge for it.

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

### Record syntax, never positional

A positional pattern and a `_` wildcard both break silently when a field is added or
reordered, and both discard the name the field already carries. Use record syntax at
every site, in one of three forms.

```haskell
-- Ignore every field: Con{} — needs no extension
freeVarsOfNodeRhs Placeholder{} = []

-- Capture by name: NamedFieldPuns
freeVarsOfNodeRhs (CallFunction MkCallFunction{callArgs}) = concatMap freeVars callArgs

-- Construct by name, every field named
exampleNode = Node{nodeBinder = "x", nodeRhs = rhs, nodeMetadata = mempty, nodeSourceLocs = []}
```

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

`{..}` works at construction sites too, and there it is the stronger form. Where a
construction lists every field as `field = someLocal`, rename the locals after the
fields and collapse the list: `Node{nodeSourceLocs = [], ..}`.

Two conditions on that collapse:

- **The renamed locals must be one-shot** — bound once, and used only in the
  construction. Do not rename a descriptive local that several call sites reuse just
  to reach `{..}`. That trades clarity for brevity.
- **`-Wname-shadowing -Werror` bites.** A local named after a field whose selector is
  in scope unqualified through an import shadows that selector, and the build fails.
  Same-module selectors and qualified ones (`L.functionParams`) are safe. Where the
  import shadows, the explicit field list stays.

**Action:** report a destructure that renames a field it could have bound by name.
Report positional matching on a record with more than two fields, and report a `_`
wildcard where `Con{}` says the same thing. Single-field non-record constructors
(`Placeholder Text`, `Var x`) stay positional. Where a name genuinely must differ —
two records of the same type in one scope, or the shadowing case above — the binding
stays explicit. Say so in the finding rather than forcing the wildcard.

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

### The rest of the type-level toolkit

Each item below is held to the same test as the section above: reach for it when it
removes a check or an impossible case, and not otherwise.

**Type indices over stored dimensions.** A rank, a length or a dimension in a record
field is a value that two branches can disagree about. As a type index under
`KnownNat` it is one fact, and `natVal` recovers it where the runtime needs it. Let
the plugins close the index arithmetic — `-fplugin GHC.TypeLits.KnownNat.Solver` and
`-fplugin GHC.TypeLits.Normalise` — rather than a hand proof or an `unsafeCoerce`.

```haskell
-- ❌ REJECT: rank is a field, and every operation re-checks it
data Tensor = Tensor { tensorRank :: Int, tensorData :: Vector Double }

-- ✅ REQUIRE: rank is an index, and the bad call does not compile
Squeeze :: KnownNat n => Expr (TTensor (n + 1)) -> Fin (n + 1) -> Expr (TTensor n)
```

**Generated singletons, never a hand-written bridge.** Where an index must be
recovered at run time, `genSingletons` and `singDecideInstances` write the `Sing`
type, the `SingI` instances and the decidable equality. The typed downcast then falls
out of `decideEquality`, which returns the `:~:` that makes the cast safe. No tag
comparison and no `unsafeCoerce` are left to review.

```haskell
hasType :: Sing (a :: Type) -> SomeExpr -> Maybe (Expr a)
hasType expected (SomeExpr @actual e) = case decideEquality expected (sing @actual) of
  Just Refl -> Just e
  Nothing   -> Nothing
```

**Injective type families.** An associated type the compiler cannot invert forces an
annotation at every call site. Declare the dependency — `TypeFamilyDependencies`, the
`= r | r -> k` form — and the wrapped payload resolves its own kind.

**Phantom parameters for namespaces.** One identifier type serving several namespaces
lets any name reach any function, and the compiler agrees. A phantom parameter over a
closed kind separates them at no runtime cost, with the raw constructor unexported.

```haskell
data NameKind = Buffer | Channel | Tensor | Kernel | Config
newtype Name (k :: NameKind) = UnsafeName RawName
declare :: Declarable k => Name k -> InfoType k -> Decls -> Decls
```

**One rank-2 traversal, not one recursion per consumer.** Every consumer that walks a
recursive type by hand is one more place where a new constructor goes unhandled and
nothing says so. Write the traversal once, rank-2 over an `Applicative`, and derive
the folds from it.

```haskell
traverseSubExprs :: Applicative f => (forall b. Expr b -> f (Expr b)) -> Expr a -> f (Expr a)

foldMapSubExprs :: Monoid m => (forall b. Expr b -> m) -> Expr a -> m
foldMapSubExprs f = getConst . traverseSubExprs (Const . f)
```

**Action:** report a stored dimension that a type index would carry; a hand-written
`Sing`, `SingI` or equality witness that `genSingletons` reaches; a non-injective
family that needs an annotation at its call sites; one identifier type shared by two
namespaces; and the second hand-written recursion over a type that already has a
traversal.

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

## Derive, never hand-write

**This is non-negotiable: derive every type class instance.** A hand-written
instance is a test surface — code that can be wrong in ways the compiler cannot
catch, and every line of it is a line a derived instance would not have. The
default is derivation, the preference is derivation, and the only thing left to
discuss at review is *which* derivation strategy.

Three rules govern this, in order:

1. **Derive inline with the data declaration.** The `deriving` clause lives on the
   `data`/`newtype` it serves — never standalone, never in another module unless
   the orphan policy below forces it.
2. **Name the strategy on every clause** (`DerivingStrategies`).
3. **Add the dependency that lets you derive** — after base runs out. If a library,
   such as `deriving-aeson` or `quickcheck-instances`, turns a hand-written instance
   into a derived one, add the dependency. A dependency is audited once; a
   hand-written instance is re-checked at every review.

A hand-written instance is permitted only when no derivation path exists *at all* —
not by adding a package, not by a `via` wrapper, not by `GeneralizedNewtypeDeriving`.
Then, and only then, it is backed by a property test or it is a finding.

### DerivingStrategies on every clause (required)

Every `deriving` clause must name its strategy — `stock`, `newtype`, `anyclass`, or
`via`. A bare `deriving (Eq, Show)` is a finding: it leaves the strategy to the
compiler's default, which is exactly the kind of implicit decision review exists to
catch, and a future GHC version can change the default under you.

```haskell
-- ❌ REJECT: no strategy — the compiler picks, and silently
data Foo = Foo Int deriving (Eq, Show)

-- ✅ REQUIRE: every class has an explicit strategy
data Foo = Foo Int
  deriving stock (Eq, Show)
```

**Action:** report every `deriving` clause that does not name a strategy.

### DerivingVia for a shared codec shape

When several types share the same class shape — the same JSON field-label modifier,
the same `Options` — that shape is a `newtype` wrapper used `via`, not a hand-written
instance copied per type. `deriving-aeson` or a one-line local wrapper both qualify.

```haskell
-- ❌ REJECT: N types, 2N hand-written instances, all identical
instance ToJSON Foo where toJSON = genericToJSON (acpOptions 3)
instance FromJSON Foo where parseJSON = genericParseJSON (acpOptions 3)

-- ✅ REQUIRE: one wrapper, derived once, reused
newtype AcpJson a = AcpJson a

instance ToJSON a => ToJSON (AcpJson a) where ...

data Foo = Foo { fooA :: Int }
  deriving (ToJSON, FromJSON) via AcpJson Foo
```

**Action:** report any `instance ToJSON X where toJSON = genericToJSON opts` — it is a
`DerivingVia` candidate. Report two or more instances sharing the same options as a
DRY violation resolvable by a single wrapper.

### GeneralizedNewtypeDeriving for newtype wrappers

A `newtype` exists to inherit the wrapped type's instances for free. Re-declaring
`Eq`, `Ord`, `ToJSON`, and other classes by hand on a newtype defeats the point.

```haskell
-- ❌ REJECT: hand-writing what the newtype gets for free
newtype UserId = UserId Text
instance ToJSON UserId where toJSON (UserId t) = toJSON t

-- ✅ REQUIRE: derive through the representation
newtype UserId = UserId Text
  deriving newtype (Eq, Ord, Show, ToJSON, FromJSON)
```

**Action:** report a hand-written instance on a `newtype` whose body is a delegation
to the wrapped value.

### `Generically` from base for product monoids

A record whose every field is a monoid has a `Semigroup` and a `Monoid` that are pure
structure: field-wise `<>`, field-wise `mempty`. base ships the wrapper that derives
them, so this case costs no package at all.

```haskell
import GHC.Generics (Generic, Generically (..))

data Subst = Subst {substNames :: Map (Name TypedFx) SomeExpr, substDims :: Map DimVar Dim}
  deriving stock (Show, Generic)
  deriving (Semigroup, Monoid) via Generically Subst
```

**Action:** report a hand-written product `Semigroup` or `Monoid`, and name
`Generically` as the fix. Report `generic-monoid` or `generic-deriving` in a
dependency list where `Generically` plus stock deriving already reach the instance.
The dependency rule below covers instances that base cannot derive. It is not a
licence to add a package first.

### No standalone deriving

`deriving instance Eq Foo` separates the instance from the type it belongs to, making
the instance set harder to read at the definition site. Put the deriving in the data
declaration's own clause.

```haskell
-- ❌ REJECT: the instance is away from the type
data Foo = Foo Int
deriving instance Eq Foo

-- ✅ REQUIRE: the instance is part of the declaration
data Foo = Foo Int
  deriving stock (Eq)
```

**Action:** report every `deriving instance` (standalone). The one exception is when
the instance must live in a different module than the data type — and the orphan
policy below already governs that.

### Add the dependency, not the instance

If an instance can be derived by adding a library instead of hand-writing it, **add
the dependency**. This is not a judgement call — a dependency is audited once; a
hand-written instance is re-checked at every review. Common cases:

- `deriving-aeson` — `ToJSON`/`FromJSON` with a field-label modifier, `via` a wrapper.
- `quickcheck-instances` — `Arbitrary` for common types.
- `quickcheck-classes-base` — the law batteries that pay for a hand-written instance,
  below.

`Semigroup` and `Monoid` for a product type are base's `Generically`, above, and not
a package.

**Action:** when a hand-written instance could be replaced by a derivable one from
an existing or addable package, name the package in the finding. "We do not have that
dependency" is not an answer — the finding is "add the dependency and derive".

### Hand-written instances must carry property tests

This is the cost of admission for a hand-written instance: it is a liability backed
by a property test, or it is a finding. No property test, no hand-written instance —
derive instead. For `ToJSON`/`FromJSON`: a round-trip test
(`decode . encode == id`). For `Eq`: reflexivity. For `Semigroup`/`Monoid`:
associativity and identity laws.

Do not hand-write the law statements either. `quickcheck-classes-base` ships the
batteries. Bind them to the test tree once, and each hand-written instance then costs
three lines.

```haskell
import Test.QuickCheck.Classes.Base (Laws (..), eqLaws, functorLaws, applicativeLaws, monadLaws)

lawsToTests :: Laws -> TestTree
lawsToTests l = testGroup (lawsTypeclass l) [testProperty n p | (n, p) <- lawsProperties l]
```

The higher-kinded batteries need `Eq1`, `Show1` and `Arbitrary1`. Orphans in the test
module are the right answer there, under the orphan policy below.

Laws worth naming in a finding: `Eq` reflexive, symmetric and transitive; `Ord`
total; `Semigroup` associative; `Monoid` identity; and the `Functor`, `Applicative`
and `Monad` laws **with superclass coherence**. `(<*>) == ap` and `pure == return`
are laws, and a hand-written `Monad` breaks them quietly. Round-trips get the same
treatment: `fromString (show x) == x`.

One caveat on round-trips. Where `Show` is not injective, so that two distinct values
print the same, the round-trip holds only on the canonical subset. Scope the
generator to that subset, and say so in the test. Do not answer a non-injective
`Show` with a merging smart constructor, because it corrupts values that are
genuinely distinct.

**Action:** report every hand-written instance that has no corresponding property
test. The fix is either to add the test, or — preferred — to find the derivation
path that removes the instance entirely.

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

`StrictData` is a module default here, not a per-field decision, and `Strict` is the
stronger form that also bangs `let`/`where` bindings and function arguments — still
to WHNF, not a deep force. A field that is lazy on purpose carries a comment saying
why.

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

- [ ] No field label on a multi-constructor type, and no `-Wno-partial-fields`
- [ ] Newtypes for domain concepts, not type aliases
- [ ] No bare `Int`, `Text`, `String` or `Bool` in a top-level signature
- [ ] Newtyped `Map` keys where a bare `Text` or `Int` is the key
- [ ] Smart constructors for validated types; raw constructor unexported
- [ ] Sum types where a `String` is standing in for a closed set
- [ ] Record syntax at record sites — `Con{}`, puns, or `{..}`; positional only where
      the Action grants it (small non-record constructors, records of two fields or fewer)
- [ ] `RecordWildCards` where a record is destructured, names matching fields
- [ ] A type parameter (`DataKinds`, a GADT index) wherever it retires a runtime check
- [ ] Type indices over stored ranks; generated singletons; injective families;
      phantom-typed namespaces
- [ ] One rank-2 traversal per recursive type, with the folds derived from it
- [ ] No partial function, no incomplete pattern match
- [ ] `foldl'`, strict accumulators, strict `Map` and `State`, `StrictData` on as the
      module default
- [ ] IO isolated from pure logic
- [ ] `DerivingStrategies` on every `deriving` clause — `stock`/`newtype`/`anyclass`/`via`
- [ ] `DerivingVia` wherever a codec shape is shared across types
- [ ] `Generically` for a product `Semigroup` or `Monoid`, and no package for it
- [ ] `GeneralizedNewtypeDeriving` on every newtype, not hand-written delegations
- [ ] No standalone `deriving instance` — derive in the data declaration
- [ ] Every hand-written instance backed by a `quickcheck-classes-base` battery,
      superclass coherence included
- [ ] Efficient structures where indexing matters (`Vector`/`Seq` over `[]`)
- [ ] Fusion-friendly patterns in stream processing
- [ ] No orphan-instance findings (see above)

Findings use the format the invoking prompt asks for. If the prompt asks for no
format, use the upstream `haskell-reviewer` format: file and line range, category,
confidence, problem, impact, concrete fix.
