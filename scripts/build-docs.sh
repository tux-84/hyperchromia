#!/bin/bash
set -euo pipefail

HYPERCHROMIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$HYPERCHROMIA_DIR/docs"
ASSETS_DIR="$HYPERCHROMIA_DIR/build/assets"
SITE_DIR="$HYPERCHROMIA_DIR/site"
TEMPLATE="$ASSETS_DIR/docs-template.html"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$SITE_DIR"
find "$SITE_DIR" -mindepth 1 -delete
mkdir -p "$SITE_DIR/assets"
cp "$ASSETS_DIR/logo.png" "$SITE_DIR/assets/logo.png"
cp "$ASSETS_DIR/logo.png" "$SITE_DIR/assets/favicon.png"
cp "$ASSETS_DIR/docs.css" "$SITE_DIR/assets/docs.css"

SOURCES=(
  "$DOCS_DIR/01-features.md:features"
  "$DOCS_DIR/02-install.md:install"
  "$DOCS_DIR/03-building.md:building"
  "$DOCS_DIR/04-usage.md:usage"
  "$DOCS_DIR/05-updating.md:updating"
  "$DOCS_DIR/06-project-layout.md:project-layout"
  "$DOCS_DIR/07-contributing.md:contributing"
  "$HYPERCHROMIA_DIR/CHANGELOG.md:changelog"
)

hy_title_for() {
  sed -n 's/^# *//p' "$1" | head -n1
}

: > "$WORK_DIR/nav-lines.txt"
for entry in "${SOURCES[@]}"; do
  src="${entry%%:*}"
  slug="${entry##*:}"
  title="$(hy_title_for "$src")"
  printf '%s\t%s\n' "$slug" "$title" >> "$WORK_DIR/nav-lines.txt"
done

hy_write_nav() {
  local current="$1" out_file="$2" slug title active
  : > "$out_file"
  while IFS=$'\t' read -r slug title; do
    active=""
    [ "$slug" = "$current" ] && active=" active"
    printf '<li><a class="nav-link%s" href="%s.html">%s</a></li>\n' "$active" "$slug" "$title" >> "$out_file"
  done < "$WORK_DIR/nav-lines.txt"
}

for entry in "${SOURCES[@]}"; do
  src="${entry%%:*}"
  slug="${entry##*:}"
  title="$(hy_title_for "$src")"
  last_updated="$(git -C "$HYPERCHROMIA_DIR" log -1 --format=%ad --date=short -- "$src")"
  [ -z "$last_updated" ] && last_updated="$(date +%Y-%m-%d)"

  pandoc --from gfm --to html5 "$src" -o "$WORK_DIR/content.html"
  hy_write_nav "$slug" "$WORK_DIR/nav.html"

  python3 "$HYPERCHROMIA_DIR/scripts/build-docs-page.py" \
    "$TEMPLATE" "$WORK_DIR/nav.html" "$WORK_DIR/content.html" \
    "$title" "$last_updated" "$SITE_DIR/$slug.html"

  [ "$slug" = "features" ] && cp "$SITE_DIR/$slug.html" "$SITE_DIR/index.html"
done

echo "==> Built site/ ($(find "$SITE_DIR" -maxdepth 1 -name '*.html' | wc -l | tr -d ' ') pages)"
