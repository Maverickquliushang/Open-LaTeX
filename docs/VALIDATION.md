# 验证记录

## 0.1.1 新增内容

- 三栏浏览器演示 13 项检查通过：三个文件切换、直接编辑 LaTeX、标题及输入文件预览、切换保留修改、完整项目版本、按文件差异、恢复与恢复前备份、HTML 作为文字显示、缺失文件提示、桌面和手机无横向溢出。README 图片来自实际运行页面。
- [GitHub Pages 部署](https://github.com/Maverickquliushang/Open-LaTeX/actions/runs/39258556934) 成功；在[实际线上地址](https://maverickquliushang.github.io/Open-LaTeX/)再次完成全部 13 项检查。页面资源仅来自该 GitHub Pages 站点，没有请求本机服务。
- 新网页 JavaScript、归档脚本、Codespaces 初始化脚本语法检查通过。
- Windows 0.1.1 三个启动器及 1.0.1 历史扩展从当前源码构建成功。
- GitHub Actions [首次独立验证](https://github.com/Maverickquliushang/Open-LaTeX/actions/runs/39253621227) 已通过：Ubuntu 编译原创英文（pdfLaTeX）及中文（XeLaTeX）样例、执行论文历史记录并上传 PDF；Windows 构建三个启动器及历史 VSIX 并上传运行包。
- 三栏更新提交 `83f5876` 对应的[独立验证](https://github.com/Maverickquliushang/Open-LaTeX/actions/runs/39258556882) 同样通过，生成中英文 PDF 与 Windows 运行包两项构建产物。
- 本机 Docker Desktop 升级后仍未就绪，当前阻塞为 Secrets Engine 通信文件初始化失败。维护者选择暂不进一步修复，先完成公开发布；因此没有把此次新增样例记作本地 Docker 编译通过。
- Codespaces 配置已提供，尚未在 GitHub 创建付费/耗额度环境完成全流程实测。完整 Windows 全新机器安装、完整 Dockerfile 在线重建也不宣称已验证。
- 此版新增公开教程、演示和云端配置；既有论文实例保持原部署版本，不因网页发布修改私人论文或 Git 历史。

## 0.1.0 已完成验证

本轮在 Windows 上执行。独立镜像基于 Ubuntu 22.04，从公开软件源安装 Python、Git、latexmk、pdfLaTeX、LuaLaTeX、XeLaTeX 与 Poppler。测试仅使用本项目目录和自制材料，没有把个人环境挂到测试容器。

- `code/scripts/test.ps1`：9 项构建/审计测试全部通过（40.682 秒），4 项历史保护测试全部通过（19.957 秒）。编译失败用例的非零退出码为预期结果，保留两处旧 PDF 的断言通过。
- `code/scripts/test-launchers.ps1 -ContainerName open-latex-dev-validation -VerifyTaskRegistration -VerifyDockerTimeout`：9 项检查通过。测试注册的独立任务从未启动，验证后已移除。
- `code/tests/test-deployment.ps1`：9 组保护检查通过，包括基线/计划冲突、篡改产物、配置键保留、部分失败恢复、后续修改保护、路径限制和 Docker 超时。
- Python、PowerShell、JavaScript 语法检查通过；两个环境入口重复加载和跨工作目录调用定位一致。
- 最终运行包 21 个文件与构建清单一致，18 项实例部署映射逐项通过目标哈希验证。

个人实例通过部署后的工具实际运行了 3 个入口：原创冒烟、缺失书目修复入口、作者引用修复入口。编译返回码全部为 0；质量状态分别为 passed、issues、passed，没有 unknown。issues 为 3 条字体提示和 1 条 Underfull；两项目标引用/作者警告均不再出现。

两个已部署 EXE 的 `--diagnose` 返回容器运行、VS Code 命令可用，明确报告 `remoteActivation=not-checked`。历史任务保持 Ready、一个实例内动作、零触发器。容器扩展注册及实现哈希已读回；没有根据文件存在声称已经激活。

私人保全检查：1,440 个初始论文/历史文件变为 1,441 个，仅有批准的一项新增与一项修改，无删除或其他变化。964 个 `.git` 文件及 3 份编辑器配置完全一致。私人路径、具体文献、补丁、原始日志、部署清单和恢复点均只保存在被忽略的本地资料中。

本次未做全量论文审计、全新完整 Dockerfile 重建、跨宿主平台测试、登录/冷启动专项和用户已有窗口断线恢复。这些未执行项不影响已核验的编译审计修复及选择性部署结论。
