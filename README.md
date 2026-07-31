# work-log-hook

[中文说明](README.cn.md)

`work-log-hook` is a small, read-only Codex plugin. After Codex compacts a root session, it injects an existing managed `log.md` into the immediate model continuation.

It complements [`work-log`](https://github.com/iC-weiyu/work-log). It does not create or update checkpoints itself.

## Behavior

The plugin registers one `SessionStart` handler with matcher `^compact$`. It resolves the Git worktree root from the event `cwd` (falling back to `cwd`), checks only the root `log.md`, and injects it only when its first line is `<!-- work-log:v1 -->` or `<!-- work-log:v2 -->`.

The Hook never searches for arbitrary logs, modifies project files, calls Context Guard, changes `compact_prompt`, or replaces Codex built-in compaction recovery.

Missing, unmarked, unreadable, or non-UTF-8 logs; malformed input; and non-compact events produce no stdout and exit successfully. Unexpected internal failures write a concise error to stderr and exit nonzero.

## Requirements

- Codex with lifecycle Hook and Plugin support.
- Python 3 available as `python` on Windows or `python3` on macOS/Linux.
- A project-root `log.md` managed by `work-log`.

## Local installation and trust

Clone or copy this repository to `~/plugins/work-log-hook/`, expose it through the default personal marketplace at `~/.agents/plugins/marketplace.json`, and install it:

```powershell
codex plugin add work-log-hook@personal
```

Open a new Codex CLI session, enter `/hooks`, inspect the `SessionStart` definition, and trust its current hash. Installing or enabling a plugin does not automatically trust bundled command Hooks.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_tests.ps1
```

The suite covers current and legacy markers, Git-root selection, read-only behavior, ignored non-compact events, unmarked logs, and malformed input.

## Removal

```powershell
codex plugin remove work-log-hook@personal
```

Removing the plugin does not remove or edit any project `log.md`.

## License

MIT
