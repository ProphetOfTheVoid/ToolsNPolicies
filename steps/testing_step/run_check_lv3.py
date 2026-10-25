from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

# Possible statuses. Only "code_error", "timeout", "no_output" and "bad_output" go to the supervisor:
# "environment_error" (license, network, Julia missing) is NOT a bug in the generated code.
OK = "ok"
CODE_ERROR = "code_error"
TIMEOUT = "timeout"
NO_OUTPUT = "no_output"
BAD_OUTPUT = "bad_output"
ENVIRONMENT_ERROR = "environment_error"

_ENV_PATTERNS = re.compile(
    r"(Error 100\d\d|no gurobi license|license.*(expired|not found|invalid)|"
    r"GRBloadenv|Gurobi\.jl.*(not installed|not found)|julia: command not found)",
    re.IGNORECASE,
)

MAX_STDERR_CHARS = 3000
MAX_STDOUT_TAIL_CHARS = 1500

# Gurobi startup lines (parameters and license info): useless for the supervisor and they
# contain license details, so they are removed from the stdout that goes into the report.
_STARTUP_NOISE = re.compile(r"^(Set parameter\b|(Academic|Restricted) license\b)", re.IGNORECASE)


def _drop_startup_noise(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not _STARTUP_NOISE.match(line.strip())
    )


@dataclass
class Level3Outcome:
    status: str
    returncode: int | None
    stderr: str
    stdout_tail: str
    duration_s: float
    detail: str = ""

    @property
    def ok(self) -> bool:
        return self.status == OK

    @property
    def is_environment_problem(self) -> bool:
        return self.status == ENVIRONMENT_ERROR

    def format_for_supervisor(self) -> str:
        """Text to pass to the supervisor (same idea as format_for_supervisor in levels 1-2)."""
        if self.ok:
            return "Level 3: execution succeeded, no errors."
        lines = [f"Level 3 (real execution): FAILED, type = {self.status}"]
        if self.detail:
            lines.append(self.detail)
        if self.returncode is not None:
            lines.append(f"Exit code: {self.returncode}")
        lines.append(f"Duration: {self.duration_s:.1f} s")
        if self.stderr.strip():
            lines.append("--- stderr (Julia error) ---")
            lines.append(self.stderr.strip())
        if self.stdout_tail.strip():
            lines.append("--- last lines of stdout ---")
            lines.append(self.stdout_tail.strip())
        return "\n".join(lines)


def _clip_head(text: str, limit: int) -> str:
    # For Julia errors, the message and the first lines of the stack trace are the most useful.
    if len(text) <= limit:
        return text
    return text[:limit] + "\n[... stderr truncated ...]"


def _clip_tail(text: str, limit: int) -> str:
    # For stdout (Gurobi log), the last lines matter.
    if len(text) <= limit:
        return text
    return "[... stdout truncated ...]\n" + text[-limit:]


def run_level3(
    code: str,
    project_root: str | Path = ".",
    expected_output: str | Path = "solution.json",
    timeout_s: int = 600,
    julia_cmd: str = "julia",
) -> Level3Outcome:

    root = Path(project_root).resolve()
    out_path = root / expected_output
    previous = out_path.read_bytes() if out_path.is_file() else None
    try:
        if out_path.is_file():
            out_path.unlink()  # so an old file is not mistaken for a new output
        return _execute(code, root, out_path, expected_output, timeout_s, julia_cmd)
    finally:
        if out_path.is_file():
            out_path.unlink()
        if previous is not None:
            out_path.write_bytes(previous)


def _execute(
    code: str,
    root: Path,
    out_path: Path,
    expected_output: str | Path,
    timeout_s: int,
    julia_cmd: str,
) -> Level3Outcome:
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "generated_code.jl"
        script.write_text(code, encoding="utf-8")

        cmd = [julia_cmd, "--startup-file=no", "--color=no", str(script)]
        start = time.monotonic()
        try:
            proc = subprocess.run(
                cmd,
                cwd=root,
                capture_output=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout_s,
            )
        except FileNotFoundError:
            return Level3Outcome(
                ENVIRONMENT_ERROR, None, "", "", time.monotonic() - start,
                detail=f"Command '{julia_cmd}' not found: Julia is not in the PATH.",
            )
        except subprocess.TimeoutExpired as exc:
            def _txt(x):
                return x.decode("utf-8", "replace") if isinstance(x, bytes) else (x or "")
            return Level3Outcome(
                TIMEOUT, None, _clip_head(_txt(exc.stderr), MAX_STDERR_CHARS),
                _clip_tail(_drop_startup_noise(_txt(exc.stdout)), MAX_STDOUT_TAIL_CHARS),
                time.monotonic() - start,
                detail=f"The code did not finish within {timeout_s} s (possible infinite loop or missing time limit).",
            )

        duration = time.monotonic() - start
        stderr = proc.stderr.replace(str(script), "generated_code.jl")
        stdout_tail = _clip_tail(_drop_startup_noise(proc.stdout), MAX_STDOUT_TAIL_CHARS)

        if proc.returncode != 0:
            status = ENVIRONMENT_ERROR if _ENV_PATTERNS.search(stderr + proc.stdout) else CODE_ERROR
            detail = (
                "Environment problem (license/installation), not a bug in the generated code."
                if status == ENVIRONMENT_ERROR else ""
            )
            return Level3Outcome(
                status, proc.returncode, _clip_head(stderr, MAX_STDERR_CHARS),
                stdout_tail, duration, detail,
            )

        # Exit code 0: check that the output exists and is valid JSON.
        if not out_path.is_file():
            return Level3Outcome(
                NO_OUTPUT, 0, _clip_head(stderr, MAX_STDERR_CHARS), stdout_tail, duration,
                detail=f"The code finished without errors but did not write '{expected_output}'.",
            )
        try:
            json.loads(out_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            return Level3Outcome(
                BAD_OUTPUT, 0, _clip_head(stderr, MAX_STDERR_CHARS), stdout_tail, duration,
                detail=f"'{expected_output}' exists but is not valid JSON: {exc}",
            )

        return Level3Outcome(OK, 0, stderr, stdout_tail, duration)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Level 3: runs a Julia file and reports the outcome.")
    ap.add_argument("file", help="Julia file (.jl) to run")
    ap.add_argument("--root", default=".", help="folder to run Julia from (default: current)")
    ap.add_argument("--output", default="solution.json", help="expected output file")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--julia", default="julia")
    args = ap.parse_args()

    result = run_level3(
        Path(args.file).read_text(encoding="utf-8"),
        project_root=args.root,
        expected_output=args.output,
        timeout_s=args.timeout,
        julia_cmd=args.julia,
    )
    print(f"status = {result.status}")
    print(result.format_for_supervisor())