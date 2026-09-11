"""Structural assertions on auto-tag.yml and release.yml.

A tag push is a release, so the wiring is a production surface. Each assertion
is one way the workflow could be present and wrong.
"""
import pathlib
import sys

import yaml

DIR = pathlib.Path(__file__).resolve().parent
WF = DIR.parent / ".github" / "workflows" / "auto-tag.yml"
CALLER = DIR.parent / ".github" / "workflows" / "release.yml"
FAILURES = []


def check(cond, msg, detail=""):
    """One assertion: prints ok or FAIL, never both, and records a failure."""
    if cond:
        print(f"ok: {msg}")
    else:
        print(f"FAIL: {msg}" + (f" -- {detail}" if detail else ""))
        FAILURES.append(msg)


def load(p):
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f)


wf = load(WF)
# PyYAML reads the bare key `on` as boolean True.
on = wf.get("on", wf.get(True))
call = on["workflow_call"]
inputs = call.get("inputs", {})
outputs = call.get("outputs", {})
jobs = wf["jobs"]

# 1. Inputs and outputs are exactly the contract.
want_inputs = {"version-command", "changelog", "post-tag-command", "default-branch"}
check(set(inputs) == want_inputs, "declares exactly the four inputs", f"inputs are {set(inputs)}")
check(inputs.get("changelog", {}).get("default") == "CHANGELOG.md", "changelog defaults to CHANGELOG.md")
check(inputs.get("default-branch", {}).get("default") == "main", "default-branch defaults to main")
check(set(outputs) == {"version", "tag"}, "declares outputs version and tag", f"outputs are {set(outputs)}")
for name in ("version", "tag"):
    val = outputs.get(name, {}).get("value", "")
    check("jobs.detect.outputs." + name in val, f"output {name} comes from detect", f"value is {val!r}")

# 2. Permissions: contents: write at workflow level; detect, which only reads, narrows to read; nothing else declares any.
check(wf.get("permissions") == {"contents": "write"}, "workflow-level permissions are exactly contents: write", f"permissions {wf.get('permissions')}")
job_perms = {j: spec["permissions"] for j, spec in jobs.items() if "permissions" in spec}
check(job_perms == {"detect": {"contents": "read"}}, "detect narrows itself to contents: read and no other job declares permissions", f"jobs with permissions: {job_perms}")

# 3. Jobs, order, gates.
check(list(jobs) == ["detect", "tag", "release", "post-tag"], "four jobs in order", f"jobs {list(jobs)}")
check(jobs["tag"].get("needs") in ("detect", ["detect"]), "tag needs detect", f"needs {jobs['tag'].get('needs')!r}")
check("needs.detect.outputs.version != ''" in str(jobs["tag"].get("if", "")), "tag is gated on a detected version", f"if: {jobs['tag'].get('if')!r}")
rel_if = str(jobs["release"].get("if", ""))
check("!cancelled()" in rel_if and "needs.detect.outputs.version != ''" in rel_if, "release runs on !cancelled() with the version gate", f"release if: {rel_if}")
check(set(jobs["release"].get("needs", [])) == {"detect", "tag"}, "release needs detect and tag", f"needs {jobs['release'].get('needs')!r}")
post_if = str(jobs["post-tag"].get("if", ""))
check(all(s in post_if for s in ("!cancelled()", "needs.release.result == 'success'", "inputs.post-tag-command != ''")), "post-tag gated on release success and a command", f"post-tag if: {post_if}")

# 4. Detect exports both outputs and reads the subject from git at github.sha.
det_out = jobs["detect"].get("outputs", {})
check(set(det_out) == {"version", "tag"}, "detect declares version and tag outputs", f"detect outputs {det_out}")
det_runs = "\n".join(s.get("run", "") for s in jobs["detect"]["steps"])
check("git log -1 --format=%s" in det_runs and "GITHUB_SHA" in det_runs, "detect reads the subject from git at github.sha")
check("release-cap-detect.sh" in det_runs, "detect calls release-cap-detect.sh")

