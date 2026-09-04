#!/usr/bin/env python3
"""Conservatively audit remote branches without deleting refs."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any
from urllib.parse import quote


SAFE_TO_DELETE = "SAFE_TO_DELETE"
REVIEW_DELETE_CANDIDATE = "REVIEW_DELETE_CANDIDATE"
RETAIN = "RETAIN"


def gh_json(*args: str) -> Any:
    command = ["gh", "api", *args]
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise RuntimeError("GitHub CLI 'gh' is required") from error
    if completed.returncode != 0:
        raise RuntimeError(
            f"{' '.join(command)} failed: {completed.stderr.strip()}"
        )
    return json.loads(completed.stdout)


def gh_paginated(endpoint: str) -> list[dict[str, Any]]:
    pages = gh_json("--paginate", "--slurp", endpoint)
    if not pages:
        return []
    if isinstance(pages, list) and all(isinstance(page, list) for page in pages):
        return [item for page in pages for item in page]
    if isinstance(pages, list):
        return pages
    raise RuntimeError(f"unexpected paginated response for {endpoint}")


def encoded_ref_endpoint(repo: str, branch: str) -> str:
    return f"repos/{repo}/git/ref/heads/{quote(branch, safe='')}"


def encoded_compare_endpoint(repo: str, branch: str) -> str:
    return f"repos/{repo}/compare/main...{quote(branch, safe='')}"


def explicit_closed_reason(pr: dict[str, Any]) -> bool:
    text = f"{pr.get('title') or ''}\n{pr.get('body') or ''}".lower()
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
    pull_requests: list[dict[str, Any]],
) -> tuple[str, str]:
    """Classify using only evidence that is safe for branch deletion."""

    ahead = compare.get("ahead_by")
    behind = compare.get("behind_by")
    if ahead == 0 and behind == 0:
        return SAFE_TO_DELETE, "branch tip is identical to main"
    if ahead == 0 and isinstance(behind, int) and behind > 0:
        return SAFE_TO_DELETE, "main contains the complete branch tip"

    if any(pr.get("state") == "open" for pr in pull_requests):
        return RETAIN, "open pull request exists"

    if branch_sha:
        exact_tip_prs = [
            pr for pr in pull_requests if pr.get("head_sha") == branch_sha
        ]
        if any(pr.get("merged_at") for pr in exact_tip_prs):
            return (
                SAFE_TO_DELETE,
                "branch tip exactly matches the head of a merged pull request",
            )
        if any(
            pr.get("state") == "closed"
            and not pr.get("merged_at")
            and explicit_closed_reason(pr)
            for pr in exact_tip_prs
        ):
            return (
                REVIEW_DELETE_CANDIDATE,
                "exact tip of an explicitly superseded or rejected closed PR",
            )

    return (
        RETAIN,
        "unique branch work is not proven covered by main or an exact merged PR head",
    )


def normalize_pull_request(pr: dict[str, Any]) -> dict[str, Any]:
    head = pr.get("head") or {}
    return {
        "number": pr.get("number"),
        "state": pr.get("state"),
        "merged_at": pr.get("merged_at"),
        "title": pr.get("title"),
        "body": pr.get("body"),
        "head_sha": head.get("sha"),
    }


def audit(repo: str) -> dict[str, Any]:
    main_ref = gh_json(f"repos/{repo}/git/ref/heads/main")
    main_sha = main_ref["object"]["sha"]
    branches = gh_paginated(f"repos/{repo}/branches?per_page=100")
    pulls = gh_paginated(f"repos/{repo}/pulls?state=all&per_page=100")

    results: list[dict[str, Any]] = []
    for branch in sorted(branches, key=lambda item: item.get("name", "")):
        name = branch.get("name")
        if not name or name == "main":
            continue
        try:
            ref = gh_json(encoded_ref_endpoint(repo, name))
            branch_sha = ref["object"]["sha"]
            compare = gh_json(encoded_compare_endpoint(repo, name))
            matching_prs = [
                normalize_pull_request(pr)
                for pr in pulls
                if (pr.get("head") or {}).get("ref") == name
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
                        item.get("filename") for item in compare.get("files") or []
                    ],
                }
            )
        except (RuntimeError, KeyError, json.JSONDecodeError) as error:
            results.append(
                {
                    "branch": name,
                    "main_sha": main_sha,
                    "decision": RETAIN,
                    "reason": f"audit data unavailable: {error}",
                }
            )

    return {
        "repository": repo,
        "main_sha": main_sha,
        "branch_count_including_main": len(branches),
        "safe_to_delete": sum(
            item["decision"] == SAFE_TO_DELETE for item in results
        ),
        "review_delete_candidates": sum(
            item["decision"] == REVIEW_DELETE_CANDIDATE for item in results
        ),
        "retain": sum(item["decision"] == RETAIN for item in results),
        "branches": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="lse872317312010/personal-os")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    args = parser.parse_args()
    try:
        report = audit(args.repo)
    except (RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"branch audit setup failed: {error}", file=sys.stderr)
        return 2

    if args.format == "json":
        json.dump(report, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"repository: {report['repository']}")
        print(f"main: {report['main_sha']}")
        print(f"branches including main: {report['branch_count_including_main']}")
        for item in report["branches"]:
            print(
                f"{item['decision']:<24} {item['branch']} "
                f"({item.get('ahead_by', '?')} ahead, "
                f"{item.get('behind_by', '?')} behind) - {item['reason']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
