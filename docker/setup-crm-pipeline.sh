#!/usr/bin/env bash
# GrowERP CRM Pipeline Setup — Wizard Interativo
# Uso: bash docker/setup-crm-pipeline.sh [--phase N] [--dry-run] [--status]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKPOINT_FILE="/tmp/.crm-pipeline-checkpoint"
DRY_RUN=0
SKIP_PHASE=""

# ── Cores ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo '╔══════════════════════════════════════════════════════════════╗'
  echo '║               GrowERP CRM Pipeline Setup                     ║'
  echo '║         Integração HubSpot → Webhook → GrowERP               ║'
  echo '╚══════════════════════════════════════════════════════════════╝'
  echo -e "${NC}"
}

die() { echo -e "${RED}⛔ $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
info() { echo -e "${BLUE}ℹ $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }

step() {
  local num="$1" title="$2"; shift 2
  echo
  echo -e "${CYAN}╔═══ Passo ${num} — ${title} ${NC}"
  echo -e "${CYAN}║${NC}"
  for line in "$@"; do echo -e "${CYAN}║${NC}  $line"; done
  echo -e "${CYAN}╚══════════════════════════════════════════════════${NC}"
}

confirm() {
  local prompt="$1" answer
  echo -ne "${YELLOW}❓ $prompt [Y/n] ${NC}"
  read -r answer
  [[ -z "$answer" || "$answer" =~ ^[YySs] ]] && return 0
  return 1
}

explain() {
  local title="$1" text="$2"
  echo
  echo -e "${BLUE}📖 $title${NC}"
  echo "$text" | fold -s -w 72 | sed 's/^/   /'
  echo
}

safe_run() {
  local step_name="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}  [dry-run]${NC} $*"
    return 0
  fi
  if "$@"; then
    ok "$step_name"
  else
    warn "$step_name FALHOU (exit code $?)"
    echo -n "  [R]etentar [P]ular [C]ancelar [V]er log? "
    read -r choice
    case "$choice" in
      R|r) safe_run "$step_name" "$@" ;;
      P|p) warn "Pulando $step_name..." ;;
      C|c) die "Cancelado pelo usuário" ;;
      V|v) [[ -f /tmp/crm-setup-errors.log ]] && tail -20 /tmp/crm-setup-errors.log
           safe_run "$step_name" "$@" ;;
    esac
  fi
}

checkpoint_save() {
  local phase="$1" status="$2" commit="$3"
  local data
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    data="$(cat "$CHECKPOINT_FILE")"
  else
    data='{"version":1,"phases":{}}'
  fi
  python3 -c "
import json, sys
d = json.loads('$data' if isinstance('$data', str) else '$data' if isinstance('$data', str) else '''$data''')
d['phases']['$phase'] = {'status': '$status', 'commit': '$commit', 'timestamp': '$(date -Iseconds)'}
json.dump(d, sys.stdout)
" > "$CHECKPOINT_FILE"
  ok "Checkpoint $phase salvo ($status)"
}

checkpoint_load() {
  if [[ ! -f "$CHECKPOINT_FILE" ]]; then return 1; fi
  python3 -c "
import json
d = json.load(open('$CHECKPOINT_FILE'))
for p, v in d['phases'].items():
    print(f\"  {p}: {v['status']} (commit: {v.get('commit','—')})\")
"
}

git_commit_and_push() {
  local msg="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}  [dry-run] git commit -m '$msg' + push${NC}"
    return 0
  fi
  git -C "$REPO_DIR" add "$@"
  git -C "$REPO_DIR" commit -m "$msg"
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git -C "$REPO_DIR" push fork integracao 2>&1 | tail -1
}

verify_url() {
  local url="$1" expected="${2:-200}"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}  [dry-run] curl -so /dev/null -w '%{http_code}' $url${NC}"
    return 0
  fi
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo '000')"
  if [[ "$code" == "$expected" ]]; then
    ok "GET $url → $code"
  else
    warn "GET $url → $code (esperava $expected)"
  fi
}

# ═══════════════════════════════════════════════
# PRÉ-REQUISITOS
# ═══════════════════════════════════════════════

check_prereqs() {
  echo
  info "Verificando pré-requisitos..."
  echo

  local ok=true

  command -v docker &>/dev/null && ok "docker encontrado" || { warn "docker não encontrado"; ok=false; }
  command -v git &>/dev/null && ok "git encontrado" || { warn "git não encontrado"; ok=false; }
  command -v python3 &>/dev/null && ok "python3 encontrado" || { warn "python3 não encontrado"; ok=false; }

  if git -C "$REPO_DIR" remote get-url fork &>/dev/null; then
    ok "remote 'fork' configurado"
  else
    warn "remote 'fork' não configurado. Use: git remote add fork git@github.com:thanermcha/erp-crm.git"
  fi

  if command -v cloudflared &>/dev/null; then
    ok "cloudflared encontrado"
  else
    warn "cloudflared não encontrado (opcional — necessário Fase 4)"
  fi

  if command -v wrangler &>/dev/null; then
    ok "wrangler encontrado"
  else
    warn "wrangler não encontrado (opcional — necessário Fase 6)"
  fi

  if command -v flatpak &>/dev/null; then
    ok "flatpak encontrado"
  else
    warn "flatpak não encontrado (opcional — necessário Fase 8)"
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^nginx$'; then
    ok "nginx container rodando"
  else
    warn "nginx container não está rodando"
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^moqui$'; then
    ok "moqui container rodando"
  else
    warn "moqui container não está rodando"
  fi

  echo
  if $ok; then
    ok "Pré-requisitos OK"
  else
    warn "Alguns pré-requisitos faltando — resolva antes de prosseguir"
  fi
  echo
}

# ═══════════════════════════════════════════════
# FASE 1 — BACKEND (SourceRecord + import#Leads)
# ═══════════════════════════════════════════════

phase_1_backend() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 1 — Entidade SourceRecord + Serviço import#Leads${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Entidade SourceRecord" \
"Tabela no PostgreSQL que rastreia cada lead recebido de fontes externas.
Mantém: UUID único, tenant dono (ownerPartyId), origem (HubSpot/CSV/Gmail),
payload JSON original, status do pipeline (staged→hygienized→imported→error),
e referência ao partyId criado no GrowERP."

  explain "Serviço import#Leads" \
"Endpoint REST que recebe JSON de leads, aplica higienização (E.164, email
lowercase, normalização de empresa), deduplicação hierárquica
(email→telefone→domínio+empresa), e upsert em Party + ContactMech +
SalesOpportunity."

  step "1.1" "Criar entidade SourceRecord em GrowerpEntities.xml"
  if confirm "Criar entidade SourceRecord?"; then
    safe_run "Criando entidade" cp "$REPO_DIR/backend/entity/GrowerpEntities.xml" "$REPO_DIR/backend/entity/GrowerpEntities.xml.bak"
    cat >> "$REPO_DIR/backend/entity/GrowerpEntities.xml" << 'EOF'

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
EOF
  fi

  step "1.2" "Adicionar serviço import#Leads ao ImportExportServices100.xml"
  if confirm "Adicionar serviço import#Leads?"; then
    safe_run "Adicionando serviço leads" bash -c "
