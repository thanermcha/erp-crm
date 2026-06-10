#!/usr/bin/env python3
"""Generate all CRM pipeline files for GrowERP."""
import os
import sys
import subprocess
from pathlib import Path

REPO = Path(os.environ.get("REPO_DIR", "/home/moore/growerp"))
DRY_RUN = "--dry-run" in sys.argv

def write(path: str, content: str):
    full = REPO / path
    full.parent.mkdir(parents=True, exist_ok=True)
    if DRY_RUN:
        print(f"[DRY-RUN] Would write {path} ({len(content)} bytes)")
        return
    full.write_text(content.lstrip("\n"))
    print(f"  ✏️  {path}")

def sed_append(path: str, after: str, block: str):
    """Append block after a matching line in an existing file."""
    full = REPO / path
    if DRY_RUN:
        print(f"[DRY-RUN] Would append after '{after}' in {path}")
        return
    text = full.read_text()
    if block.strip() in text:
        print(f"  ⏩ {path}: block already present, skipping")
        return
    text = text.replace(after, after + "\n" + block)
    full.write_text(text)
    print(f"  ✏️  {path} (appended)")

def git_commit(message: str, *paths: str):
    if DRY_RUN:
        print(f"[DRY-RUN] git commit -m '{message[:60]}' + push")
        return
    subprocess.run(["git", "-C", str(REPO), "add", *paths], check=True)
    subprocess.run(["git", "-C", str(REPO), "commit", "-m", message], check=True)
    # push to fork
    subprocess.run(
        ["git", "-C", str(REPO), "push", "fork", "integracao"],
        capture_output=True,
    )
    commit_hash = subprocess.run(
        ["git", "-C", str(REPO), "log", "--oneline", "-1"],
        capture_output=True, text=True,
    ).stdout.strip().split()[0]
    print(f"  ✅ Commit {commit_hash}: {message[:60]}")
    return commit_hash


# ═══════════════════════════════════════════════
# PHASE 1 — Backend: SourceRecord + importLeads
# ═══════════════════════════════════════════════

