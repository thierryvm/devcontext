## What breaks without this

<!-- The situation, not the diff. Name the incident if there was one. -->

## How it was verified

<!-- On a REAL machine, not only in the harness. Paste what you observed. -->

```
```

## Checklist

- [ ] `pwsh -NoProfile -File .\tests\RunTests.ps1` is green
- [ ] For a bugfix: I reintroduced the bug and **watched the new test fail**
- [ ] No secret anywhere in the diff — fixtures are obviously synthetic
- [ ] No destructive command tested against a real service (decoy binary used)
- [ ] Documentation updated if behaviour changed
- [ ] `CHANGELOG.md` updated if user-visible
