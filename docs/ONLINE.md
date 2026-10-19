# 在线体验：只用 GitHub，不连接开发者电脑

## 两种入口，各自能做什么

| | GitHub Pages 交互演示 | GitHub Codespaces |
|---|---|---|
| 打开方式 | [直接打开网页](https://Maverickquliushang.github.io/Open-LaTeX/) | [创建自己的云端环境](https://github.com/codespaces/new?hide_repo_select=true&repo=Maverickquliushang%2FOpen-LaTeX) |
| 登录与安装 | 无需登录，无需安装 | 需要 GitHub 账号和可用 Codespaces 额度 |
| 编辑与历史 | 浏览器中演示修改、命名版本、差异与恢复前备份 | Linux 容器中的实际文件与 Git 历史 |
| 排版 | HTML / MathML 排版示意，**不是 TeX 编译** | 真正运行 XeLaTeX / pdfLaTeX / latexmk |
| 保存在哪里 | 当前页面内存；刷新清空，可下载 `.tex` | 访问者自己的 Codespace 中，需自行下载备份 |
| 是否访问作者本机 | 否 | 否 |
| Windows 启动器 | 不运行 | 不运行；浏览器直接使用云端 VS Code |

GitHub Pages 仅托管静态页面；Codespaces 提供独立云端开发容器。这两个入口都不会调用作者电脑的 Docker、端口或私人论文目录。[Pages 官方说明](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages) · [Codespaces 官方说明](https://docs.github.com/en/codespaces/about-codespaces/what-are-codespaces)

## 路线 A：一分钟体验写作与回退

1. 打开交互演示，不需要安装任何东西。
2. 修改左侧标题和正文，右侧查看浏览器排版示意。
3. 输入“初稿完成”，点击“保存版本”。
4. 再改几句话，点击历史列表里的“初稿完成”，查看红绿差异。
5. 点击“恢复此版本”，旧内容恢复，同时增加“恢复前备份”。
6. 展开“查看生成的 LaTeX 示例源码”，下载 `main.tex`，在本地或 Codespaces 用 XeLaTeX 编译。

页面不请求后端，不使用第三方脚本，也不把输入持久保存到浏览器。演示最多保留 20 个版本；关闭或刷新页面会丢失尚未下载的演示文本。它演示操作逻辑，不冒充实际 VS Code 界面或真实 Git 仓库。

## 路线 B：在 Codespaces 真实编译

### 1. 创建环境

1. 登录 GitHub，打开 Open-LaTeX 仓库。
2. 点击 **Code → Codespaces → Create codespace on main**；也可使用上方快捷链接。
3. 确认计费账号与额度。Codespaces 有账号相关的免费额度，超出后是否产生费用取决于你自己的付款与预算设置；用完应停止或删除不用的环境。
4. 等待容器构建、TeX 软件包安装及初始化完成。首次需要下载，不是秒开环境。

仓库 `.devcontainer/devcontainer.json` 使用公开的 Ubuntu 配方安装入门编译工具。此云端配方适合随附样例，不等于本地完整工具链，未安装所有期刊模板、特殊字体和现代 tagged-PDF 依赖。

### 2. 打开独立写作目录

初始化会准备 `/workspaces/open-latex-writing`，并让 `/work` 指向它。该目录与 GitHub 克隆的源码仓库分开，因此论文历史不会嵌套进源码仓库。

在浏览器 VS Code 中选择 **File → Open Folder... → `/work`**。如果初次未自动初始化，在仓库根终端运行：

```bash
python3 code/scripts/setup-codespaces.py
```

脚本保留已有写作内容，不覆盖样例、运行工具或编辑器配置；如果 `/work` 指向别处会停止。重建后如需更新工具，应先备份再自行更新。

### 3. 编译英文和中文示例

打开云端终端，分别执行：

```bash
python3 /work/.latex-tools/fast_build.py --engine pdf --document /work/papers/hello-en/main.tex
python3 /work/.latex-tools/fast_build.py --engine xe --document /work/papers/hello-zh/main.tex
```

成功后分别查看 `papers/hello-en/output/main.pdf`、`papers/hello-zh/output/main.pdf`。通过 LaTeX Workshop 的 **View LaTeX PDF file** 打开，或在文件树右键下载 PDF。

编辑中文样例时选择 XeLaTeX recipe。网页中的 PDF 才是实际编译结果；Pages 演示不是这份 PDF。

### 4. 查看实际论文历史

```bash
python3 /work/.latex-tools/paper_history.py sweep
python3 /work/.latex-tools/paper_history.py menu
```

第一条记录一次各样例的修改；第二条打开终端中文菜单。此云端体验没有 Windows 计划任务，需按需手动运行 `sweep`。

初始化脚本尝试安装本地打包的历史扩展。如果侧栏没有出现它，在源码仓库的 `code/.tmp/codespaces/` 找到 `paper-history-1.0.1.vsix`，通过 **Extensions: Install from VSIX...** 安装并重载，再打开 `/work`。

### 5. 保存与退出

下载自己的源码和 PDF；不要把私人论文提交到公开仓库。Codespace 不是永久独立备份。使用完成后，在 [你的 Codespaces 列表](https://github.com/codespaces)停止环境，不需要时删除，以管理自己的资源与额度。

## 自己部署 Pages 演示

1. Fork 仓库，或通过 GitHub 网页上传公开发行目录。
2. 进入 **Settings → Pages → Build and deployment → Source**，选择 **GitHub Actions**。
3. 进入 **Actions → Deploy interactive demo to GitHub Pages → Run workflow → main**。
4. 等工作流成功，在 Settings → Pages 查看网站地址。
5. 如果更换账号或仓库名，更新 README、`code/web/index.html` 和本文里的仓库、教程、Codespaces 链接。

工作流只发布 `code/web/`，不会发布运行目录、论文、私有配置或开发缓存。不需要自建服务器，不需要公网穿透，也不需要作者电脑保持开机。

## 验证边界

Pages 的交互与实际发布状态见[公开验证记录](VALIDATION.md)。Codespaces 配方与初始化脚本会做本地静态/隔离检查；如果未在 GitHub 上创建真实 Codespace，就不能宣称云端全流程已实测。完整 Windows 功能仍按[本地教程](GETTING_STARTED.md)配置。
