---
name: plan
description: Generate a structured implementation plan and save it as a Markdown file in temp/plans/. Use this skill whenever the user asks to "create a plan", "plan a feature", "plan this change", "/plan", or describes a feature/fix they want to implement and asks how to approach it. Always use this skill before writing code for non-trivial changes.
---

# Plan

Generate a detailed, codebase-grounded implementation plan and write it to `temp/plans/`.

## Process

### 1. Understand the requirement

Read the user's requirement carefully. Identify:
- Which modules are involved (`auth-front`, `auth-back`, `drai-pro`, `token`, etc.)
- What data layer changes are needed (Prisma schema, Redis keys, etc.)
- Key architectural decisions that must be made upfront

### 2. Explore the codebase

Read the actual source files before writing a single line of the plan. At minimum:
- Affected controller(s) — find exact method names and line numbers
- Affected service(s) — understand current logic
- `token.service.ts` if session/token changes are involved
- `prisma/schema.prisma` if schema changes are needed
- Note reusable patterns (e.g. wildcard Redis scans, guard usage, existing helpers)

Never guess file contents — read them.

### 3. Make architectural decisions

Decide the approach before writing steps:
- Where logic should live (controller vs service vs shared helper)
- Whether existing utilities can be reused
- Ordering constraints between steps (e.g. shared helper must come first)
- Edge cases (authenticated vs token-based, no-op when empty, admin vs self, etc.)

### 4. Derive the output filename

Convert the requirement into a kebab-case filename:
- Strip filler words (a, the, for, on, etc.)
- Keep nouns and verbs
- Prefix with `plan-`
- Example: "clear sessions on password change" → `plan-clear-sessions-on-password-change.md`

### 5. Write the plan file

Save to `temp/plans/<filename>.md` using **exactly** this structure:

---

```markdown
# Plan: <Concise Title>

**Goal:** <One or two sentences — what this achieves and why.>

**Architecture decision:** <The key design choice (where logic lives, what pattern is reused).>

**Prerequisite:** <Any step that must be done first across related plans, or "None".>

---

## Decision Log

- **<Topic>:** <What was decided and the reasoning.>
- **<Topic>:** <What was decided and the reasoning.>

---

## <Relevant Context Section Title>

<Background the implementer needs: key data structures, Redis key patterns, existing utility locations, etc. Include file paths and line numbers where relevant.>

---

## Implementation Steps

### Step 1 — <Title>

**File:** `path/to/file.ts`

<What to add or change, with enough surrounding context to locate it exactly — e.g. "~line 92", "after the existing X call".>

```typescript
// compilable TypeScript grounded in what was read from the actual file
```

> Note: <non-obvious constraint or gotcha, if any>

---

### Step 2 — <Title>

**File:** `path/to/file.ts`

**2a. <Sub-task label>**

<Explanation.>

**2b. `methodName()` (~line N)**

<Explanation.>

```typescript
// code
```

---

## Files to Touch

​```
path/to/file1.ts    ← what changes
path/to/file2.ts    ← what changes
​```

---

## Testing Checklist

- [ ] <Scenario: expected outcome>
- [ ] <Scenario: expected outcome>
- [ ] <Edge case: expected outcome>
```

---

## Rules for plan content

- Every code snippet must be real, compilable TypeScript grounded in what you read from the source files
- Include `~line N` references so the implementer can navigate directly to the right place
- Decision Log must capture non-obvious choices so future readers understand the why
- Testing Checklist must cover: the happy path, the inverse (e.g. admin vs self-change), and the empty/no-op case
- Do not pad with generic advice — every sentence must be actionable or load-bearing context
- Use `> Note:` callouts only for genuinely non-obvious constraints

### 6. Confirm

After saving the file, output:
- The full path to the saved plan file
- A short paragraph summarising the approach
