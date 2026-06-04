 implementação da integração entre o GrowERP e o ecossistema Freela-SDR / freelabot (no host chagas) está detalhada no arquivo de documentação 

growerp_freelabot_integration.md
.

Aqui está um resumo de como ficou a arquitetura para a integração de dados local e a integração com o HubSpot:

1. Integração de Dados Local (Área de Staging e Higienização)
Para evitar a inserção direta de dados brutos ou duplicados nas tabelas operacionais do GrowERP, o pipeline no host chagas foi estruturado em 4 fases:

Fase 1: Ingestão de Origem (Staging)
Os dados brutos recebidos das fontes externas (formulários WordPress, CSVs, HubSpot) são salvos inicialmente na tabela source_records de um banco de dados SQLite local (sdr_vault.db gerenciado pelo script crm_db.py / crm_core.py). O JSON original do payload é preservado para auditorias e possíveis rollbacks.
Fase 2: Higienização e Normalização
E-mails: Convertidos para minúsculas e validados por regex.
Telefones: Formatados no padrão internacional E.164 (ex: +5511999999999).
Empresas: Remoção de sufixos jurídicos repetitivos (ex: "Ltda", "S/A", "ME") para otimizar o agrupamento de contas.
Domínios: Extração automatizada do domínio principal da lead (a partir do e-mail corporativo ou do site).
Fase 3: Motor de Deduplicação e Fusão (Merge)
O cruzamento de identidades utiliza três regras em cascata:
Match exato de e-mail (email).
Match exato de telefone no formato E.164.
Match aproximado de domínio corporativo + nome aproximado da empresa.
Resolução de Conflitos (source_priority): Caso existam dados conflitantes para a mesma lead, prevalece a prioridade de origem:
HubSpot CRM (Prioridade Alta/Comercial).
WordPress Jetpack CRM (Prioridade Média/Interação direta em site).
CSVs & Bancos de Scraping (Prioridade Baixa).
Fase 4: Gravação Canônica
Os dados consolidados e limpos são enviados ao GrowERP via REST API (mapeados para entidades nativas como mantle.party.Person, mantle.party.contact.ContactMech, etc.). Após o cadastro bem-sucedido, o registro local em source_records é atualizado com o partyId retornado e o syncDate.
2. Integração com o HubSpot
A integração com o HubSpot foi desenhada para atuar em tempo real e de forma segura:

Substituição de Polling por Webhooks:
Em vez de loops e consultas periódicas via cron, a integração utiliza webhooks ativos do HubSpot Developer Account vinculados ao endpoint /webhook/hubspot exposto em crm_core.py.
O endpoint escuta em tempo real eventos como criação de contatos (contact.creation), alteração de propriedades (contact.propertyChange) e criação de oportunidades (deal.creation).
Validação e Segurança (HMAC):
Toda requisição recebida no webhook valida a assinatura digital contida no header X-HubSpot-Signature com o segredo compartilhado. Isso garante a autenticidade e impede a injeção de dados falsificados no banco de staging.
Sincronização Reversa de Atividades (Back-sync):
Quando tarefas ou notas de acompanhamento são geradas como CommunicationEvent no GrowERP (seja por um vendedor humano ou por um squad de SDR-BOT), um conector chamado HubSpotBack sincroniza de volta essas interações para o HubSpot, alinhando as duas plataformas.
3. Governança Multi-Contas (Multi-Tenancy)
Isolamento por Organização (ownerPartyId):
Para gerenciar múltiplos clientes isoladamente (ex: M Tratores, Blah, Workana) em uma única infraestrutura, os registros no GrowERP compartilham o mesmo banco de dados Moqui, mas são rotulados com o ownerPartyId da organização correspondente.
Cada squad de agentes autônomos (freelabot) opera sob um manifesto JSON que define seu escopo e suas credenciais específicas (API Keys / tokens vinculados ao tenant da organização correspondente), garantindo isolamento total de segurança entre clientes.
19:28, 27/05/2026
15:20
abra a tela do crm com os as amostragens e mensagens personalizadas a serem enviadas por whatsapp e e-mail para os clientes foco no site blahsoftware.ia.br, cada segmento tera uma pagina de destino diferente com um subdominio, exemplo agronegocio.blahsoftware.ia.br, agents.blahsoftware.com.br, Enterprise@blahsoftware.ia.br, business.blahsoftware.ia.br, agencia-house-local.blahsoftware.ia.br
franquia.blahsoftware.ia.br
solucoes.blahsoftware.ia.br, etc, adaptado aos segmentos de cada cliente.  tarefa inicial. 1 - abrir crm com dados importados, 2 - dar andamento nas implementações e realizar commit e push, caso ainda não tenha, criar a branch integração e analisar as diferenças em relação a ela. quero abrir o crm com os dados importados em seguida.  
