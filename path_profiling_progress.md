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

- A closure cannot assign to a captured local. The fix is a manual
  `for (l = list; l != null; l = l.tail)` loop instead of `Lists.apply`.
- A field is assignable only if declared `var`; `def` fields and constructor parameters are not.
- A generic type parameter `B` cannot be compared to `null` — use a domain flag (e.g.
  `ControlStack.isUnreachable()`) instead.
- Value types (`type X(...) #unboxed`) and variant types (`type X { case ... }`) cannot be compared
  to `null`, so they can't use `null` as an "unset" sentinel.
- There is no destructuring binding; `def (a, b) = f()` is a parse error. Use `.0` / `.1`.
- Class names are global across the whole build **unless declared `private`**, which scopes them to
  the file. `ExitProbe` initially collided with `R3Monitor`'s; once both were `private class` the
  name could be reused freely — it now exists independently in `PathProfilingMonitor`,
  `FuncProfileMonitor`, and `R3Monitor`. Prefer `private` for everything not deliberately exported.
- `Vector.extract()` empties the vector and is at least as cheap as `copy()`; `Arrays.sort` is a
  mergesort that allocates a new array and never mutates its input.

## 1. What the monitor does

Enabled with `--monitors=path-profile`. For each acyclic function it assigns every ENTRY→EXIT path a
unique integer, instruments a minimal set of edges so that a register `r` accumulates that integer at
runtime, and reports `counts[k]` = how many times path `k` executed.

Cyclic functions are handled too: Section 4 converts the CFG to a DAG, and `counts[k]` then counts
**acyclic path segments**, not whole-function paths (see §4.3).

## 2. Pipeline

`onParse`, per function:

| Step | Code | Paper |
|---|---|---|
| Build CFG, get `(entry, exit)` | `cfgBuilder.build` | §3.1 |
| CFG → DAG: dummy edges, exclude backedges | `addDummies` | §4 steps 1–2 |
| Assign `Val(e)` / `NumPaths(v)` | `assignVals` | Fig. 5, §3.2 |
| Maximum spanning tree | `kruskals` | §3.3 |
| `Increment(e)` for each chord | `SpanningTree.computeIncrements` | Fig. 4 |
| Instrument edges | `placeInit` / `placeCount` / `placeDefault` | Fig. 8, §3.4 |
| Instrument backedges / self-loops | `placeBackedges` | §4 |
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

The subtlety: `end` and `loop` are merge points, so they belong to the block they merge **into**, not
to whichever block the iterator happened to be in when it dispatched them. For `end`, both arms
converge before it; for `loop`, the backedge and the fallthrough both arrive at it. Nothing reaches
either without entering the merge block.

This is recorded in `CfgBuilder.build`:

```v3
def before = ctl_stack.block, op = bi.current();
def isMerge = op == Opcode.END || op == Opcode.LOOP;
bi.dispatch(ctl_stack);
def owner = if(isMerge, ctl_stack.block, before);
if (owner != null) owner.last_instr_pc = bi.pc;
```

`LOOP` was added to this rule to fix a real miscount — see §4.3.

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

Verified: all functions previously instrumented still are.

After this, the only remaining `pc=-1` edges come from trap-terminated blocks (`unreachable`,
`throw`), which is correct — a trapping path never reaches EXIT, so there is no instruction to
attribute.

### 4.3 Section 4 — cyclic CFGs

The paper's §4 converts a general CFG into a DAG so the acyclic algorithms apply unchanged. Its three
steps, and how each lands here:

**Step 1 — dummy edges.** For every backedge `v -> w`, add `ENTRY -> w` and `v -> EXIT`. These carry a
`Val` but no instruction, so they are marked `CfgEdge.isDummy` and skipped by anything that needs a
probe site. `addDummies` does this in one pass and returns the backedges.

**Step 2 — remove backedges.** Backedges are **excluded, not deleted**: they stay in `outgoing`
because the probe at a decision block still has to dispatch on them at runtime. `dagOut` filters
`isBackedge` out of a successor list, and every acyclic computation (`assignVals`, `kruskals`,
`computeIncrements`, `walkPath`) goes through it. `realOut` is the dual filter, dropping `isDummy`
where an instruction is required.

**Step 3 — the acyclic algorithms** then run untouched.

