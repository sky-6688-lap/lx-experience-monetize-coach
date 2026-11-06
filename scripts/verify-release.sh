#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_ref="${1:-WORKTREE}"
verify_root="$repo_root"
temp_dir=""

cleanup() {
  if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
    rm -rf "$temp_dir"
  fi
}
trap cleanup EXIT

if [[ "$target_ref" != "WORKTREE" ]]; then
  temp_dir="$(mktemp -d)"
  git -C "$repo_root" archive "$target_ref" | tar -x -C "$temp_dir"
  verify_root="$temp_dir"
fi

python3 - "$verify_root" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

root = Path(sys.argv[1])

required_files = [
    "SKILL.md",
    "agents/openai.yaml",
    "assets/report-example.html",
    "references/html-report.md",
    "references/boundaries-and-handoff.md",
    "tests/regression-checklist.md",
    "tests/test-cases.md",
]

for relative in required_files:
    if not (root / relative).is_file():
        raise SystemExit(f"校验失败：缺少 {relative}")

skill = (root / "SKILL.md").read_text(encoding="utf-8")
if not skill.startswith("---\n") or "name: lx-experience-productize-coach" not in skill:
    raise SystemExit("校验失败：SKILL.md frontmatter 不完整")

checks = {
    "SKILL.md": ["# 个人经验产品化 Skill"],
    "agents/openai.yaml": ['display_name: "个人经验产品化 Skill"'],
    "assets/report-example.html": [
        '<span class="group-title">产品构想</span>',
        '<span class="group-title">判断依据</span>',
        '<span class="group-title">验证行动</span>',
        "<span>个人经验产品化 Skill</span>",
        "下一步（可选）",
        "https://github.com/sky-6688-lap/lx-zero-to-course",
    ],
    "references/html-report.md": [
        "### 核心设计原则",
        "一、产品构想",
        "二、判断依据",
        "三、验证行动",
        "交接模块使用比正文更轻的样式",
    ],
    "references/boundaries-and-handoff.md": [
        "## 本 Skill 的完成边界",
        "## 完整收尾",
        "## 交接模块：接往「零基础做课 Skill」",
        "只指向一个地址：`https://github.com/sky-6688-lap/lx-zero-to-course`",
    ],
}

for relative, markers in checks.items():
    text = (root / relative).read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            raise SystemExit(f"校验失败：{relative} 缺少关键内容：{marker}")

report_html = (root / "assets/report-example.html").read_text(encoding="utf-8")
layout_markers = [
    ".steps{display:grid;grid-template-columns:repeat(4,1fr)",
    ".steps{grid-template-columns:1fr 1fr}",
    ".steps{grid-template-columns:1fr}",
]
layout_positions = [report_html.find(marker) for marker in layout_markers]
if -1 in layout_positions or layout_positions != sorted(layout_positions):
    raise SystemExit("校验失败：四步卡的桌面、窄屏和手机样式缺失或顺序错误")

import re

link_pattern = re.compile(r"https?://(?!github\.com)[^\s)）\"'<>]+")
contact_pattern = re.compile(r"(微信号?|QQ|电话|手机号)\s*[:：]\s*\S")

for relative in required_files + ["README.md", "SKILL.md"]:
    path = root / relative
    if path.exists():
        text = path.read_text(encoding="utf-8")
        # 不出现外部文章链接与任何联系方式
        found_link = link_pattern.search(text)
        if found_link:
            raise SystemExit(f"校验失败：{relative} 仍包含外部链接：{found_link.group(0)}")
        if contact_pattern.search(text):
            raise SystemExit(f"校验失败：{relative} 仍包含联系方式")

allowed_urls = {"https://github.com/sky-6688-lap/lx-zero-to-course"}
found_urls = set(re.findall(r"https?://[^\s)）\"'<>]+", report_html))
extra = found_urls - allowed_urls
if extra:
    raise SystemExit(f"校验失败：报告模板出现未允许的链接：{sorted(extra)}")

if "handoff-btn" in report_html or 'target="_blank"' in report_html:
    raise SystemExit("校验失败：报告模板不应包含跳转网站的打开链接按钮")

class ReportParser(HTMLParser):
    pass

ReportParser().feed(report_html)
print(f"内容防回退校验通过：{sys.argv[1]}")
PY

if [[ "$target_ref" == "WORKTREE" ]]; then
  git -C "$repo_root" diff --check
fi
