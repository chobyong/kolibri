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
#    sudo ./import-kolibri-channels.sh english       # English only
#    sudo ./import-kolibri-channels.sh spanish       # Spanish only
# =============================================================================

# --- English Channels --------------------------------------------------------
ENGLISH_CHANNELS=(
  "1ceff53605e55bef987d88e0908658c5|Khan Academy (English)"
  "aeab3758bb2e5a3ba3af87e81b7ea8f5|CK-12"
  "e1b463b7a5b85e72bb13045e6a5286e5|Blockly Games"
  "da53f90b1be25752a04682bbc353659f|African Storybook"
  "74f3a5a2b7715926a09148015e79e6db|Touchable Earth"
)

# --- Spanish Channels --------------------------------------------------------
SPANISH_CHANNELS=(
  "51d01fe3c36c5890aa756b1bf3ee8c66|Khan Academy (Español)"
  "e09925e2a77c5e7ab03cd33a1d0049db|Biblioteca Digital (Spanish)"
  "efe8a702e51f5e3394751e2c3e9a0a02|CK-12 (Español)"
)

# --- Helpers -----------------------------------------------------------------

log()  { echo -e "\n\033[1;34m>>>\033[0m $*"; }
ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
err()  { echo -e "  \033[1;31m✗\033[0m $*" >&2; }
warn() { echo -e "  \033[1;33m!\033[0m $*"; }

if [ "$(id -u)" -ne 0 ]; then
  err "Run with sudo:  sudo $0 [english|spanish]"
  exit 1
fi

if ! command -v kolibri >/dev/null 2>&1; then
  err "Kolibri is not installed."
  exit 1
fi

import_channel() {
  local id="$1" name="$2"
  echo ""
  echo "  Importing: $name"
  echo "  Channel ID: $id"

  echo "    Downloading channel metadata..."
  if kolibri manage importchannel network "$id"; then
    ok "Channel metadata downloaded"
  else
    err "Failed to download channel metadata for $name"
    return 1
  fi

  echo "    Downloading content (this may take a while)..."
  if kolibri manage importcontent network "$id"; then
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
  all|*)
    import_group "English" "${ENGLISH_CHANNELS[@]}"
    import_group "Spanish" "${SPANISH_CHANNELS[@]}"
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
