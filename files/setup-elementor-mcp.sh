#!/usr/bin/env bash
# =============================================================================
# setup-elementor-mcp.sh — Wire up the Elementor MCP server against a
# WordPress site (Local-by-Flywheel or live host) and write a .mcp.json
# in the current directory so Claude Code can drive Elementor.
#
# Usage:  bash ~/.claude/scripts/setup-elementor-mcp.sh
#
# What it does:
#   1. Asks Local vs live host
#   2. Validates connectivity + REST auth
#   3. Confirms Elementor + Hello Elementor are installed (warns if not)
#   4. Downloads + installs WordPress MCP Adapter and elementor-mcp plugins
#      (handles the GitHub-only zips, repacks elementor-mcp source zipball)
#   5. Verifies the /mcp/elementor-mcp-server route appears
#   6. Writes .mcp.json in the current directory
#
# Idempotent: safe to re-run.
# =============================================================================

set -uo pipefail

# ---- pretty-print helpers ----------------------------------------------------
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

step()  { printf "\n${BOLD}${CYAN}▸ %s${RESET}\n" "$*"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠${RESET} %s\n" "$*"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$*"; }
info()  { printf "  ${DIM}%s${RESET}\n" "$*"; }
ask()   { printf "${BOLD}? %s${RESET} " "$*"; }

abort() { fail "$1"; exit 1; }

# ---- prereq check ------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || abort "Missing required command: $1"; }
need curl
need python3
need unzip
need zip

# Lenient JSON parser. Some WP plugins (Fluent Forms, etc.) emit malformed JSON
# in /wp-json/ index — bad backslash escapes like \s inside string values.
# This helper falls back to escaping those before parsing, then reads dotted
# paths from the result. Usage: cmd | jq_lenient '.namespaces' OR
#   cmd | jq_lenient_test '.namespaces' 'mcp'   (prints "yes" if value present)

JQ_LENIENT_PY='
import sys, json, re
def _sanitize(s):
    valid = set("\"\\/bfnrtu")
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i+1 < len(s) and s[i+1] not in valid:
            out.append("\\\\")
        else:
            out.append(c)
        i += 1
    return "".join(out)
def _load(s):
    try: return json.loads(s)
    except json.JSONDecodeError: return json.loads(_sanitize(s))
'

# Read pretty/raw value at a dotted path from stdin JSON.
# Supports: .key, .key.subkey, .[0], .key.[0]
jq_lenient() {
  python3 -c "$JQ_LENIENT_PY"'
import sys, json
data = _load(sys.stdin.read())
path = sys.argv[1].lstrip(".").split(".") if sys.argv[1] != "." else []
cur = data
for p in path:
    if p == "": continue
    if p.startswith("[") and p.endswith("]"):
        cur = cur[int(p[1:-1])]
    else:
        cur = cur.get(p) if isinstance(cur, dict) else None
    if cur is None: break
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print("" if cur is None else cur)
' "$1"
}

# Test if a string value appears in a list field at a dotted path.
# Returns "yes"/"no" on stdout.
jq_lenient_contains() {
  python3 -c "$JQ_LENIENT_PY"'
import sys
data = _load(sys.stdin.read())
path = sys.argv[1].lstrip(".").split(".")
needle = sys.argv[2]
cur = data
for p in path:
    if p == "": continue
    cur = cur.get(p) if isinstance(cur, dict) else None
    if cur is None: break
if isinstance(cur, list):
    print("yes" if any(needle in str(x) for x in cur) else "no")
elif isinstance(cur, dict):
    print("yes" if any(needle in str(k) for k in cur.keys()) else "no")
else:
    print("no")
' "$1" "$2"
}

# ---- intro -------------------------------------------------------------------
clear 2>/dev/null || true
cat <<'BANNER'

  ╭───────────────────────────────────────────────╮
  │   Elementor MCP — Setup Wizard                │
  │   ───────────────────────────                 │
  │   Wires Claude Code to a WordPress site so    │
  │   I can build Elementor pages directly.       │
  ╰───────────────────────────────────────────────╯

