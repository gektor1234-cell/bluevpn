#!/usr/bin/env python3
"""Fail when Git-visible files contain likely production credentials.

Findings contain only a rule name and file/line coordinate. Matched values are
deliberately never printed, so CI logs cannot become another secret store.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[str]


EXPLICIT_RULES = (
    Rule("private-key-header", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----")),
    Rule("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    Rule("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    Rule("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    Rule("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    Rule("stripe-live-key", re.compile(r"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b")),
    Rule("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    Rule("telegram-bot-token", re.compile(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b")),
    Rule("pypi-token", re.compile(r"\bpypi-[A-Za-z0-9_-]{30,}\b")),
    Rule("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")),
    Rule(
        "wireguard-private-key",
        re.compile(r"(?im)^\s*PrivateKey\s*=\s*[A-Za-z0-9+/]{43}=\s*$"),
    ),
    Rule(
        "credential-in-url",
        re.compile(r"\b(?:https?|postgres(?:ql)?|mysql|redis)://[^\s/:@]+:[^\s/@]+@"),
    ),
)

SENSITIVE_NAME = (
    r"(?:api[_-]?key|secret(?:[_-]?key)?|access[_-]?token|refresh[_-]?token|"
    r"auth[_-]?token|admin[_-]?token|password|passwd|client[_-]?secret|"
    r"smtp[_-]?password|private[_-]?key)"
)
QUOTED_ASSIGNMENT = re.compile(
    rf"(?i)\b{SENSITIVE_NAME}\b\s*(?:=|:)\s*(['\"])([^'\"\r\n]{{8,}})\1"
)
ENV_ASSIGNMENT = re.compile(r"(?m)^\s*([A-Z][A-Z0-9_]{2,})\s*=\s*([^\s#]{8,})\s*$")

SAFE_VALUE_MARKERS = (
    "example",
    "placeholder",
    "replace_me",
    "replace-me",
    "changeme",
    "change_me",
    "dummy",
    "fake",
    "redacted",
    "test-only",
    "test_only",
    "not-a-real",
    "not_real",
    "your_",
    "your-",
    "<",
    ">",
    "${",
    "{{",
    "}}",
)

FORBIDDEN_TRACKED_SUFFIXES = (
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".pem",
    ".key",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--include-untracked",
        action="store_true",
        help="also scan untracked files that are not excluded by .gitignore",
    )
    parser.add_argument(
        "--history",
        action="store_true",
        help="also scan added/removed lines across every local branch and tag",
    )
    parser.add_argument(
        "--max-file-bytes",
        type=int,
        default=4 * 1024 * 1024,
        help="maximum text file size to inspect (default: 4 MiB)",
    )
    return parser.parse_args()


def repository_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return Path(result.stdout.decode("utf-8").strip()).resolve()


def git_visible_files(root: Path, include_untracked: bool) -> list[Path]:
    command = ["git", "ls-files", "-z", "--cached"]
    if include_untracked:
        command.extend(("--others", "--exclude-standard"))
    result = subprocess.run(command, cwd=root, check=True, stdout=subprocess.PIPE)
    files: list[Path] = []
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = Path(raw_path.decode("utf-8", errors="strict"))
        absolute = (root / relative).resolve()
        try:
            absolute.relative_to(root)
        except ValueError as exc:
            raise RuntimeError(f"Git path escapes repository: {relative}") from exc
        if absolute.is_file():
            files.append(absolute)
    return sorted(set(files))


def is_forbidden_credential_file(relative: Path) -> bool:
    lowered = relative.name.lower()
    if lowered == ".env":
        return True
    if lowered.endswith(".env") and not lowered.endswith((".example.env", ".sample.env", ".template.env")):
        return True
    if lowered.endswith(FORBIDDEN_TRACKED_SUFFIXES) and not lowered.endswith(".pub"):
        return True
    return False


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def value_looks_safe(value: str) -> bool:
    normalized = value.strip().strip("'\"").lower()
    if not normalized or normalized in {"none", "null", "true", "false"}:
        return True
    if normalized.startswith(("$", "${", "$(", "{{")):
        return True
    if normalized.startswith("/"):
        return True
    if "(" in normalized and normalized.endswith(")"):
        return True
    if re.fullmatch(r"(?:demo|mock|dev|test|sample)[_-]?(?:token|password|secret|key)\d*", normalized):
        return True
    return any(marker in normalized for marker in SAFE_VALUE_MARKERS)


def env_name_is_sensitive(name: str) -> bool:
    if name.endswith(("_FILE", "_PATH", "_URL", "_URI", "_DIR", "_NAME", "_HOST", "_ID")):
        return False
    if "PUBLIC_KEY" in name:
        return False
    markers = ("PASSWORD", "PASSWD", "SECRET", "TOKEN", "API_KEY", "PRIVATE_KEY")
    return any(marker in name for marker in markers)


def scan_text(relative: Path, text: str) -> set[tuple[str, int]]:
    findings: set[tuple[str, int]] = set()
    for rule in EXPLICIT_RULES:
        for match in rule.pattern.finditer(text):
            if rule.name == "credential-in-url":
                candidate = match.group(0)
                if (
                    "{" in candidate
                    or "}" in candidate
                    or "example.com" in candidate
                    or "preview-user:preview-pass" in candidate
                ):
                    continue
            findings.add((rule.name, line_number(text, match.start())))
    for match in QUOTED_ASSIGNMENT.finditer(text):
        if not value_looks_safe(match.group(2)):
            findings.add(("literal-sensitive-assignment", line_number(text, match.start())))
    for match in ENV_ASSIGNMENT.finditer(text):
        if env_name_is_sensitive(match.group(1)) and not value_looks_safe(match.group(2)):
            findings.add(("env-sensitive-assignment", line_number(text, match.start())))
    return findings


def scan_history(root: Path) -> set[tuple[str, str, str]]:
    marker = "__GREENVPN_SECRET_SCAN_COMMIT__"
    process = subprocess.Popen(
        [
            "git",
            "log",
            "--all",
            f"--format={marker}%H",
            "--patch",
            "--binary",
            "--no-ext-diff",
            "--no-renames",
        ],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.stdout is None:
        raise RuntimeError("Unable to read git history")

    commit = "unknown"
    path = "unknown"
    findings: set[tuple[str, str, str]] = set()
    for raw_line in process.stdout:
        line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
        if line.startswith(marker):
            commit = line[len(marker) :]
            path = "unknown"
            continue
        if line.startswith("+++ b/"):
            path = line[6:]
            if is_forbidden_credential_file(Path(path)):
                findings.add((commit[:12], path, "tracked-credential-file"))
            continue
        if not line.startswith(("+", "-")) or line.startswith(("+++", "---")):
            continue
        content = line[1:]
        for rule_name, _ in scan_text(Path(path), content):
            findings.add((commit[:12], path, rule_name))

    stderr = process.stderr.read() if process.stderr is not None else b""
    return_code = process.wait()
    if return_code != 0:
        message = stderr.decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"git log failed: {message}")
    return findings


def main() -> int:
    args = parse_args()
    root = repository_root()
    findings: list[tuple[str, int, str]] = []
    skipped_large = 0
    skipped_binary = 0
    files = git_visible_files(root, args.include_untracked)

    for absolute in files:
        relative = absolute.relative_to(root)
        relative_text = relative.as_posix()
        if is_forbidden_credential_file(relative):
            findings.append((relative_text, 1, "tracked-credential-file"))
            continue
        if absolute.stat().st_size > args.max_file_bytes:
            skipped_large += 1
            continue
        content = absolute.read_bytes()
        if b"\0" in content[:8192]:
            skipped_binary += 1
            continue
        text = content.decode("utf-8", errors="replace")
        for rule_name, line in scan_text(relative, text):
            findings.append((relative_text, line, rule_name))

    if findings:
        print(f"secret_scan_status=failed findings={len(findings)}")
        for path, line, rule_name in sorted(findings):
            print(f"{path}:{line}: {rule_name}")
        return 1

    history_findings: set[tuple[str, str, str]] = set()
    if args.history:
        history_findings = scan_history(root)
    if history_findings:
        print(f"secret_history_scan_status=failed findings={len(history_findings)}")
        for commit, path, rule_name in sorted(history_findings):
            print(f"history:{commit}:{path}: {rule_name}")
        return 1

    print(
        "secret_scan_status=passed "
        f"files={len(files)} "
        f"skipped_large={skipped_large} skipped_binary={skipped_binary} "
        f"history={'checked' if args.history else 'not_checked'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
