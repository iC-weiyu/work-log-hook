# work-log-hook

[English README](README.md)

`work-log-hook` 是一个小型、只读的 Codex Plugin。Codex 压缩根会话后，它会把已有的受管 `log.md` 注入紧接着的模型 continuation。

它是 [`work-log`](https://github.com/iC-weiyu/work-log) 的可选补充，但不会自行创建或更新检查点。

## 工作方式

插件只注册一个 matcher 为 `^compact$` 的 `SessionStart` 处理器。它根据事件中的 `cwd` 定位 Git worktree 根目录（无法定位时回退到 `cwd`），只检查根目录 `log.md`，并且仅在第一行是 `<!-- work-log:v1 -->` 或 `<!-- work-log:v2 -->` 时注入。

Hook 不会搜索任意日志，不会修改项目文件，不调用 Context Guard，不修改 `compact_prompt`，也不替代 Codex 内置压缩恢复。

日志缺失、无标记、不可读或不是 UTF-8，输入畸形，或者事件并非 compact 时，Hook 不输出 stdout 并成功退出。未预期的内部错误会向 stderr 写入简短说明并以非零状态退出。

## 环境要求

- Codex 支持 lifecycle Hook 与 Plugin。
- Windows 上可调用 `python`，macOS/Linux 上可调用 `python3`。
- 项目根目录存在由 `work-log` 管理的 `log.md`。

## 本地安装与信任

把本仓库克隆或复制到 `~/plugins/work-log-hook/`，通过默认个人 marketplace `~/.agents/plugins/marketplace.json` 暴露插件，然后安装：

```powershell
codex plugin add work-log-hook@personal
```

新开一个 Codex CLI 会话，输入 `/hooks`，检查 `SessionStart` 定义后信任当前哈希。安装或启用 Plugin 不会自动信任其中的命令 Hook。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_tests.ps1
```

测试覆盖当前与旧版标记、Git 根目录选择、只读行为、忽略非压缩事件、忽略无标记日志以及畸形输入。

## 卸载

```powershell
codex plugin remove work-log-hook@personal
```

卸载 Plugin 不会删除或修改任何项目 `log.md`。

## License

MIT
