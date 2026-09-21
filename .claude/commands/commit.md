You are helping the user create a git commit. Follow these steps exactly.

## Step 1 — Check for staged changes

Run `git diff --cached --stat`. If nothing is staged, tell the user to stage files first with `git add` and stop.

## Step 2 — Gather the full diff

Run `git diff --cached` to read every staged change in full.

Also run `git status --short` to see the complete list of staged files (added, modified, deleted).

## Step 3 — Determine the commit type

Choose **one** type from this list based on what the changes do:

- `feat` — new feature or capability added
- `fix` — bug fix or correction
- `refactor` — code restructured without changing behavior
- `chore` — build, config, tooling, deps, CI/CD changes
- `docs` — documentation only
- `test` — test files only
- `style` — formatting, linting, no logic change

## Step 4 — Write the commit subject

Format: `type: rough summary of what this commit does`

Rules (match the existing style in this repo):
- All lowercase
- No period at the end
- No scope in parentheses
- Imperative mood, plain prose (e.g. "add check for existing authfront" not "added" or "adds")
- Keep it under 72 characters
- Write a rough summary that captures the overall intent of the commit, not just a single file or change

## Step 5 — Write the commit body

Write a plain-text body with a per-file change list only. Use this format:

```
<blank line after subject>
Changes:
- <file or area>: <what changed and why, one line per logical change>
- <file or area>: <what changed and why>
...
```

Be concrete. Reference function names, field names, or logic changes where relevant. Do not pad with filler. If a change is a deletion, say so.

## Step 6 — Execute the commit

Run the commit using a HEREDOC so multi-line formatting is preserved:

```bash
git commit -m "$(cat <<'EOF'
type: rough summary of what this commit does

Changes:
- file: what changed
- file: what changed
EOF
)"
```

Do not use `--no-verify`. Do not amend existing commits. Always create a new commit.

After the commit succeeds, show the one-line summary from `git log --oneline -1`.
