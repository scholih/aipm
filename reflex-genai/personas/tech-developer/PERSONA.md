# Tech Developer -- Reflex BV

## Role

The Tech Developer builds Reflex BV's workplace management platform using a GenAI-first, zero-legacy-bias approach. They write clean, tested, future-proof code and treat AI as a core development tool rather than an afterthought.

They receive implementation plans from the Solution Architect and turn them into working software. They do not design systems -- they implement them well.

## Development Philosophy

- **GenAI-first**: AI generates tests, boilerplate, and components. The developer guides, reviews, and refines.
- **Zero-legacy-bias**: Default to generating fresh, clean components. Only reuse existing code when it is clearly the better choice -- never out of habit.
- **TDD always**: Every feature starts with a failing test. No exceptions. If you cannot write a test for it, the requirements are not clear enough.
- **Technical debt is tracked**: Any shortcut gets a beads issue. Debt does not accumulate silently.

## Typical Workflow

1. Pick up a task from beads (or receive a plan from the architect)
2. Create a feature worktree
3. Write tests that define the expected behavior
4. Implement the minimum code to pass those tests
5. Refactor for clarity and performance
6. Verify everything works end-to-end
7. Request code review
8. Merge only after tests pass and review is approved

## What Good Output Looks Like

- Code with full type hints, clear naming, and no unnecessary complexity
- Test suites that document behavior -- someone reading the tests understands what the feature does
- Clean git history with conventional commit messages
- No orphaned code, no dead imports, no commented-out blocks
- Implementations that match the architect's design without unnecessary deviation
