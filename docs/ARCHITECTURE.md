# 结构与运行边界

`code/` 是唯一当前源码。`src/tools/` 保留 Python 编译与历史工具、Windows C# 启动器、PowerShell 会话；`src/extension/` 为容器侧中文历史扩展。项目根保存协作规则、说明与版本索引；本项目源码保持普通文件目录，由维护者自行通过 GitHub 网页上传。

`code/web/` 是独立浏览器交互演示，仅此目录由 GitHub Pages 工作流发布。演示没有后端请求，HTML/MathML 预览不冒充 TeX 编译。`code/examples/` 存放原创入门样例。`.devcontainer/` 提供 Codespaces 入口，云端写作目录与克隆的源码仓库分开，不连接开发者本机。配置过程见 `docs/GETTING_STARTED.md` 和 `docs/ONLINE.md`。

运行包保持既有布局：根目录两个启动器，工具位于 `.latex-tools/`，用户论文位于 `papers/`。个人部署位置从被忽略的 `code/.local/deployment.json` 读取；运行实例通过自己的配置定位容器及按需历史任务，不依赖开发目录。

Windows 保存论文、每篇论文的 Git 历史、生成成品及运行入口。Docker Linux 容器挂载工作目录为 `/work`；TeX、内部构建缓存和预览位于容器。LaTeX Workshop 在容器扩展主机中运行，保存文件后调用 `fast_build.py`，编译成功再发布 PDF。编译失败时旧 PDF 会保留，不能以预览存在判断本轮编译成功。

开发测试使用独立镜像、带标签的 `open-latex-dev-*` 容器、自制材料和缓存。测试容器仅挂载本项目 `code/`（只读）及 `code/.tmp/dev-work`（可写），不挂载个人部署目录，不启动个人历史任务。Docker 管理的镜像和底层构建缓存不受项目内缓存路径约束。

历史会话只在用户启动时按需开启；计划任务没有登录、开机或时间触发器。后台保护手动暂存、其他 Git 操作及非受管仓库。任何恢复演练只对自制测试仓库执行。

首版平台为 Windows、Docker Desktop Linux 引擎及 VS Code。未验证 macOS、Linux 宿主机及任意远程 Docker 主机。现代 TeX Live 安装来源仍为在线 CTAN，完整运行环境尚未做到逐包锁定。
