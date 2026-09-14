# Plano de Tratamento — Dirty State em `edu_price_analysis`

**Data:** 2026-09-13  
**Repositório:** `~/Documents/GitHub/edu_price_analysis`  
**Status do git:** `main` em `ea2518a`, **in sync com `origin/main`**, mas com working tree sujo.  
**Contexto já documentado:** Nota do Obsidian `edu_price_analysis.md` identifica o dirty state como *"v2→v3 workbook migration"*.

---

## 1. Resumo das Alterações Não Commitadas

### 1.1 Deletados (traked)
| Arquivo | Motivo provável |
|---|---|
| `02_Models/personal_inflation_tracker-v2.xlsx` | Substituído pelo v3 |
| `02_Models/personal_inflation_tracker-v2.BACKUP_pre_append.xlsx` | Backup pré-migração não mais necessário |
| `Claude outputs/SKILL.md` | Skill movida para outro local |
| `skill/edu-price-analysis.mdc` | Regra migrada para `.cursor/rules/` |

### 1.2 Modificados (tracked)
| Arquivo | Motivo provável |
|---|---|
| `.claude/skills/edu-price-analysis/SKILL.md` | Atualização de skill |
| `.cursor/rules/edu-price-analysis.mdc` | Atualização de regra |
| `02_Models/iip_terminal.html` | HTML congelado v3 |
| `02_Models/modelo_financeiro_saneado_v3.xlsx` | Ajustes no modelo saneado |
| `03_Raw_Data/MercadoPago_Apr-Aug_2026_Professional_Analysis.xlsx` | Dados brutos atualizados |
| `AGENTS.md` | Regras atualizadas para v3 |
| `Makefile` | Alvos atualizados para v3 |
| `README.md` | Documentação da migração |
| `README_Personal_Inflation.md` | README v3 |
| `USER_GUIDE.md` | Guia v3 |
| `open_analysis.command` | Launcher v3 |
| `skill/SKILL.md` | Skill v3 |

### 1.3 Não rastreados (`??`)
| Arquivo / Diretório | Motivo provável |
|---|---|
| `.cursor/rules/020-context-and-tabs.mdc` | Nova regra de contexto |
| `.cursor/rules/030-verification.mdc` | Nova regra de verificação |
| `02_Models/_backups/` | Backups gerados automaticamente |
| `02_Models/personal_inflation_tracker-v3_classificacao.xlsx` | **Novo workbook canônico v3** |
| `A_NOTE_TO_FUTURE_ME.md` | Nota de migração |
| `CONTEXT_CHECKLIST.md` | Checklist de contexto |
| `_to_delete/` | Lixeira de leftovers |
| `edu_price_analysis.json` | Configuração WorkCloseout para o projeto |
| `scripts/refresh_iip_categories.py` | Script de refresh de categorias |
| `tests/test_refresh_iip_categories.py` | Testes do script |

---

## 2. Recomendação de Commit

Dado que o dirty state é uma migração v2→v3 coerente e já documentada, recomenda-se **um único commit de migração** seguido de limpeza de leftovers.

### Passo 1 — Commit da migração v2→v3
Mensagem sugerida:
```
feat: migrate inflation tracker from v2 to v3

- Replace personal_inflation_tracker-v2.xlsx with v3 classification workbook
- Add category refresh script + tests (refresh_iip_categories.py)
- Update README, USER_GUIDE, AGENTS.md, Makefile, and open_analysis.command for v3
- Add WorkCloseout project config (edu_price_analysis.json)
- Add context and verification Cursor rules
- Remove obsolete v2 backup and old skill location
```

Arquivos incluídos:
- Todos os modified tracked, exceto itens que devem ser ignorados (ver Passo 2).
- Todos os untracked acima, exceto `_to_delete/` e `02_Models/_backups/` (ver Passo 2).

### Passo 2 — Limpeza pós-commit
| Item | Ação recomendada |
|---|---|
| `_to_delete/` | Revisar conteúdo e deletar se confirmado lixo. |
| `02_Models/_backups/` | Adicionar a `.gitignore` ou mover para fora do repo. |
| `02_Models/personal_inflation_tracker-v2.BACKUP_pre_append.xlsx` (deleted) | Confirmar que já existe backup externo; permitir exclusão do git. |

### Passo 3 — Verificação
- `make check-categories` deve continuar retornando `Current`.
- `make tree` deve listar a estrutura v3 sem `_to_delete`.

---

## 3. Riscos e Decisões Pendentes

| Decisão | Opções | Recomendação |
|---|---|---|
| `_to_delete/` contém lixo seguro? | (a) revisar e deletar; (b) manter fora do commit; (c) mover para archive externo | **(a)** após revisão de 30 segundos |
| `_backups/` deve ser versionado? | (a) sim; (b) não, adicionar a `.gitignore`; (c) manter fora do repo | **(b)** — backups são artefatos de execução |
| `03_Raw_Data/MercadoPago_Apr-Aug_2026_Professional_Analysis.xlsx` deve ir no commit? | (a) sim, dados fonte; (b) não, dados sensíveis | **(a)** — já estava tracked |

---

## 4. Comando Proposto (não executado)

```bash
cd ~/Documents/GitHub/edu_price_analysis

# 1. Stage da migração v2→v3 (excluindo _to_delete e _backups)
git add --all
# Desfazer staging de leftovers
# (seria executado com os paths específicos após aprovação)

# 2. Commit
git commit -m "feat: migrate inflation tracker from v2 to v3"

# 3. Limpeza de leftovers (após revisão manual)
# rm -rf _to_delete/
# echo "02_Models/_backups/" >> .gitignore
```

**Ação requerida:** Aprovação explícita para executar o commit e a limpeza acima.

---

## 5. Execução Realizada (2026-09-13)

Após aprovação do usuário, os seguintes passos foram executados:

1. **Commit da migração v2→v3** — `99f52af`:
   - 24 arquivos alterados, 1.073 inserções, 568 deleções.
   - Incluiu todos os arquivos planejados, excluindo `_to_delete/` e `02_Models/_backups/`.

2. **Limpeza pós-commit** — `7502a7f`:
   - `_to_delete/` removido (continha `.DS_Store`, `IMG_1641.HEIC`, `IMG_1641.jpeg`, `dashboard_financeiro_profissional.xlsx`, `family_office_logo_cover.png`).
   - `02_Models/_backups/` adicionado a `.gitignore`.

3. **Verificação**:
   - `make check-categories` → `Current` ✅
   - `git status --short` → limpo ✅

**Status:** Plano executado com sucesso. Repositório está limpo e na branch `main` com 2 commits acima de `ea2518a`.

### 5.1 Push para origin (executado após aprovação adicional)
```text
To https://github.com/AUTOGIO/Personal_Finance.git
   ea2518a..7502a7f  main -> main
```
Ambos os commits (`99f52af` e `7502a7f`) foram enviados para `origin/main`.

---

*Documento criado em: `/Users/giovannini.eduardogmail.com/Documents/GitHub/WorkCloseout/Review/edu_price_analysis-dirty-state-plan.md`*
