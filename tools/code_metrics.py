#!/usr/bin/env python3
"""Git-tracked first-party source metrics: cloc LOC, language, tests, 7-day net change.

Runs offline. Counts source files on HEAD and the last commit before the weekly cutoff.
No metrics leave this repository; GitHub Actions artifacts belong to the caller repo.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

EXT = {
    ".py", ".pyi", ".rs", ".c", ".h", ".cc", ".cpp", ".cxx", ".hpp",
    ".dart", ".kt", ".kts", ".java", ".go", ".swift", ".zig",
    ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".vue", ".svelte",
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".sh", ".bash", ".zsh", ".ps1", ".sql", ".rb", ".lua", ".pl",
    ".r", ".m", ".mm", ".cs", ".fs", ".fsx", ".scala", ".asm",
    ".s", ".v", ".sv", ".vhd", ".vhdl",
}
EXCLUDE_DIR = {
    ".git", ".venv", "venv", "node_modules", "vendor", "third_party",
    "third-party", "target", "build", "dist", "coverage", ".next",
    ".nuxt", "out", ".dart_tool", ".gradle", ".pub-cache",
    "__pycache__", "generated", "gen", "site-packages", "pods",
    "external",
}
TEST_DIR = {
    "test", "tests", "__tests__", "androidtest", "integration_test",
    "integrationtests", "e2e", "uitests", "benchmark", "benchmarks",
}
GENERATED = (
    ".min.js", ".min.css", ".g.dart", ".freezed.dart", ".mocks.dart",
    ".gr.dart", ".pb.dart", ".pb.go", ".generated.", ".designer.",
)
FIELDS = ("code", "comment", "blank")


def git(root, *args):
    return subprocess.check_output(
        ["git", "-C", str(root), *args], stderr=subprocess.PIPE,
        text=True,
    ).strip()


def source_file(path):
    parts = PurePosixPath(path).parts
    lower = [x.lower() for x in parts]
    return (
        path != "tools/code_metrics.py"  # self-instrumentation is not product growth
        and not set(lower[:-1]).intersection(EXCLUDE_DIR)
        and not any(g in lower[-1] for g in GENERATED)
        and PurePosixPath(path).suffix.lower() in EXT
    )


def test_file(path):
    parts = PurePosixPath(path).parts
    name = parts[-1].lower()
    stem = PurePosixPath(name).stem
    return bool(
        set(p.lower() for p in parts[:-1]).intersection(TEST_DIR)
        or name.startswith(("test_", "spec_"))
        or stem.endswith(("_test", "_tests", "_spec"))
        or re.search(r"(?:^|[._-])(?:test|spec)(?:[._-]|$)", name)
    )


def tracked_sources(root):
    data = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
    names = [x.decode("utf-8", "surrogateescape") for x in data.split(b"\0") if x]
    return sorted(x for x in names if source_file(x)
                  and (root / x).is_file() and not (root / x).is_symlink())


def count_files(root, paths):
    if not paths:
        return {}
    # Count independently by source suffix. A Python tooling addition must not
    # change the way cloc classifies unchanged Dart/Rust/Kotlin source files.
    groups = {}
    for path in paths:
        groups.setdefault(PurePosixPath(path).suffix.lower(), []).append(path)
    result = {}
    for extension, group in sorted(groups.items()):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt") as file:
            for name in group:
                if "\n" in name or "\r" in name:
                    raise ValueError("newline in tracked source path")
                file.write(name + "\n")
            file.flush()
            output = subprocess.check_output(
                ["cloc", "--json", "--by-file", "--skip-uniqueness",
                 "--quiet", "--list-file=" + file.name],
                cwd=root, text=True,
            )
        data = json.loads(output)
        for name, item in data.items():
            if name in ("header", "SUM") or not isinstance(item, dict) or "code" not in item:
                continue
            result[name.removeprefix("./")] = {
                "language": item["language"],
                **{field: int(item[field]) for field in FIELDS},
            }
    missed = set(paths) - set(result)
    # cloc intentionally omits zero-length files; preserve them as zero-LOC
    # tracked sources rather than treating an empty package marker as a failure.
    for name in sorted(missed):
        if not (root / name).read_bytes().strip():
            result[name] = {
                "language": "Empty source", "code": 0, "comment": 0, "blank": 0,
            }
    missed = set(paths) - set(result)
    if missed:
        raise RuntimeError("cloc did not classify these tracked files: "
                           + repr(sorted(missed)[:8]))
    return result


def totals(items):
    def empty():
        return {"files": 0, "code": 0, "comment": 0, "blank": 0}
    overall = empty()
    sections = {"production": empty(), "test": empty()}
    languages = {}
    for name, row in sorted(items.items()):
        lang = languages.setdefault(row["language"], empty())
        kind = sections["test" if test_file(name) else "production"]
        for counter in (overall, kind, lang):
            counter["files"] += 1
            for field in FIELDS:
                counter[field] += row[field]
    return {"total": overall, "sections": sections, "languages": languages}


def snapshot(root):
    return totals(count_files(root, tracked_sources(root)))


def markdown(report):
    current = report["current"]
    prior = report["baseline"]
    total = current["total"]
    def change(section):
        if prior is None:
            return "n/a"
        if section is None:
            return f"{total['code'] - prior['total']['code']:+d}"
        return f"{current['sections'][section]['code'] - prior['sections'][section]['code']:+d}"
    out = [
        "# Weekly source code metrics", "",
        f"- Repository: {report['repository']}",
        f"- HEAD: {report['commit']}",
        f"- UTC: {report['generated_at_utc']}",
        f"- 7-day baseline commit: {report['baseline_commit'] or 'unavailable'}",
        f"- Source files: **{total['files']:,}**",
        f"- Code: **{total['code']:,} LOC**; comments: **{total['comment']:,}**; "
        f"blank: **{total['blank']:,}**",
        f"- 7-day net change: **{change(None)} code LOC**", "",
        "| Scope | Files | Code LOC | Comment | Blank | 7-day net code LOC |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for section in ("production", "test"):
        item = current["sections"][section]
        out.append(
            f"| {section} | {item['files']} | {item['code']} | {item['comment']} | "
            f"{item['blank']} | {change(section)} |"
        )
    out += ["", "| Language | Files | Code LOC | Comment | Blank |",
            "|---|---:|---:|---:|---:|"]
    for lang, item in sorted(current["languages"].items(),
                             key=lambda pair: -pair[1]["code"]):
        out.append(f"| {lang} | {item['files']} | {item['code']} | "
                   f"{item['comment']} | {item['blank']} |")
    out += [
        "",
        "Scope: tracked source extensions only; known vendor/build/generated folders "
        "excluded. Test classification is path-based and does not separate inline tests. "
        "Baseline is the last commit before the UTC seven-day cutoff. "
        "Net LOC is a snapshot difference, **not** churn or author productivity.",
    ]
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="outputs/code-metrics")
    args = parser.parse_args()
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel")).resolve()
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=7)
    base = git(root, "rev-list", "-1",
               "--before=" + cutoff.strftime("%Y-%m-%dT%H:%M:%SZ"), "HEAD")
    current = snapshot(root)
    prior = None
    if base:
        with tempfile.TemporaryDirectory(prefix="weekly-code-metrics-") as tmp:
            checkout = Path(tmp) / "baseline"
            try:
                subprocess.run(
                    ["git", "-C", str(root), "worktree", "add", "--detach",
                     str(checkout), base],
                    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                )
                prior = snapshot(checkout)
            finally:
                if checkout.exists():
                    subprocess.run(
                        ["git", "-C", str(root), "worktree", "remove",
                         "--force", str(checkout)],
                        check=True, stdout=subprocess.DEVNULL,
                    )
    report = {
        "schema_version": "1.0",
        "repository": os.environ.get("GITHUB_REPOSITORY", root.name),
        "commit": git(root, "rev-parse", "HEAD"),
        "generated_at_utc": now.isoformat(),
        "baseline_cutoff_utc": cutoff.isoformat(),
        "baseline_commit": base or None,
        "current": current,
        "baseline": prior,
        "scope": "cloc on git-tracked first-party source extensions; path-based test split",
    }
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    (out / "metrics.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    summary = markdown(report)
    (out / "summary.md").write_text(summary, encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
