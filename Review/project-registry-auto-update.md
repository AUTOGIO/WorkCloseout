# Auto-Update do Registro de Projetos do WorkCloseout

**Data:** 2026-09-13  
**Solicitação:** Adicionar 10 projetos ao `work-closeout.json` e garantir atualização automática no futuro.

---

## 1. Projetos Adicionados

| # | Display Name | ID | Caminho | Comando de Verificação |
|---|---|---|---|---|
| 1 | BEATS | `beats` | `~/Automation/BEATS` | `python3 -m unittest discover -s tests -v` |
| 2 | cursor-skills | `cursor-skills` | `~/Documents/GitHub/cursor-skills` | *(nenhum)* |
| 3 | edu price analysis | `edu-price-analysis` | `~/Documents/GitHub/edu_price_analysis` | `make check-categories` |
| 4 | MacHealthOS | `machealthos` | `~/Documents/GitHub/MacHealthOS` | `swift test` |
| 5 | MacPanel | `macpanel` | `~/Automation/MacPanel` | `swift test` |
| 6 | Personal Finance | `personal-finance` | `~/Documents/GitHub/Personal_Finance` | `make check` |
| 7 | ProjectPulse | `projectpulse` | `~/Documents/GitHub/ProjectPulse` | `make check` |
| 8 | spencer | `spencer` | `~/Automation/spencer` | *(nenhum)* |
| 9 | WorkCloseout | `workcloseout` | `~/Documents/GitHub/WorkCloseout` | `swift test` |
| 10 | WorkflowSuggesterPro | `workflowsuggesterpro` | `~/Automation/WorkflowSuggesterPro` | `swift test` |

---

## 2. Script de Atualização Automática

Criado: `~/Documents/GitHub/WorkCloseout/scripts/update_work_closeout_config.py`

### O que ele faz
1. Lê `work-closeout.json` existente para preservar `artifactDirectory` e `obsidianProjectsDirectory`.
2. Varre os diretórios raiz configurados (`SCAN_ROOTS` sob `$HOME`):
   - `~/Automation`
   - `~/Documents/GitHub`
3. Encontra subdiretórios que são repositórios Git.
4. Processa projetos extras (`EXTRA_PROJECTS`) que não precisam ser Git — no caso, `~/Automation/spencer`.
5. Para cada projeto detectado:
   - Define `id`, `displayName`, `repositoryRoot`.
   - Descobre `allowedRoots` a partir de pastas como `scripts/`, `Sources/`, `src/`, `tests/`, `Tests/`, `docs/`, `config/` (**não** inclui `data/` nem `nfce/`).
   - Define `allowedExtensions` padrão.
   - Determina `verificationCommands` apenas em formas aceitas pelo core (`swift test`, `make check` / `check-categories` / `test` / `lint` / `verify`, `python3 -m unittest …`, `pytest`, `npm test`).
   - Associa `obsidianProjectNote` **somente** se a nota já existir com `type: project`. O script **nunca** cria, renomeia ou sobrescreve notas do Obsidian.
6. Escreve `work-closeout.json` de forma atômica via `tempfile` + `replace`.

### Como usar
```bash
cd ~/Documents/GitHub/WorkCloseout
python3 scripts/update_work_closeout_config.py
```

Após rodar, basta reabrir o app WorkCloseout (ou recarregar a config) para ver os projetos atualizados no dropdown.

---

## 3. Notas do Obsidian

Histórico (2026-09-13): uma execução anterior chegou a criar `~/Documents/Obsidian/Projects/ProjectPulse.md`. Esse comportamento foi removido — o updater atual apenas referencia notas existentes e registra `[skip-note]` quando faltam.

---

## 4. Validação Realizada

| Verificação | Resultado |
|---|---|
| `python3 -m json.tool work-closeout.json` | ✅ Válido |
| BEATS: `python3 -m unittest discover -s tests -v` | ✅ 13 tests OK |
| edu_price_analysis: `make check-categories` | ✅ `Current` |
| Personal_Finance: `make check` | ✅ `integrity check passed` |
| ProjectPulse: (após alinhamento) usar apenas comandos do allowlist do core | ver seção 5 |

---

## 5. Correção Após Lançamento Inicial

Na primeira abertura do app, a configuração foi rejeitada com:
```
Invalid configuration: verification command is not an approved check/test form: /usr/bin/python3 -m unittest discover -s tests -v
```

Causa: o WorkCloseout só aceita comandos que **comecem exatamente** com uma lista fixa:
```
make check
make check-categories
make test
make lint
make verify
swift test
python -m unittest
python3 -m unittest
pytest
npm test
```

Correções aplicadas:
- BEATS: `/usr/bin/python3 ...` → `python3 -m unittest ...`
- MacHealthOS: `./scripts/test.sh` → `swift test`
- ProjectPulse: descobriu-se que um `Makefile` com alvo `check` já existia, mapeando `make check` → `python3 scripts/scan_workspace.py`, então o comando aprovado `make check` é usado.

## 6. Observações

- Projetos sem `verificationCommands` (cursor-skills, spencer) aparecem no dropdown mas não executam verificação durante o closeout.
- O app WorkCloseout precisa ser reiniciado para refletir a nova configuração.
- `work-closeout.json` e o script `update_work_closeout_config.py` ainda não foram commitados no repositório WorkCloseout (o próprio WorkCloseout está em estado inicial sem commits). Isso pode ser feito quando o scaffold do WorkCloseout for commitado.

---

*Documento criado em: `/Users/giovannini.eduardogmail.com/Documents/GitHub/WorkCloseout/Review/project-registry-auto-update.md`*
