#!/usr/bin/env python3
"""Read-only GitHub branch audit for Personal OS.

This tool never deletes refs. It classifies branches conservatively:
- SAFE_TO_DELETE only when main contains the branch tip, the refs are identical,
  or the exact branch tip is the head of a merged pull request.
- REVIEW_DELETE_CANDIDATE for an exact tip of an explicitly superseded/closed PR.
- RETAIN when the branch has unproven unique work, an open PR, or incomplete data.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any
from urllib.parse import quote


def gh_json(*args: str) -> Any:
    command = ["gh", "api", *args]
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{' '.join(command)} failed: {completed.stderr.strip()}"
        )
    return json.loads(completed.stdout)


def gh_paginated(endpoint: str) -> list[dict[str, Any]]:
    raw = gh_json("--paginate", "--slurp", endpoint)
    if not raw:
        return []
    if isinstance(raw, list) and raw and all(isinstance(page, list) for page in raw):
        return [item for page in raw for item in page]
    if isinstance(raw, list):
        return raw
    raise RuntimeError(f"unexpected paginated response for {endpoint}")


def branch_endpoint(repo: str, branch: str) -> str:
    return f"repos/{repo}/git/ref/heads/{quote(branch, safe='')}"


def compare_endpoint(repo: str, branch: str) -> str:
    return f"repos/{repo}/compare/main...{quote(branch, safe='')}"


def explicit_closed_reason(pr: dict[str, Any]) -> bool:
    title = str(pr.get("title") or "").lower()
    body = str(pr.get("body") or "").lower()
    text = f"{title}\n{body}"
    markers = (
        "superseded",
        "closed: unsafe",
        "closed: stale",
        "closed: misleading",
        "closed: incompatible",
        "false equivalence",
        "roadmap leakage",
    )
    return any(marker in text for marker in markers)


def classify(
    compare: dict[str, Any],
    branch_sha: str | None,
    prs: list[dict[str, Any]],
) -> tuple[str, str]:
    ahead = compare.get("ahead_by")
    behind = compare.get("behind_by")

    if ahead == 0 and behind == 0:
        return "SAFE_TO_DELETE", "branch tip is identical to main"

    if ahead == 0 and isinstance(behind, int) and behind > 0:
        return "SAFE_TO_DELETE", "main contains the complete branch tip"

    if any(pr.get("state") == "open" for pr in prs):
        return "RETAIN", "open pull request exists"

    if branch_sha:
        for pr in prs:
            if pr.get("merged_at") and pr.get("head", {}).get("sha") == branch_sha:
                return "SAFE_TO_DELETE", (
                    "branch tip exactly matches the head of a merged pull request"
                )

        for pr in prs:
            if (
                pr.get("state") == "closed"
                and not pr.get("merged_at")
                and pr.get("head", {}).get("sha") == branch_sha
                and explicit_closed_reason(pr)
            ):
                return (
                    "REVIEW_DELETE_CANDIDATE",
                    "exact tip of an explicitly superseded or rejected closed PR",
                )

    return (
        "RETAIN",
        "unique branch work is not proven to be covered by main or a merged PR",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo",
        default="lse872317312010/personal-os",
        help="GitHub repository in owner/name form",
    )
    parser.add_argument(
        "--format",
        choices=("json", "text"),
        default="json",
        help="output format",
    )
    args = parser.parse_args()

    try:
        main_ref = gh_json(f"repos/{args.repo}/git/ref/heads/main")
        main_sha = main_ref["object"]["sha"]
        branches = gh_paginated(f"repos/{args.repo}/branches?per_page=100")
        pulls = gh_paginated(f"repos/{args.repo}/pulls?state=all&per_page=100")
    except (RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"branch audit setup failed: {error}", file=sys.stderr)
        return 2

    results: list[dict[str, Any]] = []
    for branch in sorted(branches, key=lambda item: item.get("name", "")):
        name = branch.get("name")
        if not name or name == "main":
            continue

        try:
            ref = gh_json(branch_endpoint(args.repo, name))
            branch_sha = ref["object"]["sha"]
            compare = gh_json(compare_endpoint(args.repo, name))
            matching_prs = [
                {
                    "number": pr.get("number"),
                    "state": pr.get("state"),
                    "merged_at": pr.get("merged_at"),
                    "title": pr.get("title"),
                    "head_sha": pr.get("head", {}).get("sha"),
                }
                for pr in pulls
                if pr.get("head", {}).get("ref") == name
            ]
            decision, reason = classify(compare, branch_sha, matching_prs)
            results.append(
                {
                    "branch": name,
                    "branch_sha": branch_sha,
                    "main_sha": main_sha,
                    "ahead_by": compare.get("ahead_by"),
                    "behind_by": compare.get("behind_by"),
                    "status": compare.get("status"),
                    "decision": decision,
                    "reason": reason,
                    "pull_requests": matching_prs,
                    "files": [
                        file.get("filename")
                        for file in (compare.get("files") or [])
                    ],
                }
            )
        except (RuntimeError, KeyError, json.JSONDecodeError) as error:
            results.append(
                {
                    "branch": name,
                    "main_sha": main_sha,
                    "decision": "RETAIN",
                    "reason": f"audit data unavailable: {error}",
                }
            )

    report = {
        "repository": args.repo,
        "main_sha": main_sha,
        "branch_count_including_main": len(branches),
        "safe_to_delete": sum(
            item["decision"] == "SAFE_TO_DELETE" for item in results
        ),
        "review_delete_candidates": sum(
            item["decision"] == "REVIEW_DELETE_CANDIDATE" for item in results
        ),
        "retain": sum(item["decision"] == "RETAIN" for item in results),
        "branches": results,
    }

    if args.format == "json":
        json.dump(report, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"repository: {report['repository']}")
        print(f"main: {report['main_sha']}")
        print(f"branches including main: {report['branch_count_including_main']}")
        for item in results:
            print(
                f"{item['decision']:<24} {item['branch']} "
                f"({item.get('ahead_by', '?')} ahead, {item.get('behind_by', '?')} behind) "
                f"- {item['reason']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