def phase1():
    print("\n=== PHASE 1: Backend (SourceRecord + importLeads) ===\n")

    # 1.1 - Entity SourceRecord
    block = """
    <!-- ===================== CRM Pipeline ===================== -->

    <entity entity-name="SourceRecord" package="growerp.general" sequence-primary-prefix="sr">
        <field name="sourceRecordId" type="id" is-pk="true" />
        <field name="ownerPartyId" type="id">
            <description>Tenant owner (e.g., BLAH_SOFT_OWNER)</description>
        </field>
        <field name="sourceEnumId" type="id">
            <description>Origin: HubSpot, CSV, Gmail, WordPress, Manual</description>
        </field>
        <field name="rawPayload" type="text-very-long">
            <description>Original JSON payload received</description>
        </field>
        <field name="statusId" type="id">
            <description>staged | hygienized | imported | error | duplicate</description>
        </field>
        <field name="occurrenceCount" type="number-integer" default="1">
            <description>Times this record was received</description>
        </field>
        <field name="sanitizedAt" type="date-time" />
        <field name="importedAt" type="date-time" />
        <field name="partyId" type="id">
            <description>Reference to created/updated Party in GrowERP</description>
        </field>
        <field name="errorFlag" type="text-indicator" />
        <field name="lastErrorMessage" type="text-long" />
        <field name="lastRawPayload" type="text-very-long">
            <description>JSON from most recent occurrence</description>
        </field>
        <relationship type="one" title="Owner" related="mantle.party.Party" short-alias="owner">
            <key-map field-name="ownerPartyId" />
        </relationship>
        <relationship type="one" title="Source" related="moqui.basic.Enumeration" short-alias="sourceType">
            <key-map field-name="sourceEnumId" />
        </relationship>
        <index name="SOURCERECORD_STATUS" unique="false">
            <index-field name="statusId" />
        </index>
        <index name="SOURCERECORD_PARTY" unique="false">
            <index-field name="partyId" />
        </index>
        <seed-data>
            <moqui.basic.EnumerationType description="Source Record Origin"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcHubSpot" description="HubSpot CRM"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcCSV" description="CSV Upload"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcGmail" description="Gmail API Ingest"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcWordPress" description="WordPress Webhook"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcManual" description="Manual Entry"
                enumTypeId="SourceRecordOrigin" />
            <moqui.basic.Enumeration enumId="SrcMeta" description="Facebook Meta Leads"
                enumTypeId="SourceRecordOrigin" />

            <moqui.basic.EnumerationType description="Source Record Status"
                enumTypeId="SourceRecordStatus" />
            <moqui.basic.Enumeration enumId="SrcStaged" description="Received, awaiting processing"
                enumTypeId="SourceRecordStatus" />
            <moqui.basic.Enumeration enumId="SrcHygienized" description="Cleaned and normalized"
                enumTypeId="SourceRecordStatus" />
            <moqui.basic.Enumeration enumId="SrcImported" description="Successfully pushed to GrowERP"
                enumTypeId="SourceRecordStatus" />
            <moqui.basic.Enumeration enumId="SrcError" description="Processing failed"
                enumTypeId="SourceRecordStatus" />
            <moqui.basic.Enumeration enumId="SrcDuplicate" description="Matched existing record, skipped"
                enumTypeId="SourceRecordStatus" />
        </seed-data>
    </entity>
"""
    sed_append("backend/entity/GrowerpEntities.xml", "</entities>", block)

    # 1.2 - Service importLeads
    service_block = '''
    <!-- ====== CRM Pipeline: Bulk Lead Import ====== -->
    <service verb="import" noun="Leads">
        <description>Import leads from CRM pipeline. Accepts JSON array, applies hygiene, dedup, upsert.</description>
        <in-parameters>
            <parameter name="leads" required="true" type="List">
                <parameter name="lead" type="Map">
                    <parameter name="email" type="text-medium" />
                    <parameter name="phone" type="text-medium" />
                    <parameter name="firstName" type="text-medium" />
                    <parameter name="lastName" type="text-medium" />
                    <parameter name="company" type="text-medium" />
                    <parameter name="website" type="text-medium" />
                    <parameter name="sourceEnumId" type="id" />
                    <parameter name="opportunityStageId" type="id" />
                    <parameter name="tags" type="List" />
                    <parameter name="notes" type="text-long" />
                    <parameter name="rawPayload" type="text-very-long" />
                </parameter>
            </parameter>
            <parameter name="ownerPartyId" type="id" />
            <parameter name="sourceEnumId" type="id" default="SrcCSV" />
        </in-parameters>
        <out-parameters>
            <parameter name="leadsImported" type="Integer" />
            <parameter name="leadsUpdated" type="Integer" />
            <parameter name="leadsSkipped" type="Integer" />
            <parameter name="errorMessages" type="text-very-long" />
        </out-parameters>
        <actions>
            <script>System.out.println(">>>> Importing " + leads?.size() + " leads")</script>
            <set field="leadsImported" type="Integer" value="0" />
            <set field="leadsUpdated" type="Integer" value="0" />
            <set field="leadsSkipped" type="Integer" value="0" />
            <set field="errorMessages" type="List" />

            <!-- Resolve owner party -->
            <if condition="!ownerPartyId">
                <service-call name="growerp.100.GeneralServices100.get#RelatedCompanyAndOwner"
                    out-map="context" />
                <set field="ownerPartyId" from="ownerPartyId ?: companyPartyId" />
            </if>
            <if condition="!ownerPartyId">
                <return error="true" message="No ownerPartyId resolved. Provide ownerPartyId or login first." />
            </if>

            <iterate list="leads" entry="lead">
                <script><![CDATA[
                    // Hygiene
                    def email = lead.email?.toString()?.trim()?.toLowerCase()
                    def phone = lead.phone?.toString()?.trim()
                    def firstName = lead.firstName?.toString()?.trim()
                    def lastName = lead.lastName?.toString()?.trim()
                    def company = lead.company?.toString()?.trim()
                    def website = lead.website?.toString()?.trim()

                    // Clean company suffixes
                    if (company) {
                        company = company.replaceAll(/(?i)\\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\\s*\$/, '').trim()
                        if (company.isEmpty()) company = lead.company.toString().trim()
                    }

                    // E.164 phone normalization
                    if (phone) {
                        phone = phone.replaceAll(/[\\s\\-()\\.]/, '')
                        if (phone.startsWith('0') && phone.length() > 2) phone = phone.substring(1)
                        if (!phone.startsWith('+')) {
                            if (phone.length() >= 12) phone = '+' + phone
                            else if (phone.length() >= 10) phone = '+55' + phone
                        }
                    }

                    // Extract domain from email or website
                    def domain = null
                    if (email && email.contains('@') && !email.endsWith('@gmail.com') && !email.endsWith('@yahoo.com') && !email.endsWith('@hotmail.com') && !email.endsWith('@outlook.com')) {
                        domain = email.substring(email.indexOf('@') + 1)
                    }
                    if (!domain && website) {
                        def m = website =~ /https?:\\/\\/(?:www\\.)?([^\\/]+)/
                        if (m) domain = m[0][1]
                    }

                    lead.cleanEmail = email
                    lead.cleanPhone = phone
                    lead.cleanCompany = company
                    lead.cleanDomain = domain
                    lead.cleanFirstName = firstName
                    lead.cleanLastName = lastName ?: firstName
                ]]></script>

                <!-- Dedup: email match -->
                <if condition="lead.cleanEmail">
                    <entity-find entity-name="mantle.party.contact.ContactMech" list="emailMeches">
                        <econdition field-name="contactMechTypeId" value="EmailAddress" />
                        <econdition field-name="infoString" from="lead.cleanEmail" />
                    </entity-find>
                    <if condition="emailMeches">
                        <set field="matchedContactMech" from="emailMeches[0]" />
                    </if>
                </if>

                <!-- Dedup: phone match -->
                <if condition="!matchedContactMech && lead.cleanPhone">
                    <entity-find entity-name="mantle.party.contact.TelecomNumber" list="phoneNums">
                        <econdition field-name="contactNumber" from="lead.cleanPhone" />
                    </entity-find>
                    <if condition="phoneNums">
                        <entity-find entity-name="mantle.party.contact.ContactMech" list="phoneMeches">
                            <econdition field-name="contactMechId" from="phoneNums[0].contactMechId" />
                        </entity-find>
                        <if condition="phoneMeches">
                            <set field="matchedContactMech" from="phoneMeches[0]" />
                        </if>
                    </if>
                </if>

                <!-- Dedup: domain+company match -->
                <if condition="!matchedContactMech && lead.cleanDomain && lead.cleanCompany">
                    <entity-find entity-name="mantle.party.contact.ContactMech" list="webMeches">
                        <econdition field-name="contactMechTypeId" value="WebAddress" />
                        <econdition field-name="infoString" like="%${lead.cleanDomain}%" />
                    </entity-find>
                    <if condition="webMeches">
                        <set field="matchedContactMech" from="webMeches[0]" />
                    </if>
                </if>

                <!-- Resolve partyId or create -->
                <if condition="matchedContactMech">
                    <entity-find entity-name="mantle.party.contact.PartyContactMech" list="partyMeches">
                        <econdition field-name="contactMechId" from="matchedContactMech.contactMechId" />
                        <econdition field-name="thruDate" xsi-nil="true" />
                    </entity-find>
                    <if condition="partyMeches">
                        <set field="partyId" from="partyMeches[0].partyId" />
                    </if>
                </if>

                <if condition="partyId">
                    <!-- UPDATE existing party -->
                    <set field="leadsUpdated" from="leadsUpdated + 1" />
                    <script>System.out.println(">>>> UPDATING party " + partyId + " from lead: " + lead.cleanEmail)</script>
                <else>
                    <!-- CREATE new Person -->
                    <service-call name="create#mantle.party.Person" in-map="[ownerPartyId:ownerPartyId, firstName:lead.cleanFirstName, lastName:(lead.cleanLastName ?: lead.cleanFirstName)]" out-map="personResult" />
                    <set field="partyId" from="personResult.partyId" />

                    <!-- Create email ContactMech -->
                    <if condition="lead.cleanEmail">
                        <service-call name="create#mantle.party.contact.ContactMech" in-map="[contactMechTypeId:'EmailAddress', infoString:lead.cleanEmail]" out-map="contactMechResult" />
                        <service-call name="create#mantle.party.contact.PartyContactMech" in-map="[partyId:partyId, contactMechId:contactMechResult.contactMechId, contactMechPurposeId:'PrimaryEmail', fromDate:ec.user.nowTimestamp]" />
                    </if>

                    <!-- Create phone ContactMech -->
                    <if condition="lead.cleanPhone">
                        <service-call name="create#mantle.party.contact.TelecomNumber" in-map="[contactMechTypeId:'TelecomNumber', countryCode:'55', contactNumber:lead.cleanPhone]" out-map="phoneResult" />
                        <service-call name="create#mantle.party.contact.PartyContactMech" in-map="[partyId:partyId, contactMechId:phoneResult.contactMechId, contactMechPurposeId:'PrimaryPhone', fromDate:ec.user.nowTimestamp]" />
                    </if>

                    <!-- Create website ContactMech -->
                    <if condition="lead.website">
                        <service-call name="create#mantle.party.contact.ContactMech" in-map="[contactMechTypeId:'WebAddress', infoString:lead.website]" out-map="webResult" />
                        <service-call name="create#mantle.party.contact.PartyContactMech" in-map="[partyId:partyId, contactMechId:webResult.contactMechId, contactMechPurposeId:'PrimaryWeb', fromDate:ec.user.nowTimestamp]" />
                    </if>

                    <!-- Link to owner organization -->
                    <entity-find entity-name="mantle.party.PartyRelationship" list="existingRel">
                        <econdition field-name="partyIdFrom" from="ownerPartyId" />
                        <econdition field-name="partyIdTo" from="partyId" />
                        <econdition field-name="roleTypeIdFrom" value="Organization" />
                        <econdition field-name="roleTypeIdTo" value="Customer" />
                        <econdition field-name="thruDate" xsi-nil="true" />
                    </entity-find>
                    <if condition="!existingRel">
                        <service-call name="create#mantle.party.PartyRelationship" in-map="[partyIdFrom:ownerPartyId, partyIdTo:partyId, roleTypeIdFrom:'Organization', roleTypeIdTo:'Customer', fromDate:ec.user.nowTimestamp]" />
                    </if>

                    <set field="leadsImported" from="leadsImported + 1" />
                    <script>System.out.println(">>>> CREATED party " + partyId + " from lead: " + lead.cleanEmail)</script>
                </if>

                <!-- Create/Update SalesOpportunity -->
                <if condition="lead.opportunityStageId">
                    <entity-find entity-name="mantle.sales.opportunity.SalesOpportunity" list="existingOpps">
                        <econdition field-name="ownerPartyId" from="ownerPartyId" />
                        <econdition field-name="partyId" from="partyId" />
                        <econdition field-name="opportunityStageId" not-equals="ClosedLost" />
                        <econdition field-name="opportunityStageId" not-equals="ClosedWon" />
                    </entity-find>
                    <if condition="!existingOpps">
                        <service-call name="growerp.100.CrmServices100.create#SalesOpportunity" in-map="[partyId:partyId, opportunityName:((lead.cleanFirstName ?: '') + ' ' + (lead.cleanLastName ?: '') + ' - ' + (lead.cleanCompany ?: 'No Company')), opportunityStageId:lead.opportunityStageId, ownerPartyId:ownerPartyId, description:(lead.notes ?: '')]" />
                    </if>
                </if>

                <!-- Save SourceRecord -->
                <entity-find entity-name="growerp.general.SourceRecord" list="existingSrc">
                    <econdition field-name="sourceEnumId" from="lead.sourceEnumId ?: sourceEnumId" />
                    <econdition field-name="partyId" from="partyId" />
                </entity-find>
                <if condition="existingSrc">
                    <set field="srcRec" from="existingSrc[0]" />
                    <set field="srcRec.occurrenceCount" from="(srcRec.occurrenceCount ?: 0) + 1" />
                    <set field="srcRec.lastRawPayload" from="lead.rawPayload ?: ''" />
                    <entity-update value-field="srcRec" />
                <else>
                    <service-call name="create#growerp.general.SourceRecord" in-map="[ownerPartyId:ownerPartyId, sourceEnumId:(lead.sourceEnumId ?: sourceEnumId), rawPayload:(lead.rawPayload ?: ''), statusId:'SrcImported', partyId:partyId, importedAt:ec.user.nowTimestamp]" />
                </if>
            </iterate>

            <set field="errorMessages" from="errorMessages.join('; ')" />
            <script>System.out.println(">>>> Import complete: " + leadsImported + " created, " + leadsUpdated + " updated, " + leadsSkipped + " skipped")</script>
        </actions>
    </service>
'''
    sed_append("backend/service/growerp/100/ImportExportServices100.xml", "</services>", service_block)

    # 1.3 - REST endpoint
    rest_block = '''
            <resource name="leads">
                <method type="post">
                    <service name="growerp.100.ImportExportServices100.import#Leads" />
                </method>
            </resource>
'''
    sed_append("backend/service/growerp.rest.xml", '<resource name="finalizeImport">', rest_block)

    print("\n--- Phase 1: Committing ---")
    git_commit(
        "feat(crm-pipeline): entidade SourceRecord + servico importLeads\n\n- Entidade SourceRecord com rastreabilidade completa\n- Servico import#Leads com hygiene + dedup hierarquico\n- REST endpoint POST /rest/growerp/100/ImportExport/leads\n- Enum types: SourceRecordOrigin + SourceRecordStatus",
        "backend/entity/GrowerpEntities.xml",
        "backend/service/growerp/100/ImportExportServices100.xml",
        "backend/service/growerp.rest.xml",
    )


