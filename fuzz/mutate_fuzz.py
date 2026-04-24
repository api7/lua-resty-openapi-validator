#!/usr/bin/env python3
"""
Mutation fuzzer for lua-resty-openapi-validator.

Takes a seed OpenAPI 3.0 spec, applies N random AST-level mutations, then
generates positive request cases against each mutated spec and runs them
through the validator. Reports any crashes (validator threw a Lua error)
and any false negatives (a schema-conforming request was rejected).

Mutations are deliberately biased toward the kinds of "weird but legal"
patterns that real-world specs use and that we've seen trigger validator
bugs:

    1. Append a literal extension to a path-template segment
       (`/users/{id}` -> `/users/{id}.json`)
    2. Add `nullable: true` (and sometimes `null` to enum/const)
    3. Add length keywords (`maxLength`, `minLength`) to non-string types
    4. Switch query param `style` between form/pipeDelimited/
       spaceDelimited and toggle `explode`
    5. Add `required` references to non-existent properties
    6. Swap scalar types (`integer` <-> `string` <-> `number` <-> `boolean`)

Output: writes a JSON-lines crash report to fuzz/out/crashes.jsonl. Exits
non-zero if any crash or false negative was found (so CI can flag).
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import random
import string
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# Mutation primitives ---------------------------------------------------------

LITERAL_EXTS = [".json", ".xml", ".txt", ".v2"]
SCALAR_TYPES = ["string", "integer", "number", "boolean"]
ARRAY_STYLES = ["form", "pipeDelimited", "spaceDelimited"]


def _walk(node: Any, fn, path=()):
    """In-order walk; calls fn(node, path) on every dict and list."""
    if isinstance(node, dict):
        fn(node, path)
        for k, v in list(node.items()):
            _walk(v, fn, path + (k,))
    elif isinstance(node, list):
        fn(node, path)
        for i, v in enumerate(node):
            _walk(v, fn, path + (i,))


def m_path_extension(spec: dict, rng: random.Random) -> bool:
    """Append a literal extension to one path that has a template param."""
    paths = list(spec.get("paths", {}).keys())
    cands = [p for p in paths if "{" in p and not any(p.endswith(e) for e in LITERAL_EXTS)]
    if not cands:
        return False
    p = rng.choice(cands)
    ext = rng.choice(LITERAL_EXTS)
    spec["paths"][p + ext] = spec["paths"].pop(p)
    return True


def m_nullable_enum(spec: dict, rng: random.Random) -> bool:
    """Find a string enum somewhere and add nullable + null entry."""
    found = []

    def visit(node, _path):
        if isinstance(node, dict) and node.get("type") == "string" and isinstance(node.get("enum"), list):
            found.append(node)

    _walk(spec, visit)
    if not found:
        return False
    s = rng.choice(found)
    s["nullable"] = True
    if None not in s["enum"]:
        s["enum"].append(None)
    return True


def m_length_on_array(spec: dict, rng: random.Random) -> bool:
    """Inject maxLength on an array-typed schema (a real-world miscoding)."""
    found = []

    def visit(node, _path):
        if isinstance(node, dict) and node.get("type") == "array":
            found.append(node)

    _walk(spec, visit)
    if not found:
        return False
    s = rng.choice(found)
    s["maxLength"] = rng.randint(1, 100)
    return True


def m_param_style(spec: dict, rng: random.Random) -> bool:
    """Switch a query-array param's style and explode."""
    found = []

    def visit(node, _path):
        if (
            isinstance(node, dict)
            and node.get("in") == "query"
            and isinstance(node.get("schema"), dict)
            and node["schema"].get("type") == "array"
        ):
            found.append(node)

    _walk(spec, visit)
    if not found:
        return False
    p = rng.choice(found)
    p["style"] = rng.choice(ARRAY_STYLES)
    p["explode"] = rng.choice([True, False])
    return True


def m_required_phantom(spec: dict, rng: random.Random) -> bool:
    """Add a non-existent property name to required[]."""
    found = []

    def visit(node, _path):
        if isinstance(node, dict) and isinstance(node.get("properties"), dict):
            found.append(node)

    _walk(spec, visit)
    if not found:
        return False
    s = rng.choice(found)
    s.setdefault("required", []).append("__nonexistent_" + "".join(rng.choices(string.ascii_lowercase, k=4)))
    return True


