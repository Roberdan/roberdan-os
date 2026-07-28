# 2026-07-28 — GBrain bash code graph investigation

## Verdict

This is a **structural limit of the current GBrain code extraction/schema path**, not a one-off indexing bug for `run_preflight`.

The repo's bash files are ingested as `code` pages and even chunked with text labels like `function run_preflight`, but the persisted symbol metadata for bash chunks has `language: null`, `symbol_type: null`, and `symbol_name: null`. `gbrain code-def` and `gbrain code-callers` depend on that symbol metadata, so they cannot resolve bash functions. The contrast is that JavaScript symbols in the same source do have symbol metadata and are found by both `code-def` and the call graph.

Use ripgrep for bash symbol lookup in this repo:

```bash
# definition lookup for one shell function
rg -n '^[[:space:]]*run_preflight[[:space:]]*\(\)[[:space:]]*\{' --glob '*.sh' .

# generic shell-function definition inventory
rg -n '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{' --glob '*.sh' .

# textual caller/reference lookup
rg -n '\brun_preflight\b' --glob '*.sh' .
```

I also checked the suggested Python example. `bus/bus-mcp.py` is tracked and contains Python functions, but this GBrain source currently has no Python code pages for it, so the positive non-bash contrast below uses JavaScript symbols from `hooks/copilot/extension.template.mjs`.

## Evidence

### Worktree pin and observed function

```console
$ cat .gbrain-source
gstack-code-roberdan-os-67e84638
exit=0

$ nl -ba factory/dispatch-runner.sh | sed -n '100,112p'
   100	
   101	# run_preflight <card> <cli> — evaluates ALL checks, records every failing reason in
   102	# PREFLIGHT_REASONS. Returns 0 only if ALL hard checks pass — which NEVER happens
   103	# while dormant (#5). #7 (lock acquirable) is a skip-not-fail and is handled in the
   104	# activation path, never reached here.
   105	PREFLIGHT_REASONS=()
   106	run_preflight() {
   107	  local card="$1" repo="" root=""
   108	  if [ -n "$card" ] && [ -f "$card" ]; then
   109	    repo="$(field "$card" repo)"
   110	    # pwd -P (physical) so root matches the CANONICAL path git/kb-init store in the
   111	    # registry — otherwise a /var -> /private/var symlink makes #2 mismatch (registry).
   112	    root="$(cd "$(dirname "$card")/../.." 2>/dev/null && pwd -P || true)"
exit=0

$ rg -n '^(run_preflight|sandbox_env_run|rda_classify)\s*\(' factory/dispatch-runner.sh factory/runner-sandbox.sh learn/classify.sh
factory/dispatch-runner.sh:106:run_preflight() {
factory/runner-sandbox.sh:20:sandbox_env_run() {
learn/classify.sh:49:rda_classify() {
exit=0

$ rg -n '^def tool_bus_send\(' bus/bus-mcp.py
133:def tool_bus_send(args):
exit=0
```

`run_preflight` demonstrably exists at `factory/dispatch-runner.sh:106`.

### GBrain version and source state

