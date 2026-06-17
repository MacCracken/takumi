# Guides

Consumer-facing guides for using takumi.

- [Building packages](building-packages.md) — write a CYML recipe and produce a
  signed `.ark`, end to end: the recipe format, the CLI, the build pipeline, the
  build environment, the sandbox, and reproducible builds.
- [Building a base system](base-system-build.md) — operator runbook for driving
  a whole recipe set with `build --execute --keep-going`: prerequisites, the
  built/failed/skipped report, and reproducibility.

See also:

- [Worked examples](../examples/README.md) — complete, annotated recipes.
- [Architecture overview](../architecture/overview.md) — module map + data flow.
- [ADRs](../adr/) — the design decisions behind each capability.
