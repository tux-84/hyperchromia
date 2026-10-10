# Contributing

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `chore:`, ...); [commitizen](https://commitizen-tools.github.io/commitizen/)
is supported (`cz commit`). Work happens on `develop` and lands on `master` via pull
request — CI runs shellcheck, commitlint, and a secret scan on every PR, and releases are
automated from Conventional Commit history via release-please.

Keep `master` free of drift: only `feat:`/`fix:` commits (via release-please's own version-bump
PR) and unavoidable `chore:`/`docs:` merges should land there. Every non-release commit pushes
`master`'s tip past the last tag, so a build off `master` shows `vX.Y.Z-dev` until the next
release — expected between releases, but avoid piling up chores on `master` when they could
wait and go out with the next real release instead.