# ═══════════════════════════════════════════════
# PHASE 2 — Webhook Server (Flask + SQLite)
# ═══════════════════════════════════════════════

def phase2():
    print("\n=== PHASE 2: Webhook Server (Flask + SQLite) ===\n")

    write("docker/webhook-server/Dockerfile", """FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
RUN mkdir -p /data

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \\
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
""")

    write("docker/webhook-server/requirements.txt", """flask>=3.0,<4
gunicorn>=22,<24
requests>=2.31,<3
python-dotenv>=1.0,<2
google-api-python-client>=2.120,<3
google-auth-oauthlib>=1.2,<2
google-auth-httplib2>=0.2,<1
""")

    write("docker/webhook-server/app.py", '''#!/usr/bin/env python3
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
    cleaned = re.sub(r"[\\s\\-()./]", "", phone)
    if not cleaned.startswith("+"):
        cleaned = "+55" + cleaned if len(cleaned) >= 10 else None
    return cleaned if cleaned and re.match(r"^\\+[1-9]\\d{6,14}$", cleaned) else None


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
        company = re.sub(r"(?i)\\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\\s*$", "", company).strip()
    domain = None
    if email and "@" in email and not re.search(r"@(gmail|yahoo|hotmail|outlook)\\.", email):
        domain = email.split("@")[1]
    if not domain and (record.get("website") or ""):
        m = re.search(r"https?://(?:www\\.)?([^/]+)", record.get("website", ""))
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
''')

    write("docker/webhook-server/.env.example", """# GrowERP Webhook Server — Environment Variables
HMAC_SECRET=your-hubspot-hmac-secret-here
GROWERP_API_KEY=
OWNER_PARTY_ID=BLAH_SOFT_OWNER
MOQUI_URL=http://moqui-server:80
LOG_LEVEL=INFO
PORT=5000
DEBUG=false
""")

    # Update docker-compose-override.yaml
    compose_file = REPO / "docker/docker-compose-override.yaml"
    compose_text = compose_file.read_text()
    webhook_block = """
  # ── Webhook Server: HubSpot ingest -> SQLite staging -> Moqui REST ──
  webhook-server:
    build:
      context: ./webhook-server
    container_name: webhook-server
    restart: unless-stopped
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - ./webhook-server/data:/data
    environment:
      - MOQUI_URL=http://moqui-server:80
      - SQLITE_PATH=/data/source_records.db
      - HMAC_SECRET=${HMAC_SECRET:-}
      - GROWERP_API_KEY=${GROWERP_API_KEY:-}
      - OWNER_PARTY_ID=BLAH_SOFT_OWNER
      - LOG_LEVEL=INFO
      - TZ=America/Belem
    depends_on:
      - moqui-server
"""
    if "webhook-server" not in compose_text:
        compose_text += webhook_block
        compose_file.write_text(compose_text)
        print("  ✏️  docker/docker-compose-override.yaml (appended webhook-server)")
    else:
        print("  ⏩ docker/docker-compose-override.yaml: already has webhook-server")

    # Create docker-compose-openclaw.yaml
    write("docker/docker-compose-openclaw.yaml", """version: "3.8"
services:
  webhook-server:
    networks:
      - meta-agency-stack_meta_net
      - openclaw-lan

networks:
  meta-agency-stack_meta_net:
    external: true
  openclaw-lan:
    external: true
""")

    # Create network connect script
    write("docker/connect-webhook-networks.sh", """#!/usr/bin/env bash
set -euo pipefail
echo "Conectando webhook-server as redes externas..."
for net in meta-agency-stack_meta_net openclaw-ai_openclaw-lan; do
  if docker network inspect "$net" &>/dev/null; then
    docker network connect "$net" webhook-server 2>/dev/null && \\
      echo "  Conectado a $net" || echo "  $net ja conectado"
  else
    echo "  Rede $net nao encontrada (ignore se nao usar)"
  fi
done
""")
    (REPO / "docker/connect-webhook-networks.sh").chmod(0o755)

    print("\n--- Phase 2: Committing ---")
    git_commit(
        "feat(crm-pipeline): webhook-server container Flask + SQLite staging\n\n- Container Flask com endpoints /webhook/hubspot, /webhook/csv, /import/*, /health\n- Staging SQLite com tabelas source_records + import_log\n- Pipeline de higienizacao: E.164 phone, email lowercase\n- Integracao com meta-agency-stack_meta_net + openclaw-lan",
        "docker/webhook-server/",
        "docker/docker-compose-override.yaml",
        "docker/docker-compose-openclaw.yaml",
        "docker/connect-webhook-networks.sh",
    )


