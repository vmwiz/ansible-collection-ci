#!/usr/bin/env python3
"""Off-GitLab test bench for the component: input rendering, !reference/extends resolution,
rules evaluation (subset of the GitLab expression language) and export of a job.

  render.py TEMPLATE [-i inputs.yml] [--out rendered.yml]           render (for check-jsonschema)
  render.py TEMPLATE -i inputs.yml --jobs CONTEXT                    created jobs (CONTEXT: mr|branch|default|tag)
  render.py TEMPLATE -i inputs.yml --job NAME --context C --emit F   shell script of the job (variables + script)

Deliberately limited emulation (input types/options/regex, whole/partial interpolation,
!reference, extends with deep merge, parallel:matrix, rules if/when). This is NOT GitLab:
the final validation is GitLab's own (CI Lint) - see README.md.
"""
import argparse, copy, json, re, sys
import yaml

INTERP = re.compile(r"\$\[\[\s*inputs\.([A-Za-z0-9_-]+)\s*\]\]")

class Ref(list):
    pass

class Loader(yaml.SafeLoader):
    pass

Loader.add_constructor("!reference", lambda l, n: Ref(l.construct_sequence(n)))

def die(msg):
    sys.exit(f"render.py: {msg}")

def as_string(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return json.dumps(v, ensure_ascii=False)          # Ruby representation of an array of strings
    return str(v)

def check_inputs(spec, given):
    errors, values = [], {}
    for k in given:
        if k not in spec:
            errors.append(f"unknown input '{k}'")
    for k, d in spec.items():
        d = d or {}
        typ = d.get("type", "string")
        if k in given:
            v = given[k]
        elif "default" in d:
            v = d["default"]
        else:
            errors.append(f"required input '{k}' missing"); continue
        ok = {"string": isinstance(v, str), "boolean": isinstance(v, bool), "array": isinstance(v, list),
              "number": isinstance(v, (int, float)) and not isinstance(v, bool)}[typ]
        if not ok:
            errors.append(f"input '{k}': type {typ} expected, got {v!r}")
        if "options" in d and typ != "array" and v not in d["options"]:
            errors.append(f"input '{k}': '{v}' not in options {d['options']}")
        if "regex" in d and isinstance(v, str) and not re.search(d["regex"], v):
            errors.append(f"input '{k}': '{v}' does not match {d['regex']}")
        values[k] = v
    if errors:
        die("invalid inputs:\n  " + "\n  ".join(errors))
    return values

def interpolate(node, values):
    if isinstance(node, Ref):
        return node
    if isinstance(node, dict):
        return {interpolate(k, values): interpolate(v, values) for k, v in node.items()}
    if isinstance(node, list):
        out = []
        for item in node:
            if isinstance(item, str) and INTERP.fullmatch(item.strip()) and isinstance(values[INTERP.fullmatch(item.strip()).group(1)], list):
                out.extend(values[INTERP.fullmatch(item.strip()).group(1)])   # array = whole item: merged
            else:
                out.append(interpolate(item, values))
        return out
    if isinstance(node, str):
        m = INTERP.fullmatch(node.strip())
        if m:
            return copy.deepcopy(values[m.group(1)])
        return INTERP.sub(lambda mm: as_string(values[mm.group(1)]), node)
    return node

def resolve_refs(node, root):
    if isinstance(node, Ref):
        cur = root
        for key in node:
            cur = cur[key]
        return resolve_refs(copy.deepcopy(cur), root)
    if isinstance(node, dict):
        return {k: resolve_refs(v, root) for k, v in node.items()}
    if isinstance(node, list):
        out = []
        for item in node:
            r = resolve_refs(item, root)
            if isinstance(item, Ref) and isinstance(r, list):
                out.extend(r)                 # GitLab flattens nested arrays (rules, script)
            else:
                out.append(r)
        return out
    return node

def render(path, given):
    text = open(path, encoding="utf-8").read()
    docs = list(yaml.load_all(text, Loader=Loader))
    if len(docs) != 2 or "spec" not in docs[0]:
        die("expected a spec header + '---' + body")
    values = check_inputs(docs[0]["spec"]["inputs"], given)
    body = interpolate(docs[1], values)
    leftover = INTERP.findall(yaml.dump(body, Dumper=yaml.SafeDumper) if not _has_ref(body) else str(body))
    if leftover:
        die(f"unresolved interpolations: {leftover}")
    return docs[0], resolve_refs(body, body)

def _has_ref(n):
    if isinstance(n, Ref): return True
    if isinstance(n, dict): return any(_has_ref(v) for v in n.values())
    if isinstance(n, list): return any(_has_ref(v) for v in n)
    return False

# ---- extends + rules --------------------------------------------------------------------------
def deep_merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            out[k] = deep_merge(a[k], v) if k in a else copy.deepcopy(v)
        return out
    return copy.deepcopy(b)

def expand(cfg, name, seen=()):
    job = cfg[name]
    if name in seen: die(f"circular extends {name}")
    parents = job.get("extends", [])
    parents = [parents] if isinstance(parents, str) else parents
    base = {}
    for p in parents:
        if p not in cfg: die(f"{name}: extends '{p}' not found")
        base = deep_merge(base, expand(cfg, p, seen + (name,)))
    merged = deep_merge(base, {k: v for k, v in job.items() if k != "extends"})
    return merged

TOKEN = re.compile(r'\s*(\(|\)|&&|\|\||==|!=|=~|"[^"]*"|\'[^\']*\'|\$[A-Za-z_][A-Za-z0-9_]*|null)')

def evaluate(expr, env):
    toks, pos = [], 0
    while pos < len(expr.rstrip()):
        m = TOKEN.match(expr, pos)
        if not m: die(f"unsupported expression: {expr!r} (position {pos})")
        toks.append(m.group(1)); pos = m.end()
    def val(t):
        if t.startswith("$"): return env.get(t[1:]) or None
        if t == "null": return None
        return t[1:-1]
    def parse_or(i):
        v, i = parse_and(i)
        while i < len(toks) and toks[i] == "||":
            w, i = parse_and(i + 1); v = bool(v) or bool(w)
        return v, i
    def parse_and(i):
        v, i = parse_cmp(i)
        while i < len(toks) and toks[i] == "&&":
            w, i = parse_cmp(i + 1); v = bool(v) and bool(w)
        return v, i
    def parse_cmp(i):
        if toks[i] == "(":
            v, i = parse_or(i + 1); return v, i + 1
        a = val(toks[i]); i += 1
        if i < len(toks) and toks[i] in ("==", "!="):
            b = val(toks[i + 1])
            return ((a or None) == (b or None)) == (toks[i] == "=="), i + 2
        return a, i
    v, i = parse_or(0)
    if i != len(toks): die(f"malformed expression: {expr!r}")
    return bool(v)

def job_when(job, env):
    rules = job.get("rules")
    if rules is None:
        return "on_success"
    for r in rules:
        if "if" not in r or evaluate(r["if"], env):
            return r.get("when", "on_success")
    return "never"

CONTEXTS = {
    "branch":  {"CI_COMMIT_BRANCH": "feature/x", "CI_DEFAULT_BRANCH": "main", "CI_PIPELINE_SOURCE": "push"},
    "default": {"CI_COMMIT_BRANCH": "main", "CI_DEFAULT_BRANCH": "main", "CI_PIPELINE_SOURCE": "push"},
    "mr":      {"CI_MERGE_REQUEST_IID": "42", "CI_MERGE_REQUEST_TARGET_BRANCH_NAME": "main", "CI_DEFAULT_BRANCH": "main",
                "CI_PIPELINE_SOURCE": "merge_request_event"},
    "tag":     {"CI_COMMIT_TAG": "1.0.0", "CI_DEFAULT_BRANCH": "main", "CI_PIPELINE_SOURCE": "push"},
    "schedule": {"CI_COMMIT_BRANCH": "main", "CI_DEFAULT_BRANCH": "main", "CI_PIPELINE_SOURCE": "schedule"},
}
RESERVED = {"default", "include", "stages", "variables", "workflow", "spec", "image", "services", "cache", "before_script", "after_script"}

def jobs(cfg, ctx):
    env = CONTEXTS[ctx]
    out = []
    for name in cfg:
        if name.startswith(".") or name in RESERVED: continue
        job = expand(cfg, name)
        when = job_when(job, env)
        if when == "never": continue
        cells = [{}]
        for m in (job.get("parallel") or {}).get("matrix", []) if isinstance(job.get("parallel"), dict) else []:
            cells = []
            keys = list(m)
            def combos(i, acc):
                if i == len(keys): cells.append(acc); return
                vals = m[keys[i]] if isinstance(m[keys[i]], list) else [m[keys[i]]]
                for v in vals: combos(i + 1, {**acc, keys[i]: v})
            combos(0, {})
        out.append((name, job, when, cells))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("template"); ap.add_argument("-i", "--inputs"); ap.add_argument("--out")
    ap.add_argument("--jobs", choices=CONTEXTS); ap.add_argument("--job"); ap.add_argument("--context", choices=CONTEXTS)
    ap.add_argument("--cell", default="{}"); ap.add_argument("--emit")
    a = ap.parse_args()
    given = yaml.safe_load(open(a.inputs)) if a.inputs else {}
    given = (given or {}).get("inputs", given or {})
    header, body = render(a.template, given)
    if a.out:
        yaml.safe_dump(body, open(a.out, "w"), sort_keys=False, allow_unicode=True, width=200)
        yaml.safe_dump(header, open(a.out.replace(".yml", ".spec.yml"), "w"), sort_keys=False, allow_unicode=True, width=200)
    if a.jobs:
        for name, job, when, cells in jobs(body, a.jobs):
            tags = ",".join(job.get("tags", []))
            af = job.get("allow_failure", False)
            for c in cells:
                label = name + (f" [{', '.join(f'{k}={v}' for k, v in c.items())}]" if c else "")
                print(f"{job.get('stage', 'test'):7} {label:45} tags={tags:16} allow_failure={json.dumps(af)} when={when}")
    if a.job:
        job = expand(body, a.job)
        env = dict(CONTEXTS[a.context or "branch"]); env.update(job.get("variables", {})); env.update(json.loads(a.cell))
        with open(a.emit, "w") as f:
            f.write("set -eo pipefail\n")
            for k, v in env.items():
                # like GitLab: $VARIABLES inside values are expanded at run time
                q = str(v).replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`")
                f.write(f'export {k}="{q}"\n')
            for line in job.get("before_script", []) + job["script"]:
                f.write(line + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
