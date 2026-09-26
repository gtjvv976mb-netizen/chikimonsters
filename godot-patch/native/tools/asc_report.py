#!/usr/bin/env python3
"""App Store Connect report: what real iPhones say about the app.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=AuthKey.p8 python3 asc_report.py [bundle id]

Prints, for the app's recent builds: processing state and TestFlight expiry, TestFlight crash
reports testers sent (with the crash log's top frames), screenshot feedback and comments, and
Apple's power & performance metrics (launch time, hangs, memory, disk writes, battery) where
enough devices have reported. Needs PyJWT and cryptography. Read-only: it changes nothing.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"


def token() -> str:
	key = open(os.environ["ASC_KEY_PATH"]).read()
	now = int(time.time())
	return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100,
		"aud": "appstoreconnect-v1"}, key, algorithm="ES256",
		headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOKEN = None


def get(path: str, accept: str = "application/json"):
	req = urllib.request.Request(path if path.startswith("http") else API + path,
		headers={"Authorization": f"Bearer {TOKEN}", "Accept": accept})
	try:
		with urllib.request.urlopen(req, timeout=60) as r:
			body = r.read()
			return json.loads(body) if body else {}
	except urllib.error.HTTPError as e:
		return {"_error": e.code, "_body": e.read().decode(errors="replace")[:300]}


def section(t: str) -> None:
	print(f"\n=== {t}")


def main() -> int:
	global TOKEN
	TOKEN = token()
	bundle = sys.argv[1] if len(sys.argv) > 1 else "com.chikimonsters.Chikoria"
	apps = get(f"/v1/apps?filter[bundleId]={bundle}")
	if not apps.get("data"):
		print("app not found:", apps)
		return 1
	app = apps["data"][0]
	aid = app["id"]
	print(f"app {app['attributes'].get('name')} ({bundle}) id {aid}")

	section("Builds (newest 8)")
	builds = get(f"/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=8"
		"&fields[builds]=version,uploadedDate,processingState,expired,expirationDate,minOsVersion")
	for b in builds.get("data", []):
		a = b["attributes"]
		print(f"  build {a.get('version'):>5}  {a.get('processingState'):<11} uploaded {a.get('uploadedDate', '')[:16]}"
			f"  expires {str(a.get('expirationDate', ''))[:10]}  expired={a.get('expired')}")

	section("TestFlight crash reports from testers")
	crashes = get(f"/v1/apps/{aid}/betaFeedbackCrashSubmissions?limit=20")
	if "_error" in crashes:
		print("  (not available:", crashes["_error"], crashes["_body"][:160], ")")
	for c in crashes.get("data", []):
		a = c["attributes"]
		print(f"  {a.get('createdDate', '')[:16]}  build {a.get('buildBundleId', '')} {a.get('appPlatform', '')}"
			f"  {a.get('deviceModel', '')} iOS {a.get('osVersion', '')}  battery {a.get('batteryPercentage')}%"
			f"  comment: {a.get('comment')!r}")
		log = get(f"/v1/betaFeedbackCrashSubmissions/{c['id']}/crashLog")
		text = (log.get("data") or {}).get("attributes", {}).get("logText", "")
		if text:
			lines = text.splitlines()
			keep = [l for l in lines if l.startswith(("Exception Type", "Exception Codes", "Termination Reason", "Crashed Thread"))]
			i = next((k for k, l in enumerate(lines) if "Crashed:" in l), None)
			if i is not None:
				keep += lines[i:i + 12]
			print("    " + "\n    ".join(keep[:18]))
	if not crashes.get("data"):
		print("  none")

	section("TestFlight screenshot feedback")
	shots = get(f"/v1/apps/{aid}/betaFeedbackScreenshotSubmissions?limit=20")
	if "_error" in shots:
		print("  (not available:", shots["_error"], shots["_body"][:160], ")")
	for s in shots.get("data", []):
		a = s["attributes"]
		print(f"  {a.get('createdDate', '')[:16]}  {a.get('deviceModel', '')} iOS {a.get('osVersion', '')}  comment: {a.get('comment')!r}")
		for sc in a.get("screenshots", []) or []:
			print(f"    screenshot {sc.get('width')}x{sc.get('height')}: {sc.get('url', '')[:120]}")
	if not shots.get("data"):
		print("  none")

	section("Power & performance metrics (Xcode Organizer data)")
	for b in builds.get("data", [])[:3]:
		m = get(f"/v1/builds/{b['id']}/perfPowerMetrics", "application/vnd.apple.xcode-metrics+json")
		v = b["attributes"].get("version")
		if "_error" in m:
			print(f"  build {v}: not available ({m['_error']})")
			continue
		cats = m.get("productData", [])
		if not cats:
			print(f"  build {v}: no data yet (needs enough devices to report)")
		for pd in cats:
			for cat in pd.get("metricCategories", []):
				for met in cat.get("metrics", []):
					for ds in met.get("datasets", [])[:1]:
						pts = ds.get("points", [])
						if pts:
							p = pts[-1]
							print(f"  build {v}: {cat.get('identifier')}/{met.get('identifier')} = {p.get('value')} {met.get('unit', {}).get('displayName', '')}")
		sig = get(f"/v1/builds/{b['id']}/diagnosticSignatures?limit=10")
		for d in sig.get("data", []):
			a = d["attributes"]
			print(f"  build {v}: diagnostic {a.get('diagnosticType')} weight {a.get('weight')}: {a.get('signature', '')[:140]}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