**Backedge instrumentation.** `placeBackedges` puts the paper's `[count[r]++; r = 0]` on each
backedge, folding in the increments of the two dummy edges it stands for (`dummyInc`). The variant
`CountReset(add, set)` expresses `counts[r + add]++ ; r = set`.

**Self-loops take no dummies.** The paper says these are "handled specially by adding a counter along
them to record the number of times they execute rather than instrumenting them with code
`[count[r]++; r = 0]`", and does not say whether step 1 still applies to them. It does not, and the
reason is what step 1 is *for*: a backedge's dummies exist because the backedge ENDS a path segment
at `v` and BEGINS one at `w`, and the dummies are what let the value assignment enumerate those
truncated segments. A self-loop is deliberately not instrumented with `[count[r]++; r = 0]`, so it
ends no segment and begins none — control stays at `v` and the segment through it continues
unbroken. Giving it dummies fabricates path slots that can never be reached, which is exactly the
symptom observed: one permanently-zero `counts[]` entry per self-loop vertex.

Self-loop trip counts are reported separately as `selfloop[...]`, in slots past the path counts.

**Two bugs this exposed**, both previously masked by adding the dummies anyway:

- `kruskals` read `disjointSet[exit]` for the `EXIT→ENTRY` union, but the disjoint set is built from
  a DFS out of ENTRY. With no `v→EXIT` dummy, a function that never returns leaves EXIT unvisited and
  the lookup returned null. The paper's `V` is the CFG's vertex set; ours was "vertices reachable
  from ENTRY". EXIT is a vertex either way, so it gets a set unconditionally.
- `assignVals` used "no DAG successors" as Fig. 5's leaf test. The figure's leaf is **EXIT itself**,
  which in the paper's CFG is the only vertex without successors. Here a vertex that never reaches
  EXIT has none either, and calling it a leaf fabricated `NumPaths = 1` for a path that never
  completes. The test is now `v == exit`, as the figure writes it.

Together these make `(loop $L (br $L))` report no path slots at all and only its self-loop counter —
correct, since a function that never returns completes no path segment.

**What `counts[k]` means now.** For a cyclic function it counts **acyclic path segments**, not
whole-function paths. There are four kinds (the paper's own enumeration, with `v->w` and `x->y`
backedges): ENTRY→EXIT; ENTRY→v ending at a backedge; w→x ending at a backedge; and w→EXIT after a
backedge. The invariant in §8 generalizes accordingly:

> **sum(counts) == activations + backedge executions**

**The `loop` ownership bug.** `br $top` targets the **`loop` opcode's pc**. That pc was originally
attributed to the block *preceding* the loop, so that block's probe re-fired on every iteration and
the whole trip count landed in one wrong bucket (`counts[2] = 4` instead of `counts[0] = 3`,
`counts[2] = 1`). Fixed by treating `LOOP` as a merge point (§3.2).

**The splice bug.** `last_instr_pc` is assigned *after* `bi.dispatch`, so a block whose only
instruction is the `br` it is being merged by still reads `-1` at `mergeCfgBlock` time and hits the
empty-block splice of §3.3. That path retargets *pre-existing* edges and returns before the
`e.isBackedge = wasBackedge` at the bottom, so the backedge marking was lost — a then-arm consisting
of nothing but `br $loop` produced an unmarked backedge, which `walkPath` then followed into a
`StackOverflow`. The splice now propagates the flag onto every inherited edge: `from` forwards
unconditionally, so reaching it commits to `from -> to`, and each inheriting edge becomes the
backedge in its place. Caught by `loop_two_backedges`.

**Entry advance.** A function whose first instruction is `loop` leaves the entry block owning nothing,
since that opcode now belongs to the loop header. Unlike the empty blocks of §3.3 it has no
predecessors to retarget, so `build` walks `entry` forward past its single unconditional successor.

## 5. Monitor changes

### 5.1 Instrumentation is immediate

`InstrPlan` and its parallel flag arrays are gone. Each `TreeEdge` carries **one** `action`, and
`SpanningTree.instrument` writes it directly, so a Fig. 8 pass takes effect at the moment it runs —
nothing reconstructs it afterwards:

```v3
def instrument(te: TreeEdge, a: Action) {
    instrumented.add(te.source);   // this block now needs a probe
    te.action = a;
}
```

