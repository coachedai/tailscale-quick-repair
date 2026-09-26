#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

TEXT_EXTENSIONS = {
    ".ps1",".psm1",".psd1",".cs",".vbs",".py",".json",".yml",".yaml",
    ".md",".txt",".xml",".config",".ini",".cfg",".conf",".toml",
    ".properties",".csv",".patch",".diff",".gitignore",".gitattributes"
}
TEXT_LEAFS = {".gitignore",".gitattributes"}
FORBIDDEN_EVIDENCE_EXTENSIONS = {
    ".png",".jpg",".jpeg",".webp",".bmp",".gif",".tif",".tiff",
    ".mp4",".mov",".webm",".avi",
    ".log",".dmp",".mdmp",".evtx",".etl",".reg",
    ".pcap",".pcapng",".har",
    ".zip",".7z",".rar",".tar",".gz",".tgz",
    ".pdf",".doc",".docx",".xls",".xlsx",".ppt",".pptx",
    ".db",".sqlite",".sqlite3",".bak",".bin"
}
SECRET_PATTERNS = [
    ("github_token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b", re.I)),
    ("github_fine_grained_token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b", re.I)),
    ("tailscale_auth_key", re.compile(r"\btskey-[A-Za-z0-9-]{10,}\b", re.I)),
    ("aws_access_key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private_key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("openai_style_secret", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b", re.I)),
]
WINDOWS_USER_PATH = re.compile(r"\b[A-Z]:\\Users\\([^\\\r\n]+)", re.I)
DEVICE_NAME = re.compile(r"\bvmi\d{5,}\b", re.I)
EMAIL = re.compile(r"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b", re.I)
IPV4 = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
IPV4_ESCAPED = re.compile(r"(?<!\d)(?:\d{1,3}\\\.){3}\d{1,3}(?!\d)")
IPV4_BRACKETED = re.compile(r"(?<!\d)(?:\d{1,3}\[\.\]){3}\d{1,3}(?!\d)")
OTHER_PROJECT = "coach" + "intake"
ALLOWED_IPV4 = {"0.0.0.0","127.0.0.1","2.0.0.0","3.0.0.0"}

# One pre-isolation README blob is known historical redaction debt. This is
# identified only by its public Git object ID; the matched cross-project text
# is intentionally not reproduced here. Any additional finding still fails.
KNOWN_LEGACY_FINDINGS = {
    ("blob","4d63c9eff326cc8cc48c1251b27fd6852609e25e","cross_project_content")
}

