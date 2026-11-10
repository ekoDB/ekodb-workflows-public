"""Structural assertions on prune-pr-caches.yml.

Callers run this on pull_request_target with a token that can delete caches, so
each assertion is one way the workflow could be present and unsafe or inert.
"""
import pathlib
import sys

import yaml

DIR = pathlib.Path(__file__).resolve().parent
WF = DIR.parent / ".github" / "workflows" / "prune-pr-caches.yml"
FAILURES = []


def check(cond, msg, detail=""):
    """One assertion: prints ok or FAIL, never both, and records a failure."""
    if cond:
        print(f"ok: {msg}")
    else:
        print(f"FAIL: {msg}" + (f" -- {detail}" if detail else ""))
        FAILURES.append(msg)


with open(WF, encoding="utf-8") as f:
    wf = yaml.safe_load(f)

# PyYAML reads the bare key `on` as boolean True.
on = wf.get("on", wf.get(True))
check(set(on) == {"workflow_call"}, "is only reusable, with no trigger of its own", f"triggers are {set(on)}")
check(
    set(on["workflow_call"]) == {"inputs"},
    "workflow_call declares inputs only: no secrets or outputs reach the job",
    f"workflow_call keys are {sorted(on['workflow_call'])}",
)
inputs = on["workflow_call"].get("inputs", {})
check(set(inputs) == {"pr-number"}, "declares exactly the pr-number input", f"inputs are {set(inputs)}")
check(inputs["pr-number"].get("required") is True, "pr-number is required")
check(inputs["pr-number"].get("type") == "number", "pr-number is typed as a number")

check(
    wf.get("permissions") == {"actions": "write", "contents": "read"},
    "declares only actions: write and contents: read",
    str(wf.get("permissions")),
)

jobs = wf["jobs"]
check(set(jobs) == {"prune"}, "has the one prune job", f"jobs are {set(jobs)}")
steps = jobs["prune"]["steps"]

checkouts = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
check(len(checkouts) == 1, "has exactly one checkout", f"found {len(checkouts)}")
for step in checkouts:
    args = step.get("with", {})
    check(args.get("repository") == "ekoDB/ekodb-workflows-public", "never checks out the caller's or pull request's code", str(args))
    check(args.get("ref") == "${{ job.workflow_sha }}", "pins the scripts to this workflow's commit", str(args))
    check(args.get("persist-credentials") is False, "leaves no token in the checkout", str(args))

runs = [s for s in steps if "run" in s]
check(any("rev-parse HEAD" in s["run"] for s in runs), "asserts the checkout is at the pin")

delete = [s for s in runs if "prune-pr-caches.sh" in s["run"]]
check(len(delete) == 1, "runs the script once", f"found {len(delete)}")
if delete:
    step = delete[0]
    check("${{" not in step["run"], "passes values through env, never interpolated into the shell", step["run"])
    env = step.get("env", {})
    check(env.get("PR_NUMBER") == "${{ inputs.pr-number }}", "takes the number from the input", str(env))
    check(env.get("REPO") == "${{ github.repository }}", "acts on the calling repository", str(env))
    check(env.get("GH_TOKEN") == "${{ github.token }}", "uses the run's own token", str(env))

if FAILURES:
    print(f"{len(FAILURES)} failure(s)")
    sys.exit(1)
print("all prune_pr_caches_wiring tests passed")
