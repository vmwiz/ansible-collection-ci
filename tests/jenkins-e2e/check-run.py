#!/usr/bin/env python3
"""TEST ONLY: checks one bench build. 1) stage order from wfapi/describe (pipeline-stage-view): every
executed stage of a block ends before any stage of the next block starts; 2) the tarball sha256 logged
by aci build / importer / certification / publish, the archived artifact and the fake Galaxy upload are
all the same. Usage: check-run.py <build-url> <console.log> [galaxy-upload-dir]"""
import hashlib, json, os, re, sys, urllib.request

url, log = sys.argv[1].rstrip("/"), sys.argv[2]
upload = sys.argv[3] if len(sys.argv) > 3 else ""
BLOCKS = [("static analysis", {"Lint", "Docs", "Changelog fragment", "Security scan", "Spotter"}),
          ("ansible-test", None), ("container tests", {"Integration", "Molecule"}),
          ("package & certify", {"Package & certify"}), ("publish", {"Publish"})]
ok = True


def block(name):
    for i, (_, names) in enumerate(BLOCKS):
        if names is None and (name.startswith("Matrix") or name in ("sanity", "units")):
            return i
        if names and name in names:
            return i
    return None


stages = json.load(urllib.request.urlopen(url + "/wfapi/describe"))["stages"]
spans = {}
for s in stages:
    b = block(s["name"])
    if b is None or s["status"] == "NOT_EXECUTED":
        continue
    lo, hi = spans.get(b, (1e20, 0))
    spans[b] = (min(lo, s["startTimeMillis"]), max(hi, s["startTimeMillis"] + s["durationMillis"]))
print("stages: " + " > ".join(f"{s['name']}[{s['status']}]" for s in stages))
order = sorted(spans)
for a, b in zip(order, order[1:]):
    if spans[a][1] > spans[b][0]:
        ok = False
        print(f"KO order: {BLOCKS[a][0]} ends after {BLOCKS[b][0]} starts")
print("blocks executed in order: " + " > ".join(BLOCKS[b][0] for b in order) + ("" if ok else "  (KO)"))

text = open(log, encoding="utf-8", errors="replace").read()
logged = re.findall(r"tarball (\S+\.tar\.gz) sha256 ([0-9a-f]{64})", text)
cmds = re.findall(r"aci \d+\.\d+\.\d+: (build|importer|certification|publish)", text)
shas = {s for _, s in logged}
if logged:
    name = logged[0][0]
    art = hashlib.sha256(urllib.request.urlopen(f"{url}/artifact/dist/{name}").read()).hexdigest()
    shas.add(art)
    line = f"tarball {name}: {len(logged)} aci steps ({', '.join(c for c in cmds if c in ('build', 'importer', 'certification', 'publish'))}) + archived artifact"
    if upload:
        up = os.path.join(upload, name)
        if os.path.exists(up):
            shas.add(hashlib.sha256(open(up, "rb").read()).hexdigest())
            line += " + fake Galaxy upload"
        else:
            ok = False
            line += " + fake Galaxy upload MISSING"
    print(f"{line}: {'same sha256 ' + art if len(shas) == 1 else 'KO different: ' + str(shas)}")
    ok = ok and len(shas) == 1
sys.exit(0 if ok else 1)
