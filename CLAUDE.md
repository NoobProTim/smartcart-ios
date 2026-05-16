# SmartCart iOS — Claude Instructions

## Token Utilization

Token efficiency is a core objective on every task. Apply these rules without exception:

### Read efficiently
- **Read targeted sections first.** Use `offset`/`limit` on large files. Only read full files when you need broad context.
- **Grep before read.** Use `grep`/`Bash` to locate symbols or confirm existence before opening files.
- **Never re-read files you just edited.** Edit/Write errors on failure — if no error, the change landed.
- **Avoid redundant confirmation reads.** Don't read a file back after writing it just to confirm contents.
- **Use `smart_outline` or `Glob` before full reads on unfamiliar large files.**

### Think first, execute once
- **For any multi-file change: gather all context before touching anything.** Read every relevant file in one parallel batch, identify all edits needed, then execute all changes in a single message.
- **Never interleave reads and edits.** The pattern read→edit→read→edit wastes tokens. Complete pattern: read all → plan all → edit all in parallel.
- **If a task needs 5 file edits, all 5 go in one message.** Independent edits are always parallel tool calls, never sequential turns.

### Stay concise
- **Batch independent tool calls in parallel.** If two reads or searches don't depend on each other, fire them in the same message.
- **Check memory before re-deriving.** Load relevant memories at session start; don't re-explore known facts.
- **Skip verbose explanations.** State what changed and what's next. One or two sentences max at end of turn.

## Definition of Done

A code task is not done until the build is verified. Before calling any code task complete:
- Run `xcodebuild -scheme SmartCart -destination 'id=2B2B08E5-0702-4DA1-A28D-B81916471D10' build` and confirm 0 errors.
- Compiler warnings are not acceptable — fix all warnings before closing a task.

## Multi-File Change Rules

### Model field additions
Adding a field to any model is always a 3-part change. Identify all 3 before touching anything:
1. **Model struct** — add the stored property
2. **Service layer** — update every initializer or decoder that constructs this model (FlippService, DatabaseManager fetch methods)
3. **View layer** — update every view that displays or depends on the field

Miss any one of these and the build will fail or the field will silently be unused.

### Bug pattern fixes
When fixing a bug caused by a code pattern (e.g. `nil == 0`, missing `import`, wrong isolation):
- Grep for every other instance of that pattern before closing the task.
- Fix all instances in the same commit — not just the one that surfaced.

## DatabaseManager Extension Routing

New database methods go in the correct extension file, not `DatabaseManager.swift` itself:
- `DatabaseManager+GroceryList.swift` — grocery list reads/writes
- `DatabaseManager+Fixes.swift` — purchase marking, replenishment recalculation
- `DatabaseManager+Alerts.swift` — alert log reads/writes
- `DatabaseManager+Purchases.swift` — purchase history inserts
- `DatabaseManager.swift` — migrations, settings helpers, store helpers, item helpers only

## UI / Design Conventions

Before adding any new UI, check the Design System Conventions section in memory (`project-sprint-state.md`). Key rules:
- Section headers: `.font(.system(size: 11, weight: .semibold).smallCaps())` + `.textCase(nil)`
- Prices: `.monospacedDigit()`
- Discount badges: green capsule — `Color.green.opacity(0.12)` background, `.foregroundStyle(.green)`
- Store badges: always use `StoreBadgeView(name:)` — never inline store name styling
- Animations: `.animation(.spring(duration: 0.35, bounce: 0.15), value:)` on list changes
- Haptics: `.sensoryFeedback(.success, trigger:)` on saves

## Project Context

- Swift 6, `-default-isolation=MainActor` project-wide. Any function called from a nonisolated context must be marked `nonisolated`.
- `-enable-upcoming-feature MemberImportVisibility` is active. Always `import Combine` explicitly in files using `@Published` or `ObservableObject`.
- SQLite.swift `try?` returns `nil` on error. Always use `?? 0` (never `== 0` bare) when comparing scalar results.
- Shared state: `GroceryListViewModel` lives in `ContentView` as `@StateObject` and is injected via `.environmentObject`. Never create a second instance in child views.
- Simulator target: iPhone 17 (id: 2B2B08E5-0702-4DA1-A28D-B81916471D10, OS: 26.5).
