#!/usr/bin/env python3
"""熔断器流程冒烟检查：本地与部署共用，启动后自动确认接口可用、数据符合基线。

检查项：
  1. GET /api/health                 服务存活；
  2. GET /api/fuse                   熔断器列表接口能返回数据；
  3. POST /api/fuse/seed/reload      重新导入一次，再查列表确认按编号覆盖而非追加；
  4. 三种情形齐全                     正常 / 已熔断 / 备件不足 各至少 1 条；
  5. 快照一致性（可选）
       --snapshot <文件>                与已有基线快照比对，不一致即失败；
       --snapshot <文件> --save-snapshot 把当前数据写成基线快照（在本地生成并提交）。

用法：
  python3 scripts/smoke.py                                  # 只做接口冒烟
  python3 scripts/smoke.py --snapshot snap.json             # 冒烟并比对基线
  python3 scripts/smoke.py --snapshot snap.json --save-snapshot  # 生成基线
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from typing import Any

REQUIRED_STATUSES = ["正常", "已熔断", "备件不足"]
EXPECTED_KEYS = ["FUSE-0001", "FUSE-0002", "FUSE-0003"]


def request_json(method: str, url: str, timeout: int = 10) -> Any:
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise AssertionError(f"{method} {url} 返回 HTTP {exc.code}：{detail}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise AssertionError(f"{method} {url} 连不通：{exc}") from exc
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{method} {url} 返回的不是合法 JSON：{exc}") from exc


def normalize(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """快照比对只看业务字段，按熔断器编号排序，避免分页顺序噪声。"""
    picked = []
    for row in items:
        picked.append({key: row.get(key) for key in (
            "熔断器编号", "status", "额定电流", "安装位置", "保护范围",
            "熔断记录", "更换日期", "备件存量", "熔断器状态",
        )})
    return sorted(picked, key=lambda row: str(row["熔断器编号"]))


def main() -> int:
    parser = argparse.ArgumentParser(description="熔断器流程冒烟检查")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="后端地址")
    parser.add_argument("--snapshot", help="基线快照文件")
    parser.add_argument("--save-snapshot", action="store_true",
                        help="把当前熔断器数据写入 --snapshot 指定的文件作为基线")
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    failures: list[str] = []

    def check(name: str, condition: bool, detail: str = "") -> bool:
        if condition:
            print(f"  ✓ {name}")
            return True
        message = f"{name}：{detail}" if detail else name
        failures.append(message)
        print(f"  ✗ {message}")
        return False

    print("[冒烟] 1/5 健康检查")
    health: Any = None
    try:
        health = request_json("GET", f"{base}/api/health")
    except AssertionError as exc:
        failures.append(str(exc))
        print(f"  ✗ {exc}")
    else:
        print("  ✓ GET /api/health 服务存活")
        check("健康检查 ok=true", bool(health.get("ok")))

    print("[冒烟] 2/5 熔断器列表接口")
    items: list[dict[str, Any]] = []
    try:
        listing = request_json("GET", f"{base}/api/fuse")
        items = listing.get("items") or []
        print("  ✓ GET /api/fuse 能返回熔断器列表")
    except AssertionError as exc:
        failures.append(str(exc))
        print(f"  ✗ {exc}")

    if items:
        statuses = {row.get("status") for row in items}
        missing_statuses = [status for status in REQUIRED_STATUSES if status not in statuses]
        check("三种情形齐全（正常/已熔断/备件不足）", not missing_statuses,
              f"缺少状态：{'、'.join(missing_statuses)}")
        keys = {str(row.get("熔断器编号")) for row in items}
        for expected in EXPECTED_KEYS:
            check(f"存在熔断器 {expected}", expected in keys,
                  f"列表中找不到 {expected}，实际编号：{sorted(keys)}")
    else:
        failures.append("熔断器列表为空：示例数据没有装载成功")
        print("  ✗ 熔断器列表为空：示例数据没有装载成功")

    print("[冒烟] 3/5 重复导入按编号覆盖（不追加）")
    before_total = len(items)
    try:
        reload_result = request_json("POST", f"{base}/api/fuse/seed/reload")
        print("  ✓ POST /api/fuse/seed/reload 重新导入")
        check("重新导入返回 ok=true", bool(reload_result.get("ok")),
              f"ok=false：{reload_result.get('message')}")
    except AssertionError as exc:
        failures.append(str(exc))
        print(f"  ✗ {exc}")
    try:
        listing2 = request_json("GET", f"{base}/api/fuse")
        after_items = listing2.get("items") or []
        print("  ✓ 重新导入后再次查询列表")
        check(
            "记录条数没有因重复导入而增加",
            len(after_items) == before_total,
            f"导入前 {before_total} 条，导入后 {len(after_items)} 条，发生了追加而不是覆盖",
        )
        items = after_items
    except AssertionError as exc:
        failures.append(str(exc))
        print(f"  ✗ {exc}")

    print("[冒烟] 4/5 种子基线快照")
    snapshot = normalize(items)
    if args.snapshot:
        if args.save_snapshot:
            with open(args.snapshot, "w", encoding="utf-8") as fh:
                json.dump(snapshot, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
            print(f"  ✓ 已生成熔断器基线快照：{args.snapshot}")
        else:
            try:
                with open(args.snapshot, encoding="utf-8") as fh:
                    saved = json.load(fh)
            except FileNotFoundError:
                failures.append(f"基线快照不存在：{args.snapshot}，请先在本地执行 make seed-snapshot 生成并提交")
                print(f"  ✗ 基线快照不存在：{args.snapshot}")
            else:
                check(
                    f"当前熔断器数据与基线 {args.snapshot} 一致",
                    snapshot == saved,
                    "上线前后熔断器数据不一致：本地基线与线上实际数据对不上，请核对种子文件后重新导入",
                )

    print("[冒烟] 5/5 结论")
    if failures:
        print(f"\n冒烟未通过，共 {len(failures)} 项：")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("全部通过：熔断器列表接口可用，三种情形齐全，重复导入为按编号覆盖。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
