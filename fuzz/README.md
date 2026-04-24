# Mutation Fuzzer for `lua-resty-openapi-validator`

A small mutation fuzzer that runs the validator against AST-mutated copies of
real-world OpenAPI specs and checks two oracles:

1. **No crashes**: `validate_request` must not throw a Lua error
   (caught with `pcall`).
2. **Schema conformance**: a request **generated to satisfy** an operation's
   schema must be **accepted** by the validator. A rejection is a candidate
   false-negative bug.

The fuzzer is the productionised form of the harness used during v1.0.3 QA.
It reproduces the bugs that QA found (path-extension Bug 1 against the
unfixed validator, `utf8_len(table)` Bug 3 against the unfixed jsonschema).

## Architecture

```text
mutate_fuzz.py (Python orchestrator)
   ├─ pick a seed spec from fuzz/seeds/
   ├─ apply N random mutations (mutators below)
   ├─ generate schema-conforming positive requests
   └─ resty -e RUNNER_LUA  (validator subprocess, one per round)
        └─ for each case: pcall(v:validate_request, req)
              └─ JSONL result on stdout: {phase, accepted, err}
```

Mutators (`fuzz/mutate_fuzz.py`):

| name | what it does | targets |
|---|---|---|
| `path_extension` | append `.json` / `.xml` / `.txt` / `.v2` to a random path | path-routing edge cases (Bug 1) |
| `nullable_enum` | inject `null` into an enum + flip `nullable: true` | nullable-enum handling (Bug 2) |
| `length_on_array` | move `maxLength` onto an `array` schema | type-inappropriate keywords (Bug 3) |
| `param_style` | flip parameter `style`/`explode` | parameter parsing (Bug 4 family) |
| `required_phantom` | add a non-existent property name to `required` | schema-validation edge cases |
| `swap_scalar_type` | swap `type: integer` ↔ `type: string` | coercion paths |

Generator (`sample_value`): produces JSON values that match a JSON Schema
fragment (string / integer / number / boolean / array / object / enum), with
a depth limit. Path/query/header parameters that are `required: true` are
filled in; the request body is sampled from the operation's
`requestBody` schema if present.

## Run locally

```bash
make fuzz                       # 60s budget
make fuzz FUZZ_BUDGET=300       # 5 min
python3 fuzz/mutate_fuzz.py --budget 60 --seed 7   # reproducible
```

Output:

- `fuzz/out/crashes.jsonl` — one JSON object per finding
- `fuzz/out/summary.json` — `{rounds, cases_run, elapsed_s, crash_count, false_negative_count, total_findings}`
- exits non-zero on any crash or candidate false-negative (CI-friendly)

## Add a seed

Drop any OpenAPI 3.x spec into `fuzz/seeds/`. Smaller specs (50–100 ops)
give more mutation rounds per second; very large specs (>500 ops) slow
each round. Recommended size: 30 KB – 300 KB.

## Add a mutator

1. Add `def my_mutator(spec, rng): ...` near the other mutators.
2. Append `("name", my_mutator)` to the `MUTATORS` list.
3. Mutator must mutate `spec` **in place** and return `True` if a mutation
   was applied, `False` otherwise. The label is taken from the tuple name.

## Noise filter

`gen_cases` does not try to satisfy every JSON Schema construct — `oneOf` /
`allOf` / `discriminator` / complex `pattern` are common in real specs but
hard to satisfy generically. Errors mentioning these are filtered as
generator artefacts, not validator bugs. The list lives near the bottom
of `mutate_fuzz.py`. If the filter masks a real bug you find by other
means, narrow / shrink it; if it lets through too much noise, widen it.

## CI

- **PR**: `.github/workflows/fuzz.yml` — 120s budget, fails the PR on any finding.
- **Nightly**: `.github/workflows/fuzz-nightly.yml` — 600s budget, on
  failure uploads `fuzz/out/` as an artifact and opens (or comments on)
  a `fuzz-nightly` issue assigned to `@jarvis9443`.
