import unittest
from unittest.mock import patch

from tool.audit_remote_branches import (
    RETAIN,
    REVIEW_DELETE_CANDIDATE,
    SAFE_TO_DELETE,
    classify,
    gh_json,
    normalize_pull_request,
)


TIP = "a" * 40
OLDER_TIP = "b" * 40


class BranchClassificationTests(unittest.TestCase):
    def test_branch_contained_by_main_is_safe(self):
        decision, _ = classify(
            {"ahead_by": 0, "behind_by": 3}, TIP, []
        )
        self.assertEqual(SAFE_TO_DELETE, decision)

    def test_exact_squash_pr_head_is_safe(self):
        decision, _ = classify(
            {"ahead_by": 7, "behind_by": 2},
            TIP,
            [{"state": "closed", "merged_at": "2026-09-04T00:00:00Z", "head_sha": TIP}],
        )
        self.assertEqual(SAFE_TO_DELETE, decision)

    def test_post_merge_commit_is_retained(self):
        decision, _ = classify(
            {"ahead_by": 8, "behind_by": 2},
            TIP,
            [
                {
                    "state": "closed",
                    "merged_at": "2026-09-04T00:00:00Z",
                    "head_sha": OLDER_TIP,
                }
            ],
        )
        self.assertEqual(RETAIN, decision)

    def test_open_pr_always_retains_diverged_branch(self):
        decision, _ = classify(
            {"ahead_by": 1, "behind_by": 2},
            TIP,
            [{"state": "open", "merged_at": None, "head_sha": TIP}],
        )
        self.assertEqual(RETAIN, decision)

    def test_explicit_superseded_exact_tip_requires_review(self):
        decision, _ = classify(
            {"ahead_by": 1, "behind_by": 2},
            TIP,
            [
                {
                    "state": "closed",
                    "merged_at": None,
                    "head_sha": TIP,
                    "title": "Superseded by #75",
                    "body": "",
                }
            ],
        )
        self.assertEqual(REVIEW_DELETE_CANDIDATE, decision)

    def test_normalization_preserves_head_sha_for_classifier(self):
        normalized = normalize_pull_request(
            {
                "number": 75,
                "state": "closed",
                "merged_at": "2026-09-04T00:00:00Z",
                "head": {"sha": TIP},
            }
        )
        self.assertEqual(TIP, normalized["head_sha"])

    @patch("tool.audit_remote_branches.subprocess.run", side_effect=FileNotFoundError)
    def test_missing_github_cli_fails_closed(self, _run):
        with self.assertRaisesRegex(RuntimeError, "GitHub CLI 'gh' is required"):
            gh_json("repos/example/project")


if __name__ == "__main__":
    unittest.main()
