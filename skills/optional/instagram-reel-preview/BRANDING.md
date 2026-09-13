# Publisher identity: approved FTS default

The operator explicitly approved this rule on 2026-09-13:
**always use the publisher/account `fightthestroke` and its actual approved logo,
unless the user explicitly requests another publisher.**
This rule belongs to this optional skill, not the global canon.
`display_name` identifies the video subject, never the publishing account.
`project_label` is an optional supplied project label, not an account override.

Approved source (keep this exact URL, including the query):

https://images.squarespace-cdn.com/content/v1/53f10f3ae4b0124ec1e3a087/2820f1f0-227f-4f45-9109-b00e56b9d0ba/logo-rgb-10years-fts.png?format=1500w

Approved original bytes, SHA-256:

```text
c85db1c75d484e54acf1373c5750909fc8a27929135148c99faa65df07b8d40b
```

The source currently returns WebP bytes despite the `.png` URL. Pillow reads the
actual format; **do not transcode**, redraw, recolor, crop, stretch, or replace the
logo with initials, a silhouette, another anniversary variant or a generated mark.
Scale proportionally with the full logo visible on white; no circular clipping.

## Safe local cache

Prefer the parent's already-downloaded local file after verifying the hash above.
Pass its path with `--publisher-logo`; no local personal path is baked into the
skill. If no approved copy exists, this is an explicitly local download of the
approved public asset, not an upload. Keep its bytes outside git and bundles.

```bash
set -euo pipefail
CACHE_DIR="/path/outside-git/fts-cache"
mkdir -p "$CACHE_DIR"
logo="$CACHE_DIR/approved-fts-logo.png"
test ! -e "$logo" && test ! -L "$logo"
tmp="$(mktemp "$CACHE_DIR/.fts-logo.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' --max-time 60 \
  'https://images.squarespace-cdn.com/content/v1/53f10f3ae4b0124ec1e3a087/2820f1f0-227f-4f45-9109-b00e56b9d0ba/logo-rgb-10years-fts.png?format=1500w' \
  --output "$tmp"
printf '%s  %s\n' \
  c85db1c75d484e54acf1373c5750909fc8a27929135148c99faa65df07b8d40b "$tmp" \
  | shasum -a 256 -c -
ln "$tmp" "$logo"
```

Existing cache files are not overwritten. For an existing file, hash-check it and
reuse it rather than running the download again. A network error, changed source
hash or missing logo is an explicit failure, **never** permission to invent a
replacement. If the upstream bytes change, seek renewed approval before changing
the pinned hash. The renderer checks the hash independently and never downloads.

## Explicit override

Only a user-requested different publisher authorizes `--publisher "Supplied account"`.
Supply that publisher's actual logo with `--publisher-logo` when available; preserve
it proportionally too. A neutral icon or supplied `--avatar` is allowed only for an
explicit non-FTS publisher without a logo. The default FTS publisher rejects avatars.
Publisher spelling is literal; do not guess another handle or add verification or
engagement claims. Translations do not change this supplied account name.

Both generated covers and post wrappers show the publisher separately from the
subject. Existing approved cover pixels remain untouched inside a wrapper.