def run_git(args, input_bytes=None):
    p = subprocess.run(["git", *args], input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if p.returncode != 0:
        raise RuntimeError("git command failed")
    return p.stdout

def path_hash(path):
    return hashlib.sha256(path.encode("utf-8", "surrogateescape")).hexdigest()

def valid_ipv4(value):
    try:
        parts = [int(x) for x in value.split(".")]
        return len(parts) == 4 and all(0 <= x <= 255 for x in parts)
    except Exception:
        return False

def is_assembly_version_line(text, start, value):
    left = text.rfind("\n", 0, start) + 1
    right = text.find("\n", start)
    if right < 0:
        right = len(text)
    line = text[left:right].strip()
    return bool(re.match(r"^\[assembly:\s*System\.Reflection\.Assembly(?:File)?Version\s*\(", line, re.I) and value in line)

def scan_text(text, add, object_id, kind):
    lower = text.lower()
    if OTHER_PROJECT in lower:
        add(kind, object_id, "cross_project_content")
    for name, pattern in SECRET_PATTERNS:
        if pattern.search(text):
            add(kind, object_id, name)
    for m in WINDOWS_USER_PATH.finditer(text):
        user = m.group(1)
        if user not in {"Public","<user>","USERNAME","$env:USERNAME"}:
            add(kind, object_id, "personal_windows_user_path")
    if DEVICE_NAME.search(text):
        add(kind, object_id, "machine_style_device_name")
    for m in EMAIL.finditer(text):
        email = m.group(0)
        if not (
            re.search(r"@users\.noreply\.github\.com$", email, re.I) or
            email.lower() == "noreply@github.com"
        ):
            add(kind, object_id, "email_address")
    for m in IPV4.finditer(text):
        value = m.group(0)
        if value in ALLOWED_IPV4 or not valid_ipv4(value) or is_assembly_version_line(text, m.start(), value):
            continue
        add(kind, object_id, "literal_ipv4")
    for pattern, reason in (
        (IPV4_ESCAPED, "escaped_literal_ipv4"),
        (IPV4_BRACKETED, "bracket_encoded_literal_ipv4"),
    ):
        for m in pattern.finditer(text):
            value = m.group(0).replace("\\.", ".").replace("[.]", ".")
            if value in ALLOWED_IPV4 or not valid_ipv4(value):
                continue
            add(kind, object_id, reason)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--result", required=True)
    args = ap.parse_args()

    findings = []
    seen_findings = set()
    counts = {"objects":0,"blobs":0,"text_blobs":0,"commits":0,"refs":0}

    def add(kind, object_id, reason, path=None):
        key = (kind, object_id, reason, path_hash(path) if path else None)
        if key in seen_findings:
            return
        seen_findings.add(key)
        item = {"kind":kind,"object":object_id,"reason":reason}
        if path is not None:
            item["path_sha256"] = path_hash(path)
        findings.append(item)

    refs = run_git(["for-each-ref","--format=%(refname)"]).decode("utf-8","replace").splitlines()
    counts["refs"] = len([r for r in refs if r.strip()])

    lines = run_git(["rev-list","--objects","--all"]).decode("utf-8","surrogateescape").splitlines()
    object_paths = {}
    all_ids = []
    for line in lines:
        if not line:
            continue
        parts = line.split(" ",1)
        sha = parts[0]
        path = parts[1] if len(parts) > 1 else None
        if sha not in object_paths:
            object_paths[sha] = set()
            all_ids.append(sha)
        if path:
            object_paths[sha].add(path)
    counts["objects"] = len(all_ids)

    batch = subprocess.Popen(
        ["git","cat-file","--batch-check=%(objectname) %(objecttype) %(objectsize)"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    check_input = ("\n".join(all_ids)+"\n").encode("ascii")
    check_out, _ = batch.communicate(check_input)
    if batch.returncode != 0:
        raise RuntimeError("git cat-file batch-check failed")

    blob_sizes = {}
    for line in check_out.decode("ascii","replace").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] == "blob":
            blob_sizes[parts[0]] = int(parts[2])
    counts["blobs"] = len(blob_sizes)

    text_blob_ids = []
    for sha, size in blob_sizes.items():
        paths = object_paths.get(sha,set())
        is_text = False
        if not paths:
            add("blob",sha,"historical_blob_without_path")
            continue
        for path in paths:
            leaf = os.path.basename(path)
            ext = os.path.splitext(leaf)[1].lower()
            low = path.lower()
            if OTHER_PROJECT in low:
                add("path",sha,"cross_project_path",path)
            if FORBIDDEN_EVIDENCE_EXTENSIONS.__contains__(ext):
                add("path",sha,"forbidden_evidence_or_opaque_file_type",path)
                continue
            if ext in TEXT_EXTENSIONS or leaf in TEXT_LEAFS:
                is_text = True
            else:
                add("path",sha,"unreviewed_non_text_historical_file",path)
        if is_text:
            if size > 5*1024*1024:
                add("blob",sha,"historical_text_blob_over_5mb")
            else:
                text_blob_ids.append(sha)

    counts["text_blobs"] = len(text_blob_ids)
    cat = subprocess.Popen(["git","cat-file","--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert cat.stdin and cat.stdout
    for sha in text_blob_ids:
        cat.stdin.write((sha+"\n").encode("ascii"))
    cat.stdin.close()
    for expected in text_blob_ids:
        header = cat.stdout.readline().decode("ascii","replace").strip().split()
        if len(header) < 3 or header[1] != "blob":
            raise RuntimeError("unexpected blob batch header")
        size = int(header[2])
        data = cat.stdout.read(size)
        cat.stdout.read(1)
        text = data.decode("utf-8","replace")
        scan_text(text, add, expected, "blob")
    cat.wait()
    if cat.returncode != 0:
        raise RuntimeError("git cat-file batch failed")

    log_bytes = run_git(["log","--all","--format=%H%x00%an%x00%ae%x00%cn%x00%ce%x00%B%x1e"])
    records = log_bytes.decode("utf-8","replace").split("\x1e")
    for rec in records:
        rec = rec.strip("\r\n")
        if not rec:
            continue
        parts = rec.split("\x00",5)
        if len(parts) != 6:
            continue
        sha, author_name, author_email, committer_name, committer_email, message = parts
        counts["commits"] += 1
        for email in (author_email,committer_email):
            if email and not (
                re.search(r"@users\.noreply\.github\.com$",email,re.I) or
                email.lower() == "noreply@github.com"
            ):
                add("commit",sha,"non_noreply_commit_email")
        scan_text(message, add, sha, "commit")

    # Public commit hashes are safe provenance. Never include matched content
    # or raw historical paths in the uploaded result.
    for finding in findings:
        if finding.get("kind") in {"blob","path"}:
            sha = finding.get("object","")
            if sha:
                try:
                    history = run_git(["log","--all","--find-object="+sha,"--format=%H","--reverse"]).decode("ascii","replace").splitlines()
                    finding["change_commits"] = [x for x in history if x][:8]
                    finding["change_commit_count"] = len([x for x in history if x])
                except Exception:
                    finding["change_commits"] = []
                    finding["change_commit_count"] = 0

    legacy = []
    unexpected = []
    for finding in findings:
        key = (finding.get("kind",""),finding.get("object",""),finding.get("reason",""))
        if key in KNOWN_LEGACY_FINDINGS:
            legacy.append(finding)
        else:
            unexpected.append(finding)

    result = {
        "schema":2,
        "passed":len(unexpected)==0,
        "scope":"All reachable Git refs; historical paths/blobs and commit metadata. Findings contain hashes/reason codes/public commit SHAs only, never matched content.",
        "counts":counts,
        "finding_count":len(findings),
        "legacy_finding_count":len(legacy),
        "unexpected_finding_count":len(unexpected),
        "legacy_findings":legacy[:50],
        "unexpected_findings":unexpected[:500],
        "truncated":len(legacy)>50 or len(unexpected)>500
    }
    with open(args.result,"w",encoding="utf-8") as f:
        json.dump(result,f,indent=2,sort_keys=True)
        f.write("\n")
    if unexpected:
        print("HISTORY PRIVACY AUDIT FAILED: %d unexpected generic finding(s); %d known legacy debt finding(s). Matched content is intentionally not printed." % (len(unexpected),len(legacy)))
        return 1
    print("History privacy audit passed with %d known legacy debt finding(s): %d commits, %d blobs, %d refs. Matched content is intentionally not printed." % (len(legacy),counts["commits"],counts["blobs"],counts["refs"]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
