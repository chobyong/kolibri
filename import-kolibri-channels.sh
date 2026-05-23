#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  Kolibri Channel Importer — HIM Education
# =============================================================================
#  Downloads educational content channels into Kolibri.
#  Works while the walled garden is running (uses Ethernet for internet).
#  Can also be run before starting the walled garden.
#
#  Usage:
#    sudo ./import-kolibri-channels.sh              # Import all channels
#    sudo ./import-kolibri-channels.sh english       # English only (39 channels, ~270 GB)
#    sudo ./import-kolibri-channels.sh spanish       # Spanish only (16 channels, ~140 GB)
#    sudo ./import-kolibri-channels.sh french        # French only  (13 channels, ~54 GB)
#    sudo ./import-kolibri-channels.sh haitian       # Haitian Creole (3 channels)
#    sudo ./import-kolibri-channels.sh multilingual  # Multilingual (6 channels)
#
#  WARNING: Downloading ALL channels requires 350+ GB of disk space.
#           Check available space with: df -h
#
#  Channel IDs sourced from https://studio.learningequality.org (updated May 2026)
# =============================================================================

# --- English Channels (39) ---------------------------------------------------
#     Total: ~270+ GB
ENGLISH_CHANNELS=(
  "8a2d480dbc9b53408c688e8188326b16|Aflatoun Academy (en)"
  "d0ef6f71e4fe4e54bb87d7dab5eeaae2|Be Strong: Internet safety resources"
  "e409b964366a59219c148f2aaa741f43|Blockly Games"
  "2d7b056d668a58ee9244ccf76108cbdb|Book Dash"
  "922e9c576c2f59e59389142b136308ff|Career Girls"
  "d35a806594a843f2864457eac34ee12e|Childhood Education International"
  "1d8f6d84618153c18c695d85074952a7|CK-12"
  "cf4fee6d062a49fc88131f8a4ea2192e|Colors of Kindness"
  "bbb4ea407a3c450cb18cbaa76f2d75cd|CSpathshala (English)"
  "9b3463eaa85354eeb26a184fe1d9a04b|Digital Awareness (English)"
  "63e8e65976f258cf9b1a5bb85e486aa8|Digital Discovery (English)"
  "c51a0f842fed427c95acff9bb4a21e3c|EENET Inclusive Education Training Materials"
  "d6e3b856125f5e6aa5fb40c8b112d5e9|EngageNY (en)"
  "61b75af2bb2c4c0ea850d85dcf88d0fd|Espresso English"
  "0418cc231e9c5513af0fff9f227f7172|Free English with Hello Channel"
  "0e173fca6e9052f8a474a2fb84055faf|Global Digital Library - Book Catalog"
  "5d53b37cc90e50128a40e293d9fadb27|Global Youth Communities"
  "b62c5c2139a65fb2aaf68987a25b28a1|Goalkicker Tech Books"
  "624e09bb5eeb4d20aa8de62e7b4778a0|How to get started with Kolibri"
  "7ec3b2ad48925d639592954e2298618f|HP LIFE - Courses (English)"
  "c9d7f950ab6b5a1199e3d6c10d7f0103|Khan Academy (English - US curriculum)"
  "6616efc8aa604a308c8f5d18b00a1ce3|Khan Academy - Standardized Test Preparation"
  "913efe9f14c65cb1b23402f21f056e99|MIT Blossoms"
  "3c77d9dd717341bb8fff8da6ab980df3|Mother Goose Club Video Lessons"
  "4dd2e97a930851579b92add96d2e81f7|Nal'ibali Web Resource Tree"
  "fc47aee82e0153e2a30197d3fdee1128|Open Stax"
  "8b28761bac075deeb66adc6c80ef119c|Osmosis.org"
  "b8bd7770063d40a8bd9b30d4703927b5|PBS SoCal: Family Math"
  "197934f144305350b5820c7c4dd8e194|PhET Interactive Simulations"
  "131e543dbecf5776bb13cfcfddf05605|Pratham Books' StoryWeaver"
  "f189d7c505644311a4e62d9f3259e31b|Sciensation"
  "3e464ee12f6a50a781cddf59147b48b1|Sikana (English)"
  "12cee68c112452a1be3f73e730ec2114|Stanford Digital MEdIC Coronavirus Toolkit"
  "8db463b116d24a6c8f56c4df4fa88041|Tackling Violence Film Series"
  "1e378725d3924b47aa5e1260628820b5|TED-Ed Lessons"
  "a9b25ac9814742c883ce1b0579448337|TESSA - Teacher Resources"
  "74f36493bb475b62935fa8705ed59fed|Thoughtful Learning"
  "000409f81dbe5d1ba67101cb9fed4530|Touchable Earth (en)"
  "a1239cf0220a5f8cb633d6d1cafcb9a2|World Health Organization COVID Advice for Public"
)

