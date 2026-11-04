# LLM::API 2.0.0 Release Notes

## Overview

Version 2.0.0 is a major release that transforms `LLM::API` from an
Anthropic-only HTTP client into a provider-independent dispatcher with
pluggable backend implementations. Amazon Bedrock Converse is added as
a first-class provider alongside the existing Anthropic direct API.
The release also includes a substantial overhaul of the build and
development toolchain.

---

## Provider Architecture

### Provider-Independent Dispatcher

`LLM::API` now selects a backend at construction time via a `provider`
argument. The default is `'anthropic'`, preserving backward
compatibility for existing callers that do not pass `provider`. The
constructor rejects unrecognized provider names with a clear error.

Provider implementations are looked up by name in the new
`providers.yml` catalog, which is shipped as a distribution share
file. The catalog maps each provider to its implementation class and
curated model pricing. It is loaded once per process and cached. For
source-checkout pre-install tests, the module falls back to loading
`providers.yml` from the project root when the installed share file is
not available.

### Amazon Bedrock Support (`LLM::API::Bedrock`)

A new `LLM::API::Bedrock` module provides transport to Amazon Bedrock
via the Converse API. Key behaviors:

- **Authentication** uses AWS credentials resolved by the underlying
  AWS client (`Amazon::Credentials`). No Anthropic API key is
  required.
- **Region** is resolved in order from: the `region` constructor
  argument, `AWS_REGION`, `AWS_DEFAULT_REGION`, falling back to
  `us-east-1`.
- **Default model** is `amazon.nova-micro-v1:0`.
- **Document handling**: text documents are sent as text content
  blocks; PDF sources are decoded from base64 and passed as raw bytes
  to the Converse transport. PDF submission requires a document-capable
  model; Nova Micro is text-only.
- **Token counting** uses the Bedrock `CountTokens` path where
  supported by the selected model.

New dependencies for Bedrock support: `Amazon::API::BedrockRuntime`
1.43.84 and `Amazon::Credentials` 2.0.1.

### Anthropic Transport (`LLM::API::Anthropic`)

The Anthropic HTTP transport has been extracted into a new
`LLM::API::Anthropic` module. The public interface of `LLM::API` is
unchanged for Anthropic callers; `LLM::API` now delegates to this
class rather than implementing transport directly.

### Provider Catalog (`providers.yml`)

`providers.yml` is the authoritative source for provider-to-class
mappings and model pricing. Each model entry records
`input_tokens` and `output_tokens` as `[price_usd, token_count]`
pairs. `pricing()` divides the quoted price by the token count to
return a per-token rate. The catalog does not perform live model
discovery.

---

## New and Changed Public API

### `new` — Constructor Changes

Two new constructor options:

- `provider` — `'anthropic'` (default) or `'bedrock'`
- `region` — AWS request region for Bedrock

For Anthropic, `api_key` remains required. For Bedrock, `api_key` is
neither required nor used.

### `send_messages` — New Method

`send_messages($messages_aref)` accepts an explicit multi-turn
conversation as a nonempty array reference of `{ role, content }`
hash references. Each message must have a role of `user` or
`assistant`; content must be an array reference of `text()` or
`document()` blocks. Document blocks are restricted to user messages.
Validation is performed in `LLM::API` before the call is delegated to
the provider. The caller supplies the complete conversation on each
invocation; no history is maintained.

### `pricing` — Rewritten

Pricing is now loaded from `providers.yml` rather than a hardcoded
Perl constant. The method throws if the requested provider/model
combination is absent or malformed in the catalog.

### `$LLM_MAX_TOKENS` Default Increased

The default `max_tokens` value has been raised from 4096 to 8192.

### Provider-Restricted Methods

`models()`, `api_keys()`, `usage_report()`, `cost_report()`, and
`headers()` now throw an explicit exception when called on a
non-Anthropic provider instance.

### New Accessors

`get_provider` / `set_provider` and `get_region` / `set_region` are
now available.

---

## `LLM::API::Response` Changes

- **`from_result`** — new class method that constructs a response from
  a normalized result hash without requiring an HTTP response body.
  Used by provider implementations that return structured data rather
  than raw HTTP responses.
- **`from_error`** — new class method that constructs a failed
  response from a code and message string, also without an HTTP body.
- **`provider_response`** — new accessor that holds the raw provider
  response object.
- **`error`** — now returns `provider_error_message` when present,
  before attempting to decode a JSON body. This correctly represents
  errors from providers that do not return an HTTP body.
- **`_load_result`** — extracted from `init()` and shared between
  `new()` and `from_result()`; tolerates missing `usage` or `content`
  keys.

---

## New Test Suite

Seven new unit test files cover the provider architecture:

| File | Coverage |
|------|----------|
| `t/01-anthropic-transport.t` | Anthropic transport: `count_input_tokens`, `send_prompt`, `headers` |
| `t/02-provider-contract.t` | Provider-restricted methods throw for non-Anthropic instances |
| `t/03-bedrock-provider.t` | Bedrock construction, region resolution, `send_prompt` dispatch |
| `t/04-conversation.t` | `send_messages` validation: bad role, missing text, document placement, valid multi-turn |
| `t/05-bedrock-count-tokens.t` | Bedrock `CountTokens` path |
| `t/06-documents.t` | `document()` block construction; Bedrock adapter translation of PDF |
| `t/07-provider-catalog.t` | `providers.yml` loading, `pricing()` calculation, missing entry errors |

