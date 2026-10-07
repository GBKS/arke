# Development Documentation

Practical guides for working with the codebase: setup, testing patterns, common workflows, and how review passes are run.

## Documents

- **[Setup.md](Setup.md)** — toolchain, schemes, how the bark binary arrives, the test command, log recipes, localization scripts (rewritten 2026-10-07; the bark-CLI-era guides are in `../Archive/Development/`)
- **[Testing_Patterns.md](Testing_Patterns.md)** — how the real test suite is organised and the patterns it uses (rewritten 2026-10-07)
- **[Change_Review_Playbook.md](Change_Review_Playbook.md)** — how review passes are run and recorded (claims audited against the code, findings tracked in `../Open_Follow_Ups.md`); the fresh-context adversarial pass is packaged as the `fault-class-reviewer` agent in `.claude/agents/`
- **[CLAUDE.md](../../CLAUDE.md)** (repo root) — the short list of operating rules every AI session reads first; change a rule there before anywhere else
- **[Release_Train.md](Release_Train.md)** — the two-week cycle that works the backlog off: decide, build, review, device day, TestFlight, soak; definition of done per tier
- **[Rework_Ledger.md](Rework_Ledger.md)** — one line per time generated code had to be revisited, by fault class; reviewed every third train to decide where the next contract rule or test goes