```console
$ gbrain --version && printf '\n--- help ---\n' && gbrain --help | sed -n '1,160p'
gbrain 0.42.65.0

--- help ---
gbrain 0.42.65.0 -- personal knowledge brain

USAGE
  gbrain <command> [options]

SETUP
  init [--pglite|--supabase|--url]   Create brain (PGLite default, no server)
  migrate --to <supabase|pglite>     Transfer brain between engines
  upgrade                            Self-update
  check-update [--json]              Check for new versions
  doctor [--json] [--fast]            Health check (resolver, skills, pgvector, RLS, embeddings)
  integrations [subcommand]          Manage integration recipes (senses + reflexes)

PAGES
  get <slug>                         Read a page
  put <slug> [< file.md]             Write/update a page
  delete <slug>                      Delete a page
  list [--type T] [--tag T] [-n N]   List pages

SEARCH
  search <query>                     Keyword search (tsvector)
  query <question> [--no-expand]     Hybrid search (RRF + expansion)
  ask <question> [--no-expand]       Alias for query

IMPORT/EXPORT
  import <dir> [--no-embed]          Import markdown directory
  sync [--repo <path>] [flags]       Git-to-brain incremental sync
  sync --watch [--interval N]        Continuous sync (loops until stopped)
                                     See also: autopilot --install (continuous daemon).
  export [--dir ./out/]              Export to markdown
  export --restore-only [--repo <p>] Restore missing supabase-only files
        [--type T] [--slug-prefix S] With optional filters

FILES
  files list [slug]                  List stored files
  files upload <file> --page <slug>  Upload file to storage
  files upload-raw <file> --page <s> Smart upload (size routing + .redirect.yaml)
  files signed-url <path>            Generate signed URL (1-hour)
  files sync <dir>                   Bulk upload directory
  files verify                       Verify all uploads

EMBEDDINGS
  embed [<slug>|--all|--stale]       Generate/refresh embeddings

LINKS
  link <from> <to>                   Create typed link (alias: link-add)
        [--link-type T] [--link-source S]   provenance defaults to 'manual'
  unlink <from> <to>                 Remove link (alias: link-rm)
        [--link-type T] [--link-source S]   filter which edges to remove
  link-sources                       List provenances in use, with edge counts
  backlinks <slug>                   Incoming links
  graph <slug> [--depth N]           Traverse link graph (returns nodes)
  graph-query <slug> [--type T]      Edge-based traversal with type/direction filters
        [--depth N] [--direction in|out|both]

TAGS
  tags <slug>                        List tags
  tag <slug> <tag>                   Add tag
  untag <slug> <tag>                 Remove tag

TIMELINE
  timeline [<slug>]                  View timeline
  timeline-add <slug> <date> <text>  Add timeline entry

TOOLS
  extract <links|timeline|all>       Extract links/timeline (idempotent)
        [--source fs|db]             fs (default) walks .md files; db iterates engine pages
        [--dir <brain>]              brain dir for fs source
        [--type T] [--since DATE]    filters (db source)
        [--dry-run] [--json]
  publish <page.md> [--password]     Shareable HTML (strips private data, optional AES-256)
  check-backlinks <check|fix> [dir]  Find/fix missing back-links across brain
  lint <dir|file> [--fix]            Catch LLM artifacts, placeholder dates, bad frontmatter
  orphans [--json] [--count]         Find pages with no inbound wikilinks
  salience [--days N] [--kind P]     v0.29: pages ranked by emotional + activity salience
  anomalies [--since D] [--sigma N]  v0.29: cohort-based statistical anomalies (tag, type)
  transcripts recent [--days N]      v0.29: recent raw .txt transcripts (local-only)
  dream [--dry-run] [--json]         Run the overnight maintenance cycle once (cron-friendly).
                                     See also: autopilot --install (continuous daemon).
  check-resolvable [--json] [--fix]  Validate skill tree (reachability/MECE/DRY)
  report --type <name> --content ... Save timestamped report to brain/reports/

BRAIN (capture / ideate / explore — v0.37/v0.38)
  capture [content] [--file PATH]    Single entrypoint for getting content into the brain
        [--stdin] [--slug s] [--type t]   Inline content / file / stdin; writes to inbox/ by default
        [--source ID] [--quiet|--json]    Multi-source brains: route to a non-default source
  brainstorm <question> [--json]     Bisociation idea generator (hybrid search + far-set + judge)
        [--save|--no-save] [--limit N]
  lsd <question> [--json]            Lateral Synaptic Drift: inverted-judge brainstorm
        [--save|--no-save] [--limit N]    rewarding far-from-obvious + axiomatic inversions

SOURCES (multi-repo / multi-brain)
  sources list                       Show registered sources
  sources add <id> --path <p>        Register a source (id = short name, e.g. 'wiki')
  sources remove <id>                Remove a source + its pages (--confirm-destructive)
  sources archive <id>               Soft-delete: hide from search, recoverable for 72h
  sources restore <id>               Un-archive a soft-deleted source
  sources archived                   List soft-deleted sources and their purge expiry
  sources purge [<id>]               Permanently delete archived sources
  sources status                     Per-source dashboard (sync lag, embed coverage)
  sources --help                     Full subcommand list (rename, default, attach,
                                     current, federate, set-cr-mode, webhook, harden, ...)
  sync --all                         Sync all sources with a local_path
  sync --source <id>                 Sync one specific source
  repos ...                          DEPRECATED alias for 'sources' (v0.19.0)

CODE INDEXING (v0.19.0 / v0.20.0 Cathedral II)
  code-def <symbol> [--lang l]       Find the definition of a symbol across code pages
  code-refs <symbol> [--lang l]      Find all references to a symbol (JSON-first)
  code-callers <symbol>              Who calls this symbol? (v0.20.0 A1)
  code-callees <symbol>              What does this symbol call? (v0.20.0 A1)
  query <q> --lang <l>               Filter hybrid search to one language (v0.20.0)
  query <q> --symbol-kind <k>        Filter to symbol type (function|class|method|...) (v0.20.0)
  reconcile-links [--dry-run]        Batch-recompute doc↔impl edges (v0.20.0)
  reindex-code [--source id] [--yes] Explicit code-page reindex (v0.20.0)
  reindex-search-vector [--dry-run] [--yes] [--json]
                                Recreate FTS triggers + backfill under
                                $GBRAIN_FTS_LANGUAGE (default 'english')
  sync --strategy code               Sync code files into the brain

JOBS (Minions)
  jobs submit <name> [--params JSON]  Submit background job [--follow] [--dry-run]
  jobs list [--status S] [--limit N]  List jobs
  jobs get <id>                       Job details + history
  jobs cancel <id>                    Cancel job
  jobs retry <id>                     Re-queue failed/dead job
  jobs prune [--older-than 30d]       Clean old jobs
  jobs stats                          Job health dashboard
  jobs work [--queue Q]               Start worker daemon (Postgres only)

ADMIN
  stats                              Brain statistics
  health                             Brain health dashboard
  history <slug>                     Page version history
  revert <slug> <version-id>         Revert to version
  features [--json] [--auto-fix]     Scan usage + recommend unused features
  autopilot [--repo] [--interval N]  Self-maintaining brain daemon
  config [show|get|set] <key> [val]  Brain config
  storage status [--repo <path>]     Storage tier status and health
        [--json]                     (git-tracked vs supabase-only)
  serve                              MCP server (stdio)
  serve --http [--port N]            HTTP MCP server with OAuth 2.1
    --token-ttl N                    Access token TTL in seconds (default: 3600)
    --enable-dcr                     Enable Dynamic Client Registration (DCR clients default to authorization_code)
    --enable-dcr-insecure            Also allow the consent-bypassing client_credentials grant on DCR (implies --enable-dcr)
    --public-url URL                 Public issuer URL (required behind proxy/tunnel)
  connect <mcp-url> --token <t>      Wire Claude Code to a remote gbrain (bearer token)
        [--install] [--json]         Print the paste-ready command, or --install to run it
  watch [--json]                     Push-based context: pipe conversation turns in,
                                     volunteered brain pages stream out (#2095)
  call <tool> '<json>'               Raw tool invocation
  version                            Version info
  --tools-json                       Tool discovery (JSON)

Run gbrain <command> --help for command-specific help.
```