# ═══════════════════════════════════════════════
# PHASE 3 — Nginx
# ═══════════════════════════════════════════════

def phase3():
    print("\n=== PHASE 3: Nginx /webhook/ + /import/ + /health ===\n")

    write("docker/nginx/crm-dashboard.conf", """# CRM dashboard + API proxy + Webhook proxy for backend.growerp.local
server {
    listen 80;
    listen 443 ssl;
    server_name backend.growerp.local;

    ssl_certificate /etc/nginx/certs/growerp.local.crt;
    ssl_certificate_key /etc/nginx/certs/growerp.local.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # CRM dashboard static files
    location /crm/ {
        alias /opt/crm-dashboard/;
        index index.html;
        try_files $uri $uri/ /crm/index.html;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Authorization, Content-Type";
    }

    # Webhook proxy -> webhook-server (Flask)
    location /webhook/ {
        proxy_pass http://webhook-server:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        client_max_body_size 20M;
    }

    # Import proxy -> webhook-server
    location /import/ {
        proxy_pass http://webhook-server:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 120s;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
        client_max_body_size 20M;
    }

    # Health check proxy -> webhook-server
    location /health {
        proxy_pass http://webhook-server:5000/health;
        proxy_set_header Host $host;
    }

    # Proxy REST/API calls to Moqui backend
    location / {
        proxy_pass http://moqui-server:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 20M;
    }
}
""")

    print("\n--- Phase 3: Committing ---")
    git_commit(
        "feat(crm-pipeline): nginx rotas /webhook/ + /import/ + /health\n\n- Adiciona location /webhook/ -> webhook-server:5000\n- Adiciona location /import/ -> webhook-server:5000\n- Adiciona location /health -> webhook-server",
        "docker/nginx/crm-dashboard.conf",
    )


