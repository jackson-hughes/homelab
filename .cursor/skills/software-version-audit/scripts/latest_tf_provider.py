#!/usr/bin/env python3
"""Print latest stable Terraform provider version (and optional same-major).

Usage:
  latest_tf_provider.py <namespace> <name> [declared_major]

declared_major must come from the declared pin in git
(rg -n '^\\s*version\\s*=' infra/terraform/*/terraform.tf), never from memory.

Examples:
  latest_tf_provider.py hashicorp aws
  latest_tf_provider.py hashicorp aws 5
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request

STABLE = re.compile(r"^\d+\.\d+\.\d+$")


def versions(namespace: str, name: str) -> list[str]:
    url = f"https://registry.terraform.io/v1/providers/{namespace}/{name}/versions"
    with urllib.request.urlopen(url, timeout=30) as resp:
        data = json.load(resp)
    stable = {v["version"] for v in data["versions"] if STABLE.fullmatch(v["version"])}
    return sorted(stable, key=lambda s: tuple(map(int, s.split("."))))


def main() -> int:
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    namespace, name = sys.argv[1], sys.argv[2]
    declared_major = sys.argv[3] if len(sys.argv) == 4 else None
    try:
        stable = versions(namespace, name)
    except Exception as exc:  # noqa: BLE001 — surface as lookup failed for agents
        print(f"lookup failed: {exc}", file=sys.stderr)
        return 1
    if not stable:
        print("lookup failed: no stable versions", file=sys.stderr)
        return 1
    latest = stable[-1]
    if declared_major is None:
        print(latest)
        return 0
    in_major = [v for v in stable if v.split(".", 1)[0] == declared_major]
    same_major = in_major[-1] if in_major else ""
    print(f"latest={latest}")
    print(f"same_major={same_major or 'lookup failed'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
