# LLM::API 1.0.1 Release Notes

## Overview

This release delivers a refactored `LLM::API::Content` class with
proper multi-block support, expanded model pricing, a bug fix in the
POD, and a collection of build-system improvements from
`CPAN::Maker::Bootstrapper`.

---

## What's Changed

### `LLM::API` (`lib/LLM/API.pm.in`)

#### New and Updated Models in `$LLM_PRICING`

Four new Claude models have been added to the pricing table:

| Model | Input (per token) | Output (per token) |
|---|---|---|
| `claude-sonnet-5` | $3 / 1M | $15 / 1M |
| `claude-opus-4-8` | $5 / 1M | $25 / 1M |
| `claude-fable-5` | $10 / 1M | $50 / 1M |
| `claude-mythos-5` | $10 / 1M | $50 / 1M |

#### `$LLM_MAX_TOKENS` Increased

The default maximum token count has been raised from **4,096** to
**8,192**.

#### POD Fix

A stray `=back` directive without a matching `=over` has been removed,
resolving the POD errors previously reported in `README.md`.

---

### `LLM::API::Content` (`lib/LLM/API/Content.pm.in`) — **Refactored**

This class has been substantially redesigned to reflect the reality
that an Anthropic API response may contain **multiple content blocks**
of different types (e.g. a `thinking` block followed by a `text` block
when extended thinking is enabled). The previous implementation
assumed a single block and exposed flat per-field accessors; the new
implementation stores the full block list and provides typed accessor
methods.

#### Breaking Changes

- The previous per-field accessors (`data`, `id`, `input`, `name`,
  `redacted_thinking`, `text`, `thinking`, `type`) have been
  **removed**.
- The constructor argument is now the raw `content` array reference
  from the API response rather than a single-element array.

#### New Accessor

| Accessor | Description |
|---|---|
| `get_blocks` / `set_blocks` | The raw, unfiltered arrayref of all content blocks as received from the API. |

#### New Methods

| Method | Returns |
|---|---|
| `text` | Concatenated text from all `text`-type blocks (empty string if none). |
| `thinking` | Concatenated thinking content from all `thinking`-type blocks, joined by newlines (empty string if none). |
| `tool_uses` | Arrayref of all `tool_use`-type blocks, unmodified. |

#### New POD

`LLM::API::Content` now ships with full inline POD documentation
covering its description, all methods, and author information.

---

### Build System Updates (`CPAN::Maker::Bootstrapper`)

The following managed `.includes/` files have been updated by
`CPAN::Maker::Bootstrapper`. No changes are required from downstream
users of the distribution itself.

#### `Makefile`

- `config.mk` is now included via `-include config.mk`, enabling
  optional per-project overrides.
- `make-cpan-dist.pl` replaced by `cpan-maker` (`CPAN_MAKER`
  variable); `cpanfile` generation now delegates to `cpan-maker
  create-cpanfile`.
- `CPAN_MAKER::Bootstrapper->VERSION` called via method rather than
  package variable.
- `SCANDEPS` absence now sets `SCAN = OFF` automatically rather than defaulting `ON`.
- `BOOTSTRAPPER` absence is now a hard `$(error ...)` at parse time.
- `MD_UTILS` absence now emits a `$(warning ...)` rather than failing silently.
- `GIT_NAME`, `GIT_EMAIL`, `GITHUB_USER`: `git config` calls now
  redirect stderr to `/dev/null`.
- `MODULE_NAME` shell snippet: `pwd` corrected to `$$(pwd)`.
- `CMB_UPDATE_CHECK` and `CMB_VERSION_DRIFT` variables introduced (defaults: `on` / `fail`).
- `NO_COLOR` variable introduced; `cpan-maker` invocation passes `--color` when unset.
- `DEPS` list now includes `update-available` as an explicit
  dependency of the tarball target.
- `$(MODULE_PATH).in` now has an explicit (rather than order-only)
  dependency on `module.pm.tmpl`; template is removed after use.
- `buildspec.yml`: `@EXTRA_FILES@` placeholder removed; output file is now `chmod 0644` after creation.
- `clean` now calls a `clean-local` hook (double-colon rule) before
  removing `CLEANFILES`.
- `cmb_md5sums.txt` added to `CLEANFILES`.
- `.DEFAULT_GOAL` changed from `all` to `$(TARBALL)`.

#### `.includes/perl.mk`

- `PODEXTRACT` replaced by `PODCHECKER` (`podchecker` binary); POD
  syntax is now validated during `check_syntax_pm` and
  `check_syntax_pl`.
- `tidy_on` and `critic_on` are now only defined when `PERLTIDY` / `PERLCRITIC` binaries are present on `PATH`.
- `check_syntax_pl`: erroneous `-M"$$module"` flag removed from `perl -wc` invocation.
- `diff` redirect in tidy sentinel rule corrected: `2>/dev/null 2>&1` → `2>/dev/null`.
- `run_podextract`: explicit check that `PODEXTRACT` is installed before attempting extraction; exits with a clear error message if not.

#### `.includes/update.mk`

- `update-available` now gates the CPAN version check behind
  `CMB_UPDATE_CHECK=on`.
- Version drift detection added: md5sums of managed files are compared
  against the installed bootstrapper; behaviour is configurable via
  `CMB_VERSION_DRIFT` (`fail` / `warn` / `ignore`).
- `NO_ECHO` applied consistently to `post-update` and `update` recipes.

#### `.includes/git.mk`

- `git init` output suppressed (`>/dev/null`).
- `NO_ECHO` applied to `git` recipe.
- Recipe converted to a single compound shell command (semicolons
  throughout).
- `NO_COMMIT` guard added: set `NO_COMMIT=1` to stage files without committing.
- Help text updated to document `NO_COMMIT`.

#### `.includes/release-notes.mk`

- Previous multi-line shell recipe replaced by a single `bootstrapper
  release-notes` invocation.
- Output target changed from `release-{version}.{diffs,lst,tar.gz}` to
  `release-notes/release-notes-{version}.md`.

---

## Bug Fixes

| Location | Fix |
|---|---|
| `lib/LLM/API.pm.in` | Removed stray `=back` POD directive that caused a reported POD error in 1.0.0. |
| `.includes/perl.mk` | Removed duplicate `2>&1` redirect in tidy diff check. |
| `.includes/perl.mk` | Removed erroneous `-M"$$module"` from `perl -wc` in `.pl` syntax check. |

---

## Upgrade Notes

- **`LLM::API::Content` is not backward compatible.** Code that
  accessed individual fields via the old accessors (`->text`,
  `->thinking`, `->type`, etc., called on a `Content` object) must be
  updated to use the new typed methods (`text()`, `thinking()`,
  `tool_uses()`) or iterate over `get_blocks()`.
- The default `max_tokens` has changed from 4,096 to 8,192. If your
  application enforces a specific token budget, set `max_tokens`
  explicitly on the `LLM::API` constructor.
- Build tooling now requires `cpan-maker` (from `CPAN::Maker`) in
  place of `make-cpan-dist.pl`.