# ═══════════════════════════════════════════════
# PHASE 4 — Cloudflare Tunnel
# ═══════════════════════════════════════════════

def phase4():
    print("\n=== PHASE 4: Cloudflare Tunnel ===\n")

    write("docker/setup-cloudflare-tunnel.sh", '''#!/usr/bin/env bash
# Setup Cloudflare Tunnel for GrowERP backend
# Usage: TUNNEL_NAME=growerp-backend bash setup-cloudflare-tunnel.sh
set -euo pipefail

TUNNEL_NAME="${TUNNEL_NAME:-growerp-backend}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-webhooks.blahsoftware.ia.br}"
LOCAL_SERVICE="${LOCAL_SERVICE:-http://localhost:80}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.cloudflared}"

if ! command -v cloudflared &>/dev/null; then
  echo "Instale cloudflared primeiro."
  exit 1
fi

echo "1. Autenticar: cloudflared tunnel login"
cloudflared tunnel login

echo "2. Criar tunnel: $TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME" 2>/dev/null || echo "  Tunnel ja existe"
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk \'{print $1}\')
echo "   ID: $TUNNEL_ID"

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json
ingress:
  - hostname: $TUNNEL_DOMAIN
    service: $LOCAL_SERVICE
  - service: http_status:404
EOF
echo "3. Config: $CONFIG_DIR/config.yml"

echo "4. DNS: cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN"
cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_DOMAIN"

echo "5. Teste: cloudflared tunnel run $TUNNEL_NAME"
echo "   Depois: curl https://$TUNNEL_DOMAIN/health"
echo
echo "Tunnel $TUNNEL_NAME -> $TUNNEL_DOMAIN -> $LOCAL_SERVICE"
''')
    (REPO / "docker/setup-cloudflare-tunnel.sh").chmod(0o755)

    write("docker/cloudflared.service", """[Unit]
Description=Cloudflare Tunnel for GrowERP
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared tunnel run growerp-backend
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
""")

    print("\n--- Phase 4: Committing ---")
    git_commit(
        "feat(crm-pipeline): cloudflare tunnel setup scripts\n\n- Script interativo setup-cloudflare-tunnel.sh\n- Systemd service template cloudflared.service",
        "docker/setup-cloudflare-tunnel.sh",
        "docker/cloudflared.service",
    )


