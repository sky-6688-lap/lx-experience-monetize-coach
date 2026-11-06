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
    "references/monetization-paths.md",
    "references/monetization-resources.md",
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
        '<span class="group-title">变现与下一步</span>',
        "精选入口",
        "暂不建议",
        "res-note",
        "<span>个人经验产品化 Skill</span>",
        "下一步（可选）",
        "https://github.com/sky-6688-lap/lx-zero-to-course",
    ],
    "references/monetization-paths.md": [
        "## 一、先问三个问题",
        "## 二、六种收钱方式",
        "## 三、六维匹配打分",
        "## 四、一票否决清单",
        "## 七、90 天：三段动作",
        "monetization-resources.md",
        "一律按 L1 处理",
        "不想跟人打交道",
        "「教」只保留**录播课、图文课、预录音频**",
    ],
    "references/monetization-resources.md": [
        "## 使用规则",
        "## 一、直接能收钱的渠道",
        "## 二、需求与行业验证（免费公开数据）",
        "## 四、开源制作工具",
        "https://mbd.pub/",
        "https://xiaobot.net/",
        "https://afdian.com/",
        "https://www.xiaoe-tech.com/",
    ],
    "references/html-report.md": [
        "### 核心设计原则",
        "一、产品构想",
        "二、判断依据",
        "三、验证行动",
        "交接模块使用比正文更轻的样式",
        "只是占位",
        "并入右格",
        "## 快速版最小内容",
        "90 天三段",
        "精选入口",
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

# 资源清单与报告模板自有链接白名单，不参与“禁止外部链接”检查
whitelist_files = {
    "assets/report-example.html",
    "references/monetization-paths.md",
    "references/monetization-resources.md",
}

for relative in required_files + ["README.md", "SKILL.md"]:
    path = root / relative
    if path.exists() and relative not in whitelist_files:
        text = path.read_text(encoding="utf-8")
        # 不出现外部文章链接与任何联系方式
        found_link = link_pattern.search(text)
        if found_link:
            raise SystemExit(f"校验失败：{relative} 仍包含外部链接：{found_link.group(0)}")
        if contact_pattern.search(text):
            raise SystemExit(f"校验失败：{relative} 仍包含联系方式")

repo_url = "https://github.com/sky-6688-lap/lx-zero-to-course"
url_pattern = re.compile(r"https?://[^\s)）\"'<>|]+")
resources = (root / "references/monetization-resources.md").read_text(encoding="utf-8")
resource_urls = {u.rstrip("，。、;；") for u in url_pattern.findall(resources)}

found_urls = {u.rstrip("，。、;；") for u in url_pattern.findall(report_html)}
extra = found_urls - resource_urls - {repo_url}
if extra:
    raise SystemExit(f"校验失败：报告模板出现清单外链接：{sorted(extra)}")

report_resources = found_urls - {repo_url}
if len(report_resources) > 8:
    raise SystemExit(f"校验失败：报告精选入口超过 8 条（当前 {len(report_resources)} 条）")

bad_terms = ["四个阶段", "四阶段完成", "三个阶段", "三个部分"]
for relative in required_files + ["README.md", "SKILL.md"]:
    path = root / relative
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    for term in bad_terms:
        if term in text:
            raise SystemExit(f"校验失败：{relative} 仍出现旧口径「{term}」")

if "handoff-btn" in report_html or "打开零基础做课 Skill" in report_html:
    raise SystemExit("校验失败：报告模板不应包含跳转网站的打开链接按钮")

class ReportParser(HTMLParser):
    pass

ReportParser().feed(report_html)
print(f"内容防回退校验通过：{sys.argv[1]}")
PY

if [[ "$target_ref" == "WORKTREE" ]]; then
  git -C "$repo_root" diff --check
fi