An edge holds a single action, not a list, so §3.4's optimization — a chord that both initializes and
counts "simply becomes `count[Inc(c)]++`" — is a plain overwrite (`placeCount` checks
`Action.RSet.?(te.action)` and assigns `CountConst`), with no separate replace helper.

`Action.Nothing` is the default for an untouched edge, which makes the three passes near-literal
transcriptions of Fig. 8 — `placeDefault`'s "for all uninstrumented chords" is
`if (Action.Nothing.?(te.action))`.

### 5.2 One probe per instrumented block

`instrument` records `te.source` in `SpanningTree.instrumented`, so `placeProbes` iterates exactly
the blocks that need a probe rather than walking the whole CFG:

- out-degree 0 → skip (EXIT)
- out-degree 1 → `EdgeProbe` at `last_instr_pc`
- out-degree > 1 → `BoolProbe` / `TableProbe` at `last_instr_pc`, which *is* the branch; the opcode
  itself says which kind is needed (`BR_TABLE` or not), and `read_labels().length` gives the exact
  dispatch width

### 5.3 The `EXIT→ENTRY` edge is seeded into the spanning tree

§3.3 requires this synthetic edge for the Increment DFS, and notes that *if* it lands as a chord its
instrumentation can be placed in the EXIT vertex. Following "Optimally Profiling and Tracing
Programs" (BL94), `kruskals` instead **seeds it into `T` before the main loop**, unioning EXIT and
ENTRY in the disjoint set so it can never be selected as a chord:

```v3
def exitTreeEdge = TreeEdge.new(exit, entry, null);
exitTreeEdge.isChord = false;
exitTreeEdge.index = tree.length;
tree.put(exitTreeEdge);
def setExit = disjointSet[exit];      // UNION(FIND-SET(EXIT), FIND-SET(ENTRY))
setExit.add(entry);
disjointSet[entry] = setExit;
```

Consequences: it carries no `Increment`, so `ExitProbe` carries no Fig. 8 instrumentation at all —
it only restores `r`. And the Kruskal tie-break that used to be needed (see §6.1) becomes
unnecessary.

`ExitProbe` is placed at every `RETURN`-family opcode plus the function's final byte, so **exactly
one fires per activation**. This deliberately does *not* use the CFG's exit-edge pcs: a `br` out of
the body carries the `br`'s pc in the CFG but at runtime lands on and executes the final `end`, so
probing both would fire twice and corrupt the recursion stack.

### 5.4 Per-function register state

`r` is per-function (`RegState`), not per-activation. Recursive re-entry pushes the caller's `r` onto
an `ArrayStack` in `EntryProbe` and pops it in `ExitProbe`. This replaced a
`HashMap<TargetFrame, int>` keyed on the live stack pointer — the state is statically known at probe
construction, so it is captured directly instead of looked up per firing.

Modelled on `FuncProfileMonitor`'s save/restore stack, differing in that it needs an explicit
`active` flag: that monitor can use `start != 0` as its sentinel, but `r = 0` is a legitimate value.

## 6. Fixes to the algorithm implementation

### 6.1 Kruskal's tie-break — removed, superseded by §5.3

*Historical; the code described here no longer exists.* Before the `EXIT→ENTRY` edge was seeded into
`T`, it competed in Kruskal's like any other edge and could land as a chord. With uniform weights the
outcome fell to arbitrary tie-breaking, and a bad tie could leave a chord-free path carrying a
nonzero `Val` with no chord to account for it — producing a negative `Increment` used as an absolute
register value, and a `BoundsCheckException` on a 4-label `br_table`.

A `pathValTo` tie-break was added to work around it. That was a patch on a symptom: the real defect
was letting the edge compete at all. Seeding it into `T` fixes the cause, and `pathValTo` is gone.

Kept here as a caution — the paper's Kruskal step needs no tie-break, and that discrepancy was the
signal that something upstream was wrong.

### 6.2 Single-path functions were never counted

A function with no decision blocks got no probes at all under the old decision-only placement, so its
single edge's instrumentation never ran and `counts[0]` stayed 0 despite the function executing.

