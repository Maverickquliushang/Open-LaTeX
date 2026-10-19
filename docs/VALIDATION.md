# 验证记录

## 0.1.1 新增内容

- 浏览器实际验证：文字编辑联动、命名版本、差异显示、恢复、恢复前备份、文本注入不执行、TeX 特殊字符转义、390px 手机与 1440px 桌面布局、无外部资源请求，共 10 项通过。README 图片来自实际运行的演示页面。
- 新网页 JavaScript、归档脚本、Codespaces 初始化脚本语法检查通过。
- Windows 0.1.1 三个启动器及 1.0.1 历史扩展从当前源码构建成功。
- 本机 Docker Desktop 本次正常启动后引擎未就绪，未把新的样例编译记作本地通过；新增 GitHub Actions 独立验证中英文样例和 Windows 构建，结果以仓库 Actions 中实际执行记录为准。
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