def m_swap_scalar_type(spec: dict, rng: random.Random) -> bool:
    """Swap a leaf scalar type to another scalar."""
    found = []

    def visit(node, _path):
        if isinstance(node, dict) and node.get("type") in SCALAR_TYPES:
            found.append(node)

    _walk(spec, visit)
    if not found:
        return False
    s = rng.choice(found)
    new_type = rng.choice([t for t in SCALAR_TYPES if t != s["type"]])
    s["type"] = new_type
    # If swapping away from string, drop string-only keywords to keep schema realistic
    if new_type != "string":
        for k in ("minLength", "maxLength", "pattern", "format"):
            s.pop(k, None)
    return True


MUTATORS = [
    ("path_extension", m_path_extension),
    ("nullable_enum", m_nullable_enum),
    ("length_on_array", m_length_on_array),
    ("param_style", m_param_style),
    ("required_phantom", m_required_phantom),
    ("swap_scalar_type", m_swap_scalar_type),
]


def mutate(spec: dict, n: int, rng: random.Random) -> list[str]:
    """Apply up to n mutations; return list of applied mutator names."""
    applied = []
    for _ in range(n):
        name, fn = rng.choice(MUTATORS)
        if fn(spec, rng):
            applied.append(name)
    return applied


# $ref resolution ---------------------------------------------------------------

def resolve_refs(spec: dict) -> dict:
    """Recursively resolve all $ref pointers in the spec (in-place)."""
    def _resolve(node, root):
        if isinstance(node, dict):
            if "$ref" in node and isinstance(node["$ref"], str):
                ref = node["$ref"]
                if ref.startswith("#/"):
                    parts = ref[2:].split("/")
                    target = root
                    for p in parts:
                        p = p.replace("~1", "/").replace("~0", "~")
                        if isinstance(target, dict):
                            target = target.get(p)
                        else:
                            return node
                    if isinstance(target, dict):
                        resolved = copy.deepcopy(target)
                        return _resolve(resolved, root)
                return node
            return {k: _resolve(v, root) for k, v in node.items()}
        if isinstance(node, list):
            return [_resolve(item, root) for item in node]
        return node
    return _resolve(spec, spec)


# Case generation -------------------------------------------------------------

def _sample_string(rng: random.Random, schema: dict) -> str:
    fmt = schema.get("format")
    if fmt == "uuid":
        return "00000000-0000-4000-8000-000000000000"
    if fmt == "date":
        return "2024-01-01"
    if fmt == "date-time":
        return "2024-01-01T00:00:00Z"
    if fmt == "email":
        return "x@y.z"
    enum = schema.get("enum")
    if isinstance(enum, list) and enum:
        v = rng.choice(enum)
        if v is not None:
            return v
    minl = schema.get("minLength", 1)
    maxl = schema.get("maxLength", max(minl, 8))
    n = rng.randint(minl, max(minl, min(maxl, 16)))
    return "x" * n


def sample_value(schema: dict, rng: random.Random, depth: int = 0):
    """Generate a value that should validate against `schema`. Best-effort."""
    if not isinstance(schema, dict):
        return None
    if depth > 4:
        return None
    if schema.get("nullable") and rng.random() < 0.2:
        return None
    # Handle const/enum generically before type-specific branches
    if "const" in schema:
        return schema["const"]
    enum = schema.get("enum")
    if isinstance(enum, list) and enum:
        return rng.choice(enum)
    t = schema.get("type")
    if isinstance(t, list):
        t = rng.choice([x for x in t if x != "null"] or t)
    if t == "string":
        return _sample_string(rng, schema)
    if t == "integer":
        lo = schema.get("minimum", 0)
        hi = schema.get("maximum", lo + 100)
        try:
            lo, hi = int(lo), int(hi)
        except (TypeError, ValueError):
            lo, hi = 0, 100
        if lo > hi:
            lo, hi = hi, lo
        return rng.randint(lo, hi)
    if t == "number":
        return float(rng.randint(0, 100))
    if t == "boolean":
        return rng.choice([True, False])
    if t == "array":
        items = schema.get("items", {})
        n = rng.randint(schema.get("minItems", 0), max(schema.get("minItems", 0), schema.get("maxItems", 3)))
        return [sample_value(items, rng, depth + 1) for _ in range(n)]
    if t == "object" or "properties" in schema:
        props = schema.get("properties", {})
        required = set(schema.get("required", []))
        out = {}
        for name, sub in props.items():
            if name in required or rng.random() < 0.4:
                out[name] = sample_value(sub, rng, depth + 1)
        return out
    return None


