You are helping the user plan and implement a task. Follow these steps exactly. Never auto-advance — every step requires explicit user confirmation before continuing.

## Step 0 — Scope check

Your mental model throughout this step is purely about Divide and Conquer. You are not yet thinking about implementation details, just whether the task is small enough to finish in one focused pass.

Ask: is this task small enough to finish in one focused pass? A task qualifies when a single developer can hold the full change in their head, it touches a bounded set of files, and its test cases can be listed in under a minute.

If no — decompose it into sub-tasks first. Present the decomposition to the user and get confirmation before continuing. Treat each sub-task as its own run of this workflow.

---

## Step 1 — Clarify uncertainties

Identify every ambiguous or underspecified aspect of the request. For each one, present a numbered interactive selection:

```
[?] <Question>

  1. *Recommended* <Option>
  2. <Option>
  3. <Option>
  4. ✏️  None of the above — let me describe what I want
```

Rules for selections:

- Options must be mutually exclusive and cover the likely cases.
- Exactly one option must be marked `*Recommended*`.
- The last option is always the free-text fallback — never omit it.

Do not proceed until every ambiguity is resolved. Stop and wait for confirmation.

---

## Step 2 — Surface all viable approaches

Even if the request implies one solution, list all viable approaches — including simpler or more idiomatic ones. For each, give one sentence on what it is and its key tradeoff. Present them using the same numbered selection format with one `*Recommended*` and a free-text fallback.

Stop and wait for the user to select an approach before continuing.

---

## Step 3 — Abstract draft

Create `temp/plans/<kebab-case-title>.md` with only the high-level skeleton:

```markdown
# Plan: <Concise Title>

**Goal:** <One or two sentences — what this achieves and why.>
**Architecture decision:** <The key design choice, stated briefly.>
**Prerequisite:** <Prior plan that must be done first, or "None".>

---

## Workflow

<ASCII or Mermaid diagram showing data flow, component relationships, or sequence of operations.>
```

Save the file, share the path, and stop. Wait for user approval before continuing.

---

## Step 4 — Decision log

Append to the plan file:

```markdown
---

## Decision Log

- **<Topic>:** <What was decided and the reasoning.>
```

Surface all non-obvious choices: where logic lives, what is reused, ordering constraints, edge case handling. Stop and wait for user confirmation before continuing.

---

## Step 5 — Full plan

Append the remaining sections to complete the plan file:

```markdown
---
## Context

<File paths, line numbers, existing helper locations, model names. Read the files — no guessing.>
---

## Files to Touch

​`
path/to/file.spec.ts   ← what changes and why
path/to/file.ts   ← what changes and why
​`

---

## Test List

Tag every entry `[NEW]` or `[MODIFY]`:

- `[NEW]` — a test that doesn't exist yet and will be written from scratch during Step 6.
- `[MODIFY]` — an existing test (name the test and its file) that must change. Existing tests are protected by default; only tag one `[MODIFY]` when changing it is actually necessary.

- [ ] [NEW] <Happy path: expected outcome>
- [ ] [NEW] <Inverse / edge case: expected outcome>
- [ ] [NEW] <Empty state / no-op: expected outcome>
- [ ] [MODIFY] <existing test name/file> — what changes and why
```

## To-Do List

Each step is one vertical slice, driven fully through RED → GREEN → REFACTOR in Step 6. Within a step, always name the test file (ex: spec.ts) before the implementation file it makes pass — never the reverse — and keep the order of steps consistent with the order of the Test List.

- [ ] Step 1 — <title> (`path/to/file.spec.ts` → `path/to/file.ts`)
- [ ] Step 2 — <title> (`path/to/other.spec.ts` → `path/to/other.ts`)

Share the completed plan file path and stop. Wait for user approval before continuing.

---

## Step 6 — Implement (TDD)

Follow the to-do list in order. For each item, drive it through RED → GREEN → REFACTOR using the Test List entries it maps to.

**Hard rule:** never create or edit an implementation file before its corresponding test has been written and shown failing (RED) for that item. If an item names both a test file and an implementation file, the test file must be touched first, as a distinct visible action, before the implementation file is opened for writing.

1. **RED** — for each `[NEW]`-tagged test this item covers: write the test, run it, and confirm it fails for the expected reason (not a syntax error or wrong-file mistake). Show the test code and the failing output.
2. **Protect existing tests** — for each `[MODIFY]`-tagged test this item touches: read the existing test as it stands today, then STOP and show the existing test content, the proposed diff, and why the change is necessary (a new test can't cover this instead). Wait for explicit user confirmation before editing it. Never touch a `[MODIFY]` test without this gate, and never touch a test that isn't tagged in the plan at all — treat any other existing test you encounter as out of scope.
3. If this item has no associated Test List entry (e.g. a pure refactor step), skip RED and go straight to step 4.
4. **GREEN** — show the exact diff before touching any file, then make the minimal change needed to pass. Read file contents before writing — never infer from memory. Do not edit the test file itself to force a pass — if a just-written `[NEW]` test looks wrong, stop and flag it to the user instead of quietly loosening it. Run the test(s) and show passing output.
5. **REFACTOR** — clean up if needed, keeping tests green; re-run and show output.
6. Tick the item in the plan.
7. Stop and wait for user confirmation before moving to the next item.

Do not bundle unrelated changes. If anything contradicts the plan, stop and surface it — do not silently adapt. Wait for user approval of all completed items before continuing.

---

## Step 7 — Verify

Run the relevant checks for this repo's stack:

```bash
# Go
go build ./...
go vet ./...
go test ./...

# Node / TypeScript
tsc --noEmit
eslint .
pnpm test
```

Show the actual output — do not summarize or elide failures. Fix any failing tests before proceeding. If tests cannot be run, say so explicitly and describe what manual verification was done instead.

Stop and wait for user approval before continuing.

---

## Step 8 — Summarize

Provide:

1. **What changed** — files modified and the nature of each change.
2. **Why** — the architectural rationale (reference the Decision Log).
3. **Follow-up considerations** — anything deferred, known limitations, or related areas that may need attention.

Keep it tight. Wait for user acknowledgement — the task is not closed until the user confirms.
