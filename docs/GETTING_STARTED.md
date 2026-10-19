# 从下载到第一篇论文：Windows 配置教程

这份教程从一台尚未配置 Open-LaTeX 的 Windows 电脑开始。你不需要会 Git，也不需要克隆仓库。**安装 Docker 后，还要创建带 TeX 工具链的容器、安装编辑器扩展并填写运行配置。**

最终效果：打开启动器 → VS Code 连接容器 → 编辑 `.tex` → 保存并编译 → 查看 PDF → 在中文面板里查看论文历史。

只想先看看：[在线交互演示](https://Maverickquliushang.github.io/Open-LaTeX/)。想在 GitHub 云端实际编译：[Codespaces 教程](ONLINE.md)。

## 0. 先认识三个目录

| 名称 | 放什么 | 你需要做什么 |
|---|---|---|
| 源码目录 | 下载的 Open-LaTeX，里面有 `code/`、`docs/` | 用来构建 Docker 镜像，或自行构建启动器 |
| 写作目录 | 两个 EXE、`.latex-tools/`、`papers/` | 把自己的论文放在这里；备份这个目录 |
| 容器内 `/work` | 写作目录在容器中的同一份文件 | VS Code 连接容器后打开这里 |

不要把论文写进下载的源码目录或浏览器缓存。不要在已有论文目录上覆盖解压运行包。以下命令分为 **Windows PowerShell** 和 **容器终端**，每一步都会标明。

## 1. 安装 Docker Desktop

1. 打开 [Docker Desktop Windows 官方安装说明](https://docs.docker.com/desktop/setup/install/windows-install/)，按页面要求检查 Windows 与虚拟化支持，下载与你的电脑架构匹配的安装程序。
2. 安装时使用 WSL 2 后端，完成安装并按安装器提示重启电脑。
3. 如果提示尚未安装 WSL，以管理员身份打开 PowerShell，运行 `wsl --install`，完成系统提示的重启与首次初始化。已有 WSL 不必重复安装。
4. 打开 Docker Desktop，等待引擎启动。确认使用 **Linux containers**；本项目不使用 Windows containers。
5. 新开一个普通 PowerShell 窗口，逐条运行：

```powershell
docker version
docker info --format '{{.OSType}}'
```

**成功标志：** 第一条同时显示 Client 和 Server，第二条显示 `linux`。只有 Client 或提示无法连接，说明 Docker 引擎还没有就绪，先解决它再继续。

首次构建会下载大量 TeX 与字体包，需稳定网络和充足磁盘空间；它不是离线安装包。Docker Desktop 的适用许可与系统要求以官方页面为准。

## 2. 安装 VS Code 和连接容器的扩展

1. 从 [VS Code 官网](https://code.visualstudio.com/Download)安装 Windows 版。
2. 安装时启用“添加到 PATH”；已安装的用户可以先试下一步。
3. 关闭旧 PowerShell，新开一个窗口，运行 `code --version`。应显示 VS Code 版本。
4. 打开 VS Code，按 `Ctrl+Shift+X` 打开扩展页。
5. 搜索 **Dev Containers**，确认发布者是 **Microsoft**，点击安装。

LaTeX Workshop 和论文历史稍后装到容器侧。只在 Windows 本地扩展区安装，不等于容器里已经可用。详见 [VS Code 官方连接容器说明](https://code.visualstudio.com/docs/devcontainers/attach-container)。

## 3. 下载源码和 Windows 运行包

1. 打开 [Open-LaTeX 仓库](https://github.com/Maverickquliushang/Open-LaTeX)。
2. 点击绿色 **Code → Download ZIP**，解压到你方便找到的文件夹。
3. 打开 [Releases](https://github.com/Maverickquliushang/Open-LaTeX/releases)，下载同版本的 `open-latex-版本号-windows-runtime.zip`。
4. 新建一个空的写作目录，例如在“文档”中创建 `Open-LaTeX-Workspace`，把运行包内容解压进去。
5. 如果 Windows 询问是否覆盖已有论文文件，取消，换一个新的空目录。

写作目录的第一层应该直接看到：

```text
Open-LaTeX-Workspace/
  Start-LaTeX.exe
  Open-LaTeX.exe
  Paper-History.cmd
  vscode-settings.example.json
  .latex-tools/
    runtime.example.json
    paper-history-1.0.1.vsix
    ...
```

**没有现成运行包，或希望自己构建？** 先安装 [Python 3](https://www.python.org/downloads/windows/)，确认 `python --version` 有结果。在源码目录右键“在终端中打开”，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\code\scripts\build.ps1
```

这只为该 PowerShell 进程选择执行策略，不修改系统策略。构建使用 Windows .NET Framework C# 编译器，输出在 `code/.build/runtime/`。把该目录里的**全部内容，包括 `.latex-tools`**复制到新建的空写作目录。构建失败时先阅读错误信息，不要跳过。

## 4. 让 PowerShell 知道你的两个目录

在源码目录的空白处右键“在终端中打开”。下面的步骤尽量在同一个 PowerShell 窗口完成。

```powershell
$SourceRoot = (Get-Location).Path
if (-not (Test-Path (Join-Path $SourceRoot 'code/config/Dockerfile'))) {
    throw '当前不是源码根目录：请进入直接包含 code 和 docs 的文件夹。'
}
$RuntimeRoot = (Read-Host '粘贴写作目录的完整路径，不加引号').Trim()
$RuntimeRoot = (Resolve-Path -LiteralPath $RuntimeRoot).Path
if (-not (Test-Path (Join-Path $RuntimeRoot '.latex-tools/runtime.example.json'))) {
    throw '未找到运行包：请检查是否多套了一层文件夹，或漏复制 .latex-tools。'
}
```

例如资源管理器地址栏显示的是你的写作目录，就复制那个地址。路径中有空格也可以，不要自己增加一对引号。关闭终端后，这两个变量会消失；继续配置前重新执行本节。

## 5. 构建 TeX 镜像

仍在 **Windows PowerShell**：

```powershell
docker build -f (Join-Path $SourceRoot 'code/config/Dockerfile') -t open-latex-toolchain:0.1.1 (Join-Path $SourceRoot 'code')
if ($LASTEXITCODE -ne 0) { throw '镜像构建失败，请先检查上方报错。' }
```

首次运行可能较久；等待命令结束。配方包含 Ubuntu 软件包与在线 CTAN 安装，网络失败时会明确退出，不能把下载中或失败状态当成安装完成。

**成功标志：** 下面的命令可以找到镜像：

```powershell
docker image inspect open-latex-toolchain:0.1.1 --format '{{.Id}}'
```

若报 `failed to resolve`、超时或 TLS 错误，先检查 Docker Desktop 的网络/代理和软件源可达性，然后重新构建。不要通过关闭证书校验来绕过错误。

## 6. 创建你的写作容器

容器名使用 `open-latex`。先检查是否已经存在：

```powershell
docker ps -a --filter 'name=^/open-latex$' --format '{{.Names}}  {{.Status}}'
```

如果已有同名容器，先确认它属于哪个环境；不要删除别人的或旧论文容器。以下命令仅用于**第一次创建新容器**：

```powershell
New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeRoot 'papers') | Out-Null
docker run -d --name open-latex --mount "type=bind,source=$RuntimeRoot,target=/work" open-latex-toolchain:0.1.1 sleep infinity
if ($LASTEXITCODE -ne 0) { throw '容器创建失败，请先处理错误，不要重复创建。' }
docker exec open-latex sh -lc 'python3 --version && latexmk -v && xelatex --version && git --version && pdfinfo -v'
```

**成功标志：** 显示上述工具的版本，`docker ps` 中出现 `open-latex`。`sleep infinity` 让容器保持运行；没有它，默认交互 shell 可能立即退出。

以后启动这个已有容器使用 `docker start open-latex`，不用再 `docker run`。本教程不公开端口，不需要访问开发者电脑。

## 7. 写入配置并复制两个入门示例

在 **Windows PowerShell**：

```powershell
$RuntimeConfig = Join-Path $RuntimeRoot '.latex-tools/runtime.json'
if (Test-Path -LiteralPath $RuntimeConfig) { throw '已有 runtime.json，请手动检查，勿覆盖个人配置。' }
Copy-Item -LiteralPath (Join-Path $RuntimeRoot '.latex-tools/runtime.example.json') -Destination $RuntimeConfig
notepad $RuntimeConfig
```

文件应为以下内容。确认容器名与上一步一致，然后保存并关闭记事本：

```json
{
  "containerName": "open-latex",
  "historyTaskName": "Open-LaTeX-Paper-History",
  "workspacePath": "/work"
}
```

创建 VS Code 配置并复制样例；已有文件时停止，避免覆盖：

```powershell
$EditorDir = Join-Path $RuntimeRoot '.vscode'
New-Item -ItemType Directory -Force -Path $EditorDir | Out-Null
$EditorSettings = Join-Path $EditorDir 'settings.json'
if (Test-Path -LiteralPath $EditorSettings) { throw '已有编辑器配置，请手动合并 vscode-settings.example.json。' }
Copy-Item -LiteralPath (Join-Path $RuntimeRoot 'vscode-settings.example.json') -Destination $EditorSettings
foreach ($SampleName in @('hello-en','hello-zh')) {
    $SampleDestination = Join-Path $RuntimeRoot ('papers/' + $SampleName)
    if (Test-Path -LiteralPath $SampleDestination) { throw "样例已存在：$SampleName，请勿覆盖。" }
    Copy-Item -LiteralPath (Join-Path $SourceRoot ('code/examples/' + $SampleName)) -Destination $SampleDestination -Recurse
}
```

## 8. 先用命令编译第一篇论文

先验证工具链，排除编辑器扩展配置的影响。在 **Windows PowerShell** 分别运行：

```powershell
docker exec open-latex python3 /work/.latex-tools/fast_build.py --engine pdf --document /work/papers/hello-en/main.tex
docker exec open-latex python3 /work/.latex-tools/fast_build.py --engine xe --document /work/papers/hello-zh/main.tex
```

**成功标志：** 最后出现 `PDF synchronized`，写作目录中有 `papers/hello-en/output/main.pdf` 和 `papers/hello-zh/output/main.pdf`。双击 PDF 查看。

英文示例用 pdfLaTeX；中文示例用 XeLaTeX。若运行失败，即使目录里存在旧 PDF，也不能视为这次成功。保留终端最后的错误，检查对应日志。

## 9. 在 VS Code 中编辑与预览

1. 打开 VS Code，按 `Ctrl+Shift+P`。
2. 输入并选择 **Dev Containers: Attach to Running Container...**。
3. 选择 `open-latex`。等待新窗口连接完成，左下角应显示容器连接信息。
4. 在这个新窗口选择 **File → Open Folder...**，输入 `/work`，确定。
5. 打开扩展页，搜索 **LaTeX Workshop**，确认发布者 **James Yu**，安装到当前容器。
6. 按 `Ctrl+Shift+P`，选择 **Extensions: Install from VSIX...**，选 `/work/.latex-tools/paper-history-1.0.1.vsix`。按提示重载当前容器窗口。
7. 打开 `/work/papers/hello-en/main.tex`，修改一句正文并保存。
8. 按 `Ctrl+Shift+P`，运行 **LaTeX Workshop: Build LaTeX project**；首次可通过 **Build with recipe** 选择 `pdfLaTeX + bibliography (latexmk)`。
9. 编译成功后运行 **LaTeX Workshop: View LaTeX PDF file**，在编辑器旁边看到预览。
10. 打开中文样例时，通过 **Build with recipe** 选择 `XeLaTeX + bibliography (latexmk)`。示例的 `% !TeX program` 行也标明了引擎。

若保存时默认仍用 pdfLaTeX 编译中文，在 `/work/.vscode/settings.json` 中把 `latex-workshop.latex.recipe.default` 改为 `XeLaTeX + bibliography (latexmk)`。混用多种论文时按项目需要选 recipe，别只看文件扩展名猜引擎。

## 10. 设置按需论文历史与日常启动

论文历史用 Git **在写作目录内保存修改记录**，不要求 GitHub 账号，也不自动上传。源码仓库和论文历史是两个独立用途。

回到 **Windows PowerShell**，先预览任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RuntimeRoot '.latex-tools/register-history-task.ps1') -Preview
```

确认输出路径指向你的写作目录、任务名是 `Open-LaTeX-Paper-History` 后，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RuntimeRoot '.latex-tools/register-history-task.ps1')
```

任务没有登录、开机、定时触发器，日常启动器按需启动它。若报任务名冲突，不要覆盖已有任务：在 `runtime.json` 换一个唯一名称后重新预览、注册。

先验证一次历史记录：

```powershell
docker exec open-latex python3 /work/.latex-tools/paper_history.py sweep
```

回到容器 VS Code，按 `Ctrl+Shift+P`，选择 **论文历史：打开可视化面板**。选择样例论文，查看版本；重要节点可以命名为“初稿完成”。恢复时先比较差异，确认目标；工具会保留恢复前记录。恢复的是源码，PDF 需要重新编译。

之后日常使用：

1. 双击写作目录里的 **Start-LaTeX.exe**，等待 Docker 与容器就绪。
2. 等 VS Code 完成连接，在 `/work/papers/` 写作。
3. 保存、编译、看 PDF，需要时打开论文历史面板。
4. 不再写作时，可在 PowerShell 运行 `docker stop open-latex`。这会停止你自己的写作容器；不要在编译中执行。论文文件保留在写作目录。

关闭编辑器不一定立即停止历史会话。容器停止后会话正常结束。历史在同一块磁盘上，不能代替独立备份。

## 11. 换成自己的论文

1. 在写作目录 `papers/` 下新建独立子目录，每篇论文一个目录。
2. 放入完整源码，包括 `.tex`、图片、`.bib` 及模板提供的类文件，不只复制主文件。
3. 从会议或期刊官网获取模板并遵守授权；仓库不包含私人论文和未经授权的模板。
4. 在 VS Code 容器窗口打开真正的主 `.tex`，选择模板要求的引擎。
5. 编译后核对引用、字体、版面及最新日志。生成 PDF 不等于符合投稿规范。

若已有论文 Git 仓库，本工具会跳过非本工具管理的仓库，以保留原有流程。不要为了启用自动历史删除已有 `.git`。

## 12. 常见问题：先定位是哪一步

| 现象 | 检查与处理 |
|---|---|
| `docker` 找不到 | 安装 Docker Desktop 后重新打开终端，检查安装与 PATH |
| 只有 Docker Client，没有 Server | 打开 Docker Desktop，等待 Linux 引擎就绪；检查 WSL 与官方故障排查 |
| 镜像构建下载失败 | 检查网络、代理、磁盘和软件源；重新构建，不跳过失败步骤 |
| 容器名冲突 | `docker ps -a` 查清已有容器；复用正确容器或给新环境换名字，不删除旧环境 |
| 容器里看不到论文 | `docker inspect open-latex` 检查 Mounts：写作目录应映射到 `/work` |
| `runtime.json` 缺失 | 检查运行包是不是多套了一层目录，以及文件是否误存为 `.json.txt` |
| `code.cmd` 找不到 | 重开终端后检查 `code --version`，修复 VS Code PATH |
| 只有源码，没有 EXE | 下载 Release 运行包，或按第 3 节自己构建；Download ZIP 是源码 |
| 中文报错或字体缺失 | 先跑自带中文样例，选择 XeLaTeX；自有模板字体需自行安装/替换 |
| LaTeX Workshop 不工作 | 确认扩展安装在容器侧、打开的是 `/work`、配置路径可见 |
| 找不到论文历史命令 | 确认 VSIX 安装到容器扩展主机，并重载该窗口 |
| 历史为空 | 先运行一次 `sweep`，查看是否存在 `.tex`、是否已有非受管 Git 仓库 |
| 已有 PDF，但本次编译失败 | 旧 PDF 会保留；以本次返回码、日志和更新时间判断 |
| 启动器诊断成功但界面没打开 | 诊断只检查配置/容器，不证明远程连接或扩展激活；按第 9 节手动连接排查 |

只读诊断命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RuntimeRoot '.latex-tools/launcher-runtime.ps1') -Diagnose
```

更多：[维护与回滚](MAINTENANCE.md) · [结构说明](ARCHITECTURE.md) · [验证范围](VALIDATION.md)。本教程依据项目实际接口编写；现有环境回归不等于所有新 Windows 机器都已验证。
