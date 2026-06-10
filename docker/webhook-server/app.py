#!/usr/bin/env python3
"""GrowERP Webhook Server — Flask + SQLite staging.

Receives webhooks from HubSpot (via Cloudflare Worker), validates HMAC,
stores in staging SQLite, processes (hygiene + dedup), and pushes to
GrowERP Moqui backend via REST API.

Endpoints:
  POST /webhook/hubspot  — receive HubSpot webhook events
  POST /webhook/csv      — receive CSV file upload
  POST /import/leads     — proxy to Moqui REST API
  POST /import/sync      — process all staged records
  GET  /health           — healthcheck
  GET  /staging/status   — queue status
"""

import os, sys, json, hashlib, hmac, sqlite3, re, csv, io, logging
from datetime import datetime, timezone
from pathlib import Path

import requests
from flask import Flask, request, jsonify, g

SQLITE_PATH = os.environ.get("SQLITE_PATH", "/data/source_records.db")
MOQUI_URL = os.environ.get("MOQUI_URL", "http://moqui-server:80")
HMAC_SECRET = os.environ.get("HMAC_SECRET", "")
GROWERP_API_KEY = os.environ.get("GROWERP_API_KEY", "")
OWNER_PARTY_ID = os.environ.get("OWNER_PARTY_ID", "BLAH_SOFT_OWNER")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logging.basicConfig(level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
log = logging.getLogger("webhook-server")
app = Flask(__name__)


def get_db():
    if "db" not in g:
        Path(SQLITE_PATH).parent.mkdir(parents=True, exist_ok=True)
        g.db = sqlite3.connect(SQLITE_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute("""
            CREATE TABLE IF NOT EXISTS source_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                owner_party_id TEXT NOT NULL,
                raw_payload TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'staged',
                occurrence_count INTEGER DEFAULT 1,
                sanitized_at TIMESTAMP,
                imported_at TIMESTAMP,
                party_id TEXT,
                error_flag BOOLEAN DEFAULT 0,
                last_error_message TEXT,
                last_raw_payload TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        g.db.execute("""
            CREATE TABLE IF NOT EXISTS import_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_record_id INTEGER,
                batch_size INTEGER,
                created INTEGER,
                updated INTEGER,
                skipped INTEGER,
                errors TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        g.db.commit()
    return g.db


@app.teardown_appcontext
def close_db(exception):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def validate_hmac(payload: bytes, signature: str | None) -> bool:
    if not HMAC_SECRET or not signature:
        return bool(HMAC_SECRET) is False  # allow if no secret configured
    expected = hmac.new(HMAC_SECRET.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def normalize_phone(phone: str) -> str | None:
    if not phone:
        return None
    cleaned = re.sub(r"[\s\-()./]", "", phone)
    if not cleaned.startswith("+"):
        cleaned = "+55" + cleaned if len(cleaned) >= 10 else None
    return cleaned if cleaned and re.match(r"^\+[1-9]\d{6,14}$", cleaned) else None


def stage_record(source: str, payload: dict) -> int:
    db = get_db()
    raw_json = json.dumps(payload, ensure_ascii=False)
    cur = db.execute(
        "INSERT INTO source_records (source, owner_party_id, raw_payload, last_raw_payload, status) VALUES (?, ?, ?, ?, 'staged')",
        (source, OWNER_PARTY_ID, raw_json, raw_json),
    )
    db.commit()
    return cur.lastrowid


def stage_records_bulk(source: str, records: list[dict]) -> int:
    db = get_db()
    count = 0
    for rec in records:
        raw_json = json.dumps(rec, ensure_ascii=False)
        db.execute(
            "INSERT INTO source_records (source, owner_party_id, raw_payload, last_raw_payload, status) VALUES (?, ?, ?, ?, 'staged')",
            (source, OWNER_PARTY_ID, raw_json, raw_json),
        )
        count += 1
    db.commit()
    return count


def hygienize_record(record: dict) -> dict:
    result = dict(record)
    email = (record.get("email") or "").strip().lower()
    phone = normalize_phone(record.get("phone") or "")
    company = (record.get("company") or "").strip()
    first_name = (record.get("firstName") or record.get("firstname") or "").strip()
    last_name = (record.get("lastName") or record.get("lastname") or "").strip()
    if company:
        company = re.sub(r"(?i)\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\s*$", "", company).strip()
    domain = None
    if email and "@" in email and not re.search(r"@(gmail|yahoo|hotmail|outlook)\.", email):
        domain = email.split("@")[1]
    if not domain and (record.get("website") or ""):
        m = re.search(r"https?://(?:www\.)?([^/]+)", record.get("website", ""))
        if m: domain = m.group(1)
    result.update(cleanEmail=email, cleanPhone=phone, cleanCompany=company,
                  cleanDomain=domain, cleanFirstName=first_name,
                  cleanLastName=last_name or first_name)
    return result


def push_to_growerp(leads: list[dict]) -> dict:
    url = f"{MOQUI_URL}/rest/s1/growerp/100/ImportExport/leads"
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if GROWERP_API_KEY:
        headers["Authorization"] = f"Bearer {GROWERP_API_KEY}"
    payload = {"leads": leads, "ownerPartyId": OWNER_PARTY_ID, "sourceEnumId": "SrcCSV"}
    try:
        resp = requests.post(url, json=payload, headers=headers, timeout=60)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        log.error(f"Push failed: {e}")
        if hasattr(e, "response") and e.response is not None:
            log.error(f"Response: {e.response.text[:500]}")
        return {"error": str(e)}


def process_staged_records(limit: int = 100) -> dict:
    db = get_db()
    rows = db.execute(
        "SELECT * FROM source_records WHERE status = 'staged' ORDER BY created_at ASC LIMIT ?",
        (limit,),
    ).fetchall()
    if not rows:
        return {"processed": 0, "message": "No staged records"}
    leads = []
    for row in rows:
        try:
            payload = json.loads(row["raw_payload"])
        except json.JSONDecodeError:
            db.execute("UPDATE source_records SET status='error', error_flag=1, last_error_message='Invalid JSON' WHERE id=?", (row["id"],))
            db.commit()
            continue
        leads.append(hygienize_record(payload))
    if not leads:
        return {"processed": 0, "message": "All records had errors"}
    result = push_to_growerp(leads)
    for row in rows:
        db.execute("UPDATE source_records SET status='imported', imported_at=? WHERE id=? AND status='staged'",
                   (datetime.now(timezone.utc).isoformat(), row["id"]))
    db.execute("INSERT INTO import_log (batch_size, created, updated, skipped, errors) VALUES (?,?,?,?,?)",
               (len(rows), result.get("leadsImported", 0), result.get("leadsUpdated", 0),
                result.get("leadsSkipped", 0), result.get("errorMessages", "")))
    db.commit()
    return {"processed": len(rows), "imported": result.get("leadsImported", 0),
            "updated": result.get("leadsUpdated", 0), "skipped": result.get("leadsSkipped", 0)}


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()})


@app.route("/webhook/hubspot", methods=["POST"])
def webhook_hubspot():
    signature = request.headers.get("X-HubSpot-Signature") or request.headers.get("X-HubSpot-Signature-v3")
    payload = request.get_data()
    if HMAC_SECRET and not validate_hmac(payload, signature):
        return jsonify({"error": "Invalid signature"}), 401
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    if isinstance(data, list):
        count = stage_records_bulk("hubspot", data)
    else:
        count = stage_record("hubspot", data)
        count = 1
    return jsonify({"staged": count, "status": "queued"}), 202


@app.route("/webhook/csv", methods=["POST"])
def webhook_csv():
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400
    file = request.files["file"]
    content = file.read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(content))
    records = [{"email": r.get("email",""), "phone": r.get("phone",""),
                "firstName": r.get("firstName","") or r.get("first_name","") or r.get("nome",""),
                "lastName": r.get("lastName","") or r.get("last_name",""),
                "company": r.get("company","") or r.get("empresa",""),
                "website": r.get("website","") or r.get("site",""),
                "rawPayload": json.dumps(r, ensure_ascii=False)} for r in reader]
    count = stage_records_bulk("csv", records)
    if request.form.get("process", "true").lower() == "true" and count > 0:
        result = process_staged_records(count)
        return jsonify({"staged": count, "processed": result}), 202
    return jsonify({"staged": count, "status": "queued"}), 202


@app.route("/import/leads", methods=["POST"])
def import_leads_proxy():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    result = push_to_growerp(data.get("leads", [data]))
    return jsonify(result), (200 if "error" not in result else 502)


@app.route("/import/sync", methods=["POST"])
def import_sync():
    limit = request.args.get("limit", 100, type=int)
    return jsonify(process_staged_records(limit)), 200


@app.route("/staging/status", methods=["GET"])
def staging_status():
    db = get_db()
    counts = {}
    for status in ("staged", "hygienized", "imported", "error"):
        row = db.execute("SELECT COUNT(*) as c FROM source_records WHERE status = ?", (status,)).fetchone()
        counts[status] = row["c"] if row else 0
    return jsonify({"counts": counts})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=os.environ.get("DEBUG", "").lower() == "true")
