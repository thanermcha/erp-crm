## TaskChecklist: scripts `growerp-start.sh` e `growerp-stop.sh`

### Objetivo
Criar um par de scripts de inicialização e desligamento que encapsulem os passos manuais descritos em `README.md`:
1. preparar o backend Moqui (build/loading/execução),
2. levantar o repositório Flutter (melos, build, `flutter run`),
3. garantir logs e envs consistentes,
4. permitir paradas ordenadas com limpeza de artefatos temporários.

O checklist abaixo serve para acompanhar o progresso das tarefas técnicas e registrar responsáveis, observações e próximos passos.

### Visão macro dos scripts
- `growerp-start.sh`: valida variáveis de ambiente, prepara as dependências, inicia Moqui (construção opcional ou execução direta), e, se definido pelo usuário, sobe o Flutter Admin via `melos` + `flutter run` ou módulo equivalente.
- `growerp-stop.sh`: envia sinais de término ordenados para Moqui (e para o processo Flutter, caso iniciado pelo start), aguarda desligamento limpo, limpa logs temporários ou portas bloqueadas e exporta status final.

### Checklist de implementação

#### Pré-requisitos
| Tarefa | Responsável | Status | Observações |
| --- | --- | --- | --- |
| Registrar requisitos mínimos (`openjdk`, Flutter, melos, `java -jar moqui.war`) | — | Não iniciado | Reutilizar trecho de `README.md` (prerequisitos). |
| Definir convenções de logging/relatório para start/stop | — | Não iniciado | Ex.: diretório `logs/growerp` e arquivo `growerp-start.log`. |
| Escolher mecanismo preferido para manter Flutter vivo (terminal TMUX, `&`, `flutter run -d web-server` etc.) | — | Não iniciado | Avaliar se script apenas imprime instruções ou efetivamente inicia UI. |

#### Implementação do `growerp-start.sh`
| Tarefa | Responsável | Status | Observações |
| --- | --- | --- | --- |
| Validar variáveis de ambiente (`JAVA_HOME`, `BACKEND_PORT`, caminhos de submódulos) e abortar com mensagem amigável se faltarem | — | Não iniciado | Usar `set -euo pipefail` e `source` de `.env.local` opcional. |
| Atualizar submódulos e ligar componentes com `bash setup-backend.sh` se necessário | — | Não iniciado | Garantir que `moqui` já foi configurado uma única vez. |
| Compilar Moqui (`./gradlew build` + `java -jar moqui.war load ...`) apenas quando sinalizado via flag `--first-run` | — | Não iniciado | Adicionar flag `--first-run`/`--reset`. |
| Iniciar Moqui (`java -jar moqui.war no-run-es`) e registrar PID em arquivo `run/.moqui.pid` | — | Não iniciado | Permite o stop saber qual PID encerrar. |
| Inicializar Flutter (`melos bootstrap`, `melos build`, `cd packages/admin && flutter run`) dentro do mesmo script ou instruir o operador caso seja opcional | — | Não iniciado | Avaliar se o processo deve rodar em background; registrar logs. |
| Emitir resumo final com URLs/credenciais (ex: `http://localhost:8080/vapps`, `SystemSupport/moqui`) | — | Não iniciado | Fazer `echo` ao final para fácil conferência. |

#### Implementação do `growerp-stop.sh`
| Tarefa | Responsável | Status | Observações |
| --- | --- | --- | --- |
| Ler PID de Moqui e enviar `SIGTERM`, aguardar até 30 s e só então `SIGKILL` (com fallback) | — | Não iniciado | Usar `trap` para limpar se o script for interrompido. |
| Encerrar processo Flutter/grupo de processos iniciado pelo start (usar `pkill -F flutter.pid` ou similar) | — | Não iniciado | Registrar `flutter.pid` no start. |
| Remover arquivos temporários (`*.pid`, `*.lck`), opcionalmente arquivar logs (`logs/current -> logs/$(date)` ) | — | Não iniciado | Documentar em `README` ou script. |
| Reportar status final (`GrowERP desligado com sucesso` ou erros) e sugerir próximos passos (ex: rodar backup antes de iniciar novamente). | — | Não iniciado | Essa mensagem orienta operadores e scripts de monitoramento. |

### Acompanhamento e próximas etapas
1. **Validação manual**: testar start/stop em máquina limpa (ambas as scripts devem ser executáveis e logar em `logs/`). Documentar qualquer diferença na execução real (ex: pacotes adicionais, runtimes específicos).
2. **Automação**: registrar esses scripts como serviços (`systemd` ou `docker-compose exec`) e garantir que `growerp-start.sh` retorna ao usuário com instruções de health-check.
3. **Documentação complementar**: atualizar o `README.md` com referência direta aos scripts, incluindo flags disponíveis (ex: `--first-run`, `--no-ui`), e vincular este checklist para rastrear alterações futuras.
4. **Monitoramento futuro**: criar issue/área de acompanhamento (ex: em `plans/` ou Notion) com links para este checklist e status de testes de cada etapa.

> Use este checklist como fonte única para saber em que ponto da implementação dos scripts `growerp-start.sh` e `growerp-stop.sh` estamos. Atualize o status e as observações sempre que uma tarefa avançar (automatizando via `git` e/ou Notion/Planos internos).