def gen_cases(spec: dict, rng: random.Random, max_per_op: int = 2) -> list[dict]:
    """Generate a small set of positive requests per op (oracle: must accept)."""
    cases = []
    for path, item in spec.get("paths", {}).items():
        if not isinstance(item, dict):
            continue
        op_count = 0
        for method, op in item.items():
            if method not in ("get", "post", "put", "delete", "patch", "head", "options"):
                continue
            if not isinstance(op, dict):
                continue
            if op_count >= max_per_op:
                break
            op_count += 1

            # Concrete path: substitute each {token} with a small value matching
            # any declared path-parameter schema.
            path_params = {p["name"]: p for p in (op.get("parameters") or [])
                           if isinstance(p, dict) and p.get("in") == "path"}
            concrete = path
            for token in (s.split("}", 1)[0] for s in path.split("{")[1:]):
                pp = path_params.get(token, {})
                schema = pp.get("schema") or {"type": "string"}
                v = sample_value(schema, rng)
                if v is None:
                    v = "abc"
                concrete = concrete.replace("{" + token + "}", str(v))

            req = {
                "method": method.upper(),
                "path": concrete,
                "query": {},
                "headers": {},
            }

            # Required query/header params: fill with conforming values
            for p in op.get("parameters") or []:
                if not isinstance(p, dict):
                    continue
                if not p.get("required"):
                    continue
                schema = p.get("schema") or {"type": "string"}
                val = sample_value(schema, rng)
                if val is None:
                    val = "x"
                if p.get("in") == "query":
                    if isinstance(val, list) and p.get("explode", True):
                        req["query"][p["name"]] = val
                    elif isinstance(val, list):
                        style = p.get("style", "form")
                        delim = {
                            "pipeDelimited": "|",
                            "spaceDelimited": " ",
                        }.get(style, ",")
                        req["query"][p["name"]] = delim.join(map(str, val))
                    else:
                        req["query"][p["name"]] = val
                elif p.get("in") == "header":
                    req["headers"][p["name"]] = str(val)

            # Body: generate matching JSON for application/json
            rb = op.get("requestBody")
            if isinstance(rb, dict):
                content = rb.get("content", {})
                if "application/json" in content:
                    schema = content["application/json"].get("schema") or {}
                    val = sample_value(schema, rng)
                    req["content_type"] = "application/json"
                    req["body"] = json.dumps(val if val is not None else {})

            cases.append({"label": "positive", "op": f"{method.upper()} {path}", "req": req})
    return cases


# Validator subprocess --------------------------------------------------------

RUNNER_LUA = r"""
-- Read JSON spec + JSONL cases on stdin: line 1 = spec, then one case per line.
local cjson = require("cjson.safe")
local ov    = require("resty.openapi_validator")

local function readline()
    return io.read("*l")
end

local spec_str = readline()
if not spec_str then return end
local v, cerr = ov.compile(spec_str)
if not v then
    io.write(cjson.encode({phase="compile", error=tostring(cerr)}), "\n")
    return
end

while true do
    local line = readline()
    if not line then break end
    local case = cjson.decode(line)
    if not case then break end
    local req = case.req
    local pcall_ok, ok, err = pcall(v.validate_request, v, req)
    if not pcall_ok then
        io.write(cjson.encode({phase="crash", op=case.op, label=case.label,
                                err=tostring(ok), req=req}), "\n")
    else
        io.write(cjson.encode({phase="ok", op=case.op, label=case.label,
                                accepted=(ok==true), err=err and tostring(err) or nil}), "\n")
    end
end
"""


