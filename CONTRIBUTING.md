# Contributing

Contributions are welcome: bug reports, ideas and pull requests.

- **Issues:** say what you did, what you expected and what happened. Include your macOS version and `spacectl version`. Never paste secrets or stack data you are not allowed to share.
- **Pull requests:** keep them small and focused. Build with `./build.sh` and check the app launches; CI runs the same build.
- **Scope:** the app shells out to `spacectl` and is read-only by default. Actions that change Spacelift state (Trigger, Retry) are opt-in behind the "Enable actions" setting and must always ask for confirmation. Never add flags that skip confirmation, such as `--auto-confirm` or `--force-apply`.
- **License:** by contributing you agree your work is released under the [MIT License](LICENSE).

Releases are automatic: merging a change to the `VERSION` file publishes `vX.Y.Z` as a GitHub Release.
