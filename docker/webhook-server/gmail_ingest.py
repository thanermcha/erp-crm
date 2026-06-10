#!/usr/bin/env python3
"""GrowERP Gmail Ingest — Domain-Wide Email Reader.

Uses Google Workspace Domain-Wide Delegation to read emails from
all @blahsoftware.ia.br mailboxes and convert them into leads.

Requires:
  1. Google Cloud Service Account with domain-wide delegation
  2. Scopes: gmail.readonly + admin.directory.user.readonly
  3. Delegated to ainexus@blahsoftware.ia.br

Usage:
  python gmail_ingest.py                        # dry-run
  python gmail_ingest.py --push                  # push to GrowERP
  python gmail_ingest.py --mailbox user@domain   # specific mailbox
"""

import os, sys, json, re, time, logging, argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import requests

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/admin.directory.user.readonly",
]
SERVICE_ACCOUNT_FILE = os.environ.get(
    "GOOGLE_SERVICE_ACCOUNT_FILE", "/app/credentials/google-service-account.json"
)
DELEGATED_ADMIN = os.environ.get("DELEGATED_ADMIN", "ainexus@blahsoftware.ia.br")
MOQUI_URL = os.environ.get("MOQUI_URL", "http://moqui-server:80")
GROWERP_API_KEY = os.environ.get("GROWERP_API_KEY", "")
OWNER_PARTY_ID = os.environ.get("OWNER_PARTY_ID", "BLAH_SOFT_OWNER")
SOURCE_ENUM_ID = "SrcGmail"
DAYS_BACK = int(os.environ.get("GMAIL_DAYS_BACK", "7"))
MAX_MAILBOXES = int(os.environ.get("GMAIL_MAX_MAILBOXES", "50"))
MAX_PER_BOX = int(os.environ.get("GMAIL_MAX_PER_BOX", "20"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("gmail-ingest")


def get_credentials():
    fpath = Path(SERVICE_ACCOUNT_FILE)
    if not fpath.exists():
        log.error("Service account file not found: %s", SERVICE_ACCOUNT_FILE)
        log.error("Place the JSON key and configure domain-wide delegation in Google Admin Console.")
        sys.exit(1)
    creds = service_account.Credentials.from_service_account_file(str(fpath), scopes=SCOPES)
    return creds.with_subject(DELEGATED_ADMIN)


def list_mailboxes(service) -> list[str]:
    log.info("Listing mailboxes via Directory API...")
    mailboxes, page_token = [], None
    try:
        while True:
            results = service.users().list(domain="blahsoftware.ia.br", maxResults=100,
                                           pageToken=page_token, projection="basic").execute()
            for user in results.get("users", []):
                email = user.get("primaryEmail")
                if email:
                    mailboxes.append(email)
            page_token = results.get("nextPageToken")
            if not page_token:
                break
    except HttpError as e:
        log.warning("Directory API error (need Admin SDK): %s. Falling back to %s", e, DELEGATED_ADMIN)
        return [DELEGATED_ADMIN]
    log.info("Found %d mailboxes", len(mailboxes))
    return mailboxes[:MAX_MAILBOXES]


def extract_lead(msg_data: dict, mailbox: str) -> dict | None:
    payload = msg_data.get("payload", {})
    headers = {h["name"].lower(): h["value"] for h in payload.get("headers", [])}
    subject = headers.get("subject", "")
    from_header = headers.get("from", "")
    body = msg_data.get("snippet", "")

    if any(k in from_header.lower() for k in ["noreply", "no-reply", "mailer-daemon", "bounce"]):
        return None

    m = re.match(r'^"?([^"<]*)"?\s*<([^>]+)>', from_header)
    if m:
        sender_name, sender_email = m.group(1).strip(), m.group(2).strip().lower()
    elif "@" in from_header:
        sender_email = from_header.strip().lower()
        sender_name = sender_email.split("@")[0]
    else:
        return None

    internal = ["blahsoftware.ia.br", "blahsoftware.com.br", "growerp.local", "growerp.com"]
    if sender_email.split("@")[1] if "@" in sender_email else "" in internal:
        return None

    free_domains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com", "live.com"]
    domain = sender_email.split("@")[1] if "@" in sender_email else ""
    company = domain.replace(".com","").replace(".br","").replace("."," ").title() if domain not in free_domains else ""

    phone = ""
    pm = re.search(r"(?:(?:\+?55)?[\s-]?)?(?:\(?\d{2}\)?[\s-]?)?\d{4,5}[\s-]?\d{4}", body)
    if pm:
        phone = pm.group(0)

    stage = "OpLead"
    if any(w in subject.lower() for w in ["orcamento", "budget", "preco", "quanto", "valor"]):
        stage = "OpQualified"

    return {
        "firstName": sender_name.split()[0] if sender_name.split() else sender_name,
        "lastName": " ".join(sender_name.split()[1:]) if len(sender_name.split()) > 1 else sender_name,
        "email": sender_email, "phone": phone, "company": company,
        "notes": f"Subject: {subject}\nFrom: {from_header}\nBox: {mailbox}\n\n{body[:500]}",
        "sourceEnumId": SOURCE_ENUM_ID, "opportunityStageId": stage,
    }


def read_mailbox(gmail, mailbox: str) -> list[dict]:
    leads = []
    try:
        query = f"after:{(datetime.now(timezone.utc) - timedelta(days=DAYS_BACK)).strftime('%Y/%m/%d')} is:inbox"
        results = gmail.users().messages().list(userId=mailbox, q=query, maxResults=MAX_PER_BOX).execute()
        for msg in results.get("messages", []):
            try:
                data = gmail.users().messages().get(userId=mailbox, id=msg["id"], format="metadata").execute()
                lead = extract_lead(data, mailbox)
                if lead:
                    leads.append(lead)
            except HttpError:
                continue
    except HttpError as e:
        log.warning("Error reading %s: %s", mailbox, e)
    return leads


def push_to_growerp(leads: list[dict]) -> dict:
    if not leads:
        return {"imported": 0}
    headers = {"Content-Type": "application/json"}
    if GROWERP_API_KEY:
        headers["Authorization"] = f"Bearer {GROWERP_API_KEY}"
    try:
        resp = requests.post(f"{MOQUI_URL}/rest/s1/growerp/100/ImportExport/leads",
                             json={"leads": leads, "ownerPartyId": OWNER_PARTY_ID, "sourceEnumId": SOURCE_ENUM_ID},
                             headers=headers, timeout=60)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        log.error("Push failed: %s", e)
        return {"error": str(e)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--push", action="store_true")
    parser.add_argument("--mailbox", type=str, default=None)
    parser.add_argument("--days-back", type=int, default=DAYS_BACK)
    args = parser.parse_args()

    global DAYS_BACK
    if args.days_back:
        DAYS_BACK = args.days_back

    creds = get_credentials()
    gmail = build("gmail", "v1", credentials=creds)
    admin = build("admin", "directory_v1", credentials=creds)

    mailboxes = [args.mailbox] if args.mailbox else list_mailboxes(admin)
    all_leads = []

    for mb in mailboxes:
        log.info("Reading %s...", mb)
        leads = read_mailbox(gmail, mb)
        if leads:
            log.info("  -> %d leads from %s", len(leads), mb)
            all_leads.extend(leads)
        time.sleep(0.5)

    log.info("Total: %d leads", len(all_leads))
    if args.push and all_leads:
        result = push_to_growerp(all_leads)
        log.info("Push: %s", json.dumps(result, indent=2)[:300])
    elif all_leads:
        log.info("Dry-run. Use --push to send to GrowERP.")
        for l in all_leads[:3]:
            log.info("  %s <%s>", l.get("firstName"), l.get("email"))
    else:
        log.info("No leads found.")


if __name__ == "__main__":
    main()
