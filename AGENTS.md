# Open-LaTeX

- 默认中文沟通。项目根为本文所在目录，当前源码唯一入口为 `code/`。个人部署实例由 `code/.local/deployment.json` 指定。
- 每个 PowerShell 进程先 `. ./project-env.ps1`；入口可从任意目录通过绝对路径加载。路径从脚本位置推导，依赖、缓存和临时资料均在 `code/` 内；不改全局环境、HOME、CODEX_HOME、凭据或应用存储。
- 先在本项目实现并隔离验证，再按清单部署。测试资源使用独立名称与自制材料，禁止测试入口启动个人历史任务、修改私人论文或操作已有编辑器窗口。
- 部署前比较目标基线，备份将替换的文件，逐文件记录哈希及失败状态；回滚只处理本轮清单。常规已验证同步已授权。破坏性操作、无法判断的冲突或必须中断写作时单独确认。
- 保留论文、各自的 Git 历史、个人配置、日志与旧备份。私人修复须先备份且仅做有依据的最小修改；私人核验资料放入被忽略的 `output/private/` 或 `code/.local/`。
- 本项目源码保持普通文件目录，不建立本地 Git 仓库；维护者自行通过 GitHub 网页上传。未经新的明确授权，不初始化源码仓库、提交、tag、设置远程、推送或发布。论文历史功能及其隔离测试所需的 Git 不受此限制，既有论文历史须保留。项目采用 MIT，署名 Open-LaTeX contributors；第三方材料未确认授权前不分发。
- 2026-10-19 维护者已明确授权本轮通过 GitHub 网页发布到 Maverickquliushang/Open-LaTeX，并配置仅由 GitHub 托管的在线体验；不重新初始化本地源码 Git。上传使用明确公开文件清单，禁止把 code/.local、output/private、论文、缓存、浏览器环境及个人配置加入网页上传。
- 产品版本以 `code/VERSION` 为单一来源；组件保持独立版本。仅完成并验证一轮交付后形成版本；历史归档不可覆盖。文档与功能同步更新，明确区分完成、未执行、失败和阻塞。
- 构建：`./code/scripts/build.ps1`。隔离测试：`./code/scripts/test.ps1 -BuildImage`；启动器诊断：`./code/scripts/test-launchers.ps1 -ContainerName open-latex-dev-validation`。
- 部署：`./code/scripts/deploy.ps1 -Action Baseline` 记录基线，`-Action Plan` 生成清单，`-Action Apply -PlanPath <清单>` 应用。已有基线不得覆盖，新一轮须显式传新的 `-BaselinePath`。回滚：`./code/scripts/rollback.ps1 -ManifestPath <清单>`。私人修复另用被忽略的专用清单与恢复点。
- 归档：`python ./code/scripts/archive.py --runtime ./code/.build/runtime --notes <已经核验的发行说明>`；版本目录已存在时拒绝执行。归档前确认 README、变更记录、验证与部署状态真实，归档后校验哈希、解压结构与解压后构建。
