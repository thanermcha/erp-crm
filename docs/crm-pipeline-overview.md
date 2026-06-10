# CRM Pipeline — Visão Geral da Arquitetura

```mermaid
graph TB
    subgraph INBOUND["🌐 Entrada de Dados"]
        HS["HubSpot<br/>Webhook"]
        CSV["CSV Upload<br/>Manual"]
        GM["Gmail API<br/>Domain-Wide"]
        WP["WordPress<br/>Webhook"]
        FB["Meta/Facebook<br/>Leads"]
    end

    subgraph EDGE["☁️ Cloudflare Edge"]
        WK["Worker webhook-ingest<br/>Python/Pyodide<br/>Valida HMAC + Higieniza"]
        TUN["Cloudflare Tunnel<br/>webhooks.blahsoftware.ia.br"]
    end

    subgraph NGINX["🔀 Nginx Proxy (backend.growerp.local)"]
        direction LR
        LOC_WEB["/webhook/ → webhook:5000"]
        LOC_IMP["/import/ → webhook:5000"]
        LOC_HTH["/health → webhook:5000"]
        LOC_API["/ → moqui:80"]
    end

    subgraph WEBHOOK["📦 Webhook Server (Flask + SQLite)"]
        direction LR
        API["app.py<br/>Endpoints REST"]
        SQL["SQLite Staging<br/>source_records<br/>import_log"]
        HYZ["Higienização<br/>E.164, email, empresa"]
    end

    subgraph BACKEND["🗄️ GrowERP Backend (Moqui)"]
        direction LR
        SRC["SourceRecord Entity<br/>Rastreabilidade"]
        IMP["import#Leads Service<br/>Dedup hierárquico<br/>Upsert Party + Opp"]
        BLAH["Tenant BLAH_SOFTWARE<br/>ownerPartyId"]
    end

    subgraph SMTP["📧 Google SMTP (Campanhas)"]
        SMTP_G["smtp.gmail.com:587<br/>STARTTLS<br/>ainexus@blahsoftware.ia.br"]
    end

    subgraph DESKTOP["🖥️ Flatpak CRM Desktop"]
        FP["Blah Software CRM<br/>Runtime GNOME 47<br/>Linux Desktop"]
    end

    subgraph NETWORKS["🌍 Redes Externas"]
        META["meta-agency-stack_meta_net<br/>172.18.0.0/16<br/>n8n, celery, waha"]
        OCL["openclaw-ai_openclaw-lan<br/>172.31.40.0/24"]
    end

    INBOUND --> WK --> TUN --> NGINX
    NGINX --> WEBHOOK
    WEBHOOK --> BACKEND
    BACKEND --> SMTP
    WEBHOOK -.-> META
    WEBHOOK -.-> OCL
```

---

## Fluxo de Dados (Pipeline 8 Fases)

```mermaid
sequenceDiagram
    participant HS as HubSpot
    participant WK as Worker CF
    participant TUN as Tunnel
    participant NGX as Nginx
    participant WH as Webhook Server
    participant SQL as SQLite Staging
    participant MQ as Moqui Backend
    participant DB as PostgreSQL

    HS->>WK: POST webhook (JSON + HMAC)
    WK->>WK: Valida HMAC SHA-256
    WK->>WK: Higieniza (E.164, email, empresa)
    WK->>TUN: Encaminha para backend
    TUN->>NGX: /webhook/hubspot
    NGX->>WH: proxy_pass webhook:5000
    WH->>SQL: INSERT source_records (staged)
    WH->>WH: Hygienize + Dedup (email→phone→domain)
    WH->>MQ: POST /rest/.../ImportExport/leads
    MQ->>MQ: import#Leads Service
    MQ->>DB: Upsert Party + ContactMech
    MQ->>DB: INSERT SourceRecord
    MQ->>DB: Create SalesOpportunity
    MQ-->>WH: 200 {leadsImported, updated, skipped}
    WH->>SQL: UPDATE status = 'imported'
```

---

## Topologia de Rede

```mermaid
graph LR
    subgraph HOST["Host Docker"]
        N8N["n8n<br/>56720:56720"]
        CLW["celery<br/>flower"]
        WHA["waha<br/>wahacenter"]
        WEBHK["webhook-server<br/>5000:5000"]
        NGX["nginx<br/>80, 443"]
        MQ["moqui-server<br/>8080:8080"]
    end

    subgraph META_NET["meta-agency-stack_meta_net (172.18.0.0/16)"]
        N8N
        CLW
        WHA
    end

    subgraph OCL_NET["openclaw-ai_openclaw-lan (172.31.40.0/24)"]
        WEBHK
    end

    subgraph DFLT["docker_default"]
        NGX
        MQ
        WEBHK
    end

    INTERNET["Internet<br/>Cloudflare"] -.-> NGX
    WEBHK -.-> N8N
    MQ -.-> WEBHK
```

---

## Matriz de Endpoints

| Rota | Proxy Para | Finalidade |
|------|-----------|------------|
| `GET /crm/*` | `/opt/crm-dashboard/` | Dashboard estático |
| `POST /webhook/hubspot` | `webhook:5000` | Webhook HubSpot |
| `POST /webhook/csv` | `webhook:5000` | Upload CSV |
| `POST /import/leads` | `webhook:5000` | Proxy leads |
| `POST /import/sync` | `webhook:5000` | Processar fila |
| `GET /health` | `webhook:5000` | Healthcheck |
| `GET /rest/*` | `moqui:80` | API Moqui |
| `POST /rest/.../ImportExport/leads` | `moqui:80` | import#Leads |

---

## Dependências entre Fases

```mermaid
graph LR
    F1["Fase 1<br/>Backend"] --> F2["Fase 2<br/>Webhook"]
    F2 --> F3["Fase 3<br/>Nginx"]
    F3 --> F4["Fase 4<br/>Tunnel"]
    F4 --> F6["Fase 6<br/>Worker"]
    F2 --> F5["Fase 5<br/>SMTP"]
    F2 --> F7["Fase 7<br/>Gmail"]
    F2 --> F8["Fase 8<br/>Flatpak"]

    style F1 fill:#4a9eff,color:#fff
    style F2 fill:#6c5ce7,color:#fff
    style F3 fill:#00b894,color:#fff
    style F4 fill:#fdcb6e,color:#000
    style F5 fill:#e17055,color:#fff
    style F6 fill:#0984e3,color:#fff
    style F7 fill:#636e72,color:#fff
    style F8 fill:#2d3436,color:#fff
```

---

## Comandos Rápidos

```bash
# Verificar estado atual
git log --oneline -10

# Gerar todas as fases
python3 docker/generate-pipeline-files.py --all

# Gerar fase específica
python3 docker/generate-pipeline-files.py --phase 2

# Build + start webhook
docker compose -f docker-compose.yaml -f docker-compose-override.yaml up -d webhook-server

# Conectar redes externas
bash docker/connect-webhook-networks.sh

# Ver saúde do pipeline
curl -k https://backend.growerp.local/health

# Ver fila de staging
curl -sk https://backend.growerp.local/staging/status

# Processar fila manualmente
curl -X POST -sk https://backend.growerp.local/import/sync
```
