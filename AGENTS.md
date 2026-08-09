## Testing

- Treat `StowMacUITests`, `StowUITests`, and `Scripts/ui_tests.sh` as local interactive UI tests.
- Keep UI test orchestration exclusively in `Scripts/ui_tests.sh`; CI scripts and workflows must never invoke UI test schemes or the local UI test script.
- Never run or ask about interactive UI tests while implementation is in progress.
- Finish the entire requested code change and all relevant non-interactive checks before starting interactive UI tests.
- Use unit tests, builds, and static checks that do not operate the desktop UI during implementation.
- When interactive UI tests are relevant, accumulate all required scenarios and run them together in one final verification batch.
- Do not run interactive UI tests after each file, controller change, or individual fix.
- If the final UI batch fails, diagnose the complete batch and group related fixes before rerunning it.