def run_validator(spec: dict, cases: list[dict], deps: str, lib: str,
                  extra_includes: list[str] = None, timeout: float = 30.0):
    payload = json.dumps(spec) + "\n" + "\n".join(json.dumps(c) for c in cases) + "\n"
    cmd = ["resty", "--shdict", "test 1m", "-I", lib]
    for inc in (extra_includes or []):
        cmd += ["-I", inc]
    if deps:
        cmd += ["-I", deps + "/share/lua/5.1"]
    cmd += ["-e", RUNNER_LUA]
    env = os.environ.copy()
    if deps:
        env["LUA_CPATH"] = f"{deps}/lib/lua/5.1/?.so;;"
    try:
        r = subprocess.run(cmd, input=payload, capture_output=True, text=True,
                           timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return [{"phase": "timeout", "stderr": "validator subprocess timed out"}]
    out = []
    for line in r.stdout.splitlines():
        try:
            out.append(json.loads(line))
        except Exception:
            pass
    if r.returncode != 0 and not out:
        out.append({"phase": "subprocess_error", "rc": r.returncode,
                    "stderr": r.stderr[-2000:]})
    return out


# Driver ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default=str(HERE / "seeds"),
                    help="directory of seed JSON specs")
    ap.add_argument("--out", default=str(HERE / "out"),
                    help="output directory")
    ap.add_argument("--budget", type=float, default=60.0,
                    help="wall-clock seconds for the fuzz session")
    ap.add_argument("--mutations", type=int, default=4,
                    help="mutations to apply per round")
    ap.add_argument("--seed", type=int, default=None,
                    help="RNG seed (for reproducibility)")
    ap.add_argument("--deps", default=os.environ.get("GATEWAY_DEPS", ""),
                    help="optional: gateway-style deps directory (used to "
                         "locate jsonschema/cjson when not on the system "
                         "package path)")
    ap.add_argument("--lib", default=str(ROOT / "lib"),
                    help="validator library path")
    ap.add_argument("-I", "--include", action="append", default=[],
                    help="extra Lua include path (passed to resty -I)")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    crashes_path = out / "crashes.jsonl"
    summary_path = out / "summary.json"

    rng = random.Random(args.seed)
    seeds = sorted(Path(args.seeds).glob("*.json"))
    if not seeds:
        print(f"no seeds found in {args.seeds}", file=sys.stderr)
        sys.exit(2)

    crashes = []
    false_negatives = []
    rounds = 0
    cases_run = 0
    t0 = time.time()

    try:
        with crashes_path.open("w") as crashf:
            while time.time() - t0 < args.budget:
                seed_path = rng.choice(seeds)
                spec = json.loads(seed_path.read_text())
                spec.pop("servers", None)
                applied = mutate(spec, args.mutations, rng)
                resolved = resolve_refs(spec)
                cases = gen_cases(resolved, rng, max_per_op=2)
                if not cases:
                    continue
                results = run_validator(spec, cases, args.deps, args.lib, args.include)
                cases_run += len(cases)
                rounds += 1
                for r in results:
                    phase = r.get("phase")
                    if phase in ("crash", "subprocess_error", "timeout"):
                        rec = {"kind": "crash", "seed": seed_path.name, "applied": applied,
                               "result": r}
                        crashes.append(rec)
                        crashf.write(json.dumps(rec) + "\n")
                        crashf.flush()
                        print(f"CRASH on {seed_path.name} after {applied}: "
                              f"{str(r.get('err') or r.get('stderr'))[:200]}",
                              file=sys.stderr)
                    elif phase == "ok" and r.get("label") == "positive" and not r.get("accepted"):
                        err = (r.get("err") or "").lower()
                        noisy = any(s in err for s in (
                            "matches none of the required",
                            "match only one schema",
                            "discriminator",
                            "failed to match pattern",
                            "string too short, expected at least",
                            "string too long",
                            "expected at most",
                            "expected at least",
                            "additionalproperties",
                            "minimum",
                            "maximum",
                            "uniqueitems",
                            "format",
                            "got userdata",
                            "expected integer, got",
                            "expected number, got",
                            "expected boolean, got",
                            "is required",
                            "failed to validate item",
                        ))
                        if noisy:
                            continue
                        rec = {"kind": "false_negative", "seed": seed_path.name,
                               "applied": applied, "result": r}
                        false_negatives.append(rec)
                        crashf.write(json.dumps(rec) + "\n")
                        crashf.flush()
                        print(f"FALSE_NEGATIVE on {seed_path.name} after {applied}: "
                              f"op={r.get('op')} err={(r.get('err') or '')[:200]}",
                              file=sys.stderr)
    finally:
        summary = {
            "rounds": rounds,
            "cases_run": cases_run,
            "elapsed_s": round(time.time() - t0, 2),
            "crash_count": len(crashes),
            "false_negative_count": len(false_negatives),
            "total_findings": len(crashes) + len(false_negatives),
            "crashes_path": str(crashes_path),
        }
        summary_path.write_text(json.dumps(summary, indent=2))
        print(json.dumps(summary, indent=2))
    sys.exit(1 if (crashes or false_negatives) else 0)


if __name__ == "__main__":
    main()