Fixed as a consequence of **§5.2** (one probe per block): a single-path function's entry block has
out-degree 1, so it now gets an `EdgeProbe`. `main` (called once) reports 1; `unconditional_br`
(called twice) reports 2. The invariant now holds across every test: **each function's counts sum to
its activation count**.

> Verified by deliberately breaking `ExitProbe` (removing its then-present `execEdge` call) and confirming the
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
| `pathValTo` | Worked around a symptom; seeding `EXIT→ENTRY` into `T` fixes the cause (§5.3, §6.1) |
| exit-chord instrumentation in `ExitProbe` | The edge is never a chord, so there is no `Increment` to apply (§5.3) |
| `hasBackedge` | Cyclic functions are no longer skipped (§4.3) |
| `SELF_LOOP_DUMMIES` | A flag standing in for a decision; the paper's own reasoning settles it (§4.3) |
| `Box<T>` | Only existed for `hasBackedge`'s closure |

## 8. Verification

No reference implementation exists, so correctness is argued three ways: the CFG's own `Val`
assignments, runtime action traces (temporarily printing each `Action` as a probe fires), and
instruction coverage (`--monitors=coverage`, to establish which pcs a given path actually executes).

Run everything with `test/monitors/path_profile_test.sh` (31 cases). Each `.wat` carries a leading
`;;` comment stating what it pins down; that comment is the authoritative description, this table is
a map.

| Case | Shape it pins down |
|---|---|
| `straight` | straight-line, no decision — the single-path base case (§6.2) |
| `diamond_only` | one `if`/`else` |
| `one_armed` | `if` with no `else` — the implicit-else elision (§3.3) |
| `empty_then` | `(if x (then))`, both arms empty |
| `deep_nest` | `if`/`else` nested three deep through the *then* arm |
| `mixed_nest` | `br_table` arm containing an `if`/`else`, and vice versa |
| `many_paths` | 32 distinct paths — five sequential diamonds |
| `wide_merge` | one block with five predecessors |
| `demo_only` | `br_table`, 4 labels |
| `wide_only` | `br_table`, 6 labels, default reused for x≥5 |
| `table1` | `br_table` with only a default — block has ONE outgoing edge |
| `table2` | `br_table` with exactly 2 entries |
| `table_default` | every executed index falls to the default label |
| `dup_labels` | `br_table` with a label repeated across indices |
| `returns` | explicit `return` on several paths; one arm returns, one doesn't |
| `br_outer` | `br`/`br_if` to outer labels (depth > 0) |
| `select_call` | `select` is data flow, **not** control flow — must stay one path |
| `dead_code` | unreachable code after an unconditional `br` |
| `dead_pred` | a block unreachable from ENTRY that still owns an instruction |
| `trap` | `unreachable` in one arm — the only remaining `pc=-1` edge |
| `loop_skip` | a `loop` with a conditional backedge (originally: that such functions were skipped) |
| `loop_types` | all four §4 acyclic-segment types in one function, distinguished |
| `selfloop` | self-loop counter vs. ordinary backedge, plus an infinite self-loop |
| `loop_two_backedges` | two distinct backedges to the *same* header — must not be collapsed |
| `loop_nested` | backedges to *different* headers, one nested in the other |
| `shapes` | empty `(block)`, `br_if` before `end`, nested empties |
| `recur` | recursive `fact` — `[7,4]`, hand-derived |
| `freq` | **does `counts[k]` equal the number of times path k ran?** (non-recursive) |
| `freq_recur` | same question under recursion |
| `freq_shapes` | same question across mixed shapes in one function |
| `demo_paths` | the original multi-shape module, 9 instrumented functions |

### Reading the output

Each block prints the pc it is probed at; each edge prints its `Val`, its `Increment` if it is a
chord, `DUMMY`/`BACKEDGE` if §4 marked it, and the instrumentation it carries; each count is
annotated with the block sequence that path denotes:

```
  block 100 pc=3
    -> block 103 val=0 DUMMY
    -> block 103 val=2 inc=2  [r=2]
  block 103 pc=12
    -> block 104 val=0
    -> block 102 val=1
  block 104 pc=21
    -> block 101 val=0 inc=0 DUMMY
    -> block 103 val=0 BACKEDGE  [count[r+0]++; r=0]
  counts[1] = 1
      path: 100 103 102 101
```