# 5. Every script checkout is pinned to job.workflow_sha and reads this repo,
#    and the three jobs that run scripts each have one.
script_checkouts = []
for j, spec in jobs.items():
    for s in spec["steps"]:
        w = s.get("with", {}) or {}
        if s.get("uses", "").startswith("actions/checkout") and w.get("repository"):
            script_checkouts.append(j)
            check(w["repository"] == "ekoDB/ekodb-workflows-public" and w.get("ref") == "${{ job.workflow_sha }}", f"{j}: scripts checkout pinned to job.workflow_sha", f"with {w}")
check(script_checkouts == ["detect", "tag", "release"], "detect, tag and release each check the scripts out", f"found {script_checkouts}")
# ... and each asserts, in the step right after, that the checkout is at that pin and the pin is non-empty.
for j in ("detect", "tag", "release"):
    steps = jobs[j]["steps"]
    idx = next((i for i, s in enumerate(steps) if (s.get("with") or {}).get("repository")), None)
    nxt = steps[idx + 1] if idx is not None and idx + 1 < len(steps) else {}
    pinned = (nxt.get("env") or {}).get("PIN") == "${{ job.workflow_sha }}" and '[ -n "$PIN" ]' in nxt.get("run", "") and "rev-parse HEAD" in nxt.get("run", "")
    check(pinned, f"{j}: the step after the scripts checkout refuses an empty pin and a checkout at any other SHA", f"next step: {nxt.get('name')!r}")

# 6. No run body interpolates inputs; the two commands go through env + eval.
interpolating = [f"{j}/{s.get('name')}" for j, spec in jobs.items() for s in spec["steps"] if "${{ inputs." in s.get("run", "")]
check(not interpolating, "no run body interpolates ${{ inputs.", f"run bodies interpolate inputs: {interpolating}")
tag_runs = "\n".join(s.get("run", "") for s in jobs["tag"]["steps"])
check('eval "$VERSION_COMMAND"' in tag_runs, "version-command runs through env + eval")
post_runs = "\n".join(s.get("run", "") for s in jobs["post-tag"]["steps"])
check('eval "$POST_TAG_COMMAND"' in post_runs, "post-tag-command runs through env + eval")

# 7. The tag job asserts containment before tagging and pushes with github.token.
check("merge-base --is-ancestor" in tag_runs, "tag asserts the commit is on the default branch")
check("release-tag-gate.sh" in tag_runs, "tag runs release-tag-gate.sh")
tag_checkout = [s for s in jobs["tag"]["steps"] if s.get("uses", "").startswith("actions/checkout") and not (s.get("with") or {}).get("repository")]
check(bool(tag_checkout) and (tag_checkout[0].get("with") or {}).get("ref") == "${{ github.sha }}", "tag checks out github.sha, not the branch tip")
check("secrets." not in yaml.dump(wf), "no secret is referenced anywhere")

# 8. Release asserts the tag exists before publishing and publishes from the block.
rel_runs = [s.get("run", "") for s in jobs["release"]["steps"]]
idx_gate = next((i for i, r in enumerate(rel_runs) if "tag-exists-gate.sh" in r), None)
idx_pub = next((i for i, r in enumerate(rel_runs) if "github-release.sh" in r), None)
check(idx_gate is not None and idx_pub is not None and idx_gate < idx_pub, "release gates on tag existence before publishing", f"gate={idx_gate} publish={idx_pub}")

# 9. The caller in this repository passes only declared inputs and matches permissions.
caller = load(CALLER)
cj = caller["jobs"]["auto-tag"]
check(cj["uses"] == "./.github/workflows/auto-tag.yml", "release.yml calls the local workflow", f"caller uses {cj['uses']}")
check(set(cj.get("with") or {}) <= want_inputs, "caller passes only declared inputs", f"caller passes {set(cj.get('with') or {})}")
check(caller.get("permissions") == {"contents": "write"}, "caller declares contents: write", f"caller permissions {caller.get('permissions')}")
con = caller.get("on", caller.get(True))
check(con.get("push", {}).get("branches") == ["main"], "caller triggers on push to main", f"caller on: {con}")

if FAILURES:
    print(f"{len(FAILURES)} failure(s)")
    sys.exit(1)
print("all auto_tag_wiring tests passed")