cat >> '$REPO_DIR/backend/service/growerp/100/ImportExportServices100.xml' << 'SERVICEEOF'

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
            <script>System.out.println(\">>>> Importing \${leads?.size()} leads\")</script>
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
                    // ── Hygiene ──
                    def email = lead.email?.toString()?.trim()?.toLowerCase()
                    def phone = lead.phone?.toString()?.trim()
                    def firstName = lead.firstName?.toString()?.trim()
                    def lastName = lead.lastName?.toString()?.trim()
                    def company = lead.company?.toString()?.trim()
                    def website = lead.website?.toString()?.trim()

                    // Clean company suffixes
                    if (company) {
                        company = company.replaceAll(/(?i)\s*(LTDA|S\/?A|ME|EPP|EIRELI|SS?)\s*$/, '').trim()
                        if (company.isEmpty()) company = lead.company.toString().trim()
                    }

                    // E.164 phone normalization
                    if (phone) {
                        phone = phone.replaceAll(/[\\s\\-()\\.]/, '')
                        if (phone.startsWith('0') && phone.length() > 2) phone = phone.substring(1)
                        if (!phone.startsWith('+')) {
                            if (phone.length() >= 12) phone = '+' + phone  // assume already with country code
                            else if (phone.length() >= 10) phone = '+55' + phone  // default BR
                        }
                    }

                    // Extract domain from email or website
                    def domain = null
                    if (email && email.contains('@') && !email.endsWith('@gmail.com') && !email.endsWith('@yahoo.com') && !email.endsWith('@hotmail.com') && !email.endsWith('@outlook.com')) {
                        domain = email.substring(email.indexOf('@') + 1)
                    }
                    if (!domain && website) {
                        def m = website =~ /https?:\/\/(?:www\.)?([^\/]+)/
                        if (m) domain = m[0][1]
                    }

                    lead.cleanEmail = email
                    lead.cleanPhone = phone
                    lead.cleanCompany = company
                    lead.cleanDomain = domain
                    lead.cleanFirstName = firstName
                    lead.cleanLastName = lastName ?: firstName
                ]]></script>

                <!-- ── Dedup: email match ── -->
                <if condition="lead.cleanEmail">
                    <entity-find entity-name="mantle.party.contact.ContactMech" list="emailMeches">
                        <econdition field-name="contactMechTypeId" value="EmailAddress" />
                        <econdition field-name="infoString" from="lead.cleanEmail" />
                    </entity-find>
                    <if condition="emailMeches">
                        <set field="matchedContactMech" from="emailMeches[0]" />
                    </if>
                </if>

                <!-- ── Dedup: phone match ── -->
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

                <!-- ── Dedup: domain+company match ── -->
                <if condition="!matchedContactMech && lead.cleanDomain && lead.cleanCompany">
                    <entity-find entity-name="mantle.party.contact.ContactMech" list="webMeches">
                        <econdition field-name="contactMechTypeId" value="WebAddress" />
                        <econdition field-name="infoString" like="%${lead.cleanDomain}%" />
                    </entity-find>
                    <if condition="webMeches">
                        <!-- found by website match, try company name too -->
                        <set field="matchedContactMech" from="webMeches[0]" />
                    </if>
                </if>

                <!-- ── Resolve partyId or create ── -->
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
                    <!-- ── UPDATE existing party ── -->
                    <set field="leadsUpdated" from="leadsUpdated + 1" />
                    <script>System.out.println(">>> UPDATING party " + partyId + " from lead: " + lead.cleanEmail)</script>
                <else>
                    <!-- ── CREATE new Person ── -->
                    <service-call name="create#mantle.party.Person" in-map="\"""
                        ownerPartyId: ownerPartyId
                        firstName: lead.cleanFirstName
                        lastName: lead.cleanLastName ?: lead.cleanFirstName
                    \""" out-map="personResult" />
                    <set field="partyId" from="personResult.partyId" />

                    <!-- Create email ContactMech -->
                    <if condition="lead.cleanEmail">
                        <service-call name="create#mantle.party.contact.ContactMech" in-map="\"""
                            contactMechTypeId: EmailAddress
                            infoString: lead.cleanEmail
                        \""" out-map="contactMechResult" />
                        <service-call name="addPartyContactMech" in-map="\"""
                            partyId: partyId
                            contactMechId: contactMechResult.contactMechId
                            contactMechPurposeId: PrimaryEmail
                        \""" />
                    </if>

                    <!-- Create phone ContactMech -->
                    <if condition="lead.cleanPhone">
                        <service-call name="create#mantle.party.contact.TelecomNumber" in-map="\"""
                            contactMechTypeId: TelecomNumber
                            countryCode: lead.cleanPhone.startsWith('+55') ? '55' : lead.cleanPhone.startsWith('+1') ? '1' : ''
                            contactNumber: lead.cleanPhone
                        \""" out-map="phoneResult" />
                        <service-call name="addPartyContactMech" in-map="\"""
                            partyId: partyId
                            contactMechId: phoneResult.contactMechId
                            contactMechPurposeId: PrimaryPhone
                        \""" />
                    </if>

                    <!-- Create website ContactMech -->
                    <if condition="lead.website">
                        <service-call name="create#mantle.party.contact.ContactMech" in-map="\"""
                            contactMechTypeId: WebAddress
                            infoString: lead.website
                        \""" out-map="webResult" />
                        <service-call name="addPartyContactMech" in-map="\"""
                            partyId: partyId
                            contactMechId: webResult.contactMechId
                            contactMechPurposeId: PrimaryWeb
                        \""" />
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
                        <service-call name="create#mantle.party.PartyRelationship" in-map="\"""
                            partyIdFrom: ownerPartyId
                            partyIdTo: partyId
                            roleTypeIdFrom: Organization
                            roleTypeIdTo: Customer
                            fromDate: ec.user.nowTimestamp
                        \""" />
                    </if>

                    <set field="leadsImported" from="leadsImported + 1" />
                    <script>System.out.println(">>> CREATED party " + partyId + " from lead: " + lead.cleanEmail)</script>
                </if>

                <!-- ── Create/Update SalesOpportunity ── -->
                <if condition="lead.opportunityStageId">
                    <entity-find entity-name="mantle.sales.opportunity.SalesOpportunity" list="existingOpps">
                        <econdition field-name="ownerPartyId" from="ownerPartyId" />
                        <econdition field-name="partyId" from="partyId" />
                        <econdition field-name="opportunityStageId" not-equals="ClosedLost" />
                        <econdition field-name="opportunityStageId" not-equals="ClosedWon" />
                    </entity-find>
                    <if condition="!existingOpps">
                        <service-call name="growerp.100.CrmServices100.create#SalesOpportunity" in-map="\"""
                            partyId: partyId
                            opportunityName: (lead.cleanFirstName ?: '') + ' ' + (lead.cleanLastName ?: '') + ' - ' + (lead.cleanCompany ?: 'No Company')
                            opportunityStageId: lead.opportunityStageId
                            ownerPartyId: ownerPartyId
                            description: lead.notes ?: ''
                        \""" />
                    </if>
                </if>

                <!-- ── Save SourceRecord ── -->
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
                    <service-call name="create#growerp.general.SourceRecord" in-map="\"""
                        ownerPartyId: ownerPartyId
                        sourceEnumId: lead.sourceEnumId ?: sourceEnumId
                        rawPayload: lead.rawPayload ?: ''
                        statusId: SrcImported
                        partyId: partyId
                        importedAt: ec.user.nowTimestamp
                    \""" />
                </if>
            </iterate>

            <set field="errorMessages" from="errorMessages.join('; ')" />
            <script>System.out.println(">>> Import complete: " + leadsImported + " created, " + leadsUpdated + " updated, " + leadsSkipped + " skipped")</script>
        </actions>
    </service>
SERVICEEOF
"
  fi

  step "1.3" "Adicionar REST endpoint leads no growerp.rest.xml"
  if confirm "Adicionar endpoint REST /ImportExport/leads?"; then
    safe_run "Adicionando endpoint leads" bash -c "
sed -i '/<resource name=\"finalizeImport\">/,/<\\/resource>/a\\
            <resource name=\"leads\">\
                <method type=\"post\">\
                    <service name=\"growerp.100.ImportExportServices100.import#Leads\" />\
                </method>\
            </resource>' '$REPO_DIR/backend/service/growerp.rest.xml'
"
  fi

  step "1.4" "Commit + push Fase 1"
  if confirm "Commitar e pushar Fase 1?"; then
    safe_run "Committing Fase 1" git_commit_and_push \
      "feat(crm-pipeline): entidade SourceRecord + servico importLeads

- Adiciona entidade SourceRecord em growerp.general com rastreabilidade
  completa (origem, status, payload, ocorrencias, referencia partyId)
- Adiciona servico import#Leads com pipeline de higienizacao (E.164, email,
  empresa), deduplicacao hierarquica (email->phone->domain+company) e upsert
- Adiciona REST endpoint POST /rest/growerp/100/ImportExport/leads
- Enum types: SourceRecordOrigin (SrcHubSpot/CSV/Gmail/WordPress/Meta)
- Enum types: SourceRecordStatus (Staged/Hygienized/Imported/Error/Duplicate)" \
      "backend/entity/GrowerpEntities.xml" \
      "backend/service/growerp/100/ImportExportServices100.xml" \
      "backend/service/growerp.rest.xml"
  fi

  checkpoint_save "phase_1_backend" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 1 concluída. Continuar para Fase 2 (Webhook Server)?" && phase_2_webhook_server
}

# ═══════════════════════════════════════════════
# FASE 2 — WEBHOOK SERVER (Flask + SQLite)
# ═══════════════════════════════════════════════

phase_2_webhook_server() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 2 — Webhook Server (Flask + SQLite Staging)${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Webhook Server" \
"Container Flask que recebe webhooks do HubSpot (via Cloudflare Worker + Tunnel),
valida HMAC, salva em staging SQLite, processa (higieniza + dedup) e
encaminha para o Moqui via REST.

Endpoints:
  POST /webhook/hubspot  — recebe payload HubSpot, valida HMAC
  POST /webhook/csv      — recebe CSV multipart
  POST /import/leads     — proxy para Moqui (usado internamente)
  POST /import/sync      — processa registros pendentes no SQLite
  GET  /health           — healthcheck"

  step "2.1" "Criar estrutura docker/webhook-server/"
  if confirm "Criar diretório e arquivos do webhook-server?"; then
    safe_run "Criando diretório" mkdir -p "$REPO_DIR/docker/webhook-server"
    safe_run "Criando .gitkeep" touch "$REPO_DIR/docker/webhook-server/.gitkeep"

    cat > "$REPO_DIR/docker/webhook-server/requirements.txt" << 'EOF'
flask>=3.0,<4
gunicorn>=22,<24
requests>=2.31,<3
python-dotenv>=1.0,<2
google-api-python-client>=2.120,<3
google-auth-oauthlib>=1.2,<2
google-auth-httplib2>=0.2,<1
EOF
    ok "requirements.txt criado"
  fi

  step "2.2" "Criar app.py (Flask webhook server)"
  if confirm "Criar app.py?"; then
    cat > "$REPO_DIR/docker/webhook-server/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
GrowERP Webhook Server — Flask + SQLite staging
================================================
Receives webhooks from HubSpot (via Cloudflare Worker), validates HMAC,
stores in staging SQLite, processes (hygiene + dedup), and pushes to
GrowERP Moqui backend via REST API.

Usage:
    python app.py              # development (port 5000)
    gunicorn app:app           # production
"""

import os
import sys
import json
import hashlib
import hmac
import sqlite3
import re
import csv
import io
import logging
from datetime import datetime, timezone
from pathlib import Path

import requests
from flask import Flask, request, jsonify, g

# ── Config ──
SQLITE_PATH = os.environ.get("SQLITE_PATH", "/data/source_records.db")
MOQUI_URL = os.environ.get("MOQUI_URL", "http://moqui-server:80")
HMAC_SECRET = os.environ.get("HMAC_SECRET", "")
GROWERP_API_KEY = os.environ.get("GROWERP_API_KEY", "")
OWNER_PARTY_ID = os.environ.get("OWNER_PARTY_ID", "BLAH_SOFT_OWNER")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("webhook-server")

app = Flask(__name__)

# ── Database ──

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

# ── HMAC Validation ──

def validate_hmac(payload: bytes, signature: str | None) -> bool:
    """Validate HubSpot HMAC-SHA256 signature."""
    if not HMAC_SECRET or not signature:
        return False
    expected = hmac.new(
        HMAC_SECRET.encode(),
        payload,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)

# ── Phone Hygiene ──

def normalize_phone(phone: str) -> str | None:
    if not phone:
        return None
    cleaned = re.sub(r"[\s\-()./]", "", phone)
    if not cleaned.startswith("+"):
        if len(cleaned) >= 12:
            cleaned = "+" + cleaned
        elif len(cleaned) >= 10:
            cleaned = "+55" + cleaned
        else:
            return None
    # Basic format validation
    if re.match(r"^\+[1-9]\d{6,14}$", cleaned):
        return cleaned
    return None

# ── Staging ──

