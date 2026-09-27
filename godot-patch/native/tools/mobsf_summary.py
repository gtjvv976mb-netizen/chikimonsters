#!/usr/bin/env python3
"""Print the findings that matter from a MobSF iOS scan: scorecard, then the binary, Info.plist /
ATS and secrets sections. `python3 mobsf_summary.py scorecard.json report.json`"""
import json
import sys


def main() -> int:
	sc = json.load(open(sys.argv[1]))
	rep = json.load(open(sys.argv[2]))
	print(f"MobSF security score: {sc.get('security_score')}/100  grade {sc.get('grade', '?')}")
	for level in ("high", "warning", "info", "secure", "hotspot"):
		items = sc.get(level) or []
		if items:
			print(f"\n[{level.upper()}] {len(items)}")
			for it in items[:25]:
				print(f"  - {it.get('title')}: {str(it.get('description', ''))[:160]}")
	print("\nApp:", rep.get("app_name"), rep.get("version_name"), rep.get("build"), "size", rep.get("size"))
	print("Min iOS:", rep.get("min_os_version"), " Platform:", rep.get("platform"))
	ats = rep.get("ats_analysis") or {}
	for f in (ats.get("ats_findings") or [])[:10]:
		print(f"ATS {f.get('severity')}: {f.get('issue')}")
	bca = rep.get("binary_analysis") or {}
	findings = bca.get("findings", bca) if isinstance(bca, dict) else {}
	if isinstance(findings, dict):
		for k, v in list(findings.items())[:30]:
			if isinstance(v, dict):
				print(f"BINARY {v.get('severity', '')}: {k} - {str(v.get('detailed_desc', ''))[:140]}")
	for s in (rep.get("secrets") or [])[:15]:
		print("SECRET?", str(s)[:160])
	return 0


if __name__ == "__main__":
	sys.exit(main())
