# Path Profiling — Code Review Notes

Working notes from a line-by-line review of the Ball-Larus path profiling implementation
(`src/monitors/PathProfilingMonitor.v3`, plus supporting changes in `src/util/CfgBuilder.v3` and
`src/util/ControlStack.v3`).

Reference: Ball & Larus, *Efficient Path Profiling*. Section/Figure numbers below refer to it.

---

## 0. Orientation — build, run, test

```sh
./build.sh wizeng x86-64-linux                                   # build the engine
./bin/wizeng.x86-64-linux --monitors=path-profile demo_paths.wasm  # run the monitor
test/monitors/path_profile_test.sh                               # run the regression suite
```

The suite diffs each `test/monitors/path_profile_*.wat` against a committed `.expected` holding the
monitor's `func` / `counts[]` lines. `REGEN=1 test/monitors/path_profile_test.sh` rewrites them —
only do that after confirming a change is intended, since these files *are* the correctness record.
`.wat` sources are compiled with `wat2wasm` (the script does this automatically when the `.wat` is
newer than the `.wasm`).

**Always rebuild and re-run the suite after every change.** Nearly every bug found in this review was
caught this way rather than by reading.

### Where things live

| File | Contents |
|---|---|
| `src/monitors/PathProfilingMonitor.v3` | The whole monitor: `assignVals`, `kruskals`, `SpanningTree` (Increment/DFS/Dir), Fig. 8 passes, `placeProbes`, the probe classes |
| `src/util/CfgBuilder.v3` | `CfgBlock` / `CfgEdge`, instruction ownership (`last_instr_pc`), empty-block elision, exit selection |
| `src/util/ControlStack.v3` | Wasm control-structure → block callbacks: `visit_IF`, `visit_BR_TABLE`, `visit_RETURN`, `end()` |
| `demo_paths.wat` | Main multi-shape test module (9 instrumented functions) |
| `test/monitors/path_profile_*.wat` | Focused single-shape cases |

`CfgBuilder` has a second consumer, `src/monitors/BytecodeProfilingMonitor.v3` (`--monitors=bprofile`) —
check it still runs after CFG changes.

### Virgil gotchas hit during this work

- A closure cannot assign to a captured local. `hasBackedge` uses a `Box<T>` for this; elsewhere the
  fix is a manual `for (l = list; l != null; l = l.tail)` loop instead of `Lists.apply`.
- A generic type parameter `B` cannot be compared to `null` — use a domain flag (e.g.
  `ControlStack.isUnreachable()`) instead.
- Value types (`type X(...) #unboxed`) and variant types (`type X { case ... }`) cannot be compared
  to `null`, so they can't use `null` as an "unset" sentinel.
- There is no destructuring binding; `def (a, b) = f()` is a parse error. Use `.0` / `.1`.
- Class names are global across the whole build. `ExitProbe` collided with `R3Monitor`'s and had to
  become `PathExitProbe`.
- `Vector.extract()` empties the vector and is at least as cheap as `copy()`; `Arrays.sort` is a
  mergesort that allocates a new array and never mutates its input.

## 1. What the monitor does

Enabled with `--monitors=path-profile`. For each acyclic function it assigns every ENTRY→EXIT path a
unique integer, instruments a minimal set of edges so that a register `r` accumulates that integer at
runtime, and reports `counts[k]` = how many times path `k` executed.

Cyclic functions are skipped entirely (`hasBackedge`). General CFG→DAG conversion (Section 4) is
**not implemented** — this is the largest outstanding gap.

## 2. Pipeline

`onParse`, per function:

| Step | Code | Paper |
|---|---|---|
| Build CFG, get `(entry, exit)` | `cfgBuilder.build` | §3.1 |
| Skip if cyclic | `hasBackedge` | §4 (unimplemented) |
| Assign `Val(e)` / `NumPaths(v)` | `assignVals` | Fig. 5, §3.2 |
| Maximum spanning tree | `kruskals` | §3.3 |
| `Increment(e)` for each chord | `SpanningTree.computeIncrements` | Fig. 4 |
| Instrument edges | `placeInit` / `placeCount` / `placeDefault` | Fig. 8, §3.4 |
| Place probes | `placeProbes` | — (engine-specific) |

## 3. The central problem

The paper says `instrument(e, code)` — attach code to an *edge*. Wizard can only attach probes to
*instructions*. So every design question in this review reduces to: **given an edge, which
instruction do we instrument?**

The answer that survived: **the last instruction of the edge's source block** (`CfgBlock.last_instr_pc`).

- For a **decision block** (out-degree > 1) that instruction *is* the branch, so the probe reads the
  operand to learn which edge was taken.
- For a **single-successor block**, entering the block already commits to the edge, so any instruction
  in it works; the last one is used for uniformity.

### 3.1 Why `CfgEdge.pc` is the wrong answer