def stage_record(source: str, payload: dict) -> int:
    """Insert a raw record into staging DB."""
    db = get_db()
    raw_json = json.dumps(payload, ensure_ascii=False)
    cur = db.execute(
        "INSERT INTO source_records (source, owner_party_id, raw_payload, last_raw_payload, status) "
        "VALUES (?, ?, ?, ?, 'staged')",
        (source, OWNER_PARTY_ID, raw_json, raw_json),
    )
    db.commit()
    return cur.lastrowid

def stage_records_bulk(source: str, records: list[dict]) -> int:
    """Bulk insert records into staging."""
    db = get_db()
    count = 0
    for rec in records:
        raw_json = json.dumps(rec, ensure_ascii=False)
        db.execute(
            "INSERT INTO source_records (source, owner_party_id, raw_payload, last_raw_payload, status) "
            "VALUES (?, ?, ?, ?, 'staged')",
            (source, OWNER_PARTY_ID, raw_json, raw_json),
        )
        count += 1
    db.commit()
    return count

# ── Hygiene ──

def hygienize_record(record: dict) -> dict:
    """Clean and normalize lead data."""
    result = dict(record)
    email = (record.get("email") or "").strip().lower()
    phone = normalize_phone(record.get("phone") or "")
    company = (record.get("company") or "").strip()
    website = (record.get("website") or "").strip()
    first_name = (record.get("firstName") or record.get("firstname") or "").strip()
    last_name = (record.get("lastName") or record.get("lastname") or "").strip()

    # Company suffix cleanup
    if company:
        company = re.sub(r"(?i)\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\s*$", "", company).strip()
        if not company:
            company = (record.get("company") or "").strip()

    # Extract domain
    domain = None
    if email and "@" in email and not re.search(r"@(gmail|yahoo|hotmail|outlook)\.", email):
        domain = email.split("@")[1]
    if not domain and website:
        m = re.search(r"https?://(?:www\.)?([^/]+)", website)
        if m:
            domain = m.group(1)

    result["cleanEmail"] = email
    result["cleanPhone"] = phone
    result["cleanCompany"] = company
    result["cleanDomain"] = domain
    result["cleanFirstName"] = first_name
    result["cleanLastName"] = last_name or first_name
    result["cleanWebsite"] = website
    return result

# ── Push to GrowERP ──

def push_to_growerp(leads: list[dict]) -> dict:
    """Push hygienized leads to GrowERP Moqui REST API."""
    url = f"{MOQUI_URL}/rest/s1/growerp/100/ImportExport/leads"
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if GROWERP_API_KEY:
        headers["Authorization"] = f"Bearer {GROWERP_API_KEY}"

    payload = {
        "leads": leads,
        "ownerPartyId": OWNER_PARTY_ID,
        "sourceEnumId": "SrcCSV",
    }

    try:
        resp = requests.post(url, json=payload, headers=headers, timeout=60)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        log.error(f"Push to GrowERP failed: {e}")
        if hasattr(e, "response") and e.response is not None:
            log.error(f"Response: {e.response.text[:500]}")
        return {"error": str(e)}

def process_staged_records(limit: int = 100) -> dict:
    """Process staged records: read, hygienize, dedup, push to GrowERP."""
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
            db.execute("UPDATE source_records SET status = 'error', error_flag = 1, "
                       "last_error_message = 'Invalid JSON' WHERE id = ?", (row["id"],))
            db.commit()
            continue
        hygienized = hygienize_record(payload)
        leads.append(hygienized)

    if not leads:
        return {"processed": 0, "message": "All records had errors"}

    result = push_to_growerp(leads)
    imported = result.get("leadsImported", 0)
    updated = result.get("leadsUpdated", 0)
    skipped = result.get("leadsSkipped", 0)

    for row in rows:
        db.execute(
            "UPDATE source_records SET status = 'imported', imported_at = ? WHERE id = ? AND status = 'staged'",
            (datetime.now(timezone.utc).isoformat(), row["id"]),
        )
    db.execute(
        "INSERT INTO import_log (batch_size, created, updated, skipped, errors) VALUES (?, ?, ?, ?, ?)",
        (len(rows), imported, updated, skipped, result.get("errorMessages", "")),
    )
    db.commit()

    return {
        "processed": len(rows),
        "imported": imported,
        "updated": updated,
        "skipped": skipped,
        "errors": result.get("errorMessages", ""),
    }

# ── Routes ──

@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "sqlite_db": SQLITE_PATH,
        "moqui_url": MOQUI_URL,
    })

@app.route("/webhook/hubspot", methods=["POST"])
def webhook_hubspot():
    """Receive HubSpot webhook events."""
    signature = request.headers.get("X-HubSpot-Signature") or \
                request.headers.get("X-HubSpot-Signature-v3")
    payload = request.get_data()

    if HMAC_SECRET:
        if not validate_hmac(payload, signature):
            log.warning("Invalid HMAC signature from HubSpot")
            return jsonify({"error": "Invalid signature"}), 401

    try:
        data = request.get_json(silent=True)
    except Exception:
        return jsonify({"error": "Invalid JSON"}), 400

    if isinstance(data, list):
        # HubSpot batch format: list of events
        count = stage_records_bulk("hubspot", data)
        return jsonify({"staged": count, "status": "queued"}), 202
    elif isinstance(data, dict):
        record_id = stage_record("hubspot", data)
        return jsonify({"staged": 1, "id": record_id, "status": "queued"}), 202
    else:
        return jsonify({"error": "Unexpected payload format"}), 400

@app.route("/webhook/csv", methods=["POST"])
def webhook_csv():
    """Receive CSV file upload, parse and stage each row."""
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["file"]
    content = file.read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(content))

    records = []
    for row in reader:
        records.append({
            "email": row.get("email", ""),
            "phone": row.get("phone", ""),
            "firstName": row.get("firstName", "") or row.get("first_name", "") or row.get("nome", ""),
            "lastName": row.get("lastName", "") or row.get("last_name", ""),
            "company": row.get("company", "") or row.get("empresa", ""),
            "website": row.get("website", "") or row.get("site", ""),
            "source": "csv",
            "rawPayload": json.dumps(row, ensure_ascii=False),
        })

    count = stage_records_bulk("csv", records)

    # Optionally process immediately
    auto_process = request.form.get("process", "true").lower() == "true"
    if auto_process and count > 0:
        result = process_staged_records(count)
        return jsonify({"staged": count, "processed": result}), 202

    return jsonify({"staged": count, "status": "queued"}), 202

@app.route("/import/leads", methods=["POST"])
def import_leads():
    """Proxy: forward lead JSON directly to Moqui."""
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    result = push_to_growerp(data.get("leads", [data]))
    return jsonify(result), 200 if "error" not in result else 502

@app.route("/import/sync", methods=["POST"])
def import_sync():
    """Process all pending staged records."""
    limit = request.args.get("limit", 100, type=int)
    result = process_staged_records(limit)
    return jsonify(result), 200

@app.route("/staging/status", methods=["GET"])
def staging_status():
    """Get staging queue status."""
    db = get_db()
    counts = {}
    for status in ("staged", "hygienized", "imported", "error"):
        row = db.execute(
            "SELECT COUNT(*) as c FROM source_records WHERE status = ?", (status,)
        ).fetchone()
        counts[status] = row["c"] if row else 0
    return jsonify({"counts": counts})

# ── Main ──

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    debug = os.environ.get("DEBUG", "").lower() == "true"
    log.info(f"Starting GrowERP Webhook Server on :{port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
PYEOF
    ok "app.py criado"
  fi

  step "2.3" "Criar Dockerfile do webhook-server"
  if confirm "Criar Dockerfile?"; then
    cat > "$REPO_DIR/docker/webhook-server/Dockerfile" << 'DOCKERFILE'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN mkdir -p /data

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
DOCKERFILE
    ok "Dockerfile criado"
  fi

  step "2.4" "Atualizar docker-compose-override.yaml"
  local compose_file="$REPO_DIR/docker/docker-compose-override.yaml"
  if confirm "Adicionar serviço webhook-server ao docker-compose?"; then
    cat >> "$compose_file" << 'COMPOSEEOF'

  # ── Webhook Server: HubSpot ingest → SQLite staging → Moqui REST ──
  webhook-server:
    build:
      context: ./webhook-server
    container_name: webhook-server
    restart: unless-stopped
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - ./webhook-server/data:/data
      - ./webhook-server/app.py:/app/app.py:ro
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

networks:
  default:
    name: docker_default
    external: true
COMPOSEEOF
    ok "docker-compose-override.yaml atualizado"
  fi

  step "2.5" "Criar docker-compose-openclaw.yaml (rede meta-stack)"
  local openclaw_file="$REPO_DIR/docker/docker-compose-openclaw.yaml"
  if [[ -f "$openclaw_file" ]]; then
    safe_run "Atualizando openclaw config" bash -c "
if ! grep -q 'webhook-server' '$openclaw_file'; then
  cat >> '$openclaw_file' << 'OPENCLAWEOF'

  webhook-server:
    networks:
      - meta-agency-stack_meta_net
      - openclaw-lan

networks:
  meta-agency-stack_meta_net:
    external: true
OPENCLAWEOF
fi
"
  else
    cat > "$openclaw_file" << 'OPENCLAWEOF'
version: "3.8"
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
OPENCLAWEOF
    ok "docker-compose-openclaw.yaml criado"
  fi

  step "2.6" "Criar arquivo .env.example para segredos"
  cat > "$REPO_DIR/docker/webhook-server/.env.example" << 'ENVEOF'
# GrowERP Webhook Server — Environment Variables
# Copy to .env and fill in secrets

# HMAC secret for HubSpot webhook validation
HMAC_SECRET=your-hubspot-hmac-secret-here

# GrowERP API Key for REST authentication
GROWERP_API_KEY=

# Owner Party ID (tenant)
OWNER_PARTY_ID=BLAH_SOFT_OWNER

# Moqui backend URL
MOQUI_URL=http://moqui-server:80

# Log level: DEBUG, INFO, WARNING, ERROR
LOG_LEVEL=INFO

# Port for Flask
PORT=5000

# Debug mode (true/false)
DEBUG=false
ENVEOF
  ok ".env.example criado"

  step "2.7" "Commit + push Fase 2"
  if confirm "Commitar e pushar Fase 2?"; then
    safe_run "Committing Fase 2" git_commit_and_push \
      "feat(crm-pipeline): webhook-server container Flask + SQLite staging

- Cria container Flask com endpoints:
  POST /webhook/hubspot — recebe webhooks HubSpot com validacao HMAC
  POST /webhook/csv — upload CSV multipart
  POST /import/leads — proxy para Moqui
  POST /import/sync — processa registros pendentes
  GET /health — healthcheck
- Staging SQLite com tabelas source_records + import_log
- Pipeline de higienizacao: E.164 phone, email lowercase, empresa
- Integracao com meta-agency-stack_meta_net + openclaw-lan" \
      "docker/webhook-server/" \
      "docker/docker-compose-override.yaml" \
      "docker/docker-compose-openclaw.yaml"
  fi

  checkpoint_save "phase_2_webhook_server" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 2 concluída. Continuar para Fase 3 (Nginx)?" && phase_3_nginx
}

