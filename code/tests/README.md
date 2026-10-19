# 回归验证

`test_build_audit.py` 必须在独立的 Linux 测试容器内运行，依赖 Python 3.10+、latexmk、pdfLaTeX、natbib 和 pdfinfo。仓库的测试脚本负责建立独立资源；不要把个人容器或论文目录作为测试目录。

```sh
python3 /repo/tests/test_build_audit.py --work-root /work --report /work/regressions.json
```

所有 TeX/BibTeX 材料由测试即时创作。每轮在工作目录下建立独立 `build-audit-*` 目录，保留源码、真实编译日志和逐入口结果，便于核验。9 个测试覆盖无警告与增量构建、引用与文献警告、数字制 natbib 的作者警告及最小修复、日志缺失/空/过期/内容变更、嵌套与多个入口、失败保留原 PDF、字体与版面分类，以及命令行的通过/问题/未知退出状态。

构建器的 `--result-file` 输出 schema version 1 的 JSON：`paths` 提供实际构建目录和 PDF 位置；`diagnostics` 提供真实 `.log`、`.blg` 路径、采集状态和 SHA256；`pdf_published` 指明本轮是否发布成功。`--fresh` 在构建锁内归档当前入口的缓存，不影响其他入口。

审计读取这份契约，不自行推导缓存路径。缺失、空、过期或读取时哈希已变化的日志使质量为 `unknown`，对应未采集的计数和列表为 `null`。没有使用文献处理器时，书目日志为 `not_applicable`。返回码、引用/交叉引用、BibTeX/Biber、字体和版面提示分别报告。`quality_status=passed` 仅表示已采集日志中未发现当前检测规则覆盖的问题，不是对学术内容或所有排版问题的人工审查。

审计命令行将当前选择的汇总写入 `summary.json`，退出码 `0` 表示通过，`1` 表示发现问题，`2` 表示未知（包括零入口）。逐入口编译退出码另存于 `returncode`。不会沿用旧报告作为本轮结果。
