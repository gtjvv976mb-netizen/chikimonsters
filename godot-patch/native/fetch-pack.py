#!/usr/bin/env python3
"""Download a published pack from chikimonsters.com and reassemble it.

    python3 fetch-pack.py index.pck.ios.lite out.zip

Reads <name>.manifest.json from https://chikimonsters.com/realm/, downloads every chunk, and checks
the SHA-256 the manifest records — a truncated or stale chunk fails here, not on a phone.
"""
import hashlib
import json
import sys
import time
import urllib.request

BASE = "https://chikimonsters.com/realm/"


def get(url: str, tries: int = 4) -> bytes:
	for i in range(tries):
		try:
			req = urllib.request.Request(url, headers={"User-Agent": "chiki-native-ci/1"})
			with urllib.request.urlopen(req, timeout=120) as r:
				return r.read()
		except Exception as e:  # noqa: BLE001 — retried, then raised
			if i == tries - 1:
				raise
			print(f"  retry {url}: {e}")
			time.sleep(3 * (i + 1))
	raise RuntimeError("unreachable")


def main() -> int:
	name, out = sys.argv[1], sys.argv[2]
	man = json.loads(get(f"{BASE}{name}.manifest.json?t={int(time.time())}"))
	v = man.get("v", "")
	h = hashlib.sha256()
	total = 0
	with open(out, "wb") as f:
		for c in man["chunks"]:
			data = get(f"{BASE}{c}?v={v}")
			f.write(data)
			h.update(data)
			total += len(data)
			print(f"  {c}  {len(data):,}")
	if total != man["total"]:
		raise SystemExit(f"size {total} != manifest {man['total']}")
	if man.get("sha256") and h.hexdigest() != man["sha256"]:
		raise SystemExit("sha256 mismatch")
	print(f"{out}: {total:,} bytes, sha256 ok, build {v}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