`enumPaths`/`walkPath` produce those routes by walking every ENTRY→EXIT path and indexing it by its
`Val` sum — the same index the runtime increments — so a golden file can be audited by hand rather
than trusted. Suppressed above `MAX_PATHS_TO_LIST` (1024).

**The checkable invariant:** for an acyclic function, `sum(counts) == number of activations`. E.g.
`$demo` is called 5 times and sums to 5; `fact(1,2,3,5)` produces 11 activations and sums to 11. This
is what caught §6.2. For a cyclic function each backedge execution also ends a segment, so it
generalizes to

> `sum(counts) == activations + backedge executions`

Self-loop trips are excluded from both sides — they are reported as `selfloop[...]`. Neither form is
machine-checked (the output has no activation count), so verify by hand against the `main` in each
`.wat`. Measured:

| Case | sum(counts) | = activations + backedges |
|---|---|---|
| `loop_types` | 8 | 3 + 5 |
| `freq` (nested loops) | 561 | 1 + 560 |
| `demo_paths` `$loop_sum(5)` | 6 | 1 + 5 |
| `demo_paths` `$loop_with_if(6)` | 5 | 1 + 4 |
| `loop_two_backedges` | 7 | 2 + 5 |
| `loop_nested` | 10 | 1 + (6 + 3) |

`bprofile` (the other `CfgBuilder` consumer) is checked for non-regression:
`./bin/wizeng.x86-64-linux --monitors=bprofile demo_paths.wasm`.

### Resolved: the `EXIT→ENTRY` "coverage gap"

An earlier draft flagged that no test produced a non-zero `Increment` on the `EXIT→ENTRY` chord — it
fired 34 times across `demo_paths` but always as `RAdd(0)`, and deleting the call passed the whole
suite unchanged.

That was a symptom, not a gap in the tests: the edge was never *supposed* to be a chord. Seeding it
into `T` (§5.3) makes that structural, and the dead instrumentation is gone.

## 9. Open items

- **`counts` is caller-independent.** Indexing by call site would need an extra dimension.
- **Trap paths.** A block ending in `unreachable`/`throw` gets a `pc=-1` edge to exit, modelling a
  path that never completes at runtime.
- **`assignVals` runs before the spanning tree.** No longer a live concern now that `pathValTo` is
  gone and the tree no longer depends on `Val`s, but the ordering is still worth remembering: `Val`
  is fixed before any tree/chord decision is made.
- **`decl_pos` is close to useless** — `splitCfgBlock` used to stamp both arms of an `if` with the
  same pc. `last_instr_pc` is the field that answers "where can this block be instrumented".

## 10. Where the review stopped / what to do next

The line-by-line review has covered the whole of `PathProfilingMonitor.v3`. The acyclic case is
believed complete: every edge is instrumented at its own source block, the `EXIT→ENTRY` edge is
handled structurally. Section 4 is implemented (§4.3), so cyclic functions are profiled too. The
suite covers 31 shapes including dedicated frequency-accuracy and loop cases.

Resolved since the review notes were first written, and kept here so they aren't reopened:

- `pathValTo` — deleted; the cause was fixed instead (§5.3, §6.1).
- The `EXIT→ENTRY` non-zero-`Increment` question — moot; the edge is never a chord (§5.3).

Suggested next steps, roughly in order of value:

1. **`counts` indexed by caller.** Noted as a TODO on `PathProfileEntry`.
2. **Review `printCfg`, `enumPaths`/`walkPath`** — never given a close reading.
   `enumPaths` in particular is verification machinery that is itself unverified, and it silently
   returns `null` above 1024 paths.
3. **Performance.** Untouched so far: `execEdge` walks a `Vector<Action>` per firing, and probes fire
   on every branch of every instrumented function.

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
  - that moving the `EXIT→ENTRY` chord to the EXIT vertex is what fixed that (it was not — see §6.2);
  - that marking a backedge at the point it is created is sufficient (the empty-block splice
    retargets edges created *earlier*, and silently dropped the mark — see §4.3).
- Do not invent paper content. If a justification depends on the paper's exact wording and the text
  is not to hand, say so rather than reconstructing it.
- Before adding a field or a helper, check whether the fact is already available. Several removals in
  §7 were structures that rebuilt information the CFG already carried.