`CfgEdge.pc` is the pc where control *arrives*, not an instruction inside the source block. Arrival
points are shared between edges. This caused a real bug earlier in development (`$double_diamond`):
the else-arm's merge edge is recorded at the `if`'s `end`, which the *then* arm also executes, so a
probe there fired on both paths.

Measured confirmation — one-armed `if`, running only the false path, coverage reports 11/13
instructions covered; the two uncovered ones are exactly the then-arm's body. **The `end` is executed
by the false path**, so it cannot identify either arm.

### 3.2 Instruction ownership

An instruction belongs to a block only if *executing it implies control entered that block*.

The subtlety: an `end` is a merge point, so it belongs to the block it merges **into**, not to
whichever block the iterator happened to be in when it dispatched it. Both arms converge before the
`end`, so nothing reaches it without entering the merge block.

This is recorded in `CfgBuilder.build`:

```v3
def before = ctl_stack.block, isEnd = bi.current() == Opcode.END;
bi.dispatch(ctl_stack);
def owner = if(isEnd, ctl_stack.block, before);
if (owner != null) owner.last_instr_pc = bi.pc;
```

Getting this wrong in an earlier attempt (excluding `END`/`ELSE` from attribution entirely) wrongly
stripped merge blocks of the final `end` they legitimately own.

### 3.3 The empty-block precondition

A block that owns no instruction has nowhere to put its edge's instrumentation. Such blocks are
spliced out in `mergeCfgBlock` — predecessors are retargeted straight at the successor, and the block
never enters the graph.

**This is a precondition, not an optimization.** Without it, per-edge instrumentation is impossible
and the instrumentation has to be folded into a predecessor.

Sources of empty blocks that were found and fixed:

- **One-armed `if`** (ubiquitous). `visit_IF` used to call `splitBlock`, materializing *both* arms
  before knowing whether an `else` exists. Now only the taken arm gets a block; the false edge is
  deferred to `visit_ELSE`, or goes straight to the merge block at `end()`.
- **Function-epilogue block** (every function). Eliminated by making exit the function's own
  outermost label — see §4.2.
- **Explicitly empty `(then)` / `(block)`** (rare). Handled by the splice.

`mergeCfgBlock` uses `cs.pc` rather than `bi.pc` so the deferred false edge still carries the `if`'s
pc — otherwise a decision block's edges would disagree about which branch owns them.

## 4. CFG changes

### 4.1 `br_table` builds one block, not a chain

`visit_BR_TABLE` used to call `brIf` per label, producing a chain of phantom blocks joined by
"continuation" edges. That does not match Wasm semantics — a real `br_table` is one indexed jump; the
intermediate blocks never execute.

It now merges every label directly out of the same source block. This deleted a whole category of
machinery (`buildChainDispatch`, `groupEdgesByPc`) and fixed a latent bug where the last chain step's
continuation and labeled edges were indistinguishable, so classification fell to array iteration
order. That bug was reachable: `br_table $L0 $L0 $L1 $L0 $L1` crashed with `BoundsCheckException`.

### 4.2 `return` is a branch; exit is the outermost label

Per the Wasm spec a `return` is a branch to the function's outermost label. `visit_RETURN` (and the
`return_call` family) now goes through `br(stack.top - 1)` instead of just `setUnreachable()`.

Consequences:

- Returns produce **real edges carrying the return instruction's own pc**, which is exclusive to that
  path — a better probe site than most edges have.
- All exits converge on the outermost label, so `build` returns it as `exit` directly. The synthetic
  exit vertex and its `pc=-1` edges are gone.
- Exit now **owns an instruction** — the function's final `end`.

Verified: `hasBackedge` is unaffected (the outermost label's `bind_pos` is set at the final `end`, so
return edges point forward), and all functions previously instrumented still are.

After this, the only remaining `pc=-1` edges come from trap-terminated blocks (`unreachable`,
`throw`), which is correct — a trapping path never reaches EXIT, so there is no instruction to
attribute.

## 5. Monitor changes

### 5.1 Instrumentation is immediate

`InstrPlan` and its parallel flag arrays are gone. Each `TreeEdge` carries its own `actions` vector,
and `placeProbes` runs *before* the Fig. 8 passes, giving probes references to the edges they cover.
`instrument(te, a)` therefore takes effect immediately — nothing reconstructs it afterwards.

```v3
def instrument(te: TreeEdge, a: Action) { te.actions.put(a); }
def reinstrument(te: TreeEdge, a: Action) { te.actions.resize(0); te.actions.put(a); }
```

`reinstrument` implements §3.4's optimization where a chord that both initializes and counts "simply
becomes `count[Inc(c)]++`".

The three passes are now near-literal transcriptions of Fig. 8 — e.g. `placeDefault`'s "for all
uninstrumented chords" is `if (te.actions.length == 0)`, the actual property rather than a sentinel.