BANNER

# ---- 1. Local vs live --------------------------------------------------------
step "1/8  Site type"
echo "    [1] Local-by-Flywheel  (sites under ~/Local Sites/)"
echo "    [2] Live host          (any WordPress site reachable over HTTP/HTTPS)"
ask "Pick (1 or 2):"
read -r SITE_TYPE
case "$SITE_TYPE" in
  1) MODE="local"; ok "Local-by-Flywheel mode" ;;
  2) MODE="live";  ok "Live-host mode" ;;
  *) abort "Invalid choice. Run again with 1 or 2." ;;
esac

# ---- 2. Site URL + path ------------------------------------------------------
step "2/8  Site URL"

if [ "$MODE" = "local" ]; then
  if [ -d "$HOME/Local Sites" ]; then
    info "Sites detected in ~/Local Sites/:"
    for d in "$HOME/Local Sites"/*/; do
      [ -d "$d" ] && printf "      ${CYAN}•${RESET} %s\n" "$(basename "$d")"
    done
  fi
  ask "Local site name (folder under ~/Local Sites/):"
  read -r SITE_NAME
  SITE_PATH="$HOME/Local Sites/$SITE_NAME/app/public"
  [ -f "$SITE_PATH/wp-config.php" ] || abort "No wp-config.php at $SITE_PATH"
  SITE_URL="http://${SITE_NAME}.local"
  ok "Site path:  $SITE_PATH"
  ok "Site URL:   $SITE_URL"
else
  ask "Full site URL (e.g. https://example.com — no trailing slash):"
  read -r SITE_URL
  SITE_URL="${SITE_URL%/}"
  [[ "$SITE_URL" =~ ^https?:// ]] || abort "URL must start with http:// or https://"
  ok "Site URL:   $SITE_URL"
fi

# ---- 3. Connectivity probe ---------------------------------------------------
step "3/8  Connectivity"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$SITE_URL/wp-json/" || echo "000")
case "$HTTP_CODE" in
  200|301|302) ok "Reached WP REST API ($HTTP_CODE)" ;;
  000) abort "Could not reach $SITE_URL — is the site running?" ;;
  401|403) warn "REST returned $HTTP_CODE — may be auth-gated; continuing" ;;
  *) abort "Got HTTP $HTTP_CODE from $SITE_URL/wp-json/" ;;
esac

# ---- 4. Auth credentials -----------------------------------------------------
step "4/8  Authentication"

cat <<EOF
    You'll need a WordPress Application Password.
    To create one:
      1. Log in to ${SITE_URL}/wp-admin
      2. Users → Profile → scroll to "Application Passwords"
      3. Name it (e.g. "ClaudeMCP"), click Add — copy the password shown
      4. The password's NAME is just a label. The username is your WP login.
EOF

ask "WordPress username (your login, NOT the app-password label):"
read -r WP_USER
ask "Application password (24 chars with spaces is OK):"
read -r WP_APP_PWD

# Verify via /users/me
USERS_ME=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/users/me" || echo "{}")
USER_ID=$(echo "$USERS_ME" | jq_lenient '.id' 2>/dev/null || echo "")
if [ -n "$USER_ID" ] && [ "$USER_ID" != "" ]; then
  USER_NAME=$(echo "$USERS_ME" | jq_lenient '.name')
  ok "Authenticated as: $USER_NAME"
else
  fail "Auth failed. Listing public users to help find the right slug:"
  USERS_LIST=$(curl -s --max-time 10 "$SITE_URL/wp-json/wp/v2/users?per_page=10" 2>/dev/null || echo "[]")
  echo "$USERS_LIST" | python3 -c "$JQ_LENIENT_PY"'
import sys
data = _load(sys.stdin.read())
if isinstance(data, list):
    for u in data:
        print(f"     • {u.get(\"slug\",\"?\")} — {u.get(\"name\",\"?\")}")
' 2>/dev/null || warn "Could not list users."
  abort "Re-run with the correct username (try a slug from the list above)."
fi

# ---- 5. Plugin baseline + optional auto-install ------------------------------
step "5/8  Plugin baseline"

# Helper: check if a given plugin folder/slug is active
plugin_is_active() {
  local slug="$1"
  echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    print("yes" if any(p.get("plugin","").startswith(slug+"/") and p.get("status")=="active" for p in d) else "no")
else:
    print("no")
' "$slug" 2>/dev/null || echo "no"
}

# Helper: check if a plugin is installed (any status)
plugin_is_installed() {
  local slug="$1"
  echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    print("yes" if any(p.get("plugin","").startswith(slug+"/") for p in d) else "no")
else:
    print("no")
' "$slug" 2>/dev/null || echo "no"
}

# Helper: install + activate a plugin from wordpress.org by slug via REST.
# REST plugins endpoint accepts {slug, status} — installs from wp.org directly.
install_wp_plugin() {
  local slug="$1"
  local label="$2"
  if [ "$(plugin_is_active "$slug")" = "yes" ]; then
    ok "$label already active"
    return 0
  fi
  if [ "$(plugin_is_installed "$slug")" = "yes" ]; then
    info "$label already installed — activating..."
    # Need to find its plugin path to activate
    local plugin_path
    plugin_path=$(echo "$PLUGINS_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
slug = sys.argv[1]
d = _load(sys.stdin.read())
if isinstance(d, list):
    for p in d:
        if p.get("plugin","").startswith(slug+"/"):
            print(p["plugin"]); break
' "$slug" 2>/dev/null)
    if [ -n "$plugin_path" ]; then
      curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 30 \
        -H "Content-Type: application/json" \
        -X POST "$SITE_URL/wp-json/wp/v2/plugins/$plugin_path" \
        -d '{"status":"active"}' >/dev/null
      ok "Activated $label"
    fi
    return 0
  fi
  info "Installing + activating $label from wordpress.org..."
  local result
  result=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 60 \
    -H "Content-Type: application/json" \
    -X POST "$SITE_URL/wp-json/wp/v2/plugins" \
    -d "{\"slug\":\"$slug\",\"status\":\"active\"}" || echo '{"code":"network_error"}')
  local err
  err=$(echo "$result" | jq_lenient '.code' 2>/dev/null || echo "")
  if [ -z "$err" ] || [ "$err" = "" ]; then
    ok "Installed + activated $label"
  else
    fail "Could not install $label: $err"
    return 1
  fi
}

# Helper: install + activate a theme from wordpress.org by slug
install_wp_theme() {
  local slug="$1"
  local label="$2"
  info "Installing $label theme from wordpress.org..."
  local result
  result=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 60 \
    -H "Content-Type: application/json" \
    -X POST "$SITE_URL/wp-json/wp/v2/themes" \
    -d "{\"slug\":\"$slug\"}" 2>&1 || echo '{}')
  # Switching themes via REST isn't standard — fall back to telling user
  # how to activate it (many WP versions don't support theme activation via REST).
  warn "Theme installed but auto-activation isn't supported via REST API in all WP versions."
  warn "Activate it manually: WP Admin → Appearance → Themes → $label → Activate"
}

# Fetch current state once
PLUGINS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/plugins" || echo "[]")
THEME_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/wp/v2/themes?status=active" || echo "[]")
ACTIVE_THEME=$(echo "$THEME_JSON" | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
print(d[0]["stylesheet"] if isinstance(d, list) and d else "?")
' 2>/dev/null || echo "?")

# Report current state
HAS_ELEMENTOR=$(plugin_is_active "elementor")
HAS_UAE=$(plugin_is_active "header-footer-elementor")
HAS_EA=$(plugin_is_active "essential-addons-for-elementor-lite")
HAS_FF=$(plugin_is_active "fluentform")

[ "$HAS_ELEMENTOR" = "yes" ] && ok "Elementor (free) — active" || warn "Elementor — not active"
[ "$ACTIVE_THEME" = "hello-elementor" ] && ok "Theme: Hello Elementor — active" || warn "Theme: $ACTIVE_THEME (Hello Elementor recommended)"
[ "$HAS_UAE" = "yes" ] && ok "UAE / Header Footer Elementor — active" || warn "UAE / Header Footer Elementor — not active (needed for headers/footers)"

# ---- 6. Optional auto-install of baseline plugins ----------------------------
step "6/8  Auto-install baseline plugins?"

NEEDS_ANY="no"
[ "$HAS_ELEMENTOR" != "yes" ] && NEEDS_ANY="yes"
[ "$HAS_UAE" != "yes" ] && NEEDS_ANY="yes"
[ "$ACTIVE_THEME" != "hello-elementor" ] && NEEDS_ANY="yes"

if [ "$NEEDS_ANY" = "no" ]; then
  ok "All baseline plugins + theme already in place — skipping auto-install."
else
  cat <<EOF
    Some baseline plugins/theme aren't yet active on this site.
    The wizard can install them for you from wordpress.org:

      • Elementor (free)         — the page builder
      • Hello Elementor (theme)  — blank canvas theme
      • UAE / Header Footer      — for site-wide headers and footers
      • Essential Addons (lite)  — extra free widgets (optional)
      • Fluent Forms             — real working contact forms (optional)

    ${YELLOW}Note:${RESET} Auto-install is safest on a fresh demo site. If this is
    an existing site with content/theme you care about, choose 'No'
    and install manually via WP Admin → Plugins → Add New.
EOF
  ask "Auto-install Elementor + UAE? [Y/n]"
  read -r DO_INSTALL
  if [[ ! "$DO_INSTALL" =~ ^[Nn]$ ]]; then
    [ "$HAS_ELEMENTOR" != "yes" ] && install_wp_plugin "elementor" "Elementor (free)"
    [ "$HAS_UAE" != "yes" ] && install_wp_plugin "header-footer-elementor" "UAE / Header Footer Elementor"

    if [ "$ACTIVE_THEME" != "hello-elementor" ]; then
      ask "Also install Hello Elementor theme? (Switch theme manually after.) [Y/n]"
      read -r DO_THEME
      [[ ! "$DO_THEME" =~ ^[Nn]$ ]] && install_wp_theme "hello-elementor" "Hello Elementor"
    fi

    ask "Also install Essential Addons + Fluent Forms (optional but useful)? [y/N]"
    read -r DO_OPT
    if [[ "$DO_OPT" =~ ^[Yy]$ ]]; then
      install_wp_plugin "essential-addons-for-elementor-lite" "Essential Addons (lite)"
      install_wp_plugin "fluentform" "Fluent Forms"
    fi
  else
    info "Skipped auto-install. You'll need to install the missing plugins yourself before using Claude to build."
  fi
fi

# ---- 7. Install MCP plugins --------------------------------------------------
step "7/8  Installing MCP plugins"

# Are they already there?
NS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/" || echo "{}")
HAS_MCP=$(echo "$NS_JSON" | jq_lenient_contains '.namespaces' 'mcp' 2>/dev/null || echo "no")

if [ "$HAS_MCP" = "yes" ]; then
  ok "MCP namespace already registered — skipping plugin install."
else
  info "Downloading WordPress MCP Adapter (latest GitHub release)..."
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT

  ADAPTER_URL=$(curl -s "https://api.github.com/repos/WordPress/mcp-adapter/releases/latest" \
    | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
a = [a for a in d.get("assets",[]) if a["name"].endswith(".zip")]
print(a[0]["browser_download_url"] if a else d.get("zipball_url",""))
')
  [ -n "$ADAPTER_URL" ] || abort "Could not fetch mcp-adapter download URL from GitHub."
  curl -sL -o "$WORK/mcp-adapter.zip" "$ADAPTER_URL" || abort "Adapter download failed."
  ok "Downloaded mcp-adapter.zip"

  info "Downloading elementor-mcp (latest GitHub release)..."
  EM_ZIPBALL=$(curl -s "https://api.github.com/repos/msrbuilds/elementor-mcp/releases/latest" \
    | python3 -c "$JQ_LENIENT_PY"'
import sys
d = _load(sys.stdin.read())
a = [a for a in d.get("assets",[]) if a["name"].endswith(".zip")]
print(a[0]["browser_download_url"] if a else d.get("zipball_url",""))
')
  [ -n "$EM_ZIPBALL" ] || abort "Could not fetch elementor-mcp download URL."
  curl -sL -o "$WORK/elementor-mcp-src.zip" "$EM_ZIPBALL" || abort "elementor-mcp download failed."

  # Repack with clean folder name (zipballs have ugly hash-suffixed dirs)
  ( cd "$WORK" && unzip -q elementor-mcp-src.zip )
  EM_DIR=$(find "$WORK" -maxdepth 1 -type d -name "*elementor-mcp*" ! -name "msrbuilds-elementor-mcp" 2>/dev/null | head -1)
  if [ -n "$EM_DIR" ] && [ "$(basename "$EM_DIR")" != "elementor-mcp" ]; then
    mv "$EM_DIR" "$WORK/elementor-mcp"
  fi
  ( cd "$WORK" && rm -f elementor-mcp.zip && zip -qr elementor-mcp.zip elementor-mcp )
  ok "Repacked elementor-mcp.zip with clean folder name"

  if [ "$MODE" = "local" ]; then
    # Local: install via WP-CLI through Local's bundled binaries
    info "Installing via Local's bundled WP-CLI..."
    LOCAL_PHP=$(find "$HOME/Library/Application Support/Local/lightning-services" -maxdepth 6 -name "php" -type f 2>/dev/null | head -1)
    LOCAL_WP="/Applications/Local.app/Contents/Resources/extraResources/bin/wp-cli/posix/wp"
    [ -x "$LOCAL_PHP" ] || abort "Local's PHP binary not found. Is Local installed?"
    [ -f "$LOCAL_WP"  ] || abort "Local's WP-CLI binary not found at $LOCAL_WP"

    # Find the MySQL socket for this site
    SOCK=$(find "$HOME/Library/Application Support/Local/run" -name "mysqld.sock" 2>/dev/null | while read s; do
      # Check which socket actually serves THIS site (only one will be live with the site running)
      if "$LOCAL_PHP" -d "mysqli.default_socket=$s" -d "pdo_mysql.default_socket=$s" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes core version >/dev/null 2>&1; then
        echo "$s"; break
      fi
    done)
    [ -n "$SOCK" ] || abort "Could not find MySQL socket for $SITE_NAME. Is the site started in Local?"
    ok "MySQL socket: $SOCK"

    PHPRUN=( "$LOCAL_PHP" -d "mysqli.default_socket=$SOCK" -d "pdo_mysql.default_socket=$SOCK" )

    info "Installing mcp-adapter..."
    "${PHPRUN[@]}" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes plugin install "$WORK/mcp-adapter.zip" --activate --force >/dev/null 2>&1 \
      && ok "mcp-adapter installed + activated" || fail "mcp-adapter install failed"

    info "Installing elementor-mcp..."
    "${PHPRUN[@]}" "$LOCAL_WP" --path="$SITE_PATH" --skip-plugins --skip-themes plugin install "$WORK/elementor-mcp.zip" --activate --force >/dev/null 2>&1 \
      && ok "elementor-mcp installed + activated" || fail "elementor-mcp install failed"

  else
    # Live host: REST upload not supported for arbitrary zips. Print instructions.
    warn "Live hosts: REST API can't install arbitrary plugin zips."
    info ""
    info "Two zips ready at:"
    info "  $WORK/mcp-adapter.zip"
    info "  $WORK/elementor-mcp.zip"
    info ""
    info "Upload them via:"
    info "  ${SITE_URL}/wp-admin/plugin-install.php?tab=upload"
    info ""
    info "(One at a time: choose file → Install Now → Activate Plugin.)"
    info ""
    ask "Press Enter once both are uploaded and activated..."
    read -r _
  fi
fi

# ---- 6b. Verify MCP namespace --------------------------------------------
info "Verifying /mcp/elementor-mcp-server route..."
sleep 2
NS_JSON=$(curl -s -u "$WP_USER:$WP_APP_PWD" --max-time 10 "$SITE_URL/wp-json/" || echo "{}")
HAS_MCP=$(echo "$NS_JSON" | jq_lenient_contains '.namespaces' 'mcp' 2>/dev/null || echo "no")
[ "$HAS_MCP" = "yes" ] || abort "MCP namespace still not registered. Check that both plugins activated successfully."
HAS_EM=$(echo "$NS_JSON" | jq_lenient_contains '.routes' 'elementor-mcp-server' 2>/dev/null || echo "no")
[ "$HAS_EM" = "yes" ] && ok "Elementor MCP server route registered ✓" || warn "MCP namespace exists but elementor-mcp-server route is missing."

# ---- 7. Write .mcp.json ------------------------------------------------------
step "8/8  Writing .mcp.json"
PROJECT_DIR="$(pwd)"
MCP_FILE="$PROJECT_DIR/.mcp.json"

# Base64-encode auth (Python3 portable)
AUTH_B64=$(printf "%s:%s" "$WP_USER" "$WP_APP_PWD" | python3 -c "import sys,base64; sys.stdout.write(base64.b64encode(sys.stdin.buffer.read()).decode())")

# If .mcp.json already exists, merge (don't clobber)
if [ -f "$MCP_FILE" ]; then
  warn ".mcp.json already exists at $MCP_FILE"
  ask "Overwrite? [y/N]"
  read -r OVR
  [[ "$OVR" =~ ^[Yy]$ ]] || { info "Leaving existing .mcp.json untouched. New config printed below."; SKIP_WRITE=1; }
fi

NEW_CONFIG=$(cat <<JSON
{
  "mcpServers": {
    "elementor": {
      "type": "http",
      "url": "${SITE_URL}/wp-json/mcp/elementor-mcp-server",
      "headers": {
        "Authorization": "Basic ${AUTH_B64}"
      }
    }
  }
}
JSON
)

if [ "${SKIP_WRITE:-0}" != "1" ]; then
  printf "%s\n" "$NEW_CONFIG" > "$MCP_FILE"
  ok "Wrote $MCP_FILE"
else
  echo
  info "Suggested config:"
  echo "$NEW_CONFIG" | sed 's/^/      /'
fi

# ---- final instructions ------------------------------------------------------
cat <<EOF

  ${BOLD}${GREEN}✓ Setup complete${RESET}

  ${BOLD}Next steps:${RESET}
    1. ${CYAN}Quit Claude Code${RESET} (Cmd-Q in the desktop app, or Ctrl-C in the CLI)
    2. ${CYAN}Reopen it in this directory:${RESET}  cd "$PROJECT_DIR"
    3. Claude Code will ask you to ${BOLD}approve the 'elementor' MCP server${RESET} — say yes
    4. Tell Claude to invoke the elementor-mcp skill, e.g. "build me an Elementor page" — it will load the conventions and start building

  ${BOLD}Useful commands inside Claude:${RESET}
    list-pages                       confirm auth + see existing pages
    get-global-settings              read current colors/fonts kit
    update-global-colors / typography  set design tokens
    create-page                      new page (use template: "elementor_canvas")
    add-container, add-heading, ...  build sections

  ${BOLD}Reference:${RESET}
    Skill file: ~/.claude/skills/elementor-mcp/SKILL.md
    MCP plugin: https://github.com/msrbuilds/elementor-mcp

EOF
