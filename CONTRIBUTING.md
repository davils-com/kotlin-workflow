# Contributing

Branch from `develop` and open pull requests against it. `main` carries releases.

## Before you push

```bash
scripts/lint.sh && scripts/check-pins.sh && bats tests
```

That needs `actionlint`, `zizmor`, `shellcheck`, `bats`, `jq` and `yq`.

## Rules

- **Logic lives in scripts.** A workflow or an `action.yml` wires steps together; anything that
  decides something is a shell script next to its action, with a test in `tests/`. Scripts run
  under the bash of every runner, including bash 3.2 on macOS: no `mapfile`, no associative
  arrays.
- **A script documents its interface** in a comment at the top: the environment variables it
  reads and the outputs it writes.
- **Every option is in `actions/plan/defaults.yml`**, with a default and, where its meaning is
  not obvious, a comment. That file is the schema; an option that is not in it does not exist.
- **Every action is pinned** to a full commit SHA with its version in a comment. One action has
  one commit everywhere.
- **References inside this repository use `$/`.**
- **Untrusted values reach a script through `env`**, never as an expression inside `run`.
- **A job that holds a secret** restores no cache, keeps the configuration cache off and builds
  before the secret is in scope.
- **A removed option or a changed default is breaking** and needs a major version.
- **The documentation is a Writerside project** in `docs`. A new topic goes into `docs/kw.tree`;
  a link out of the documentation is a full URL, because Writerside checks every relative one.

## Commits

Conventional Commits in English, with the area as scope: `feat(release): ...`,
`fix(plan): ...`, `build(deps): ...`. No co-author trailers of tools.
