"""
Python wrapper around check_syntax.jl.

Runs the parse+lowering check on a Julia code file as a subprocess, and
returns a structured result ready to hand to the supervisor LLM.

Requires only a working `julia` binary on PATH — no JuMP, no Gurobi, no
tool implementations, no instance file.
"""

import subprocess
from dataclasses import dataclass
from typing import List


@dataclass
class CodeError:
    line: int
    stage: str  # "parse" | "lowering"
    statement: str
    message: str


@dataclass
class SyntaxCheckResult:
    ok: bool
    errors: List[CodeError]
    raw_stdout: str
    raw_stderr: str

    def format_for_supervisor(self) -> str:
        """
        Render the errors as plain text, ready to paste into the
        supervisor prompt alongside the code.
        """
        if self.ok:
            return "No parsing/lowering errors found."

        lines = [f"{len(self.errors)} error(s) found:"]
        for i, err in enumerate(self.errors, start=1):
            location = f"line {err.line}" if err.line >= 0 else "location unknown"
            lines.append(f"\n[{i}] {location} ({err.stage})")
            if err.statement:
                lines.append(f"    Statement: {err.statement}")
            lines.append(f"    Error: {err.message}")
        return "\n".join(lines)


def _checker_failure(reason: str, raw_stdout: str = "", raw_stderr: str = "") -> SyntaxCheckResult:
    return SyntaxCheckResult(
        ok=False,
        errors=[CodeError(line=-1, stage="checker_failure", statement="", message=reason)],
        raw_stdout=raw_stdout,
        raw_stderr=raw_stderr,
    )


def check_julia_syntax(
    code_path: str,
    julia_bin: str = "julia",
    checker_script: str = "check_syntax.jl",
    timeout: float = 30.0,
) -> SyntaxCheckResult:
    try:
        proc = subprocess.run(
            [julia_bin, checker_script, code_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        return _checker_failure(
            f"Julia checker process timed out after {timeout}s.",
            raw_stdout=e.stdout or "",
            raw_stderr=e.stderr or "",
        )
    except FileNotFoundError:
        return _checker_failure(f"Could not find the `{julia_bin}` executable on PATH.")

    stdout = proc.stdout

    if proc.returncode != 0 and "ok=" not in stdout:
        return _checker_failure(
            f"check_syntax.jl exited with code {proc.returncode} and produced no result.",
            raw_stdout=stdout,
            raw_stderr=proc.stderr,
        )

    lines = stdout.splitlines()

    ok = None
    errors: List[CodeError] = []

    i = 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("ok="):
            ok = line[len("ok="):].strip() == "true"
        elif line == "error_begin":
            err_line = -1
            err_stage = ""
            err_statement = ""
            err_message_lines: List[str] = []
            i += 1
            while i < len(lines) and lines[i] != "error_end":
                l = lines[i]
                if l.startswith("line="):
                    err_line = int(l[len("line="):].strip())
                elif l.startswith("stage="):
                    err_stage = l[len("stage="):].strip()
                elif l.startswith("statement="):
                    err_statement = l[len("statement="):]
                elif l == "message_start":
                    i += 1
                    while i < len(lines) and lines[i] != "message_end":
                        err_message_lines.append(lines[i])
                        i += 1
                i += 1
            errors.append(CodeError(
                line=err_line,
                stage=err_stage,
                statement=err_statement,
                message="\n".join(err_message_lines),
            ))
        i += 1

    if ok is None:
        return _checker_failure(
            "Unexpected output format from check_syntax.jl.",
            raw_stdout=stdout,
            raw_stderr=proc.stderr,
        )

    return SyntaxCheckResult(ok=ok, errors=errors, raw_stdout=stdout, raw_stderr=proc.stderr)


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("Usage: python run_syntax_check.py <path_to_julia_code.jl>")
        sys.exit(1)

    result = check_julia_syntax(sys.argv[1])
    print(f"ok: {result.ok}")
    print(result.format_for_supervisor())