```console
$ gbrain sources current
source: gstack-code-roberdan-os-67e84638
  tier: dotfile (.gbrain-source)
exit=0
```

### Active schema pack

```console
$ gbrain schema active
Active pack: gbrain-base-v2 v1.0.0
Source: home-config
Pack identity: gbrain-base-v2@1.0.0+f4f6494a
Page types: 17
Link verbs: 14
Takes kinds: fact, take, bet, hunch

14-type DRY/MECE canonical taxonomy + `note` catch-all (15 total). Successor to gbrain-base. Issue
exit=0

$ gbrain schema show gbrain-base-v2
# gbrain-base-v2 v1.0.0
# 14-type DRY/MECE canonical taxonomy + `note` catch-all (15 total). Successor to gbrain-base. Issue
# extends: null (no parent)

Page types (17):
  person :: entity (people/, person/) aliases:[people, contact, individual, founder, partner, partner-profile] [expert]
  company :: entity (companies/, company/, products/, orgs/) aliases:[yc-company, product, org, people-org, organization, startup, business] [expert]
  media :: media (media/, videos/, articles/, essays/, books/, podcasts/, blog/, posts/) aliases:[article, video, essay, book, podcast, blog-post, youtube-video, podcast-episode] [extractable]
  tweet :: media (tweets/, twitter/) aliases:[tweet-single, tweet-thread, tweet-bundle, tweet-stub, twitter-post] [extractable]
  social-digest :: temporal (digests/social/) aliases:[social-digest-daily, social-digest-monthly]
  analysis :: media (wiki/analysis/, analysis/) aliases:[pricing-analysis, hiring-analysis, market-analysis, competitive-analysis, research, organization-research] [extractable]
  atom :: annotation (atoms/) aliases:[atom-extraction, atom-manual, atom-lore, content-atom, lore]
  concept :: concept (wiki/concepts/, wiki/concept/) aliases:[concept-stub, definition] [extractable]
  source :: media (sources/, source/) aliases:[sources/article, source/article, transcript, ref] [extractable]
  deal :: temporal (deals/, deal/) aliases:[investment, term-sheet]
  email :: temporal (emails/, email/) aliases:[email-thread] [extractable]
  slack :: temporal (slack/) aliases:[slack-message, slack-thread] [extractable]
  writing :: media (writing/) aliases:[draft, post-draft] [extractable]
  project :: concept (projects/, project/) aliases:[initiative, workstream]
  note :: concept (notes/, note/) aliases:[memo, anecdote, insight, principle, framework] [extractable]
  event :: temporal (life/events/)
  diary :: temporal (life/diary/)

Link verbs (14):
  partner_of
  relates_to
  mentions
  discusses
  founded
  works_at
  invested_in
  sourced_from
  derived_from
  supersedes
  redirects_to
  attended
  authored
  attributed_to

Takes kinds: fact, take, bet, hunch
Enrichable types: (none)
exit=0

$ gbrain call get_active_schema_pack '{}'
{
  "pack_name": "gbrain-base-v2",
  "version": "1.0.0",
  "sha8": "f4f6494a",
  "identity": "gbrain-base-v2@1.0.0+f4f6494a",
  "page_types_count": 17,
  "link_types_count": 14,
  "primitive_summary": {
    "entity": 2,
    "media": 5,
    "temporal": 6,
    "annotation": 1,
    "concept": 3
  },
  "source_tier": "home-config"
}
exit=0

$ gbrain call schema_explain_type '{"type":"code"}'
{
  "error": "type_not_found",
  "type": "code",
  "pack": "gbrain-base-v2"
}
exit=0
```

The active schema pack does not declare `bash`, `shell`, or even a `code` page type. Code pages exist as a separate code-indexing path, but not as schema-declared extractable types.

### Code pages exist, including bash pages

