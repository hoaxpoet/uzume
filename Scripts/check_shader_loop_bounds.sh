#!/usr/bin/env bash
# check_shader_loop_bounds.sh — every shader loop has a compile-time bound (VQ.0, D-264).
#
# A single command buffer that runs for seconds freezes the whole desktop through the shared
# WindowServer, and no governor can interrupt it. So every `for` / `while` in every `.metal` file must
# have a trip count bounded at compile time. A loop passes when, after comments are stripped:
#   - a `for` condition compares against an integer literal, a compile-time constant (declared with
#     `constant` / `constexpr` / `#define` / `const` anywhere in the shader sources), or `min(x, CONST)`; or
#   - the loop carries a `// loop-bound: <bound> — <why>` annotation on its line or the line above
#     (a bound enforced elsewhere, or an unbounded loop listed for VQ.5 in
#     docs/diagnostics/VQ0_SHADER_LOOP_AUDIT.md).
# Anything else fails. A new loop must meet the first rule or be annotated (and audited).
#
# Usage: Scripts/check_shader_loop_bounds.sh [--list]   (--list prints every loop with its verdict)

set -euo pipefail
cd "$(dirname "$0")/.."

python3 -I - "$@" <<'PY'
import re, sys, pathlib

LIST = "--list" in sys.argv[1:]
# Out of VQ.0's scope, listed in the audit for VQ.5: uncertified, owned by its own programme.
EXEMPT = {"UzumeEngine/Sources/Presets/Shaders/Understory.metal": "uncertified; UND.* owns it"}
files = sorted(f for f in pathlib.Path("UzumeEngine/Sources").rglob("*.metal") if str(f) not in EXEMPT)

def strip_comments(text):
    # Block comments → same number of newlines; line comments → removed.
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return [re.sub(r"//.*", "", line) for line in text.split("\n")]

raw = {f: f.read_text().split("\n") for f in files}
code = {f: strip_comments(f.read_text()) for f in files}

const_re = re.compile(
    r"(?:\b(?:constant|constexpr|const|static)\s+)+(?:(?:int|uint|short|ushort|float|half|size_t)\s+)?"
    r"([A-Za-z_]\w*)\s*=|#define\s+([A-Za-z_]\w*)")
constants = set()
local_consts = {}
for f in files:
    for line in code[f]:
        # File-scope declarations, or anything `constant` / `constexpr`; never a function-local
        # `const` initialised from a uniform.
        if not (line[:1].strip() or "constexpr" in line or re.search(r"\bconstant\b", line) or "#define" in line):
            # A function-local `const` counts only when its initialiser is itself constant.
            m = re.search(r"\bconst\s+(?:int|uint|short|ushort)\s+([A-Za-z_]\w*)\s*=\s*([^;]+);", line)
            if m:
                local_consts[m.group(1)] = m.group(2)
            continue
        for decl, define in const_re.findall(line):
            constants.add(decl or define)

INT = r"-?\d+[uU]?"
def is_const(expr):
    expr = expr.strip()
    while expr.startswith("(") and expr.endswith(")") and balanced(expr[1:-1]):
        expr = expr[1:-1].strip()
    if re.fullmatch(INT, expr):
        return True
    if re.fullmatch(r"[A-Za-z_]\w*", expr):
        if expr in constants:
            return True
        init = local_consts.pop(expr, None)        # pop: no recursion through a self-reference
        ok = init is not None and is_const(init)
        if init is not None:
            local_consts[expr] = init
        return ok
    m = re.fullmatch(r"(?:min|metal::min)\s*\((.*)\)", expr)
    if m:
        args = split_args(m.group(1))
        return any(is_const(a) for a in args)
    depth = 0
    for i, ch in enumerate(expr):                       # CONST ± CONST, split at top level
        depth += (ch == "(") - (ch == ")")
        if depth == 0 and ch in "+-*" and i > 0:
            return is_const(expr[:i]) and is_const(expr[i + 1:])
    return False

def balanced(s):
    depth = 0
    for ch in s:
        depth += (ch == "(") - (ch == ")")
        if depth < 0:
            return False
    return depth == 0

def split_args(s):
    depth, cur, out = 0, "", []
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return out

def for_bounded(header):
    parts = split_semis(header)
    if len(parts) < 3:
        return False
    init, cond = parts[0], parts[1]
    m = re.search(r"([A-Za-z_]\w*)\s*=", init)
    var = m.group(1) if m else None
    for conj in re.split(r"&&", cond):
        conj = conj.strip()
        m = re.fullmatch(r"([A-Za-z_]\w*)\s*(<=|<|>=|>)\s*(.+)", conj)
        if m and (var is None or m.group(1) == var) and is_const(m.group(3)):
            # Counting down needs a constant START too.
            if m.group(2) in (">", ">="):
                start = init.split("=", 1)[1] if "=" in init else ""
                if not is_const(start):
                    continue
            return True
    return False

def split_semis(header):
    depth, cur, out = 0, "", []
    for ch in header:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == ";" and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return out

def header_at(lines, i, start):
    text, depth, j, k = "", 0, i, start
    while j < len(lines):
        line = lines[j]
        while k < len(line):
            ch = line[k]
            if ch == "(":
                depth += 1
                if depth == 1:
                    k += 1
                    continue
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return text
            if depth >= 1:
                text += ch
            k += 1
        j += 1
        k = 0
        text += " "
    return text

loop_re = re.compile(r"(?<![A-Za-z_0-9])(for|while)\s*\(")
failures, rows = [], []
for f in files:
    lines = code[f]
    for i, line in enumerate(lines):
        for m in loop_re.finditer(line):
            kind = m.group(1)
            header = header_at(lines, i, m.end() - 1)
            annotated = any("loop-bound:" in raw[f][j] for j in (i, i - 1) if j >= 0)
            bounded = kind == "for" and for_bounded(header)
            verdict = "const" if bounded else ("annotated" if annotated else "UNBOUNDED")
            rel = str(f).replace("UzumeEngine/Sources/", "")
            rows.append(f"{verdict:9}  {rel}:{i + 1}  {kind} ({' '.join(header.split())})")
            if verdict == "UNBOUNDED":
                failures.append(rows[-1])

if LIST:
    print("\n".join(rows))
print(f"check_shader_loop_bounds: {len(rows)} loops, "
      f"{sum(r.startswith('const') for r in rows)} constant-bound, "
      f"{sum(r.startswith('annotated') for r in rows)} annotated, {len(failures)} unbounded")
if failures:
    print("Unbounded loops (bound the trip count at compile time, or annotate `// loop-bound: <bound> — <why>`):")
    print("\n".join(failures))
    sys.exit(1)
PY