### 5.2 One probe per block

`placeProbes` walks blocks, not decisions:

- out-degree 0, or owns no instruction → skip (EXIT)
- out-degree 1 → `EdgeProbe` at `last_instr_pc`
- out-degree > 1 → `BoolProbe` / `TableProbe` at `last_instr_pc`, which is the branch; the opcode
  itself says which kind is needed (`BR_TABLE` or not), and `read_labels().length` gives the exact
  dispatch width

### 5.3 The `EXIT→ENTRY` chord

§3.3 requires this synthetic edge for the Increment DFS, and says that if it lands as a chord, "its
instrumentation can be placed in the EXIT vertex." Now that exit is a real block, that is exactly
what `PathExitProbe` does — it runs the chord's actions, then restores `r`.

It is placed at every `RETURN`-family opcode plus the function's final byte, so **exactly one fires
per activation**. This deliberately does *not* use the CFG's exit-edge pcs: a `br` out of the body
carries the `br`'s pc in the CFG but at runtime lands on and executes the final `end`, so probing both
would fire twice and corrupt the recursion stack.

### 5.4 Per-function register state

`r` is per-function (`RegState`), not per-activation. Recursive re-entry pushes the caller's `r` onto
an `ArrayStack` in `EntryProbe` and pops it in `PathExitProbe`. This replaced a
`HashMap<TargetFrame, int>` keyed on the live stack pointer — the state is statically known at probe
construction, so it is captured directly instead of looked up per firing.

Modelled on `FuncProfileMonitor`'s save/restore stack, differing in that it needs an explicit
`active` flag: that monitor can use `start != 0` as its sentinel, but `r = 0` is a legitimate value.

## 6. Fixes to the algorithm implementation

### 6.1 Kruskal's tie-break (`pathValTo`)

With uniform edge weights the spanning tree was chosen by arbitrary tie-break. When several tied
edges compete to connect a shared vertex, the tree edge could land on a source whose chord-free chain
from ENTRY carries a nonzero `Val`, with no chord anywhere on that path to account for it.

Ties are now broken by ascending `pathValTo(source)` — the cost of the unique chord-free chain from
ENTRY. **Verified load-bearing**: reverting it reproduces a `BoundsCheckException` on a 4-label
`br_table`.

### 6.2 Single-path functions were never counted

A function with no decision blocks got no probes at all under the old decision-only placement, so its
single edge's instrumentation never ran and `counts[0]` stayed 0 despite the function executing.

Fixed as a consequence of **§5.2** (one probe per block): a single-path function's entry block has
out-degree 1, so it now gets an `EdgeProbe`. `main` (called once) reports 1; `unconditional_br`
(called twice) reports 2. The invariant now holds across every test: **each function's counts sum to
its activation count**.

> Verified by deliberately breaking `PathExitProbe` (removing its `execEdge` call) and confirming the
> counts did *not* change — the fix comes from per-block probing, not from §5.3. An earlier draft of
> this document credited §5.3; that was wrong.

## 7. Deleted

| Removed | Reason |
|---|---|
| `groupEdgesByPc` | Rebuilt a reverse map from data already on the edges |
| `buildChainDispatch` | Only existed for `br_table` phantom chains (§4.1) |
| `chainFrom` / `execChain` | Folding is unnecessary once every block owns an instruction |
| `appendExitAction` | Dead once leaf→exit edges exist before the Fig. 8 passes run |
| `InstrPlan`, `actionsFor`, `treeActions`, `replayFrom` | Superseded by immediate instrumentation (§5.1) |
| `orderBySourceOutgoing` | A two-line list-to-array copy with no logic |
| `findChordIndex` / `findTreeIndex` | O(n) scans replaced by `SpanningTree.edgeMap` + `TreeEdge.isChord`/`index` |
| `Action.Nothing` | "Unset" is now `actions.length == 0`, the real property |
| `splitBlock` / `splitCfgBlock` | Unused after the `visit_IF` rewrite |
| synthetic exit vertex, `EXIT_DECL_POS` | Exit is the function's own outermost label (§4.2) |

## 8. Verification

No reference implementation exists, so correctness is argued three ways: the CFG's own `Val`
assignments, runtime action traces (temporarily printing each `Action` as a probe fires), and
instruction coverage (`--monitors=coverage`, to establish which pcs a given path actually executes).

Run everything with `test/monitors/path_profile_test.sh`. The cases, all in `test/monitors/`:

| Case | Shape it pins down | Profiled counts |
|---|---|---|
| `diamond_only` | `if`/`else` | `[1,1]` |
| `demo_only` | `br_table`, 4 labels | `[2,1,1,1]` |
| `wide_only` | `br_table`, 6 labels, default reused for x≥5 | `[3,1,1,1,1,1]` |
| `dup_labels` | `br_table` with a label repeated across indices | `[1,1,1,1,1]` |
| `one_armed` | `if` with no `else` (the implicit-else elision) | `[1,1]` |
| `empty_then` | `(if x (then))` — both arms empty | `[1,1]` |
| `shapes` | empty `(block)`, `br_if` before `end`, nested empties | no empty block retains edges |
| `trap` | `unreachable` in one arm | the only remaining `pc=-1` edge |
| `recur` | recursive `fact` | `[7,4]` — hand-derived: 7 recursive, 4 base |
| `demo_paths` | all of the above plus loops (skipped) and `br` merges | 9 instrumented functions |

**The checkable invariant:** for each function, `sum(counts) == number of activations`. E.g. `$demo`
is called 5 times and sums to 5; `fact(1,2,3,5)` produces 11 activations and sums to 11. This is what
caught §6.2. It is not machine-checked — the output has no activation count — so verify by hand
against the `main` in each `.wat`.

`bprofile` (the other `CfgBuilder` consumer) is checked for non-regression:
`./bin/wizeng.x86-64-linux --monitors=bprofile demo_paths.wasm`.

### Known coverage gap

**No test exercises a non-zero `Increment` on the `EXIT→ENTRY` chord.** Instrumenting it (`§5.3`) is
implemented and does fire — 34 times across `demo_paths` — but its action is always `RAdd(0)`, a
no-op. Deleting the `execEdge` call in `PathExitProbe` passes the entire suite unchanged.

That may be structural rather than accidental: the chord closes the ENTRY→…→EXIT→ENTRY cycle, and a
zero increment is what makes `r` reset per activation. Whether it can *ever* be non-zero is
unverified. Until a case is found that makes it non-zero, this path is untested and could be silently
wrong.

## 9. Open items

- **CFG→DAG conversion (Section 4) is unimplemented.** Cyclic functions are skipped. This is the
  biggest functional gap.
- **`counts` is caller-independent.** Indexing by call site would need an extra dimension.
- **Trap paths.** A block ending in `unreachable`/`throw` gets a `pc=-1` edge to exit, modelling a
  path that never completes at runtime.
- **`assignVals` runs before the spanning tree**, so `pathValTo`'s tie-break depends on `Val`s that
  were assigned without knowledge of the tree. Correct in all tested cases but the coupling is subtle.
- **`decl_pos` is close to useless** — `splitCfgBlock` used to stamp both arms of an `if` with the
  same pc. `bind_pos` (arrival point) is still used by `hasBackedge`; `last_instr_pc` is the field
  that answers "where can this block be instrumented".

## 10. Where the review stopped / what to do next

The line-by-line review has covered the whole of `PathProfilingMonitor.v3`. The last change made was
removing `chainFrom`, which completed the goal of instrumenting every edge at its own source block.

Suggested next steps, roughly in order of value:

1. **Close the coverage gap in §8** — find (or prove impossible) a program where the `EXIT→ENTRY`
   chord's `Increment` is non-zero. Until then `PathExitProbe`'s `execEdge` call is unexercised.
2. **Section 4: CFG→DAG conversion.** The largest functional gap; cyclic functions are currently
   skipped outright via `hasBackedge`. This is a substantial piece of new work, not a cleanup.
3. **Re-examine `pathValTo`.** It is a tie-break invented here, not from the paper (§6.1). It is
   load-bearing — reverting it crashes `demo_only` — but that suggests something upstream may be
   subtly wrong; the paper's Kruskal step needs no such tie-break. Worth understanding *why* it is
   needed rather than leaving it as a patch.
4. **`counts` indexed by caller.** Noted as a TODO on `PathProfileEntry`.
5. **Review `hasBackedge` and `printCfg`** — the two remaining functions that never got a close
   reading.

## 11. Review conventions

Notes for anyone continuing this review:

- Comments transcribing pseudocode go on their own line directly above the line they describe, and
  should quote the paper rather than reference implementation-local variables.
- "Passes 1/2/3" is this implementation's framing of Fig. 8, not the paper's own terminology.
- Claims about runtime behavior must be **measured** (coverage, action traces), not derived. Several
  plausible-sounding derivations during this review turned out to be wrong:
  - that an edge's recorded `pc` is a valid probe site (it is the *arrival* pc, shared between edges);
  - that `end` belongs to whichever block was current when it dispatched (it belongs to the block it
    merges *into*);
  - that single-path functions correctly report `counts[0] = 0` (they were simply never instrumented);
  - that moving the `EXIT→ENTRY` chord to the EXIT vertex is what fixed that (it was not — see §6.2).
- Do not invent paper content. If a justification depends on the paper's exact wording and the text
  is not to hand, say so rather than reconstructing it.
- Before adding a field or a helper, check whether the fact is already available. Several removals in
  §7 were structures that rebuilt information the CFG already carried.