# ═══════════════════════════════════════════════
# PHASE 5 — Google SMTP
# ═══════════════════════════════════════════════

def phase5():
    print("\n=== PHASE 5: Google SMTP ===\n")

    write("docker/configure-smtp.sh", '''#!/usr/bin/env bash
# Configure Google SMTP for GrowERP (ainexus@blahsoftware.ia.br)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose-override.yaml"

echo "Gere um App Password em: https://myaccount.google.com/apppasswords"
echo "App name: GrowERP CRM"
read -rsp "App Password (16 caracteres): " SMTP_PASS
echo
SMTP_PASS_CLEAN="${SMTP_PASS// /}"

cat >> "$COMPOSE_FILE" << EOF

  # SMTP config (Google Workspace)
  moqui-server:
    environment:
      - SMTP_USER=ainexus@blahsoftware.ia.br
      - SMTP_PASSWORD=${SMTP_PASS_CLEAN}
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=587
      - SMTP_STARTTLS=true
      - default_locale=pt_BR
      - default_time_zone=America/Belem
EOF

echo "Reinicie: docker compose -f docker-compose.yaml -f docker-compose-override.yaml restart moqui-server"
echo "Teste: envie um email template via REST API."
''')
    (REPO / "docker/configure-smtp.sh").chmod(0o755)

    print("\n--- Phase 5: Committing ---")
    git_commit(
        "feat(crm-pipeline): google SMTP setup script\n\n- Script configure-smtp.sh para App Password\n- smtp.gmail.com:587 STARTTLS\n- Conta ainexus@blahsoftware.ia.br",
        "docker/configure-smtp.sh",
    )


# ═══════════════════════════════════════════════
# PHASE 6 — Cloudflare Worker (Python/Pyodide)
# ═══════════════════════════════════════════════

def phase6():
    print("\n=== PHASE 6: Cloudflare Worker (Python/Pyodide) ===\n")

    write("workers/webhook-ingest/wrangler.toml", """name = "webhook-ingest"
main = "src/index.py"
compatibility_date = "2025-05-01"
compatibility_flags = ["python_workers"]

[vars]
BACKEND_URL = "https://webhooks.blahsoftware.ia.br"
HMAC_SECRET = ""
OWNER_PARTY_ID = "BLAH_SOFT_OWNER"

[env.production]
vars = { ENVIRONMENT = "production" }

[env.staging]
vars = { ENVIRONMENT = "staging", BACKEND_URL = "https://staging-webhooks.blahsoftware.ia.br" }

routes = [
  { pattern = "webhooks.blahsoftware.ia.br/*", zone_id = "" }
]
""")

    write("workers/webhook-ingest/src/index.py", '''"""
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
    cleaned = re.sub(r"[\\s\\-()./]", "", phone)
    if not cleaned.startswith("+"):
        cleaned = "+55" + cleaned if len(cleaned) >= 10 else None
    return cleaned if cleaned and re.match(r"^\\+[1-9]\\d{6,14}$", cleaned) else None


def hygienize_lead(lead: dict) -> dict:
    result = dict(lead)
    email = (lead.get("email") or "").strip().lower()
    phone = normalize_phone(lead.get("phone") or "")
    company = (lead.get("company") or "").strip()
    first_name = (lead.get("firstName") or lead.get("firstname") or "").strip()
    last_name = (lead.get("lastName") or lead.get("lastname") or "").strip()
    if company:
        company = re.sub(r"(?i)\\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\\s*$", "", company).strip()
    domain = None
    if email and "@" in email and not any(email.endswith(f"@{d}.com") for d in ["gmail","yahoo","hotmail","outlook"]):
        domain = email.split("@")[1]
    if not domain and (lead.get("website") or lead.get("url") or ""):
        m = re.search(r"https?://(?:www\\.)?([^/]+)", lead.get("website") or lead.get("url") or "")
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
''')

    write("workers/webhook-ingest/.env.example", """HMAC_SECRET=your-hubspot-hmac-secret
BACKEND_URL=https://webhooks.blahsoftware.ia.br
OWNER_PARTY_ID=BLAH_SOFT_OWNER
""")

    print("\n--- Phase 6: Committing ---")
    git_commit(
        "feat(crm-pipeline): cloudflare worker webhook-ingest (python/pyodide)\n\n- Worker Python com validacao HMAC HubSpot\n- Higienizacao de leads no edge (E.164, email, empresa)\n- Encaminhamento para webhook-server via Tunnel",
        "workers/webhook-ingest/",
    )


