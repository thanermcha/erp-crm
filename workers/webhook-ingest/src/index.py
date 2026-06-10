"""
Cloudflare Worker — Webhook Ingest (Python/Pyodide)
Receives HubSpot webhooks, validates HMAC, forwards to GrowERP via Tunnel.

Deploy: wrangler deploy
Test:   wrangler dev
"""

import json, hashlib, hmac, re
from urllib.request import Request, urlopen
from urllib.error import URLError

BACKEND_URL = ""
HMAC_SECRET = ""
OWNER_PARTY_ID = "BLAH_SOFT_OWNER"


def validate_hmac(payload: bytes, signature: str | None) -> bool:
    if not HMAC_SECRET or not signature:
        return False
    expected = hmac.new(HMAC_SECRET.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def normalize_phone(phone: str) -> str | None:
    if not phone:
        return None
    cleaned = re.sub(r"[\s\-()./]", "", phone)
    if not cleaned.startswith("+"):
        cleaned = "+55" + cleaned if len(cleaned) >= 10 else None
    return cleaned if cleaned and re.match(r"^\+[1-9]\d{6,14}$", cleaned) else None


def hygienize_lead(lead: dict) -> dict:
    result = dict(lead)
    email = (lead.get("email") or "").strip().lower()
    phone = normalize_phone(lead.get("phone") or "")
    company = (lead.get("company") or "").strip()
    first_name = (lead.get("firstName") or lead.get("firstname") or "").strip()
    last_name = (lead.get("lastName") or lead.get("lastname") or "").strip()
    if company:
        company = re.sub(r"(?i)\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\s*$", "", company).strip()
    domain = None
    if email and "@" in email and not any(email.endswith(f"@{d}.com") for d in ["gmail","yahoo","hotmail","outlook"]):
        domain = email.split("@")[1]
    if not domain and (lead.get("website") or lead.get("url") or ""):
        m = re.search(r"https?://(?:www\.)?([^/]+)", lead.get("website") or lead.get("url") or "")
        if m: domain = m.group(1)
    result.update(cleanEmail=email, cleanPhone=phone, cleanCompany=company,
                  cleanDomain=domain, cleanFirstName=first_name,
                  cleanLastName=last_name or first_name)
    return result


async def on_request(request):
    url = request.url
    if request.method == "OPTIONS":
        return Response(status=204, headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, X-HubSpot-Signature",
            "Access-Control-Max-Age": "86400",
        })
    if request.method != "POST":
        return Response(json.dumps({"error": "Method not allowed"}), status=405,
                        headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"})
    if url.path in ("/health", "/"):
        return Response(json.dumps({"status": "ok", "worker": "webhook-ingest"}),
                        headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"})

    payload_bytes = await request.body()
    signature = request.headers.get("X-HubSpot-Signature") or request.headers.get("X-HubSpot-Signature-v3")
    if HMAC_SECRET and signature and not validate_hmac(payload_bytes, signature):
        return Response(json.dumps({"error": "Invalid HMAC"}), status=401,
                        headers={"Content-Type": "application/json"})

    try:
        data = json.loads(payload_bytes)
    except json.JSONDecodeError:
        return Response(json.dumps({"error": "Invalid JSON"}), status=400,
                        headers={"Content-Type": "application/json"})

    leads = data if isinstance(data, list) else [data]
    hygienized = [hygienize_lead(l) for l in leads]

    backend_resp = {"staged": False}
    if BACKEND_URL:
        try:
            fp = json.dumps({"leads": hygienized, "ownerPartyId": OWNER_PARTY_ID}).encode()
            req = Request(f"{BACKEND_URL}/webhook/hubspot", data=fp,
                          headers={"Content-Type": "application/json"}, method="POST")
            resp = urlopen(req, timeout=10)
            backend_resp = json.loads(resp.read())
        except URLError as e:
            backend_resp = {"error": str(e)}

    return Response(json.dumps({"received": len(leads), "hygienized": len(hygienized), "backend": backend_resp}),
                    headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"})


async def fetch(request):
    return await on_request(request)
