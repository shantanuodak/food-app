# Cleanup Archive - 2026-04-25

This folder holds files moved during the Food App cleanup/stabilization pass.

## Policy

- Active app/backend source, migrations, tests, Xcode project files, API models, and release scripts stayed in place.
- Old planning docs and unused static assets were moved here instead of deleted so they remain recoverable.
- Ignored/generated artifacts were deleted when the disk was full; they can be recreated with normal build/eval commands.

## Contents

- `docs-archive/`: old planning docs, Jira backlog, sprint notes, UI brainstorms, future enhancement notes.
- `generated-artifacts/`: intentionally left as the placeholder for generated material; prior ignored build/eval artifacts were deleted to free disk.
- `landing-page/`: unused static landing page files.