# --- French Channels (16) ----------------------------------------------------
#     Total: ~54+ GB
FRENCH_CHANNELS=(
  "8166e765a0095bfaa49e98d034653dc5|Aflatoun Academy (fr)"
  "0294a064f7224899887ce07bd47f9991|Citoyennes de la Terre"
  "d2e80a502efa45d199d24a2b08dccd8d|Citoyennes: Portraits de femmes engagees"
  "0095239178fc583f8e4fb846b319c576|Decouverte Digitale (Francais)"
  "0928b562e60256b081c0fbc990f3f33e|HP LIFE - Cours (Francais)"
  "878ec2e6f88c5c268b1be6f202833cd4|Khan Academy (Francais)"
  "708fc2e73a0f4ab59dfeebfd1203896d|Les jeux traditionnels pour apprendre les maths"
  "3e7b3ae54d9753a7b2ff43d5c12c2094|PhET simulations interactives"
  "f52913a93b625dc8a563d7a9492f422d|Sensibilisation au Numerique (Francais)"
  "8ef625db6e86506c9a3bac891e413fff|Sikana (Francais)"
  "b336c2e2c45c53d5b24e5c476a54b077|Touchable Earth (fr)"
  "90de6b49f71251c1855e34a416da2f20|WHO COVID Advice for Public (fr)"
  "adb2042d0abe40b8918e599c9f36ab19|Education internationale de la petite enfance"
)

# --- Haitian Creole Channels (3) ---------------------------------------------
HAITIAN_CHANNELS=(
  "58db7fdb8f115b92bc1a83bc98245665|All Children Reading (Ayiti)"
  "8aa6be55d57c48f9a5727f3f5b0090c7|An n aprann ak Lakou Kajou"
  "f4715a7769725c729d25d29977b8b308|Similasyon Enteraktif PhET"
)

# --- Multilingual Channels (6) -----------------------------------------------
MULTILINGUAL_CHANNELS=(
  "f9d3e0e46ea25789bbed672ff6a399ed|African Storybook Library (multiple languages)"
  "378cf4128c854c2795c100b5aca7a3ed|Inclusive Home Learning Activities"
  "254f1b384c2551ed80ada423449212a1|PointB 21CS Guide"
  "305b12ea5ea84fa18f933705c23f5ee0|School of Thought"
  "3eaf194585ca4051bdfded581e85b072|Stop It at the Start Toolkit"
  "f393c30f95fb4bec87f873b2013ec9e3|The Passionfruit Island Series"
)

# --- Spanish Channels (16) ---------------------------------------------------
#     Total: ~140+ GB
SPANISH_CHANNELS=(
  "fed29d60e4d84a1e8dcfc781d920b40e|Biblioteca Elejandria"
  "1c98e92b8c2f536796960bed8d137a25|Ceibal"
  "da53f90b1be25752a04682bbc353659f|Ciencia NASA"
  "604ad3b85d844dd89ee70fa12a9a5a6e|CREE+"
  "7e68bc59d4304e718a0750b1b87125ad|Cultura Emprendedora"
  "a12aa60789ab5b11b7f0b87bafe093e5|EngageNY (es)"
  "0a3446937e3340fa86e6010ba80e16e1|Guia de Alfabetizacion Digital Critica"
  "d0cb2b465843584e9c72969ea5ea5519|HP LIFE - Cursos (Espanol)"
  "c1f2b7e6ac9f56a2bb44fa7a48b66dce|Khan Academy (Espanol)"
  "f6cb302ef6594db4b4a04b4991a595c2|Plan Educativo TIC Basico"
  "f446655247a95c0aa94ca9fa4d66783b|Proyecto Biosfera"
  "c4ad70f67dff57738591086e466f9afc|Proyecto Descartes"
  "30c71c99c42c57d181e8aeafd2e15e5f|Sikana (Espanol)"
  "8fa678af1dd05329bf3218c549b84996|Simulaciones interactivas PhET"
  "b06dd546e8ba4b44bf921862c9948ffe|WiiXii"
  "6cb19f6919055fe8991b0d323c5eed28|WHO COVID Advice (Espanol)"
)

# --- Helpers -----------------------------------------------------------------

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }
warn() { echo -e "  \033[1;33m!\033[0m $*"; }

if [ "$(id -u)" -ne 0 ]; then
  err "Run with sudo:  sudo $0 [english|spanish|all]"
  exit 1
fi

# Always store Kolibri data in the him user's home directory,
# regardless of who runs this script.
if [ ! -d /home/him ]; then
  warn "/home/him does not exist — creating it"
  mkdir -p /home/him
  chown him:him /home/him
  chmod 755 /home/him
