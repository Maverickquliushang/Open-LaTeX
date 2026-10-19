# Open-LaTeX Windows 运行包

此包由 Open-LaTeX 源码构建。依赖 Windows、Docker Desktop 的 Linux 引擎、VS Code 与 Dev Containers。TeX、Python 3、Git、latexmk、pdfinfo 需在目标 Linux 容器中安装；完整 Dockerfile 在同版本源码包内。本运行包不是离线 TeX 安装器。

第一次安装请按 [Windows 手把手教程](https://github.com/Maverickquliushang/Open-LaTeX/blob/main/docs/GETTING_STARTED.md)逐步配置；下方是简要清单。源码仓库还提供原创中英文样例和独立的 [GitHub 在线体验](https://Maverickquliushang.github.io/Open-LaTeX/)。

1. 在独立工作目录解压，保留根目录两个 EXE 和 `.latex-tools/`，不要覆盖既有论文目录。
2. 创建或使用已配置 TeX 环境的容器，将此工作目录绑定挂载到 `/work`。创建 `papers/` 保存自己的论文。
3. 复制 `.latex-tools/runtime.example.json` 为 `.latex-tools/runtime.json`，设置实际容器名与唯一历史任务名。`workspacePath` 保持 `/work`。
4. 将 `vscode-settings.example.json` 所需键合并到工作目录的 `.vscode/settings.json`，保留个人设置。通过 Dev Containers 连接容器，并在容器侧安装 LaTeX Workshop 和 `.latex-tools/paper-history-1.0.1.vsix`。
5. 在该目录运行 `.latex-tools/register-history-task.ps1 -Preview` 核实路径，然后不带 `-Preview` 注册按需任务。已有不匹配任务会被拒绝覆盖；不添加登录、开机或定时触发器。
6. 使用 `Start-LaTeX.exe` 开始日常会话。`Open-LaTeX.exe` 保留轻量入口。两者的 `--diagnose` 只读检查配置和容器，不启动历史或编辑器，且不证明远程扩展已激活。

保存文件后由 LaTeX Workshop 调用 `.latex-tools/fast_build.py`。成功 PDF 发布到容器预览目录，再回传到主文件同级 `output/`。失败时保留旧 PDF，必须结合本次编译日志判断。

论文历史是论文目录各自的本地 Git，不会上传远程；关闭 VS Code 后会话仍可能按需继续，容器停止后会话正常结束。用户主动恢复历史时会先保留恢复点。Git 历史仍在同一磁盘上，应另行做自己的独立备份。

请与同版本源码包、RELEASE_NOTES.md 和 SHA256SUMS.txt 一并保存。采用随包 MIT License；第三方依赖适用各自授权。公开下载以仓库 Releases 页面为准。