# ═══════════════════════════════════════════════
# FASE 3 — NGINX (/webhook/ location)
# ═══════════════════════════════════════════════

phase_3_nginx() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 3 — Nginx: location /webhook/ → webhook-server${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Rota /webhook/ no nginx" \
"O Cloudflare Tunnel aponta para nginx:80. Precisamos que /webhook/*
seja roteado para o webhook-server (Flask:5000) enquanto /rest/*
continua indo para o moqui-server (API)."

  step "3.1" "Atualizar crm-dashboard.conf com /webhook/"
  if confirm "Adicionar location /webhook/ no nginx?"; then
    cat > "$REPO_DIR/docker/nginx/crm-dashboard.conf" << 'NGINXEOF'
# CRM dashboard + API proxy + Webhook proxy for backend.growerp.local
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

    # Webhook proxy → webhook-server (Flask)
    location /webhook/ {
        proxy_pass http://webhook-server:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-HubSpot-Signature $http_x_hubspot_signature;

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        client_max_body_size 20M;
    }

    # Import proxy → webhook-server (Flask)
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

    # Health check proxy → webhook-server
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
NGINXEOF
    ok "crm-dashboard.conf atualizado com /webhook/, /import/, /health"
  fi

  step "3.2" "Criar docker network alias para webhook-server"
  if confirm "Criar script de conexão de redes?"; then
    cat > "$REPO_DIR/docker/connect-webhook-networks.sh" << 'NETEOF'
#!/usr/bin/env bash
# Connect webhook-server to external networks
set -euo pipefail

echo "Conectando webhook-server às redes externas..."

# Meta-agency-stack
if docker network inspect meta-agency-stack_meta_net &>/dev/null; then
  docker network connect meta-agency-stack_meta_net webhook-server 2>/dev/null && \
    echo "✅ Conectado a meta-agency-stack_meta_net" || \
    echo "ℹ  já conectado a meta-agency-stack_meta_net"
else
  echo "⚠  Rede meta-agency-stack_meta_net não encontrada (ignore se não usar meta-stack)"
fi

# OpenClaw LAN
if docker network inspect openclaw-ai_openclaw-lan &>/dev/null; then
  docker network connect openclaw-ai_openclaw-lan webhook-server 2>/dev/null && \
    echo "✅ Conectado a openclaw-ai_openclaw-lan" || \
    echo "ℹ  já conectado a openclaw-ai_openclaw-lan"
else
  echo "⚠  Rede openclaw-ai_openclaw-lan não encontrada (ignore se não usar openclaw)"
fi

echo "Redes configuradas."
NETEOF
    chmod +x "$REPO_DIR/docker/connect-webhook-networks.sh"
    ok "connect-webhook-networks.sh criado"
  fi

  step "3.3" "Commit + push Fase 3"
  if confirm "Commitar e pushar Fase 3?"; then
    safe_run "Committing Fase 3" git_commit_and_push \
      "feat(crm-pipeline): nginx rotas /webhook/ + /import/ + /health

- Adiciona location /webhook/ → webhook-server:5000
- Adiciona location /import/ → webhook-server:5000
- Adiciona location /health → webhook-server:5000/health
- Script connect-webhook-networks.sh para redes externas" \
      "docker/nginx/crm-dashboard.conf" \
      "docker/connect-webhook-networks.sh"
  fi

  checkpoint_save "phase_3_nginx" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 3 concluída. Continuar para Fase 4 (Cloudflare Tunnel)?" && phase_4_tunnel
}

# ═══════════════════════════════════════════════
# FASE 4 — CLOUDFLARE TUNNEL
# ═══════════════════════════════════════════════

phase_4_tunnel() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 4 — Cloudflare Tunnel${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Cloudflare Tunnel" \
"Cria um túnel seguro do edge da Cloudflare até o nginx rodando localmente.
O Worker Python webhook-ingest encaminha webhooks através deste túnel.
Tráfego: Internet → Cloudflare Edge → Tunnel → nginx → backend

Requer:
  1. cloudflared instalado
  2. Conta Cloudflare com domínio blahsoftware.ia.br
  3. Autenticação via cloudflared tunnel login"

  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared não encontrado. Instale primeiro:"
    echo "  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb"
    echo "  sudo dpkg -i /tmp/cloudflared.deb"
    echo
    if ! confirm "Pular Fase 4 (Cloudflare Tunnel)?"; then
      return
    fi
  fi

  step "4.1" "Criar script de setup do tunnel"
  cat > "$REPO_DIR/docker/setup-cloudflare-tunnel.sh" << 'TUNEOF'
#!/usr/bin/env bash
# Setup Cloudflare Tunnel for GrowERP backend
# Usage: bash setup-cloudflare-tunnel.sh [--install]
set -euo pipefail

TUNNEL_NAME="${TUNNEL_NAME:-growerp-backend}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-webhooks.blahsoftware.ia.br}"
LOCAL_SERVICE="${LOCAL_SERVICE:-http://localhost:80}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.cloudflared}"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Cloudflare Tunnel Setup — GrowERP Backend       ║"
echo "╚══════════════════════════════════════════════════╝"
echo

if ! command -v cloudflared &>/dev/null; then
  echo "⛔ cloudflared não instalado."
  echo "   Instale: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
  exit 1
fi

# Step 1: Authenticate
echo "📌 PASSO 1: Autenticar cloudflared"
echo "   Será aberto um navegador. Faça login na conta Cloudflare."
echo "   Pressione ENTER para continuar..."
read -r
cloudflared tunnel login

# Step 2: Create tunnel
echo
echo "📌 PASSO 2: Criar tunnel '$TUNNEL_NAME'"
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
  echo "   Tunnel '$TUNNEL_NAME' já existe."
else
  cloudflared tunnel create "$TUNNEL_NAME"
fi

# Get tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
echo "   Tunnel ID: $TUNNEL_ID"

# Step 3: Create config file
echo
echo "📌 PASSO 3: Criar config.yml"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json

ingress:
  - hostname: $TUNNEL_DOMAIN
    service: $LOCAL_SERVICE
  # Health check endpoint
  - service: http_status:404
EOF
echo "   Config saved: $CONFIG_DIR/config.yml"

# Step 4: DNS route
echo
echo "📌 PASSO 4: Criar DNS CNAME"
echo "   cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN"
cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_DOMAIN"

# Step 5: Test
echo
echo "📌 PASSO 5: Testar tunnel"
echo "   Execute em outro terminal: cloudflared tunnel run $TUNNEL_NAME"
echo "   Depois teste: curl -s https://$TUNNEL_DOMAIN/health"
echo
echo "📌 PASSO 6: Instalar como serviço (opcional)"
echo "   sudo cloudflared service install"
echo
echo "✅ Setup concluído! Tunnel: $TUNNEL_NAME → $TUNNEL_DOMAIN → $LOCAL_SERVICE"
TUNEOF
  chmod +x "$REPO_DIR/docker/setup-cloudflare-tunnel.sh"
  ok "setup-cloudflare-tunnel.sh criado"

  step "4.2" "Criar systemd service template"
  cat > "$REPO_DIR/docker/cloudflared.service" << 'SYSDF'
[Unit]
Description=Cloudflare Tunnel for GrowERP
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=%i
ExecStart=/usr/bin/cloudflared tunnel run growerp-backend
Restart=always
RestartSec=5
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
SYSDF
  ok "cloudflared.service template criado"

  step "4.3" "Commit + push Fase 4"
  if confirm "Commitar Fase 4?"; then
    safe_run "Committing Fase 4" git_commit_and_push \
      "feat(crm-pipeline): cloudflare tunnel setup scripts

- Script interativo setup-cloudflare-tunnel.sh
- Systemd service template para cloudflared" \
      "docker/setup-cloudflare-tunnel.sh" \
      "docker/cloudflared.service"
  fi

  checkpoint_save "phase_4_tunnel" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 4 concluída. Continuar para Fase 5 (Google SMTP)?" && phase_5_smtp
}

# ═══════════════════════════════════════════════
# FASE 5 — GOOGLE SMTP
# ═══════════════════════════════════════════════

phase_5_smtp() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 5 — Google SMTP (ainexus@blahsoftware.ia.br)${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Google SMTP" \
"Configura o envio de emails do GrowERP via smtp.gmail.com usando o
App Password da conta ainexus@blahsoftware.ia.br.

O MX do domínio blahsoftware.ia.br já aponta para smtp.google.com
(prioridade 1), confirmado por consulta DNS."

  step "5.1" "Criar script de configuração SMTP"
  cat > "$REPO_DIR/docker/configure-smtp.sh" << 'SMTPEOF'
#!/usr/bin/env bash
# Configure Google SMTP for GrowERP
# Usage: bash configure-smtp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose-override.yaml"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Google SMTP Setup — ainexus@blahsoftware.ia.br ║"
echo "╚══════════════════════════════════════════════════╝"
echo

echo "📌 Antes de continuar, gere um App Password em:"
echo "   https://myaccount.google.com/apppasswords"
echo "   App name: 'GrowERP CRM'"
echo
echo -n "App Password (16 caracteres, espaços opcionais): "
read -rs SMTP_PASS
echo

if [[ -z "$SMTP_PASS" ]]; then
  echo "⛔ Password não pode ser vazio"
  exit 1
fi

# Remove espaços
SMTP_PASS_CLEAN="${SMTP_PASS// /}"

echo
echo "📌 Atualizando docker-compose-override.yaml..."
cat >> "$COMPOSE_FILE" << EOF

  # SMTP config (Google Workspace — ainexus@blahsoftware.ia.br)
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

echo
echo "✅ SMTP configurado! Reinicie o moqui-server:"
echo "   docker compose -f docker-compose.yaml -f docker-compose-override.yaml restart moqui-server"
echo
echo "📌 Teste de envio:"
echo "   curl -sk -X POST 'https://backend.growerp.local/rest/s1/growerp/100/EmailTemplate' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"emailTemplateId\":\"TestEmail\"}'"
SMTPEOF
  chmod +x "$REPO_DIR/docker/configure-smtp.sh"
  ok "configure-smtp.sh criado"

  step "5.2" "Commit + push Fase 5"
  if confirm "Commitar Fase 5?"; then
    safe_run "Committing Fase 5" git_commit_and_push \
      "feat(crm-pipeline): google SMTP setup script

- Script configure-smtp.sh para configurar SMTP_USER/PASSWORD
- smtp.gmail.com:587 com STARTTLS
- Conta ainexus@blahsoftware.ia.br com App Password" \
      "docker/configure-smtp.sh"
  fi

  checkpoint_save "phase_5_smtp" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 5 concluída. Continuar para Fase 6 (Worker Cloudflare)?" && phase_6_worker
}

# ═══════════════════════════════════════════════
# FASE 6 — WORKER CLOUDFLARE (Python/Pyodide)
# ═══════════════════════════════════════════════

phase_6_worker() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 6 — Cloudflare Worker webhook-ingest (Python)${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Worker Cloudflare" \
"Worker em Python (Pyodide) no edge da Cloudflare. Recebe webhooks do
HubSpot, valida HMAC, e reencaminha para o webhook-server via Tunnel.

Vantagens: sem servidor, escala a zero, latência global."

  step "6.1" "Criar estrutura workers/webhook-ingest/"
  if confirm "Criar estrutura do Worker?"; then
    mkdir -p "$REPO_DIR/workers/webhook-ingest/src"
    ok "Estrutura criada"
  fi

  step "6.2" "Criar wrangler.toml"
  if confirm "Criar wrangler.toml?"; then
    cat > "$REPO_DIR/workers/webhook-ingest/wrangler.toml" << 'WREOF'
name = "webhook-ingest"
main = "src/index.py"
compatibility_date = "2025-05-01"
compatibility_flags = ["python_workers"]

[[services]]
binding = "WEBHOOK_BACKEND"
service = "webhook-backend"

[vars]
BACKEND_URL = "https://webhooks.blahsoftware.ia.br"
HMAC_SECRET = ""
OWNER_PARTY_ID = "BLAH_SOFT_OWNER"

[env.production]
vars = { ENVIRONMENT = "production" }

[env.staging]
vars = { ENVIRONMENT = "staging", BACKEND_URL = "https://staging-webhooks.blahsoftware.ia.br" }

# Routes
routes = [
  { pattern = "webhooks.blahsoftware.ia.br/*", zone_id = "" }
]
WREOF
    ok "wrangler.toml criado"
  fi

  step "6.3" "Criar src/index.py (Worker Python)"
  if confirm "Criar Worker Python?"; then
    mkdir -p "$REPO_DIR/workers/webhook-ingest/src"
    cat > "$REPO_DIR/workers/webhook-ingest/src/index.py" << 'PYWEOF'
"""
Cloudflare Worker — Webhook Ingest (Python/Pyodide)
===================================================
Receives webhooks from HubSpot, validates HMAC, forwards to
GrowERP webhook-server via Cloudflare Tunnel.

Deploy: wrangler deploy
Test:   wrangler dev
"""

import json
import hashlib
import hmac
from urllib.request import Request, urlopen
from urllib.error import URLError

BACKEND_URL = ""  # Set via wrangler.toml [vars]
HMAC_SECRET = ""  # Set via wrangler.toml [vars] or wrangler secret put
OWNER_PARTY_ID = "BLAH_SOFT_OWNER"


def validate_hmac(payload: bytes, signature: str | None) -> bool:
    """Validate HubSpot HMAC-SHA256 signature."""
    if not HMAC_SECRET or not signature:
        return False
    expected = hmac.new(
        HMAC_SECRET.encode(),
        payload,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def normalize_phone(phone: str) -> str | None:
    """Normalize phone to E.164."""
    if not phone:
        return None
    import re
    cleaned = re.sub(r"[\s\-()./]", "", phone)
    if not cleaned.startswith("+"):
        if len(cleaned) >= 12:
            cleaned = "+" + cleaned
        elif len(cleaned) >= 10:
            cleaned = "+55" + cleaned
        else:
            return None
    if re.match(r"^\+[1-9]\d{6,14}$", cleaned):
        return cleaned
    return None


def hygienize_lead(lead: dict) -> dict:
    """Clean and normalize lead data."""
    result = dict(lead)
    email = (lead.get("email") or "").strip().lower()
    phone = normalize_phone(lead.get("phone") or "")
    company = (lead.get("company") or "").strip()
    first_name = (lead.get("firstName") or lead.get("firstname") or "").strip()
    last_name = (lead.get("lastName") or lead.get("lastname") or "").strip()

    # Company suffix cleanup
    import re
    if company:
        company = re.sub(r"(?i)\s*(LTDA|S/?A|ME|EPP|EIRELI|SS?)\s*$", "", company).strip()
        if not company:
            company = (lead.get("company") or "").strip()

    # Extract domain
    domain = None
    if email and "@" in email and not any(
        email.endswith(f"@{d}.com") for d in ["gmail", "yahoo", "hotmail", "outlook"]
    ):
        domain = email.split("@")[1]
    if not domain and (lead.get("website") or lead.get("url") or ""):
        website = lead.get("website") or lead.get("url") or ""
        m = re.search(r"https?://(?:www\.)?([^/]+)", website)
        if m:
            domain = m.group(1)

    result["cleanEmail"] = email
    result["cleanPhone"] = phone
    result["cleanCompany"] = company
    result["cleanDomain"] = domain
    result["cleanFirstName"] = first_name
    result["cleanLastName"] = last_name or first_name
    return result


async def on_request(request):
    """Handle incoming HTTP request."""
    url = request.url
    method = request.method

    # CORS preflight
    if method == "OPTIONS":
        return Response(
            status=204,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, X-HubSpot-Signature",
                "Access-Control-Max-Age": "86400",
            },
        )

    # Only accept POST
    if method != "POST":
        return Response(
            json.dumps({"error": "Method not allowed"}),
            status=405,
            headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        )

    # Health check
    if url.path == "/health" or url.path == "/":
        return Response(
            json.dumps({"status": "ok", "worker": "webhook-ingest", "runtime": "python"}),
            headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        )

    payload_bytes = await request.body()
    signature = request.headers.get("X-HubSpot-Signature") or \
                request.headers.get("X-HubSpot-Signature-v3")

    # Validate HMAC (if configured)
    if HMAC_SECRET and signature:
        if not validate_hmac(payload_bytes, signature):
            return Response(
                json.dumps({"error": "Invalid HMAC signature"}),
                status=401,
                headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            )

    # Parse payload
    try:
        data = json.loads(payload_bytes)
    except json.JSONDecodeError:
        return Response(
            json.dumps({"error": "Invalid JSON"}),
            status=400,
            headers={"Content-Type": "application/json"},
        )

    # Determine source
    source = "hubspot"
    if url.path.startswith("/csv"):
        source = "csv"
    elif url.path.startswith("/webhook/wordpress"):
        source = "wordpress"

    # Process leads
    leads = data if isinstance(data, list) else [data]
    hygienized_leads = [hygienize_lead(lead) for lead in leads]

    # Forward to backend via Tunnel
    if BACKEND_URL:
        try:
            forward_payload = json.dumps({
                "leads": hygienized_leads,
                "source": source,
                "ownerPartyId": OWNER_PARTY_ID,
            }).encode()

            req = Request(
                url=f"{BACKEND_URL}/webhook/hubspot",
                data=forward_payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Forwarded-Source": source,
                },
                method="POST",
            )
            # Non-blocking fire-and-forget in production would use
            # fetch() which is available in Workers runtime
            resp = urlopen(req, timeout=10)
            backend_response = json.loads(resp.read())
        except URLError as e:
            backend_response = {"backend_error": str(e), "staged_locally": False}
    else:
        backend_response = {"staged_locally": True, "note": "BACKEND_URL not configured"}

    return Response(
        json.dumps({
            "received": len(leads),
            "hygienized": len(hygienized_leads),
            "backend": backend_response,
        }),
        headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
    )


# Entry point (Workers runtime calls this)
async def fetch(request):
    response = await on_request(request)
    return response


# For local testing
if __name__ == "__main__":
    import sys
    print("Cloudflare Worker — Webhook Ingest")
    print("Run with: wrangler dev")
PYWEOF
    ok "src/index.py criado"
  fi

  step "6.4" "Criar .env.example do Worker"
  cat > "$REPO_DIR/workers/webhook-ingest/.env.example" << 'WENV'
# Cloudflare Worker — Webhook Ingest
# Copy to .env and fill in secrets

# HMAC secret for HubSpot webhook validation
HMAC_SECRET=your-hubspot-hmac-secret

# Backend URL (Cloudflare Tunnel endpoint)
BACKEND_URL=https://webhooks.blahsoftware.ia.br

# Owner Party ID
OWNER_PARTY_ID=BLAH_SOFT_OWNER
WENV
  ok ".env.example criado"

  step "6.5" "Commit + push Fase 6"
  if confirm "Commitar Fase 6?"; then
    safe_run "Committing Fase 6" git_commit_and_push \
      "feat(crm-pipeline): cloudflare worker webhook-ingest (python/pyodide)

- Worker Python com validacao HMAC HubSpot
- Higienizacao de leads no edge (E.164, email, empresa)
- Encaminhamento para webhook-server via Cloudflare Tunnel" \
      "workers/webhook-ingest/"
  fi

  checkpoint_save "phase_6_worker" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 6 concluída. Continuar para Fase 7 (Gmail API)?" && phase_7_gmail
}

# ═══════════════════════════════════════════════
# FASE 7 — GMAIL API + gmail_ingest.py
# ═══════════════════════════════════════════════

phase_7_gmail() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 7 — Gmail API + Domain-Wide Delegation${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Gmail API Integration" \
"O gmail_ingest.py usa uma Service Account do Google Cloud com domain-wide
delegation para ler todas as caixas @blahsoftware.ia.br.

Fluxo: Gmail API (todas caixas) → gmail_ingest.py → hygiene + dedup →
      POST /import/leads → GrowERP"

  step "7.1" "Criar gmail_ingest.py"
  if confirm "Criar gmail_ingest.py?"; then
    cat > "$REPO_DIR/docker/webhook-server/gmail_ingest.py" << 'GMAILPY'
#!/usr/bin/env python3
"""
GrowERP Gmail Ingest — Domain-Wide Email Reader
=================================================
Uses Google Workspace Domain-Wide Delegation to read emails from
ALL mailboxes @blahsoftware.ia.br and convert them into leads.

Requires:
  1. Google Cloud Service Account with domain-wide delegation
  2. Scopes: https://www.googleapis.com/auth/gmail.readonly
             https://www.googleapis.com/auth/admin.directory.user.readonly
  3. Delegate to ainexus@blahsoftware.ia.br in Admin Console

Usage:
  python gmail_ingest.py                          # dry-run (read only)
  python gmail_ingest.py --push                   # push to GrowERP
  python gmail_ingest.py --mailbox user@domain    # specific mailbox
"""

import os
import sys
import json
import time
import logging
import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Google API
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

import requests

# ── Config ──
SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/admin.directory.user.readonly",
]
SERVICE_ACCOUNT_FILE = os.environ.get(
    "GOOGLE_SERVICE_ACCOUNT_FILE",
    "/app/credentials/google-service-account.json",
)
DELEGATED_ADMIN = os.environ.get("DELEGATED_ADMIN", "ainexus@blahsoftware.ia.br")
MOQUI_URL = os.environ.get("MOQUI_URL", "http://moqui-server:80")
GROWERP_IMPORT_URL = f"{MOQUI_URL}/rest/s1/growerp/100/ImportExport/leads"
GROWERP_API_KEY = os.environ.get("GROWERP_API_KEY", "")
OWNER_PARTY_ID = os.environ.get("OWNER_PARTY_ID", "BLAH_SOFT_OWNER")
SOURCE_ENUM_ID = "SrcGmail"
DAYS_BACK = int(os.environ.get("GMAIL_DAYS_BACK", "7"))
MAX_MAILBOXES = int(os.environ.get("GMAIL_MAX_MAILBOXES", "50"))
MAX_EMAILS_PER_BOX = int(os.environ.get("GMAIL_MAX_PER_BOX", "20"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("gmail-ingest")


def get_credentials():
    """Create delegated credentials from Service Account."""
    if not Path(SERVICE_ACCOUNT_FILE).exists():
        log.error(f"Service account file not found: {SERVICE_ACCOUNT_FILE}")
        log.error("Place the JSON key at this path and ensure domain-wide delegation is configured.")
        sys.exit(1)

    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES
    )
    delegated = creds.with_subject(DELEGATED_ADMIN)
    return delegated


def list_mailboxes(service) -> list[str]:
    """List all user mailboxes in the domain via Directory API."""
    log.info("Listing mailboxes via Directory API...")
    mailboxes = []
    page_token = None

    try:
        while True:
            results = service.users().list(
                domain="blahsoftware.ia.br",
                maxResults=100,
                pageToken=page_token,
                projection="basic",
            ).execute()

            for user in results.get("users", []):
                email = user.get("primaryEmail")
                if email:
                    mailboxes.append(email)

            page_token = results.get("nextPageToken")
            if not page_token:
                break
    except HttpError as e:
        log.warning(f"Directory API error (need Admin SDK enabled): {e}")
        log.warning("Falling back to single mailbox: %s", DELEGATED_ADMIN)
        return [DELEGATED_ADMIN]

    log.info(f"Found {len(mailboxes)} mailboxes")
    return mailboxes[:MAX_MAILBOXES]


def extract_lead_from_email(msg_data: dict, mailbox: str) -> dict | None:
    """Extract lead information from a Gmail message."""
    payload = msg_data.get("payload", {})
    headers = {h["name"].lower(): h["value"] for h in payload.get("headers", [])}

    subject = headers.get("subject", "")
    from_header = headers.get("from", "")
    to_header = headers.get("to", "")
    date_str = headers.get("date", "")
    body_snippet = msg_data.get("snippet", "")

    # Skip automated/noreply
    if any(
        keyword in from_header.lower()
        for keyword in ["noreply", "no-reply", "mailer-daemon", "bounce"]
    ):
        return None

    # Parse sender
    import re
    name_match = re.match(r'^"?([^"<]*)"?\s*<([^>]+)>', from_header)
    if name_match:
        sender_name = name_match.group(1).strip()
        sender_email = name_match.group(2).strip().lower()
    elif "@" in from_header:
        sender_email = from_header.strip().lower()
        sender_name = sender_email.split("@")[0]
    else:
        return None

    # Skip known internal domains
    internal_domains = [
        "blahsoftware.ia.br", "blahsoftware.com.br",
        "growerp.local", "growerp.com",
    ]
    sender_domain = sender_email.split("@")[1] if "@" in sender_email else ""
    if sender_domain in internal_domains:
        return None

    # Extract company from email domain (if not free email)
    free_domains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com", "live.com"]
    company = ""
    if sender_domain not in free_domains:
        company = sender_domain.replace(".com", "").replace(".br", "").replace(".", " ").title()

    # Extract phone from body
    phone = ""
    phone_match = re.search(
        r"(?:(?:\+?55)?[\s-]?)?(?:\(?\d{2}\)?[\s-]?)?\d{4,5}[\s-]?\d{4}",
        body_snippet,
    )
    if phone_match:
        phone = phone_match.group(0)

    # Determine opportunity stage from subject
    stage = "OpLead"
    if any(w in subject.lower() for w in ["orcamento", "budget", "preco", "quanto", "valor"]):
        stage = "OpQualified"

    return {
        "firstName": sender_name.split()[0] if sender_name.split() else sender_name,
        "lastName": " ".join(sender_name.split()[1:]) if len(sender_name.split()) > 1 else sender_name,
        "email": sender_email,
        "phone": phone,
        "company": company,
        "notes": f"Subject: {subject}\nFrom: {from_header}\nReceived at: {mailbox}\n\n{body_snippet[:500]}",
        "sourceEnumId": SOURCE_ENUM_ID,
        "opportunityStageId": stage,
    }


def read_mailbox(gmail_service, mailbox: str) -> list[dict]:
    """Read recent emails from a mailbox and extract leads."""
    leads = []

    try:
        # Search recent emails
        query = f"after:{(datetime.now(timezone.utc) - timedelta(days=DAYS_BACK)).strftime('%Y/%m/%d')} is:inbox"
        results = (
            gmail_service.users()
            .messages()
            .list(userId=mailbox, q=query, maxResults=MAX_EMAILS_PER_BOX)
            .execute()
        )

        messages = results.get("messages", [])
        if not messages:
            return []

        for msg in messages:
            try:
                msg_data = (
                    gmail_service.users()
                    .messages()
                    .get(userId=mailbox, id=msg["id"], format="metadata")
                    .execute()
                )
                lead = extract_lead_from_email(msg_data, mailbox)
                if lead:
                    leads.append(lead)
            except HttpError as e:
                log.warning(f"Error reading message {msg['id']} from {mailbox}: {e}")
                continue

    except HttpError as e:
        log.warning(f"Error reading {mailbox}: {e}")

    return leads


def push_to_growerp(leads: list[dict]) -> dict:
    """Push leads to GrowERP."""
    if not leads:
        return {"imported": 0, "message": "No leads to push"}

    headers = {"Content-Type": "application/json"}
    if GROWERP_API_KEY:
        headers["Authorization"] = f"Bearer {GROWERP_API_KEY}"

    payload = {
        "leads": leads,
        "ownerPartyId": OWNER_PARTY_ID,
        "sourceEnumId": SOURCE_ENUM_ID,
    }

    try:
        resp = requests.post(GROWERP_IMPORT_URL, json=payload, headers=headers, timeout=60)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        log.error(f"Push to GrowERP failed: {e}")
        if hasattr(e, "response") and e.response is not None:
            log.error(f"Response: {e.response.text[:300]}")
        return {"error": str(e)}


def main():
    parser = argparse.ArgumentParser(description="GrowERP Gmail Ingest")
    parser.add_argument("--push", action="store_true", help="Push leads to GrowERP")
    parser.add_argument(
        "--mailbox", type=str, default=None,
        help="Specific mailbox to read (default: all domain mailboxes)",
    )
    parser.add_argument(
        "--days-back", type=int, default=DAYS_BACK,
        help=f"Days back to search (default: {DAYS_BACK})",
    )
    args = parser.parse_args()

    log.info("Starting Gmail Ingest (dry-run: %s)", not args.push)
    global DAYS_BACK
    if args.days_back:
        DAYS_BACK = args.days_back

    # Authenticate
    log.info("Authenticating with Google Service Account...")
    creds = get_credentials()
    gmail_service = build("gmail", "v1", credentials=creds)
    admin_service = build("admin", "directory_v1", credentials=creds)

    # Get mailboxes
    if args.mailbox:
        mailboxes = [args.mailbox]
    else:
        mailboxes = list_mailboxes(admin_service)

    total_leads = 0
    all_leads = []

    for mailbox in mailboxes:
        log.info(f"Reading {mailbox}...")
        leads = read_mailbox(gmail_service, mailbox)

        if leads:
            log.info(f"  → {len(leads)} leads extracted from {mailbox}")
            all_leads.extend(leads)
            total_leads += len(leads)
        else:
            log.info(f"  → No leads found in {mailbox}")

        # Rate limiting
        time.sleep(0.5)

    log.info(f"Total leads extracted: {total_leads}")

    if args.push and all_leads:
        result = push_to_growerp(all_leads)
        log.info(f"Push result: {json.dumps(result, indent=2)}")
    elif all_leads:
        log.info("Dry-run mode. Use --push to send to GrowERP.")
        for lead in all_leads[:5]:
            log.info(f"  Sample: {lead.get('firstName')} {lead.get('lastName')} <{lead.get('email')}>")
        if len(all_leads) > 5:
            log.info(f"  ... and {len(all_leads) - 5} more")
    else:
        log.info("No leads found.")


if __name__ == "__main__":
    main()
GMAILPY
    ok "gmail_ingest.py criado"
  fi

  step "7.2" "Criar credentials/.gitkeep e .gitignore"
  safe_run "Criando diretório credentials" mkdir -p "$REPO_DIR/docker/webhook-server/credentials"
  touch "$REPO_DIR/docker/webhook-server/credentials/.gitkeep"
  if [[ -f "$REPO_DIR/.gitignore" ]]; then
    if ! grep -q "google-service-account" "$REPO_DIR/.gitignore"; then
      cat >> "$REPO_DIR/.gitignore" << 'GIEOF'

# Google Service Account credentials (Gmail API domain-wide delegation)
docker/webhook-server/credentials/google-service-account.json
GIEOF
      ok ".gitignore atualizado"
    fi
  fi

  step "7.3" "Criar script de setup do Gmail API"
  cat > "$REPO_DIR/docker/setup-gmail-api.sh" << 'GMSETUP'
#!/usr/bin/env bash
# Setup Gmail API Domain-Wide Delegation
# Usage: bash setup-gmail-api.sh
set -euo pipefail

CREDENTIALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/webhook-server/credentials"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Gmail API Setup — Domain-Wide Delegation        ║"
echo "╚══════════════════════════════════════════════════╝"
echo

echo "📌 PASSO 1: Google Cloud Console"
echo "   1. Acesse https://console.cloud.google.com"
echo "   2. Crie um projeto 'GrowERP CRM Integration'"
echo "   3. Ative as APIs:"
echo "      - Gmail API"
echo "      - Admin SDK API"
echo "   4. IAM → Service Accounts → Criar 'growerp-crm-ingest'"
echo "   5. Gerar chave JSON → salvar em:"
echo "      $CREDENTIALS_DIR/google-service-account.json"
echo
echo "📌 PASSO 2: Google Workspace Admin Console"
echo "   1. Acesse https://admin.google.com"
echo "   2. Segurança → Controles de API → Domain-wide Delegation"
echo "   3. Adicionar novo:"
echo "      - Client ID: (copiar do Service Account)"
echo "      - Escopos:"
echo "        https://www.googleapis.com/auth/gmail.readonly"
echo "        https://www.googleapis.com/auth/admin.directory.user.readonly"
echo "   4. Delegar para: ainexus@blahsoftware.ia.br"
echo
echo "📌 PASSO 3: Testar"
echo "   cd $CREDENTIALS_DIR"
echo "   docker exec webhook-server python /app/gmail_ingest.py"
echo
echo "📌 PASSO 4: Push para GrowERP"
echo "   docker exec webhook-server python /app/gmail_ingest.py --push"
echo
echo "✅ Mais detalhes: https://developers.google.com/workspace/guides/create-credentials"
GMSETUP
  chmod +x "$REPO_DIR/docker/setup-gmail-api.sh"
  ok "setup-gmail-api.sh criado"

  step "7.4" "Commit + push Fase 7"
  if confirm "Commitar Fase 7?"; then
    safe_run "Committing Fase 7" git_commit_and_push \
      "feat(crm-pipeline): gmail api ingest - domain-wide delegation

- gmail_ingest.py: Gmail API + Directory API para ler todas as caixas
- Extracao de leads de emails (remetente, telefone, empresa, stage)
- Push para GrowERP via /rest/.../ImportExport/leads
- Service Account credentials (gitignored)
- Script setup-gmail-api.sh com instrucoes de configuracao" \
      "docker/webhook-server/gmail_ingest.py" \
      "docker/webhook-server/credentials/.gitkeep" \
      ".gitignore" \
      "docker/setup-gmail-api.sh"
  fi

  checkpoint_save "phase_7_gmail" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  confirm "Fase 7 concluída. Continuar para Fase 8 (Flatpak)?" && phase_8_flatpak
}

# ═══════════════════════════════════════════════
# FASE 8 — FLATPAK CRM BLAH SOFTWARE
# ═══════════════════════════════════════════════

phase_8_flatpak() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  FASE 8 — Flatpak: CRM Blah Software (Linux Desktop)${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  explain "Flatpak CRM Blah Software" \
"Empacota o app Flutter admin (com widgets CRM) como Flatpak para
distribuição em máquinas Ubuntu. Usa runtime GNOME 47.

O app é baseado no admin existente que já registra os widgets:
ActivityList, OpportunityList, UserListLead, UserListCustomer."

  step "8.1" "Criar estrutura do Flatpak"
  if confirm "Criar estrutura Flatpak?"; then
    mkdir -p "$REPO_DIR/flutter/packages/admin/flatpak"
    ok "Estrutura criada"
  fi

  step "8.2" "Criar manifest Flatpak"
  if confirm "Criar io.growerp.crm.blah.yml?"; then
    cat > "$REPO_DIR/flutter/packages/admin/flatpak/io.growerp.crm.blah.yml" << 'FLATYML'
id: io.growerp.crm.blah
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
  - --env=FLUTTER_WEBAPP_URL=https://backend.growerp.local
  - --env=GROWERP_API_URL=https://backend.growerp.local/rest/s1/growerp/100

modules:
  - name: growerp-crm
    buildsystem: simple
    build-commands:
      - flutter build linux --release -v
      - install -Dm755 build/linux/*/release/bundle/growerp_crm /app/bin/growerp-crm
      - install -Dm644 build/linux/*/release/bundle/lib/*.so /app/lib/
      - install -Dm644 io.growerp.crm.blah.metainfo.xml /app/share/metainfo/
      - install -Dm644 io.growerp.crm.blah.desktop /app/share/applications/
      - install -Dm644 io.growerp.crm.blah.png /app/share/icons/hicolor/256x256/apps/
      - install -Dm644 io.growerp.crm.blah-symbolic.png /app/share/icons/hicolor/symbolic/apps/
    sources:
      - type: dir
        path: ..
      - type: file
        path: flatpak/io.growerp.crm.blah.metainfo.xml
      - type: file
        path: flatpak/io.growerp.crm.blah.desktop
      - type: file
        path: flatpak/io.growerp.crm.blah.png
      - type: file
        path: flatpak/io.growerp.crm.blah-symbolic.png
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
FLATYML
    ok "Manifest Flatpak criado"
  fi

  step "8.3" "Criar AppStream metadata"
  if confirm "Criar metainfo.xml?"; then
    cat > "$REPO_DIR/flutter/packages/admin/flatpak/io.growerp.crm.blah.metainfo.xml" << 'APPDATA'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.growerp.crm.blah</id>
  <name>Blah Software CRM</name>
  <summary>GrowERP CRM para Blah Software — Gestão de Leads e Campanhas</summary>
  <developer_name>Blah Software</developer_name>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>CC0-1.0</project_license>
  <description>
    <p>Cliente desktop do GrowERP CRM para Blah Software. Gerencie leads,
    oportunidades, landing pages e campanhas de outreach diretamente do
    seu computador.</p>
    <p>Recursos:</p>
    <ul>
      <li>Dashboard com visão geral de métricas</li>
      <li>Gestão de leads e oportunidades</li>
      <li>Landing pages por segmento</li>
      <li>Campanhas de WhatsApp e Email</li>
      <li>Analytics do Search Console</li>
    </ul>
  </description>
  <categories>
    <category>Office</category>
    <category>Business</category>
  </categories>
  <url type="homepage">https://blahsoftware.ia.br</url>
  <screenshots>
    <screenshot type="default">
      <image>https://backend.growerp.local/crm/screenshot.png</image>
    </screenshot>
  </screenshots>
  <releases>
    <release version="1.0.0" date="2026-06-10">
      <description>First release — CRM pipeline integration</description>
    </release>
  </releases>
</component>
APPDATA
    ok "AppStream metadata criado"
  fi

  step "8.4" "Criar .desktop file"
  if confirm "Criar .desktop file?"; then
    cat > "$REPO_DIR/flutter/packages/admin/flatpak/io.growerp.crm.blah.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Blah Software CRM
Comment=GrowERP CRM para Blah Software
Exec=growerp-crm
Icon=io.growerp.crm.blah
Terminal=false
Type=Application
Categories=Office;Business;
StartupNotify=true
X-Flatpak-RenamedFrom=growerp-crm.desktop;
DESKTOP
    ok ".desktop file criado"
  fi

  step "8.5" "Criar Makefile para build"
  if confirm "Criar Makefile?"; then
    cat > "$REPO_DIR/flutter/packages/admin/flatpak/Makefile" << 'MAKEFILE'
# Flatpak CRM Blah Software — Build targets
.PHONY: all build install clean publish

APP_ID = io.growerp.crm.blah
BUILD_DIR = build-dir
REPO_DIR = repo

all: build

build: $(BUILD_DIR)
	flatpak-builder --force-clean --ccache $(BUILD_DIR) $(APP_ID).yml

$(BUILD_DIR): $(APP_ID).yml $(APP_ID).metainfo.xml $(APP_ID).desktop
	flatpak-builder --force-clean --ccache $(BUILD_DIR) $(APP_ID).yml

install: build
	flatpak-builder --user --install --force-clean $(BUILD_DIR) $(APP_ID).yml

repo: build
	flatpak build-export $(REPO_DIR) $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(REPO_DIR)

publish: repo
	@echo "Publish to S3/GitHub Releases:"
	@echo "  tar -czf $(APP_ID).flatpak repo/"
	@echo "  scp $(APP_ID).flatpak user@host:"
	@echo "  # On client: flatpak install $(APP_ID).flatpak"
MAKEFILE
    ok "Makefile criado"
  fi

  step "8.6" "Criar script de setup do Flatpak no cliente"
  cat > "$REPO_DIR/docker/setup-flatpak-client.sh" << 'FLATSH'
#!/usr/bin/env bash
# Setup Ubuntu client for Flatpak CRM
# Usage: bash setup-flatpak-client.sh [--server-ip 192.168.x.x]
set -euo pipefail

SERVER_IP="${1:-192.168.15.100}"
FLATPAK_FILE="${FLATPAK_FILE:-growerp-crm.flatpak}"
CERT_DIR="/usr/local/share/ca-certificates"
CERT_FILE="$CERT_DIR/growerp-local.crt"

echo "╔══════════════════════════════════════════════════╗"
echo "║  Ubuntu Client Setup — Blah Software CRM         ║"
echo "╚══════════════════════════════════════════════════╝"
echo

# 1. /etc/hosts
echo "📌 Atualizando /etc/hosts..."
for host in backend.growerp.local admin.growerp.local; do
  if ! grep -q "$host" /etc/hosts 2>/dev/null; then
    echo "$SERVER_IP $host" | sudo tee -a /etc/hosts >/dev/null
    echo "   + $host → $SERVER_IP"
  else
    echo "   • $host já configurado"
  fi
done

# 2. SSL Certificate
echo
echo "📌 Instalando certificado SSL..."
if curl -sL "https://backend.growerp.local/certs/growerp.local.crt" -o /tmp/growerp-local.crt 2>/dev/null; then
  sudo cp /tmp/growerp-local.crt "$CERT_FILE"
  sudo update-ca-certificates
  echo "   ✅ Certificado instalado"
elif [[ -f "growerp.local.crt" ]]; then
  sudo cp growerp.local.crt "$CERT_FILE"
  sudo update-ca-certificates
  echo "   ✅ Certificado instalado (local)"
else
  echo "   ⚠  Certificado não encontrado. Copie growerp.local.crt manualmente."
fi

# 3. Flatpak
echo
echo "📌 Verificando Flatpak..."
if command -v flatpak &>/dev/null; then
  echo "   ✅ Flatpak encontrado"
else
  echo "   Instalando Flatpak..."
  sudo apt-get update && sudo apt-get install -y flatpak
fi

# 4. Instalar app
echo
if [[ -f "$FLATPAK_FILE" ]]; then
  echo "📌 Instalando $FLATPAK_FILE..."
  flatpak install --user --assumeyes "$FLATPAK_FILE"
  echo "   ✅ App instalado! Execute: flatpak run io.growerp.crm.blah"
else
  echo "📌 Arquivo $FLATPAK_FILE não encontrado."
  echo "   Copie de: scp user@$SERVER_IP:growerp-crm.flatpak ."
fi

echo
echo "✅ Setup concluído!"
echo "   • Dashboard: https://backend.growerp.local/crm/"
echo "   • Flatpak:   flatpak run io.growerp.crm.blah"
FLATSH
  chmod +x "$REPO_DIR/docker/setup-flatpak-client.sh"
  ok "setup-flatpak-client.sh criado"

  step "8.7" "Commit + push Fase 8"
  if confirm "Commitar Fase 8?"; then
    safe_run "Committing Fase 8" git_commit_and_push \
      "feat(crm-pipeline): flatpak crm blah software linux desktop

- Manifest Flatpak io.growerp.crm.blah (runtime GNOME 47)
- AppStream metadata (io.growerp.crm.blah.metainfo.xml)
- Desktop file + Makefile para build
- Script setup-flatpak-client.sh para instalacao em Ubuntu" \
      "flutter/packages/admin/flatpak/" \
      "docker/setup-flatpak-client.sh"
  fi

  checkpoint_save "phase_8_flatpak" "completed" "$(git -C "$REPO_DIR" log --oneline -1 2>/dev/null | awk '{print $1}')"
  echo
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  FASE 8 CONCLUÍDA — Pipeline CRM totalmente estruturado!${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
  echo
  echo "Resumo de integração pendente:"
  echo "  1. docker compose up -d webhook-server"
  echo "  2. docker compose restart nginx-proxy"
  echo "  3. bash setup-cloudflare-tunnel.sh"
  echo "  4. Preencher SMTP_USER/PASSWORD via configure-smtp.sh"
  echo "  5. wrangler deploy (Worker Python webhook-ingest)"
  echo "  6. Configurar Service Account Google + setup-gmail-api.sh"
  echo "  7. flatpak-builder (build do app Linux)"
}

# ═══════════════════════════════════════════════
# STATUS REPORT
# ═══════════════════════════════════════════════

status_report() {
  echo
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  STATUS DO PIPELINE CRM${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo

  if [[ ! -f "$CHECKPOINT_FILE" ]]; then
    echo "Nenhum checkpoint encontrado. Nenhuma fase foi executada ainda."
    return
  fi

  python3 -c "
import json, sys
d = json.load(open('$CHECKPOINT_FILE'))
phases = d.get('phases', {})
print(f\"{'Fase':<25} {'Status':<15} {'Commit'}\")
print('-' * 65)
order = ['phase_1_backend','phase_2_webhook_server','phase_3_nginx',
         'phase_4_tunnel','phase_5_smtp','phase_6_worker',
         'phase_7_gmail','phase_8_flatpak']
names = {'phase_1_backend':'1 - Backend SourceRecord',
         'phase_2_webhook_server':'2 - Webhook Server',
         'phase_3_nginx':'3 - Nginx rotas',
         'phase_4_tunnel':'4 - Cloudflare Tunnel',
         'phase_5_smtp':'5 - Google SMTP',
         'phase_6_worker':'6 - Worker Cloudflare',
         'phase_7_gmail':'7 - Gmail API',
         'phase_8_flatpak':'8 - Flatpak CRM'}
for p in order:
    if p in phases:
        v = phases[p]
        s = v.get('status','?')
        c = v.get('commit','-')
        emoji = '✅' if s == 'completed' else '⏳' if s == 'in_progress' else '⬜'
        print(f\"{emoji} {names.get(p,p):<23} {s:<15} {c}\")
    else:
        print(f\"⬜ {names.get(p,p):<23} {'pending':<15} -\")
print()

completed = sum(1 for p in order if p in phases and phases[p].get('status') == 'completed')
print(f'Progresso: {completed}/{len(order)} fases concluídas')
"

  echo
  echo "Últimos commits:"
  git -C "$REPO_DIR" log --oneline -10 2>/dev/null || echo "(sem histórico)"
}

# ═══════════════════════════════════════════════
# RUN ALL
# ═══════════════════════════════════════════════

run_all() {
  phase_1_backend
  phase_2_webhook_server
  phase_3_nginx
  phase_4_tunnel
  phase_5_smtp
  phase_6_worker
  phase_7_gmail
  phase_8_flatpak
}

# ═══════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════

main_menu() {
  while true; do
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    MENU PRINCIPAL                            ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  0) Sair                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  1) Verificar pré-requisitos                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  2) Fase 1 — Backend (SourceRecord + importLeads)        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  3) Fase 2 — Webhook Server (Flask + SQLite)             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  4) Fase 3 — Nginx (rota /webhook/)                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  5) Fase 4 — Cloudflare Tunnel                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  6) Fase 5 — Google SMTP                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  7) Fase 6 — Worker Cloudflare (Python)                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  8) Fase 7 — Gmail API + Domain-Wide Delegation          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  9) Fase 8 — Flatpak CRM Blah Software                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 10) Execução completa (Fases 1→8)                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 11) Status geral                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -n "Escolha uma opção: "
    read -r choice

    case "$choice" in
      0) echo "Saindo..."; exit 0 ;;
      1) check_prereqs ;;
      2) phase_1_backend ;;
      3) phase_2_webhook_server ;;
      4) phase_3_nginx ;;
      5) phase_4_tunnel ;;
      6) phase_5_smtp ;;
      7) phase_6_worker ;;
      8) phase_7_gmail ;;
      9) phase_8_flatpak ;;
      10) run_all ;;
      11) status_report ;;
      *) warn "Opção inválida" ;;
    esac
  done
}

# ═══════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --phase) SKIP_PHASE="$2"; shift ;;
      --status) status_report; exit 0 ;;
      --help|-h) echo "Uso: $0 [--phase N] [--dry-run] [--status]"; exit 0 ;;
      *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
    shift
  done
}

main() {
  banner
  parse_args "$@"

  # Resume from checkpoint if exists
  if [[ -f "$CHECKPOINT_FILE" && -z "$SKIP_PHASE" ]]; then
    echo "Checkpoint encontrado:"
    checkpoint_load
    echo
    if confirm "Retomar da última fase concluída?"; then
      # Find last completed phase
      LAST_PHASE=$(python3 -c "
import json
d = json.load(open('$CHECKPOINT_FILE'))
phases = d.get('phases', {})
order = ['phase_1_backend','phase_2_webhook_server','phase_3_nginx',
         'phase_4_tunnel','phase_5_smtp','phase_6_worker',
         'phase_7_gmail','phase_8_flatpak']
for p in order:
    if p not in phases or phases[p].get('status') != 'completed':
        print(p); exit(0)
print('all')
")
      if [[ "$LAST_PHASE" == "all" ]]; then
        echo "Todas as fases já foram concluídas!"
        status_report
        exit 0
      fi
      # Jump to first incomplete phase
      case "$LAST_PHASE" in
        phase_1_backend) phase_1_backend ;;
        phase_2_webhook_server) phase_2_webhook_server ;;
        phase_3_nginx) phase_3_nginx ;;
        phase_4_tunnel) phase_4_tunnel ;;
        phase_5_smtp) phase_5_smtp ;;
        phase_6_worker) phase_6_worker ;;
        phase_7_gmail) phase_7_gmail ;;
        phase_8_flatpak) phase_8_flatpak ;;
      esac
      return
    fi
  fi

  # Direct phase jump
  if [[ -n "$SKIP_PHASE" ]]; then
    case "$SKIP_PHASE" in
      1|phase_1) phase_1_backend ;;
      2|phase_2) phase_2_webhook_server ;;
      3|phase_3) phase_3_nginx ;;
      4|phase_4) phase_4_tunnel ;;
      5|phase_5) phase_5_smtp ;;
      6|phase_6) phase_6_worker ;;
      7|phase_7) phase_7_gmail ;;
      8|phase_8) phase_8_flatpak ;;
      *) die "Fase inválida: $SKIP_PHASE" ;;
    esac
    return
  fi

  main_menu
}

main "$@"
