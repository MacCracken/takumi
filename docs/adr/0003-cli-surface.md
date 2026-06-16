# 0003 — CLI surface and exit-code convention

- **Status**: accepted (takumi 0.8.4)
- **Date**: 2026-06-16

## Context

Through 0.8.3 `src/main.cyr` was a stub (`"takumi ready"`). All engine
capability existed but was unreachable from a shell, which also blocked the
0.9.x integration-test and CI items. 0.8.4 adds the CLI — the program's public
interface — so the command set and exit-code contract are recorded here.

Build execution (configure/make/install) is still 0.9.x, so the CLI must expose
something useful for `build` without pretending to build.

## Decision

A subcommand CLI in `src/cli.cyr`, dispatched by `main`:

| Command | Behavior |
|---|---|
| `validate <recipe.cyml>...` | parse + `validate_recipe` each; print errors/warnings |
| `list <dir>` | print `name  version` per recipe, sorted |
| `order <dir>` | print the topological build order |
| `build <dir>` | **dry-run**: validate all, resolve order, print the plan, then state execution is not yet implemented |
| `version` | print `takumi <version>` |
| `help` / `-h` / `--help` / no args | usage |

**Exit-code convention:**
- `0` — success
- `1` — operational error: bad/missing input, a recipe fails to parse or
  validate, or a dependency cycle
- `2` — usage error (unknown command, missing argument) **or** a
  not-yet-implemented path. `build` prints its plan and exits `2`, signalling
  "did not complete" without conflating it with a hard `1` failure.

**Testability split:** dispatch lives in `cli_dispatch(args_vec)` — a plain
function over a vec of cstrs that returns the exit code and never touches
`argv`. `main` only marshals `argv` into that vec. Every command is therefore
unit-tested by passing a synthetic args vec and asserting the returned code; no
subprocess harness is needed.

**Output:** plain text via direct `write` (`_putln`), not `println`, for
runtime strings — `println`'s overload dispatch routes an i64-typed argument
(which `str_cstr`/`vec_get` return) to the integer printer, which would print a
pointer instead of the string. Static string literals still use `println`.

**Version string:** a single `takumi_version()` in `src/cli.cyr` is the CLI's
version source; it joins `VERSION`, `cyrius.cyml`, and the `src/package.cyr`
builder stamp as a sync point (all four must match).

## Consequences

- takumi is runnable; integration tests and a CI workflow can now drive it.
- `build` is honest about the 0.9.x execution gap while still doing real work
  (validation + ordering) and exercising the plan path end to end.
- The `cli_dispatch` split keeps the CLI fully covered by the in-process test
  suite (exit-code assertions) — no separate process-spawning test harness.
- Adding a command is local: a `cmd_*` function plus a `streq` branch in
  `cli_dispatch`.

## Alternatives considered

- **Flag parser (clap-style), as ark uses** — heavier than needed for a
  six-command surface; a `streq` dispatch is simpler to read and audit. Can be
  revisited if option parsing grows.
- **Omit `build` until execution lands** — rejected; a dry-run plan is useful
  now and makes the eventual execution a drop-in.
- **`build` exits `0`** — rejected; it hasn't built anything, so a non-zero
  code is the honest signal for scripts.