fi
export KOLIBRI_HOME=/home/him/.kolibri

if ! command -v kolibri >/dev/null 2>&1; then
  err "Kolibri is not installed."
  exit 1
fi

# Detect which user the Kolibri service runs as (set by the Debian installer).
# Running 'kolibri manage' as root writes to /root/.kolibri — wrong instance.
KOLIBRI_SVC_USER="$(cat /etc/kolibri/username 2>/dev/null | tr -d '[:space:]')"
KOLIBRI_SVC_USER="${KOLIBRI_SVC_USER:-him}"

if ! id "$KOLIBRI_SVC_USER" >/dev/null 2>&1; then
  err "Kolibri service user '$KOLIBRI_SVC_USER' not found. Check /etc/kolibri/username."
  exit 1
fi

KOLIBRI_HOME_DIR="$(getent passwd "$KOLIBRI_SVC_USER" | cut -d: -f6)/.kolibri"
ok "Kolibri service user : $KOLIBRI_SVC_USER"
ok "Kolibri data directory: $KOLIBRI_HOME_DIR"
ok "Content directory    : $KOLIBRI_HOME_DIR/content/storage"

import_channel() {
  local id="$1" name="$2"
  echo ""
  echo "  Importing: $name"
  echo "  Channel ID: $id"

  echo "    Downloading channel metadata..."
  if sudo -u "$KOLIBRI_SVC_USER" kolibri manage importchannel network "$id"; then
    ok "Channel metadata downloaded"
  else
    err "Failed to download channel metadata for $name"
    return 1
  fi

  echo "    Downloading content (this may take a while)..."
  if sudo -u "$KOLIBRI_SVC_USER" kolibri manage importcontent network "$id"; then
    ok "$name — content downloaded"
  else
    warn "$name — partial download (some content may have failed)"
  fi
}

import_group() {
  local label="$1"
  shift
  local channels=("$@")

  log "$label Channels (${#channels[@]} total)"

  for entry in "${channels[@]}"; do
    local id="${entry%%|*}"
    local name="${entry##*|}"
    import_channel "$id" "$name"
  done
}

# --- Main --------------------------------------------------------------------

FILTER="${1:-all}"

echo ""
echo "============================================================"
echo "     Kolibri Channel Importer — HIM Education"
echo "============================================================"
echo "  Filter: $FILTER"
echo "============================================================"

case "$FILTER" in
  english|en)
    import_group "English" "${ENGLISH_CHANNELS[@]}"
    ;;
  spanish|es)
    import_group "Spanish" "${SPANISH_CHANNELS[@]}"
    ;;
  french|fr)
    import_group "French" "${FRENCH_CHANNELS[@]}"
    ;;
  haitian|ht)
    import_group "Haitian Creole" "${HAITIAN_CHANNELS[@]}"
    ;;
  multilingual|multi)
    import_group "Multilingual" "${MULTILINGUAL_CHANNELS[@]}"
    ;;
  all)
    import_group "English" "${ENGLISH_CHANNELS[@]}"
    import_group "Spanish" "${SPANISH_CHANNELS[@]}"
    import_group "French" "${FRENCH_CHANNELS[@]}"
    import_group "Haitian Creole" "${HAITIAN_CHANNELS[@]}"
    import_group "Multilingual" "${MULTILINGUAL_CHANNELS[@]}"
    ;;
  from-file)
    FILE="${2:-/opt/him-edu/channels.json}"
    if [ ! -f "$FILE" ]; then
      err "File not found: $FILE"
      err "Generate it first with: ./export-channel-list.sh"
      exit 1
    fi
    log "Importing from $FILE"
    while IFS= read -r line; do
      id=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d['id'])")
      name=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d['name'])")
      import_channel "$id" "$name"
    done < <(python3 -c "import json; [print(json.dumps(c)) for c in json.load(open('$FILE'))]")
    ;;
  *)
    err "Unknown filter: '$FILTER'"
    err "Valid options: english (en), spanish (es), french (fr), haitian (ht), multilingual (multi), all"
    err "            or: from-file [path/to/channels.json]"
    err "Usage: sudo $0 [english|spanish|french|haitian|multilingual|all|from-file]"
    exit 1
    ;;
esac

echo ""
echo "============================================================"
echo "     Import Complete!"
echo "============================================================"
echo "  Channels are now available in Kolibri at:"
echo "    http://10.42.0.1:8080/"
echo ""
echo "  To add more channels, visit https://kolibri-catalog-en.learningequality.org"
echo "  and find the channel ID, then run:"
echo "    sudo kolibri manage importchannel network <channel_id>"
echo "    sudo kolibri manage importcontent network <channel_id>"
echo "============================================================"