A live integration test (`xt/live-bedrock-pdf.t`) with a sample PDF
(`xt/sample.pdf`) is provided for Bedrock PDF document submission;
this test requires AWS credentials and a document-capable model, and
is not run as part of the standard test suite.

New test dependencies: `HTTP::Tiny` 0.088, `JSON::PP` 4.16.

---

## Build and Toolchain Changes

This release includes a comprehensive overhaul of the
`CPAN::Maker::Bootstrapper`-managed build infrastructure. These
changes are primarily developer-visible.

### Makefile

- Requires **GNU Make 4.3** (grouped-target feature). The Makefile
  now checks for this at startup and fails with a clear error if the
  requirement is not met.
- `pipefail` is now set via `.SHELLFLAGS`, making shell pipelines in
  recipes fail on the first failing command.
- A `config.mk` file is introduced for local project configuration.
  `build-config.mk` is generated from `cmb create-build-config` and
  included unconditionally.
- Project-registered command role extensions are loaded via
  `-include .roles/*/role.mk`.
- Dependency scanning (`SCANDEPS`) now produces `requires.raw`,
  `recommends.raw`, and `suggests.raw` in a single grouped target,
  replacing the previous per-file scan macro. A reconcile step follows
  via `BOOTSTRAPPER reconcile-deps`.
- `recommends` and `suggests` dependency tiers are now tracked in
  addition to `requires`.
- `cpanfile` is now assembled from `cpanfile.requires`,
  `cpanfile.suggests`, and `cpanfile.recommends` partial files.
- Two new targets: `real-quick` (skips scanning, linting, pod
  checking, and syntax checking) and `package` (enforces
  `LINT=on SCAN=on`).
- Removed targets: `build-ci`, `workflow`, `modulino`.
- DarkPAN support added: `cpanfile.darkpan` and `cpanm.darkpan`
  targets, controlled by `DARKPAN_REQUIRES` and `DARKPAN_URL`.

### Module Rendering Pipeline (`perl.mk`)

- Source files are rendered as `.pm.in` → `.pm.rendered` (via
  `BOOTSTRAPPER resolve-vars` with a generated vars file) → `.pm`
  (copy or `podextract`).
- Syntax checking (`%.pm.checked`, `%.pl.checked`) now depends on the
  `.rendered` intermediate file and respects a `compile.skip` file.
- `perltidy` and `perlcritic` checks now batch all files via
  `BOOTSTRAPPER perltidy/perlcritic --file-list` grouped targets,
  replacing the previous per-file pattern rules.
- `PERLCRITIC_SEVERITY` (default: `5`) and `PERLCRITIC_THEME`
  (default: `pbp`) are new configurable variables.
- `PERLINCLUDE` now includes `local/lib/perl5`. `PERL5LIB` is cleared
  during syntax checks.
- `check-syntax`, `render-files`, and `test-resolver` are new phony
  targets.
- `deps.mk` is now generated from source files via `BOOTSTRAPPER
  create-deps` and included automatically.

### Update Infrastructure (`update.mk`)

- `MANAGED_MK_FILES` is now derived by globbing the bootstrapper
  distribution directory rather than from a static list.
- `post-update` merges `.gitignore` entries from the bootstrapper and
  copies `Makefile.txt`.
- `update-available` now uses `BOOTSTRAPPER update-available` instead
  of an ad-hoc version comparison. `CMB_UPDATE_CHECK` and
  `CMB_VERSION_DRIFT` are enforced with explicit `fail`/`warn`/
  `ignore`/`invalid` handling.

### Version Targets (`version.mk`)

`release`, `minor`, and `major` now depend on `clean` before bumping
the version.

### New Include Files

Eight new `.includes/` files are added as part of the bootstrapper
update:

`add-plugin.mk`, `bash-completion.mk`, `bootstrap.mk`,
`build-init.mk`, `builder.mk`, `local.mk`, `modulino.mk`, `test.mk`

`.includes/release-notes.mk` has been deleted.

### Git Helpers (`git.mk`)

- `recommends` and `suggests` are added to `RECOMMENDED_ARTIFACTS`.
- The `ChangeLog`-generation `find` loop now prunes `local/` in
  addition to `.git`.
- New `repo` target creates a GitHub repository via
  `GITHUB_ACTIONS`; accepts `REPO`, `PUBLIC`, `REPO_DESCRIPTION`,
  and `DRYRUN` variables.

### `help.mk`

Help output is now buffered to a temp file and paged through `$PAGER`
(falling back to `less`, `more`, or `cat`). `SYNTAX_CHECKING=OFF` and
`SKIP_TESTS=1` are listed in the variables section.

### New Project Files

`config.mk`, `build-mirrors`, `recommends`, `suggests`, and a
`.prompts/change-log.prompt` LLM prompt file are added to the
repository.

A CPAN::Maker::Bootstrapper command role extension is registered under
`.roles/CPAN-Maker-Bootstrapper-Role-LLM/` (`role.mk`, `role.yml`).

---

## Dependency Changes

| Dependency | Change | Version |
|---|---|---|
| `Amazon::API::BedrockRuntime` | Added | 1.43.84 |
| `Amazon::Credentials` | Added | 2.0.1 |
| `File::ShareDir` | Added | 1.118 |
| `YAML::Tiny` | Added | 1.76 |
| `HTTP::Tiny` | Added (runtime + test) | 0.088 |
| `JSON::PP` | Added (runtime + test) | 4.16 |

---
