# Contributing

Contributions are welcome: bug reports, ideas and pull requests.

- **Issues:** say what you did, what you expected and what happened. Include your macOS version and `spacectl version`. Never paste secrets or stack data you are not allowed to share.
- **Pull requests:** keep them small and focused. Build with `./build.sh` and check the app launches; CI runs the same build.
- **Scope:** the app is read-only and shells out to `spacectl`. Features that change Spacelift state are out of scope.
- **License:** by contributing you agree your work is released under the [MIT License](LICENSE).

Releases are cut by tagging `vX.Y.Z` where the tag matches the `VERSION` file.
