#!/usr/bin/env python3
"""Summarize an e-mail (.eml) without rendering it.

Prints the headers that matter for phishing triage, the MIME structure, the
links found in the body and the attachments (with hashes). With --extract DIR
it also writes the attachments to DIR so that `analyze` can inspect them.
"""
import argparse
import email
import hashlib
import os
import re
from email import policy

HEADERS = ("From", "Sender", "Reply-To", "Return-Path", "To", "Cc", "Subject",
           "Date", "Message-ID", "X-Mailer", "User-Agent", "X-Originating-IP")
AUTH_HEADERS = ("Authentication-Results", "ARC-Authentication-Results", "Received-SPF")
URL_RE = re.compile(r"""(?:https?|ftp)://[^\s"'<>()\\]+""", re.I)
HREF_RE = re.compile(r"""<a\b[^>]*?href\s*=\s*["']?([^"'\s>]+)[^>]*>(.*?)</a>""", re.I | re.S)
TAG_RE = re.compile(r"<[^>]+>")


def safe_name(name, index):
    base = os.path.basename(name or "") or "part"
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base)[:100]
    return f"{index:02d}_{base}"


def body_text(part):
    try:
        return part.get_content()
    except Exception:
        payload = part.get_payload(decode=True) or b""
        return payload.decode("utf-8", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--extract", metavar="DIR")
    args = ap.parse_args()

    with open(args.file, "rb") as fh:
        msg = email.message_from_binary_file(fh, policy=policy.default)

    print("\n-- Headers")
    for h in HEADERS:
        for v in msg.get_all(h, []):
            print(f"{h}: {v}")
    dkim = [re.findall(r"\b[ds]=([^;\s]+)", str(v)) for v in msg.get_all("DKIM-Signature", [])]
    for d in dkim:
        print(f"DKIM-Signature: {' '.join(d)}")
    for h in AUTH_HEADERS:
        for v in msg.get_all(h, []):
            print(f"{h}: {' '.join(str(v).split())}")

    received = msg.get_all("Received", [])
    if received:
        print(f"\n-- Received chain ({len(received)} hops, most recent first)")
        for i, v in enumerate(received, 1):
            print(f"{i:2d}. {' '.join(str(v).split())}")

    print("\n-- MIME structure")
    links = {}
    attachments = []
    for part in msg.walk():
        ctype = part.get_content_type()
        fname = part.get_filename()
        disp = part.get_content_disposition()
        if part.is_multipart():
            print(f"  {ctype}")
            continue
        payload = part.get_payload(decode=True) or b""
        print(f"  {ctype}  {len(payload)} bytes"
              + (f"  [{disp}]" if disp else "")
              + (f"  name={fname!r}" if fname else ""))
        if fname or disp == "attachment" or not ctype.startswith("text/"):
            attachments.append((fname, ctype, payload))
            continue
        text = body_text(part)
        if ctype == "text/html":
            for href, label in HREF_RE.findall(text):
                label = " ".join(TAG_RE.sub("", label).split())[:80]
                links.setdefault(href, label)
        for url in URL_RE.findall(text):
            links.setdefault(url, "")

    print(f"\n-- Links in the body ({len(links)})")
    for url, label in links.items():
        print(f"  {url}" + (f"   <- text: {label!r}" if label else ""))

    print(f"\n-- Attachments ({len(attachments)})")
    for i, (fname, ctype, payload) in enumerate(attachments, 1):
        sha = hashlib.sha256(payload).hexdigest()
        print(f"  {i}. {fname!r}  {ctype}  {len(payload)} bytes  sha256={sha}")
        if args.extract:
            path = os.path.join(args.extract, safe_name(fname, i))
            with open(path, "wb") as out:
                out.write(payload)


if __name__ == "__main__":
    main()