# ═══════════════════════════════════════════════
# PHASE 7 — Gmail API
# ═══════════════════════════════════════════════

def phase7():
    print("\n=== PHASE 7: Gmail API + Domain-Wide Delegation ===\n")

    write("docker/webhook-server/gmail_ingest.py", '''#!/usr/bin/env python3
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

    m = re.match(r'^"?([^"<]*)"?\\s*<([^>]+)>', from_header)
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
    pm = re.search(r"(?:(?:\\+?55)?[\\s-]?)?(?:\\(?\\d{2}\\)?[\\s-]?)?\\d{4,5}[\\s-]?\\d{4}", body)
    if pm:
        phone = pm.group(0)

    stage = "OpLead"
    if any(w in subject.lower() for w in ["orcamento", "budget", "preco", "quanto", "valor"]):
        stage = "OpQualified"

    return {
        "firstName": sender_name.split()[0] if sender_name.split() else sender_name,
        "lastName": " ".join(sender_name.split()[1:]) if len(sender_name.split()) > 1 else sender_name,
        "email": sender_email, "phone": phone, "company": company,
        "notes": f"Subject: {subject}\\nFrom: {from_header}\\nBox: {mailbox}\\n\\n{body[:500]}",
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
''')

    write("docker/webhook-server/credentials/.gitkeep", "")
    gitignore_entry = "\n# Google Service Account credentials\ndocker/webhook-server/credentials/google-service-account.json\n"
    gitignore = REPO / ".gitignore"
    if "google-service-account" not in gitignore.read_text():
        with open(gitignore, "a") as f:
            f.write(gitignore_entry)
        print("  ✏️  .gitignore (added google-service-account)")

    write("docker/setup-gmail-api.sh", '''#!/usr/bin/env bash
# Setup Gmail API Domain-Wide Delegation
set -euo pipefail

CRED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/webhook-server/credentials"
echo "1. Google Cloud Console:"
echo "   - Criar projeto 'GrowERP CRM Integration'"
echo "   - Ativar Gmail API + Admin SDK API"
echo "   - IAM > Service Accounts > criar 'growerp-crm-ingest'"
echo "   - Gerar chave JSON -> $CRED_DIR/google-service-account.json"
echo
echo "2. Google Admin Console (admin.google.com):"
echo "   - Seguranca > Controles de API > Domain-wide Delegation"
echo "   - Client ID do Service Account + escopos:"
echo "     https://www.googleapis.com/auth/gmail.readonly"
echo "     https://www.googleapis.com/auth/admin.directory.user.readonly"
echo "   - Delegar para: ainexus@blahsoftware.ia.br"
echo
echo "3. Teste:"
echo "   docker exec webhook-server python /app/gmail_ingest.py"
echo "   docker exec webhook-server python /app/gmail_ingest.py --push"
''')
    (REPO / "docker/setup-gmail-api.sh").chmod(0o755)

    print("\n--- Phase 7: Committing ---")
    git_commit(
        "feat(crm-pipeline): gmail api ingest - domain-wide delegation\n\n- gmail_ingest.py: le todas as caixas @blahsoftware.ia.br via Gmail API\n- Extracao de leads de emails (nome, email, telefone, empresa)\n- Push para GrowERP via REST importLeads\n- Service Account credentials (gitignored)\n- Script setup-gmail-api.sh com instrucoes",
        "docker/webhook-server/gmail_ingest.py",
        "docker/webhook-server/credentials/.gitkeep",
        ".gitignore",
        "docker/setup-gmail-api.sh",
    )


# ═══════════════════════════════════════════════
# PHASE 8 — Flatpak CRM Blah Software
# ═══════════════════════════════════════════════

