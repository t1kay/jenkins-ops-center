#!/usr/bin/env python3
"""Kiểm tra sức khoẻ app server: HTTP /health, % disk, % RAM.

Chạy trên app server (Jenkins gọi qua SSH, chỉ dùng thư viện chuẩn):
    python3 /opt/app/scripts/healthcheck.py --url http://localhost:8080/health

Exit 0 nếu mọi thứ OK, exit 1 nếu có mục vượt ngưỡng / lỗi.
"""

import argparse
import json
import shutil
import sys
import urllib.error
import urllib.request

DEFAULT_URLS = [
    "http://localhost:8080/health",  # prod
    "http://localhost:8081/health",  # staging
]


def check_http(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            body = json.loads(resp.read().decode() or "{}")
            ok = resp.status == 200 and body.get("status") == "ok"
            return ok, f"HTTP {resp.status} {body}"
    except urllib.error.HTTPError as exc:
        return False, f"HTTP {exc.code}"
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return False, f"lỗi kết nối: {exc}"


def disk_percent(path):
    usage = shutil.disk_usage(path)
    return usage.used * 100 / usage.total


def mem_percent(meminfo_path="/proc/meminfo"):
    info = {}
    with open(meminfo_path) as f:
        for line in f:
            key, value = line.split(":", 1)
            info[key] = int(value.split()[0])
    return (info["MemTotal"] - info["MemAvailable"]) * 100 / info["MemTotal"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", action="append", help="URL /health (lặp lại được)")
    parser.add_argument("--disk-path", default="/")
    parser.add_argument("--disk-threshold", type=float, default=85.0)
    parser.add_argument("--mem-threshold", type=float, default=90.0)
    args = parser.parse_args(argv)

    problems = []

    for url in args.url or DEFAULT_URLS:
        ok, detail = check_http(url)
        print(f"[{'OK' if ok else 'FAIL'}] {url}: {detail}")
        if not ok:
            problems.append(f"{url} không healthy ({detail})")

    disk = disk_percent(args.disk_path)
    disk_ok = disk < args.disk_threshold
    print(f"[{'OK' if disk_ok else 'FAIL'}] disk {args.disk_path}: "
          f"{disk:.1f}% (ngưỡng {args.disk_threshold}%)")
    if not disk_ok:
        problems.append(f"disk {args.disk_path} {disk:.1f}%")

    mem = mem_percent()
    mem_ok = mem < args.mem_threshold
    print(f"[{'OK' if mem_ok else 'FAIL'}] RAM: {mem:.1f}% (ngưỡng {args.mem_threshold}%)")
    if not mem_ok:
        problems.append(f"RAM {mem:.1f}%")

    if problems:
        print("PROBLEMS: " + "; ".join(problems))
        return 1
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