```console
$ gbrain schema stats --source $(cat .gbrain-source)
Pack: gbrain-base-v2@1.0.0+f4f6494a
Total pages: 160
Typed: 160 (100.0%)
Untyped: 0

By type:
  note                 70
  code                 53
  concept              37

Dead prefixes (declared but 0 pages):
  person               people/
  person               person/
  company              companies/
  company              company/
  company              products/
  company              orgs/
  media                media/
  media                videos/
  media                articles/
  media                essays/
  media                books/
  media                podcasts/
  media                blog/
  media                posts/
  tweet                tweets/
  tweet                twitter/
  social-digest        digests/social/
  analysis             wiki/analysis/
  analysis             analysis/
  atom                 atoms/
  concept              wiki/concepts/
  concept              wiki/concept/
  source               sources/
  source               source/
  deal                 deals/
  deal                 deal/
  email                emails/
  email                email/
  slack                slack/
  writing              writing/
  project              projects/
  project              project/
  note                 notes/
  note                 note/
  event                life/events/
  diary                life/diary/
exit=0

$ gbrain list --type code -n 20
bus-roles-implementer-json	code	2026-07-28	bus/roles/implementer.json (json)
bus-roles-sol-gate-json	code	2026-07-28	bus/roles/sol-gate.json (json)
hooks-autofmt-sh	code	2026-07-28	hooks/autofmt.sh (bash)
test-test-autofmt-sh	code	2026-07-28	test/test-autofmt.sh (bash)
hooks-copilot-extension-template-mjs	code	2026-07-27	hooks/copilot/extension.template.mjs (javascript)
test-test-copilot-adapter-sh	code	2026-07-27	test/test-copilot-adapter.sh (bash)
test-test-canon-guardrails-sh	code	2026-07-26	test/test-canon-guardrails.sh (bash)
bin-sync-sh	code	2026-07-25	bin/sync.sh (bash)
eval-report-sh	code	2026-07-22	eval/report.sh (bash)
eval-run-eval-sh	code	2026-07-22	eval/run-eval.sh (bash)
eval-test-eval-pipeline-sh	code	2026-07-22	eval/test-eval-pipeline.sh (bash)
evolve-declined-sh	code	2026-07-22	evolve/declined.sh (bash)
test-test-evolve-declined-sh	code	2026-07-22	test/test-evolve-declined.sh (bash)
test-test-factory-kb-sh	code	2026-07-20	test/test-factory-kb.sh (bash)
test-test-pending-sh	code	2026-07-20	test/test-pending.sh (bash)
bin-copilot-local-sh	code	2026-07-18	bin/copilot-local.sh (bash)
hooks-bash-guard-sh	code	2026-07-15	hooks/bash-guard.sh (bash)
test-leak-check-sh	code	2026-07-15	test/leak-check.sh (bash)
test-test-federated-kb-sh	code	2026-07-14	test/test-federated-kb.sh (bash)
test-test-kb-done-gate-sh	code	2026-07-14	test/test-kb-done-gate.sh (bash)
hooks-pre-completion-gate-sh	code	2026-07-10	hooks/pre-completion-gate.sh (bash)
bin-check-embedder-sh	code	2026-07-09	bin/check-embedder.sh (bash)
bin-pending-digest-sh	code	2026-07-09	bin/pending-digest.sh (bash)
bin-install-hooks-sh	code	2026-07-08	bin/install-hooks.sh (bash)
hooks-auto-checkpoint-sh	code	2026-07-08	hooks/auto-checkpoint.sh (bash)
hooks-post-task-sync-sh	code	2026-07-08	hooks/post-task-sync.sh (bash)
hooks-verify-done-sh	code	2026-07-08	hooks/verify-done.sh (bash)
learn-backfill-classify-sh	code	2026-07-08	learn/backfill-classify.sh (bash)
learn-capture-sh	code	2026-07-08	learn/capture.sh (bash)
learn-classify-sh	code	2026-07-08	learn/classify.sh (bash)
learn-distill-sh	code	2026-07-08	learn/distill.sh (bash)
loop-receipt-sh	code	2026-07-08	loop/receipt.sh (bash)
ontology-curate-sh	code	2026-07-08	ontology/curate.sh (bash)
test-test-install-hooks-sh	code	2026-07-08	test/test-install-hooks.sh (bash)
test-test-metaloop-sh	code	2026-07-08	test/test-metaloop.sh (bash)
test-test-receipts-sh	code	2026-07-08	test/test-receipts.sh (bash)
factory-lib-sh	code	2026-07-07	factory/lib.sh (bash)
test-test-sync-install-sh	code	2026-07-07	test/test-sync-install.sh (bash)
bin-identity-init-sh	code	2026-07-06	bin/identity-init.sh (bash)
bin-make-bundle-sh	code	2026-07-06	bin/make-bundle.sh (bash)
factory-dispatch-runner-sh	code	2026-07-06	factory/dispatch-runner.sh (bash)
factory-enqueue-sh	code	2026-07-06	factory/enqueue.sh (bash)
factory-run-sh	code	2026-07-06	factory/run.sh (bash)
factory-runner-sandbox-sh	code	2026-07-06	factory/runner-sandbox.sh (bash)
kanban-lint-cards-sh	code	2026-07-06	kanban/lint-cards.sh (bash)
test-test-fork-merge-sh	code	2026-07-06	test/test-fork-merge.sh (bash)
eval-judge-sh	code	2026-07-04	eval/judge.sh (bash)
eval-lib-sh	code	2026-07-04	eval/lib.sh (bash)
github-workflows-validate-yml	code	2026-07-02	.github/workflows/validate.yml (yaml)
bin-install-git-hooks-sh	code	2026-07-02	bin/install-git-hooks.sh (bash)
exit=0
```

### Python file check

