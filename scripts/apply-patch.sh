#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Project Tenderheart Patch Installer"
PATCH_DIR=".patches"
BACKUP_DIR="$PATCH_DIR/backups"
APPLIED_DIR="$PATCH_DIR/applied"
REPORT_DIR="$PATCH_DIR/reports"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
DELETE_ZIP_AFTER_APPLY="${DELETE_ZIP_AFTER_APPLY:-1}"
DELETE_MANIFEST_NAME=".patch-delete"

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
log() { printf "%b[patch]%b %s\n" "$BLUE" "$NC" "$1"; }
success() { printf "%b✓%b %s\n" "$GREEN" "$NC" "$1"; }
warn() { printf "%b⚠%b %s\n" "$YELLOW" "$NC" "$1"; }
fail() { printf "%b✗%b %s\n" "$RED" "$NC" "$1" >&2; exit 1; }

require_tools() {
  command -v unzip >/dev/null 2>&1 || fail "unzip is required."
  command -v zipinfo >/dev/null 2>&1 || fail "zipinfo is required."
  command -v python3 >/dev/null 2>&1 || fail "python3 is required for safe cross-platform path validation."
}

init_dirs() { mkdir -p "$BACKUP_DIR" "$APPLIED_DIR" "$REPORT_DIR"; }
list_zips() { find . -maxdepth 1 -type f -name '*.zip' | sed 's#^\./##' | sort; }

choose_zip() {
  local zips_file count only_zip i choice selected
  zips_file="$(mktemp)"; list_zips > "$zips_file"
  count="$(wc -l < "$zips_file" | tr -d ' ')"
  [ "$count" != "0" ] || { rm -f "$zips_file"; fail "No .zip files found in project root."; }
  if [ "$count" = "1" ]; then only_zip="$(sed -n '1p' "$zips_file")"; rm -f "$zips_file"; printf '%s\n' "$only_zip"; return; fi
  printf 'Found %s zip files:\n\n' "$count" >&2
  i=1; while IFS= read -r zip; do printf '  %s) %s\n' "$i" "$zip" >&2; i=$((i + 1)); done < "$zips_file"
  printf '\n' >&2; read -r -p "Choose patch number: " choice
  printf '%s' "$choice" | grep -Eq '^[0-9]+$' || { rm -f "$zips_file"; fail "Invalid choice."; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] || { rm -f "$zips_file"; fail "Choice out of range."; }
  selected="$(sed -n "${choice}p" "$zips_file")"; rm -f "$zips_file"; printf '%s\n' "$selected"
}

show_history() {
  if [ ! -d "$APPLIED_DIR" ] || [ -z "$(find "$APPLIED_DIR" -type f 2>/dev/null | head -n 1)" ]; then warn "No applied patch history yet."; exit 0; fi
  log "Applied patches:"; find "$APPLIED_DIR" -type f | sort
}

normalize_zip_entries() { zipinfo -1 "$1" | grep -v '/$' | grep -v '^__MACOSX/' | grep -v '/\.DS_Store$' || true; }

detect_wrapper_prefix() {
  local zip_file="$1" temp_file first_dirs count only
  temp_file="$(mktemp)"; normalize_zip_entries "$zip_file" > "$temp_file"
  first_dirs="$(awk -F/ 'NF>1 {print $1}' "$temp_file" | sort -u)"
  count="$(printf '%s\n' "$first_dirs" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" = "1" ]; then
    only="$(printf '%s\n' "$first_dirs" | head -n 1)"
    case "$only" in docs|tasks|prompts|agents|memory|reports|decisions|plans|checklists|context|scripts|apps|packages|src|server|public) printf '\n' ;; *) printf '%s/\n' "$only" ;; esac
  else printf '\n'; fi
  rm -f "$temp_file"
}

safe_entry_path() {
  local entry="$1" prefix="$2"
  [ -z "$prefix" ] || entry="${entry#"$prefix"}"
  entry="${entry#./}"; [ -n "$entry" ] || return 1
  printf '%s' "$entry" | grep -Eq '(^/|(^|/)\.\.(/|$))' && return 1
  printf '%s\n' "$entry"
}

canonical_project_path() {
  python3 -c 'import os,sys; root=os.path.realpath(sys.argv[1]); path=os.path.realpath(os.path.join(root,sys.argv[2])); print(root); print(path)' "$PWD" "$1"
}