def phase8():
    print("\n=== PHASE 8: Flatpak CRM Blah Software ===\n")

    flatpak_dir = "flutter/packages/admin/flatpak"

    write(f"{flatpak_dir}/io.growerp.crm.blah.yml", """id: io.growerp.crm.blah
runtime: org.gnome.Platform
runtime-version: "47"
sdk: org.gnome.Sdk
command: growerp-crm
finish-args:
  - --share=ipc
  - --socket=x11
  - --socket=wayland
  - --share=network
  - --device=dri
  - --filesystem=home
  - --env=GROWERP_API_URL=https://backend.growerp.local/rest/s1/growerp/100

modules:
  - name: growerp-crm
    buildsystem: simple
    build-commands:
      - flutter build linux --release -v
      - install -Dm755 build/linux/*/release/bundle/growerp_crm /app/bin/growerp-crm
      - install -Dm644 io.growerp.crm.blah.metainfo.xml /app/share/metainfo/
      - install -Dm644 io.growerp.crm.blah.desktop /app/share/applications/
      - install -Dm644 io.growerp.crm.blah.png /app/share/icons/hicolor/256x256/apps/
    sources:
      - type: dir
        path: ..
    modules:
      - name: flutter
        buildsystem: simple
        build-commands:
          - git clone https://github.com/flutter/flutter.git -b stable /app/flutter
          - /app/flutter/bin/flutter config --enable-linux-desktop
        sources:
          - type: archive
            url: https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.33.0-stable.tar.xz
            sha256: ""
""")

    write(f"{flatpak_dir}/io.growerp.crm.blah.metainfo.xml", """<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.growerp.crm.blah</id>
  <name>Blah Software CRM</name>
  <summary>GrowERP CRM para Blah Software</summary>
  <developer_name>Blah Software</developer_name>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>CC0-1.0</project_license>
  <description>
    <p>Cliente desktop do GrowERP CRM para Blah Software. Gerencie leads,
    oportunidades, landing pages e campanhas de outreach.</p>
  </description>
  <categories>
    <category>Office</category>
    <category>Business</category>
  </categories>
  <url type="homepage">https://blahsoftware.ia.br</url>
  <releases>
    <release version="1.0.0" date="2026-06-10" />
  </releases>
</component>
""")

    write(f"{flatpak_dir}/io.growerp.crm.blah.desktop", """[Desktop Entry]
Name=Blah Software CRM
Comment=GrowERP CRM para Blah Software
Exec=growerp-crm
Icon=io.growerp.crm.blah
Terminal=false
Type=Application
Categories=Office;Business;
StartupNotify=true
""")

    write(f"{flatpak_dir}/Makefile", """APP_ID = io.growerp.crm.blah
BUILD_DIR = build-dir
REPO_DIR = repo

all: build

build:
\tflatpak-builder --force-clean --ccache $(BUILD_DIR) $(APP_ID).yml

install: build
\tflatpak-builder --user --install --force-clean $(BUILD_DIR) $(APP_ID).yml

repo: build
\tflatpak build-export $(REPO_DIR) $(BUILD_DIR)

clean:
\trm -rf $(BUILD_DIR) $(REPO_DIR)

publish: repo
\t@echo "tar -czf $(APP_ID).flatpak repo/"
\t@echo "scp $(APP_ID).flatpak user@host:"
\t@echo "# Client: flatpak install $(APP_ID).flatpak"
""")

    write("docker/setup-flatpak-client.sh", '''#!/usr/bin/env bash
# Setup Ubuntu client for Flatpak CRM Blah Software
SERVER_IP="${1:-192.168.15.100}"
FLATPAK_FILE="${FLATPAK_FILE:-growerp-crm.flatpak}"

echo "1. /etc/hosts..."
for host in backend.growerp.local admin.growerp.local; do
  grep -q "$host" /etc/hosts 2>/dev/null || echo "$SERVER_IP $host" | sudo tee -a /etc/hosts >/dev/null
done

echo "2. SSL Certificate..."
curl -sL "https://backend.growerp.local/certs/growerp.local.crt" -o /tmp/growerp-local.crt 2>/dev/null && \\
  sudo cp /tmp/growerp-local.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates || \\
  echo "  Certificado nao disponivel"

echo "3. Flatpak..."
command -v flatpak &>/dev/null || sudo apt-get install -y flatpak

if [[ -f "$FLATPAK_FILE" ]]; then
  flatpak install --user --assumeyes "$FLATPAK_FILE"
  echo "Instalado! Execute: flatpak run io.growerp.crm.blah"
else
  echo "Copie $FLATPAK_FILE para este diretorio."
fi

echo "Dashboard: https://backend.growerp.local/crm/"
''')
    (REPO / "docker/setup-flatpak-client.sh").chmod(0o755)

    print("\n--- Phase 8: Committing ---")
    git_commit(
        "feat(crm-pipeline): flatpak crm blah software linux desktop\n\n- Manifest Flatpak io.growerp.crm.blah (runtime GNOME 47)\n- AppStream metadata + .desktop file\n- Makefile para build\n- Script setup-flatpak-client.sh para instalacao em Ubuntu",
        str(flatpak_dir),
        "docker/setup-flatpak-client.sh",
    )


# ═══════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════

if __name__ == "__main__":
    phases = {
        1: phase1, 2: phase2, 3: phase3, 4: phase4,
        5: phase5, 6: phase6, 7: phase7, 8: phase8,
    }

    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        phase_num = int(sys.argv[1])
        if phase_num in phases:
            phases[phase_num]()
        else:
            print(f"Phase {phase_num} not found. Use 1-8")
    elif "--all" in sys.argv:
        for i in range(1, 9):
            phases[i]()
            print(f"\n{'='*60}\n")
    else:
        print("Usage: python generate-pipeline-files.py [1-8|--all|--dry-run]")
        print()
        print("Generate all CRM pipeline files for GrowERP.")
        print("  --dry-run  : show what would be done without writing")
        print("  --all      : generate and commit all phases 1-8")
        print("  1-8        : generate and commit a specific phase")
