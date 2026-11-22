"""Rule-based phishing detector: parses an email and flags common phishing indicators."""

import re
import sys
from email import message_from_string
from urllib.parse import urlparse
from difflib import SequenceMatcher
from email.utils import parseaddr

# Matches http/https URLs until whitespace, quotes or angle brackets.
URL_RE = re.compile(r"https?://[^\s\"'<>]+")
# Matches a hostname that is a raw IPv4 address, e.g. 192.168.1.5
IP_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
# Top-level domains frequently abused in phishing campaigns.
SUSPICIOUS_TLDS = {"xyz", "top", "zip", "click", "ru", "tk"}
# Domains of brands that are commonly impersonated in phishing.
TRUSTED_DOMAINS = {
    "paypal.com",
    "microsoft.com",
    "google.com",
    "apple.com",
    "amazon.com",
}

# Pressure and social-engineering phrases, grouped by the tactic they use.
SUSPICIOUS_PHRASES = {
    "urgency": ["urgent", "immediately", "within 24 hours", "act now"],
    "threat": ["suspended", "locked", "unauthorized", "unusual activity"],
    "credentials request": [
        "verify your account",
        "confirm your password",
        "login details",
        "update your payment",
    ],
    "reward": ["you have won", "prize", "gift card"],
}

# File types that can run code when opened.
DANGEROUS_EXTENSIONS = {"exe", "scr", "js", "vbs", "bat", "cmd", "iso", "docm", "xlsm"}
# Harmless-looking types used to disguise a dangerous file (invoice.pdf.exe).
DOCUMENT_EXTENSIONS = {"pdf", "doc", "docx", "xls", "xlsx", "jpg", "png", "txt"}

# Score at or above which an email is classified as phishing.
PHISHING_THRESHOLD = 5
# Score at or above which an email is suspicious and worth a manual look.
SUSPICIOUS_THRESHOLD = 3


def parse_email(text):
    """Parse raw email text into sender, subject, body and attachment names."""
    msg = message_from_string(text)
    body, attachments = "", []
    # walk() covers both simple emails and multipart emails with attachments.
    for part in msg.walk():
        name = part.get_filename()
        if name:
            attachments.append(name)
        elif part.get_content_type() == "text/plain":
            body += part.get_payload()
    return {
        "sender": msg.get("From", ""),
        "subject": msg.get("Subject", ""),
        "body": body,
        "attachments": attachments,
    }


def check_links(body):
    """Flag links that point to an IP address or use a suspicious TLD.

    Returns a list of (indicator, detail, points) tuples.
    """
    findings = []
    for url in URL_RE.findall(body):
        host = urlparse(url).hostname or ""
        if IP_RE.match(host):
            findings.append(("Link uses an IP address", url, 3))
        elif host.split(".")[-1] in SUSPICIOUS_TLDS:
            findings.append(("Link with an uncommon domain ending", url, 2))
    return findings


def check_sender(sender):
    """Flag senders that imitate a trusted brand by domain or display name."""
    findings = []
    name, address = parseaddr(sender)
    domain = address.split("@")[-1].lower()
    for trusted in TRUSTED_DOMAINS:
        # The real domain or one of its subdomains is legitimate.
        if domain == trusted or domain.endswith("." + trusted):
            continue
        if SequenceMatcher(None, domain, trusted).ratio() >= 0.8:
            findings.append(
                (
                    "Sender domain imitates a trusted brand",
                    f"{domain} looks like {trusted}",
                    3,
                )
            )
        elif trusted.split(".")[0] in name.lower():
            findings.append(
                ("Sender name does not match its domain", f"{name} <{address}>", 2)
            )
    return findings


def check_wording(subject, body):
    """Flag social-engineering language, one finding per tactic."""
    findings = []
    text = f"{subject} {body}".lower()
    for category, phrases in SUSPICIOUS_PHRASES.items():
        hits = [phrase for phrase in phrases if phrase in text]
        if hits:
            findings.append((f"Suspicious wording: {category}", ", ".join(hits), 1))
    return findings


def check_attachments(attachments):
    """Flag attachments that can run code or disguise their real type."""
    findings = []
    for name in attachments:
        parts = name.lower().split(".")
        if parts[-1] in DANGEROUS_EXTENSIONS:
            findings.append(("Dangerous attachment type", name, 3))
        if len(parts) > 2 and parts[-2] in DOCUMENT_EXTENSIONS:
            findings.append(("Attachment hides its real type", name, 2))
    return findings


def analyze(text, flagged_before=False):
    """Run every check on a raw email and return findings, score and verdict."""
    parsed = parse_email(text)
    # Each check returns a list, so + joins them into one list of findings.
    findings = (
        check_links(parsed["body"])
        + check_sender(parsed["sender"])
        + check_wording(parsed["subject"], parsed["body"])
        + check_attachments(parsed["attachments"])
    )
    # The caller looks this up in the history database.
    if flagged_before:
        findings.append(("Sender was flagged as phishing before", parsed["sender"], 3))
    # Every finding is (indicator, detail, points); add up the points.
    score = sum(points for _, _, points in findings)
    if score >= PHISHING_THRESHOLD:
        verdict = "phishing"
    elif score >= SUSPICIOUS_THRESHOLD:
        verdict = "suspicious"
    else:
        verdict = "safe"
    return {
        "sender": parsed["sender"],
        "subject": parsed["subject"],
        "findings": findings,
        "score": score,
        "verdict": verdict,
    }


def print_report(result):
    """Print an analysis result in a readable form."""
    print(f"From: {result['sender']}")
    print(f"Subject: {result['subject']}")
    for indicator, detail, points in result["findings"]:
        print(f"  [+{points}] {indicator}: {detail}")
    print(f"Score: {result['score']}  Verdict: {result['verdict'].upper()}")


# Runs only when the file is executed directly, not when it is imported.
if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python detector.py <email_file>")
    with open(sys.argv[1], encoding="utf-8") as f:
        print_report(analyze(f.read()))