safe_delete_path() {
  local raw="$1" path canonical project_root resolved
  path="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$path" ] || return 1
  case "$path" in \#*) return 1 ;; esac
  path="${path#./}"
  printf '%s' "$path" | grep -Eq '(^/|(^|/)\.\.(/|$))' && fail "Unsafe delete path in $DELETE_MANIFEST_NAME: $raw"
  case "$path" in .|./|.git|.git/*|.patches|.patches/*) fail "Protected path cannot be deleted: $path" ;; esac
  canonical="$(canonical_project_path "$path")"
  project_root="$(printf '%s\n' "$canonical" | sed -n '1p')"
  resolved="$(printf '%s\n' "$canonical" | sed -n '2p')"
  case "$resolved" in "$project_root"/*) ;; *) fail "Delete path escapes project root: $path" ;; esac
  printf '%s\n' "$path"
}

extract_patch() {
  local zip_file="$1" prefix="$2" temp_dir source_dir
  temp_dir="$(mktemp -d)"; unzip -q "$zip_file" -d "$temp_dir"; source_dir="$temp_dir"
  if [ -n "$prefix" ] && [ -d "$temp_dir/${prefix%/}" ]; then source_dir="$temp_dir/${prefix%/}"; fi
  printf '%s\n%s\n' "$temp_dir" "$source_dir"
}

manifest_paths() {
  local source_dir="$1" manifest="$source_dir/$DELETE_MANIFEST_NAME" line
  [ -f "$manifest" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do safe_delete_path "$line" || true; done < "$manifest"
}

preview_patch() {
  local zip_file="$1" prefix="$2" source_dir="$3" create_count=0 update_count=0 skip_count=0 delete_count=0 missing_delete_count=0 entry target entries_file path
  entries_file="$(mktemp)"; normalize_zip_entries "$zip_file" > "$entries_file"
  while IFS= read -r entry; do
    target="$(safe_entry_path "$entry" "$prefix")" || { skip_count=$((skip_count + 1)); continue; }
    [ "$target" != "$DELETE_MANIFEST_NAME" ] || continue
    if [ -e "$target" ] || [ -L "$target" ]; then update_count=$((update_count + 1)); else create_count=$((create_count + 1)); fi
  done < "$entries_file"; rm -f "$entries_file"
  while IFS= read -r path; do [ -n "$path" ] || continue; if [ -e "$path" ] || [ -L "$path" ]; then delete_count=$((delete_count + 1)); else missing_delete_count=$((missing_delete_count + 1)); fi; done < <(manifest_paths "$source_dir")
  printf '\n'; log "Patch preview:"
  printf '  Creates:          %s\n  Updates:          %s\n  Deletes:          %s\n  Already missing:  %s\n  Skips:            %s\n\n' "$create_count" "$update_count" "$delete_count" "$missing_delete_count" "$skip_count"
  if [ -f "$source_dir/$DELETE_MANIFEST_NAME" ]; then log "Files/directories requested for deletion:"; manifest_paths "$source_dir" | sed 's/^/  - /'; printf '\n'; fi
}

backup_one() {
  local target="$1" backup_root="$2"
  if [ -e "$target" ] || [ -L "$target" ]; then mkdir -p "$backup_root/$(dirname "$target")"; cp -a "$target" "$backup_root/$target"; fi
}

backup_existing_files() {
  local zip_file="$1" prefix="$2" source_dir="$3" backup_root="$BACKUP_DIR/$TIMESTAMP" backed_up=0 entry target entries_file path
  mkdir -p "$backup_root"; entries_file="$(mktemp)"; normalize_zip_entries "$zip_file" > "$entries_file"
  while IFS= read -r entry; do target="$(safe_entry_path "$entry" "$prefix")" || continue; [ "$target" != "$DELETE_MANIFEST_NAME" ] || continue; if [ -e "$target" ] || [ -L "$target" ]; then backup_one "$target" "$backup_root"; backed_up=$((backed_up + 1)); fi; done < "$entries_file"
  rm -f "$entries_file"
  while IFS= read -r path; do [ -n "$path" ] || continue; if [ -e "$path" ] || [ -L "$path" ]; then backup_one "$path" "$backup_root"; backed_up=$((backed_up + 1)); fi; done < <(manifest_paths "$source_dir")
  printf '%s\n' "$backup_root" > "$PATCH_DIR/last-backup.txt"; success "Backed up $backed_up existing paths to $backup_root"
}

apply_deletions() {
  local source_dir="$1" path deleted=0
  while IFS= read -r path; do [ -n "$path" ] || continue; if [ -e "$path" ] || [ -L "$path" ]; then rm -rf "$path"; deleted=$((deleted + 1)); fi; done < <(manifest_paths "$source_dir")
  success "Deleted $deleted paths listed in $DELETE_MANIFEST_NAME"
}

apply_files() {
  local source_dir="$1" item copied=0
  while IFS= read -r -d '' item; do [ "$(basename "$item")" != "$DELETE_MANIFEST_NAME" ] || continue; cp -a "$item" ./; copied=$((copied + 1)); done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)
  success "Copied $copied top-level patch entries"
}

write_report() {
  local zip_file="$1" prefix="$2" source_dir="$3" report="$REPORT_DIR/patch-$TIMESTAMP.txt" applied="$APPLIED_DIR/patch-$TIMESTAMP.txt" entry target
  {
    printf 'Patch Applied: %s\nTimestamp: %s\nWrapper Prefix: %s\n\nDeleted Paths:\n' "$zip_file" "$TIMESTAMP" "${prefix:-none}"
    manifest_paths "$source_dir" | sed 's/^/- /' || true
    printf '\nCopied Files:\n'
    while IFS= read -r entry; do target="$(safe_entry_path "$entry" "$prefix")" || continue; [ "$target" != "$DELETE_MANIFEST_NAME" ] && printf '%s\n' "$target"; done < <(normalize_zip_entries "$zip_file")
  } > "$report"
  cp "$report" "$applied"; success "Patch report written to $report"
}

delete_processed_zip() {
  local zip_file="$1"
  [ "$DELETE_ZIP_AFTER_APPLY" = "1" ] || { warn "Leaving processed zip because DELETE_ZIP_AFTER_APPLY=$DELETE_ZIP_AFTER_APPLY"; return; }
  [ -f "$zip_file" ] || { warn "Processed zip already missing: $zip_file"; return; }
  rm -f "$zip_file"; success "Deleted processed zip: $zip_file"
}

usage() {
  cat <<EOF_HELP
$APP_NAME

Usage:
  bash apply-patch.sh [patch-file.zip]
  bash apply-patch.sh --list
  bash apply-patch.sh --history
  DELETE_ZIP_AFTER_APPLY=0 bash apply-patch.sh patch-file.zip

A patch may include a root-level $DELETE_MANIFEST_NAME file with one project-relative path per line.
EOF_HELP
}

main() {
  require_tools; init_dirs
  case "${1:-}" in --help|-h) usage; exit 0 ;; --list) list_zips; exit 0 ;; --history) show_history; exit 0 ;; esac
  local zip_file="${1:-}" prefix extracted temp_dir source_dir confirm
  [ -n "$zip_file" ] || zip_file="$(choose_zip)"; [ -f "$zip_file" ] || fail "Zip file not found: $zip_file"
  log "$APP_NAME"; log "Selected patch: $zip_file"
  prefix="$(detect_wrapper_prefix "$zip_file")"; [ -z "$prefix" ] || warn "Detected wrapper folder: $prefix"
  extracted="$(extract_patch "$zip_file" "$prefix")"; temp_dir="$(printf '%s\n' "$extracted" | sed -n '1p')"; source_dir="$(printf '%s\n' "$extracted" | sed -n '2p')"
  trap "rm -rf '$temp_dir'" EXIT
  preview_patch "$zip_file" "$prefix" "$source_dir"
  read -r -p "Apply this patch? Files may be overwritten or deleted after backup. (y/N): " confirm
  case "$confirm" in y|Y|yes|YES) ;; *) warn "Patch canceled."; exit 0 ;; esac
  backup_existing_files "$zip_file" "$prefix" "$source_dir"; apply_deletions "$source_dir"; apply_files "$source_dir"; write_report "$zip_file" "$prefix" "$source_dir"; delete_processed_zip "$zip_file"
  success "Patch applied successfully."
  printf '\nNext steps:\n  git status\n  review deleted and changed files\n  npm run imports:check\n  npm run typecheck\n  npm test\n  npm run build\n'
}

main "$@"