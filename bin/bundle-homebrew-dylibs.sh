#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  bundle-homebrew-dylibs.sh <app_path> <app_binary_name> [entitlements_path] [homebrew_prefix]

Bundles any dylibs the app links against that are under the given Homebrew prefix (default: /opt/homebrew)
into <app_path>/Contents/Frameworks, rewrites load paths to @rpath/<dylib>, and ad-hoc signs the result.

Notes:
  - This is for local GH-release-style packaging. Developer ID signing + notarization are handled separately.
  - If signing ad-hoc (the default), entitlements are not applied.
  - Compatibility depends on the bundled dylibs' LC_BUILD_VERSION (minos). If a dylib was built with a higher
    minimum macOS version than your deployment target, the app will not run on older macOS versions.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

app="${1:-}"
app_binary="${2:-}"
entitlements="${3:-}"
prefix="${4:-/opt/homebrew}"

if [[ -z "$app" || -z "$app_binary" ]]; then
  usage
  exit 2
fi

exe="$app/Contents/MacOS/$app_binary"
frameworks="$app/Contents/Frameworks"

if [[ ! -d "$app" ]]; then
  echo "error: app not found: $app" >&2
  exit 1
fi

if [[ ! -f "$exe" ]]; then
  echo "error: app executable not found: $exe" >&2
  exit 1
fi

identity="${CODESIGN_IDENTITY:--}"

if [[ -n "$entitlements" && "$identity" != "-" && ! -f "$entitlements" ]]; then
  echo "error: entitlements file not found: $entitlements" >&2
  exit 1
fi

mkdir -p "$frameworks"

seen_file="$(mktemp)"
queue_file="$(mktemp)"
cleanup() {
  rm -f "$seen_file" "$queue_file" 2>/dev/null || true
}
trap cleanup EXIT

deps_of() {
  local target="$1"
  # Skip the header line, then print just the dep paths.
  otool -L "$target" | tail -n +2 | awk '{print $1}'
}

add_dep() {
  local p="$1"
  [[ -n "$p" ]] || return 0
  [[ -f "$p" ]] || return 0
  [[ "$p" == "$prefix/"* ]] || return 0
  if ! grep -Fqx "$p" "$seen_file" 2>/dev/null; then
    echo "$p" >>"$seen_file"
    echo "$p" >>"$queue_file"
  fi
}

while read -r dep; do add_dep "$dep"; done < <(deps_of "$exe" || true)

if [[ ! -s "$queue_file" ]]; then
  exit 0
fi

i=1
while true; do
  src="$(sed -n "${i}p" "$queue_file" || true)"
  if [[ -z "$src" ]]; then
    break
  fi

  base="$(basename "$src")"
  dest="$frameworks/$base"

  if [[ ! -f "$dest" ]]; then
    ditto "$src" "$dest"
    chmod 755 "$dest" || true
    install_name_tool -id "@rpath/$base" "$dest"
  fi

  while read -r dep; do add_dep "$dep"; done < <(deps_of "$src" || true)
  i=$((i + 1))
done

# Ensure the app can resolve @rpath dylibs from Contents/Frameworks.
if ! otool -l "$exe" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$exe"
fi

patch_target() {
  local target="$1"
  while read -r src; do
    [[ -n "$src" ]] || continue
    base="$(basename "$src")"
    install_name_tool -change "$src" "@rpath/$base" "$target" 2>/dev/null || true
  done <"$queue_file"
}

patch_target "$exe"
while read -r src; do
  [[ -n "$src" ]] || continue
  base="$(basename "$src")"
  patch_target "$frameworks/$base"
done <"$queue_file"

# Ad-hoc sign everything so the output is runnable after install_name_tool changes.
# (Developer ID signing + notarization is handled separately.)
find "$frameworks" -maxdepth 1 -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
  codesign --force --sign "$identity" --timestamp=none "$fw"
done
find "$frameworks" -maxdepth 1 -type f -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
  codesign --force --sign "$identity" --timestamp=none "$dylib"
done

if [[ "$identity" != "-" && -n "$entitlements" ]]; then
  codesign --force --sign "$identity" --timestamp=none --entitlements "$entitlements" "$app"
else
  codesign --force --sign "$identity" --timestamp=none "$app"
fi

bundled_count="$(wc -l <"$queue_file" | tr -d ' ')"
echo "Bundled ${bundled_count} Homebrew dylib(s) into $frameworks"