```console
$ git ls-files bus/bus-mcp.py
bus/bus-mcp.py
exit=0

$ git status --short -- bus/bus-mcp.py factory/dispatch-runner.sh factory/runner-sandbox.sh learn/classify.sh hooks/copilot/extension.template.mjs
exit=0

$ gbrain list --type code -n 200 | grep -i "(python)"
exit=1

$ rg -n "^def |^class " --glob "*.py" .
./bus/bus-mcp.py:74:class ToolError(Exception):
./bus/bus-mcp.py:78:def _slug(field: str, value, *, allow_broadcast: bool = False) -> str:
./bus/bus-mcp.py:91:def _run_bus(args, *, stdin_path=None):
./bus/bus-mcp.py:133:def tool_bus_send(args):
./bus/bus-mcp.py:182:def _read_like(args, *, peek):
./bus/bus-mcp.py:192:def tool_bus_read(args):
./bus/bus-mcp.py:196:def tool_bus_peek(args):
./bus/bus-mcp.py:200:def tool_bus_log(args):
./bus/bus-mcp.py:270:def _result(request_id, payload):
./bus/bus-mcp.py:274:def _error(request_id, code, message):
./bus/bus-mcp.py:278:def handle(request):
./bus/bus-mcp.py:327:def main():
exit=0

$ gbrain code-def tool_bus_send --source "$(cat .gbrain-source)"
{
  "symbol": "tool_bus_send",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0
```

`bus/bus-mcp.py` exists and is tracked, but the source has no Python code page in the first 200 code pages and `tool_bus_send` is not found. I therefore used JavaScript for the required non-bash contrast.

### `code-def`: bash symbols fail, JavaScript symbols work

