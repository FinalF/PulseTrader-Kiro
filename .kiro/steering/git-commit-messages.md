---
inclusion: always
---

# Git Commit Message Convention

After every set of file changes, always provide a git commit message using this format:

```
<type>(<scope>): <summary under 70 chars>

- Bullet describing what changed and why
- Another bullet if needed
```

## Types
- `feat` — new feature or capability
- `fix` — bug fix
- `refactor` — code change with no behavior change
- `style` — formatting, color, UI polish
- `docs` — documentation / spec / README only
- `test` — adding or updating tests
- `chore` — build config, project setup, dependencies

## Scopes (this project)
`models` · `networking` · `indicators` · `signals` · `viewmodels` · `views` · `app` · `config` · `specs`

## Rules
- Summary line must be under 70 characters
- Use imperative mood: "add", "fix", "update" — not "added", "fixed"
- List each changed file or behavior in the body bullets
- Never include API keys, secrets, or tokens in commit messages