```console
$ gbrain code-def run_preflight
{
  "symbol": "run_preflight",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def run_preflight --source "$(cat .gbrain-source)"
{
  "symbol": "run_preflight",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def sandbox_env_run
{
  "symbol": "sandbox_env_run",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def sandbox_env_run --source "$(cat .gbrain-source)"
{
  "symbol": "sandbox_env_run",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def rda_classify
{
  "symbol": "rda_classify",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def rda_classify --source "$(cat .gbrain-source)"
{
  "symbol": "rda_classify",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def diag --source "$(cat .gbrain-source)"
{
  "symbol": "diag",
  "count": 1,
  "status": "ready",
  "ready": true,
  "results": [
    {
      "slug": "hooks-copilot-extension-template-mjs",
      "file": "hooks/copilot/extension.template.mjs",
      "language": "javascript",
      "symbol_type": "function",
      "start_line": 65,
      "end_line": 72,
      "snippet": "[JavaScript] hooks/copilot/extension.template.mjs:65-72 function diag\n\nfunction diag(where, e) {\n    try {\n        const msg = e && e.stack ? e.stack : String(e);\n        process.stderr.write(`[roberdan-os] ${where}: ${msg}\\n`);\n    } catch (_e) {\n        /* stderr itself is unavailable — there is nowhere left to report; do not crash the CLI */\n    }\n}"
    }
  ]
}
exit=0

$ gbrain code-def applyGuard --source "$(cat .gbrain-source)"
{
  "symbol": "applyGuard",
  "count": 1,
  "status": "ready",
  "ready": true,
  "results": [
    {
      "slug": "hooks-copilot-extension-template-mjs",
      "file": "hooks/copilot/extension.template.mjs",
      "language": "javascript",
      "symbol_type": "function",
      "start_line": 199,
      "end_line": 231,
      "snippet": "[JavaScript] hooks/copilot/extension.template.mjs:199-231 function applyGuard\n\nasync function applyGuard(scriptRel, stdinObj, cwd) {\n    const scriptPath = join(HOOKS, scriptRel);\n    if (!existsSync(scriptPath)) return undefined; // guard not installed -> no override\n    const { code, stdout } = await runScript(scriptPath, JSON.stringify(stdinObj), cwd);\n    if (code !== 0) {\n        return {\n            permissionDecision: \"ask\",\n            permissionDecisionReason: `roberdan-os ${scriptRel} "
    }
  ]
}
exit=0
```

Extra bash probes also failed, including bash chunks that search labels as functions:

```console
$ gbrain code-def mutate --source "$(cat .gbrain-source)"
{
  "symbol": "mutate",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def extract_json --source "$(cat .gbrain-source)"
{
  "symbol": "extract_json",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def mk_dispatch_card --source "$(cat .gbrain-source)"
{
  "symbol": "mk_dispatch_card",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def conf_get --source "$(cat .gbrain-source)"
{
  "symbol": "conf_get",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0

$ gbrain code-def fm --source "$(cat .gbrain-source)"
{
  "symbol": "fm",
  "count": 0,
  "status": "ready",
  "ready": true,
  "results": []
}
exit=0
```

### `code-callers` before graph rebuild

```console
$ gbrain code-callers run_preflight
{
  "symbol": "run_preflight",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "indexing",
  "ready": false,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers run_preflight --source "$(cat .gbrain-source)"
{
  "symbol": "run_preflight",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "indexing",
  "ready": false,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers sandbox_env_run --source "$(cat .gbrain-source)"
{
  "symbol": "sandbox_env_run",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "indexing",
  "ready": false,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers rda_classify --source "$(cat .gbrain-source)"
{
  "symbol": "rda_classify",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "indexing",
  "ready": false,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers diag --source "$(cat .gbrain-source)"
{
  "symbol": "diag",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 2,
  "status": "ready",
  "ready": true,
  "callers": [
    {
      "id": 425642,
      "from_chunk_id": 303759,
      "to_chunk_id": null,
      "from_symbol_qualified": "runStopChain",
      "to_symbol_qualified": "diag",
      "edge_type": "calls",
      "edge_metadata": {
        "resolved_chunk_id": 303753
      },
      "source_id": "gstack-code-roberdan-os-67e84638",
      "resolved": false
    },
    {
      "id": 425649,
      "from_chunk_id": 303758,
      "to_chunk_id": null,
      "from_symbol_qualified": "applyGuard",
      "to_symbol_qualified": "diag",
      "edge_type": "calls",
      "edge_metadata": {
        "resolved_chunk_id": 303753
      },
      "source_id": "gstack-code-roberdan-os-67e84638",
      "resolved": false
    }
  ]
}
exit=0
```

Before the rebuild, `diag` already proved the graph was not wholly empty, but the bash symbols still reported `ready: false`, so I rebuilt the graph as requested.

### Graph rebuild

```console
$ gbrain dream --source $(cat .gbrain-source)
[cycle.lint] start
[cycle.lint] done
[cycle.backlinks] start
[backlinks.scan] start
[backlinks.scan] done
[cycle.backlinks] done
[cycle.sync] start
[gbrain phase] sync.resolve_repo
[gbrain phase] sync.load_active_pack
[gbrain phase] sync.validate_repo_state
[gbrain phase] sync.discover_git_root
[gbrain phase] sync.detect_head
  Deleted un-syncable page: bin-bootstrap-sh
  Deleted un-syncable page: bus-bus-sh
  Deleted un-syncable page: evolve-watch-sh
  Deleted un-syncable page: hooks-context-inject-sh
  Deleted un-syncable page: kanban-kb-sh
  Deleted un-syncable page: test-test-bus-mutants-sh
  Deleted un-syncable page: test-test-bus-sh
  Deleted un-syncable page: test-validate-sh
[sync.imports] start
[gbrain] content-sanity warn: changelog (82315 bytes) — exceeds warn threshold, consider splitting
[sync.imports] 5/5 (100%) AGENTS.md
[sync.imports] 5/5 (100%) done
Text imported. Run 'gbrain embed --stale' to generate embeddings.
[cycle.sync] done
[cycle.synthesize] start
[cycle.synthesize] done
[cycle.extract] start
[extract.incremental] start
[extract.incremental] 5/5 (100%)
[extract.incremental] 5/5 (100%) done
[cycle.extract] done
Incremental extract: created 1 link(s), 0 timeline entries from 5/5 page(s)
[cycle.extract_facts] start
[cycle.extract_facts] done
[cycle.resolve_symbol_edges] start
[cycle.resolve_symbol_edges] done
[cycle.patterns] start
[cycle.patterns] done
[cycle.recompute_emotional_weight] start
[cycle.recompute_emotional_weight] done
[cycle.consolidate] start
[cycle.consolidate] done
[cycle.propose_takes] start
[cycle.propose_takes] done
[cycle.grade_takes] start
[cycle.grade_takes] done
[cycle.calibration_profile] start
[cycle.calibration_profile] done
[cycle.drift] start
[cycle.drift] done
[cycle.conversation_facts_backfill] start
[cycle.conversation_facts_backfill] done
[cycle.enrich_thin] start
[cycle.enrich_thin] done
[cycle.skillopt] start
[cycle.skillopt] done
[cycle.embed] start

  Error embedding apps-web-src-components-settings-sections-profile-settings-tsx: [embed(ollama:bge-m3)] the input length exceeds the context length

  Error embedding docs-docusaurus-package-lock-json: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding virtualbpm-js: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding index-html: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding virtualbpm-css: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding test_server_contracts-py: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding test_meeting_updates_concurrency-py: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-roberdan-os/2026-07-21-9c54967a-985: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-trading-os/2026-07-13-233df5a4-018: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-trading-os/2026-07-17-410ffdb4-372: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding drawer_contract_harness-js: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding edge_frontend_smoke-js: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-roberdan-os/2026-07-07-b441b188-9e9: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-roberdan-os/2026-07-06-92b79484-770: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-roberdan-os/2026-07-04-625261ff-898: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-roberdan-os/2026-07-01-bef7cea6-a10: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-fabrica/2026-07-08-9202f66c-0e6: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-fabrica/2026-07-09-64a3617b-3ac: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-fabrica/2026-07-06-96f585a0-926: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-fabrica/2026-07-05-f1d2287a-e2b: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-convergioedu2030/2026-07-06-dc99eba4-3f2: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-convergioedu2030/2026-07-04-ae690222-5d7: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan-convergio-edu/2026-07-03-58282d19-b62: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan_microsoft-virtualbpmfy27/2026-07-27-94cf6424-ea4: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan_microsoft-virtualbpmfy27/2026-07-26-6386b659-341: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan_microsoft-virtualbpmfy27/2026-07-25-f0ab6117-84a: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan_microsoft-virtualbpmfy27/2026-07-25-0e756319-fbf: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/roberdan_microsoft-virtualbpmfy27/2026-07-19-8bdb2d0f-b56: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/mcaps-microsoft-studio3_emea/2026-07-20-b8120e68-609: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/fightthestroke-mirrorbuddy/2026-07-03-0517afe6-062: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/fightthestroke-mirrorbuddy/2026-07-02-ff72b99f-932: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding transcripts/claude-code/_unattributed/2026-07-24-7dc38efe-825: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding test_sol_round11-py: [embed(ollama:bge-m3)] The operation timed out.

  Error embedding test_sol_round10-py: [embed(ollama:bge-m3)] The operation timed out.
[cycle.embed] done
[cycle.orphans] start
[orphans.scan] start
[orphans.scan] done
[cycle.orphans] done
[cycle.schema_suggest] start
[cycle.schema_suggest] done
[cycle.purge] start
[cycle.purge] done
[cycle] phase 'embed' ran 592s, exceeding the 30s worker force-evict deadline — if this cycle is force-evicted on abort, 'embed' is the likely cause (#1972).
Dream cycle (partial) in 610.9s:
  ! lint        0 fix(es) applied, 406 remaining
  ✓ backlinks   no missing back-links found
  ✓ sync        +0 added, ~5 modified, -0 deleted
  - synthesize  dream.synthesize.session_corpus_dir is unset
  ✓ extract     1 link(s), 0 timeline entries (incremental: 5 slugs)
  ✓ extract_facts  0 fact(s) reconciled across 5 page(s)
  - extract_atoms  extract_atoms: active pack does not declare this phase (run `gbrain dream --phase extract_atoms --drain` to drain a backlog)
  ✓ resolve_symbol_edges  6391 chunk(s) walked; resolved 739, ambiguous 7, unmatched 11481
  - patterns    0 reflections in last 30d (need ≥3)
  - synthesize_concepts  synthesize_concepts: active pack does not declare this phase
  ✓ recompute_emotional_weight  recompute_emotional_weight (23 pages)
  ✓ consolidate  promoted 0 facts into 0 takes across 0 buckets
  - propose_takes  propose_takes skipped: no Anthropic API key configured (set ANTHROPIC_API_KEY or run: gbrain config set anthropic_api_key ...)
  ✓ grade_takes  grade_takes: scanned 0 takes (0 too recent, 0 cached, 0 new verdicts, 0 auto-applied)
  ✓ calibration_profile  calibration_profile: holder=self has only 0 resolved takes (need >=5 for a profile)
  - drift       dream.drift.enabled is false
  - conversation_facts_backfill  cycle.conversation_facts_backfill.enabled=false (default OFF)
  - enrich_thin  cycle.enrich_thin.enabled=false (default OFF)
  - skillopt    feature flag off (gbrain config set cycle.skillopt.enabled true to enable)
  ✓ embed       4731 chunk(s) newly embedded (0 already had embeddings)
  ! orphans     89 orphan page(s) out of 160 total
  ✓ schema-suggest  8 suggestions emitted
  ✓ purge       purged 0 source(s), 0 page(s), 0 orphan clone temp dir(s), 0 stale op_checkpoint(s), 0 stale brainstorm checkpoint(s), 0 stale batch-retry audit file(s), and 0 stale volunteer event(s)
  totals: lint=0 backlinks=0 synced=5 extracted=1 embedded=4731 orphans=89 synth_transcripts=0 synth_pages=0 patterns=0
exit=0
```

### `code-callers` after graph rebuild

```console
$ gbrain code-callers run_preflight --source "$(cat .gbrain-source)"
{
  "symbol": "run_preflight",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "ready",
  "ready": true,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers sandbox_env_run --source "$(cat .gbrain-source)"
{
  "symbol": "sandbox_env_run",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "ready",
  "ready": true,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers rda_classify --source "$(cat .gbrain-source)"
{
  "symbol": "rda_classify",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "ready",
  "ready": true,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0

$ gbrain code-callers diag --source "$(cat .gbrain-source)"
{
  "symbol": "diag",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 2,
  "status": "ready",
  "ready": true,
  "callers": [
    {
      "id": 425642,
      "from_chunk_id": 303759,
      "to_chunk_id": null,
      "from_symbol_qualified": "runStopChain",
      "to_symbol_qualified": "diag",
      "edge_type": "calls",
      "edge_metadata": {
        "resolved_chunk_id": 303753
      },
      "source_id": "gstack-code-roberdan-os-67e84638",
      "resolved": false
    },
    {
      "id": 425649,
      "from_chunk_id": 303758,
      "to_chunk_id": null,
      "from_symbol_qualified": "applyGuard",
      "to_symbol_qualified": "diag",
      "edge_type": "calls",
      "edge_metadata": {
        "resolved_chunk_id": 303753
      },
      "source_id": "gstack-code-roberdan-os-67e84638",
      "resolved": false
    }
  ]
}
exit=0

$ gbrain code-callers applyGuard --source "$(cat .gbrain-source)"
{
  "symbol": "applyGuard",
  "source_id": "gstack-code-roberdan-os-67e84638",
  "scope": "single",
  "count": 0,
  "status": "ready",
  "ready": true,
  "callers": [],
  "hint": "No callers in source 'gstack-code-roberdan-os-67e84638'. Try --all-sources to search every source."
}
exit=0
```

After `gbrain dream`, the bash results changed from `status: indexing` to `status: ready`, but still have zero callers. That rules out “graph not built” as the reason.

### The settling evidence: chunk metadata for bash vs JavaScript

```console
$ gbrain call get_chunks "{\"slug\":\"factory-dispatch-runner-sh\"}" | python3 -c 'import json,sys; chunks=json.load(sys.stdin); print("chunk_count", len(chunks));
for c in chunks[:10]:
    preview=(c.get("chunk_text") or "")[:110].replace("\n","\\n")
    print({"idx":c.get("chunk_index"),"lang":c.get("language"),"type":c.get("symbol_type"),"symbol":c.get("symbol_name"),"start":c.get("start_line"),"end":c.get("end_line")}, preview)'
chunk_count 8
{'idx': 0, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:15-37 merged (8 siblings)\n\nDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
{'idx': 1, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:38-48 merged (2 siblings)\n\nKB_HOME="${RDA_KANBAN:-$ROOT/kanban}"\n\n_repo_in_a
{'idx': 2, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:52-61 function _board_privacy_ok\n\n_board_privacy_ok() {\n  local root="$1" ho
{'idx': 3, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:64-70 function _worktree_ok\n\n_worktree_ok() {\n  local root="$1"\n  [ -n "$roo
{'idx': 4, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:73-78 function _cred_stripping_ok\n\n_cred_stripping_ok() {\n  [ -f "$DIR/runne
{'idx': 5, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:81-105 merged (4 siblings)\n\n_os_floor_ok() { [ "$OS_FLOOR_PRESENT" -eq 1 ]; 
{'idx': 6, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:106-124 function run_preflight\n\nrun_preflight() {\n  local card="$1" repo="" 
{'idx': 7, 'lang': None, 'type': None, 'symbol': None, 'start': None, 'end': None} [Bash] factory/dispatch-runner.sh:126-147 function main\n\nmain() {\n  local arg="${1:-}" cli="${2:-copilot-cli}"
exit=0

$ gbrain call get_chunks "{\"slug\":\"hooks-copilot-extension-template-mjs\"}" | python3 -c 'import json,sys; chunks=json.load(sys.stdin); print("chunk_count", len(chunks));
for c in chunks[:10]:
    preview=(c.get("chunk_text") or "")[:110].replace("\n","\\n")
    print({"idx":c.get("chunk_index"),"lang":c.get("language"),"type":c.get("symbol_type"),"symbol":c.get("symbol_name"),"start":c.get("start_line"),"end":c.get("end_line")}, preview)'
chunk_count 13
{'idx': 0, 'lang': 'javascript', 'type': 'merged', 'symbol': None, 'start': 47, 'end': 59} [JavaScript] hooks/copilot/extension.template.mjs:47-59 merged (6 siblings)\n\nconst RDA_OS = process.env.RDA_OS
{'idx': 1, 'lang': 'javascript', 'type': 'lexical declaration', 'symbol': None, 'start': 60, 'end': 60} [JavaScript] hooks/copilot/extension.template.mjs:60-60 lexical declaration\n\nconst RDA_KANBAN_REGISTRY = proce
{'idx': 2, 'lang': 'javascript', 'type': 'function', 'symbol': 'diag', 'start': 65, 'end': 72} [JavaScript] hooks/copilot/extension.template.mjs:65-72 function diag\n\nfunction diag(where, e) {\n    try {\n   
{'idx': 3, 'lang': 'javascript', 'type': 'lexical declaration', 'symbol': None, 'start': 76, 'end': 76} [JavaScript] hooks/copilot/extension.template.mjs:76-76 lexical declaration\n\nconst WRITE_TOOLS = new Set(["edi
{'idx': 4, 'lang': 'javascript', 'type': 'merged', 'symbol': None, 'start': 77, 'end': 111} [JavaScript] hooks/copilot/extension.template.mjs:77-111 merged (6 siblings)\n\nconst SHELL_TOOLS = new Set(["ba
{'idx': 5, 'lang': 'javascript', 'type': 'merged', 'symbol': None, 'start': 113, 'end': 140} [JavaScript] hooks/copilot/extension.template.mjs:113-140 merged (2 siblings)\n\nlet session;\n\nfunction runScrip
{'idx': 6, 'lang': 'javascript', 'type': 'function', 'symbol': 'runKb', 'start': 145, 'end': 188} [JavaScript] hooks/copilot/extension.template.mjs:145-188 function runKb\n\nfunction runKb(argv, cwd) {\n    retu
{'idx': 7, 'lang': 'javascript', 'type': 'function', 'symbol': 'applyGuard', 'start': 199, 'end': 231} [JavaScript] hooks/copilot/extension.template.mjs:199-231 function applyGuard\n\nasync function applyGuard(scrip
{'idx': 8, 'lang': 'javascript', 'type': 'function', 'symbol': 'runStopChain', 'start': 235, 'end': 263} [JavaScript] hooks/copilot/extension.template.mjs:235-263 function runStopChain\n\nasync function runStopChain(c
{'idx': 9, 'lang': 'javascript', 'type': 'function', 'symbol': 'kanbanArgv', 'start': 270, 'end': 310} [JavaScript] hooks/copilot/extension.template.mjs:270-310 function kanbanArgv\n\nfunction kanbanArgv(args) {\n   
exit=0
```

This is the key distinction. The bash chunk text itself says `function run_preflight`, but the symbol columns are null. JavaScript chunks populate `language`, `symbol_type`, `symbol_name`, and line numbers. That is why the JavaScript symbol lookup works and bash lookup does not.

## Conclusion

Not an indexing bug specific to `run_preflight`. The GBrain source has the file and the chunk, and after `gbrain dream` the graph is ready. The missing piece is structural: bash chunks do not populate symbol metadata in this schema/extractor path, so symbol-aware commands cannot see bash functions.

Until GBrain adds bash/shell symbol extraction, use ripgrep for shell functions in this repo:

```bash
rg -n '^[[:space:]]*run_preflight[[:space:]]*\(\)[[:space:]]*\{' --glob '*.sh' .
rg -n '\brun_preflight\b' --glob '*.sh' .
```
