#!/bin/bash
# Builds MultiPasty, installs it into /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.pierrelecalvez.multipasty"

./build.sh

echo "→ Installing into /Applications"
if pgrep -f "MultiPasty.app/Contents/MacOS/MultiPasty" > /dev/null; then
    pkill -f "MultiPasty.app/Contents/MacOS/MultiPasty" || true
    sleep 1
fi
rm -rf /Applications/MultiPasty.app
cp -R build/MultiPasty.app /Applications/MultiPasty.app

# The app is ad-hoc signed, so every build has a new code hash. macOS keeps the
# Accessibility grant of the *previous* hash, leaving a checkbox that looks
# enabled but no longer matches the binary that runs. Clearing the entry is the
# only way to get a grant that actually applies. See README → Troubleshooting.
echo "→ Clearing the stale Accessibility entry"
tccutil reset Accessibility "$BUNDLE_ID" > /dev/null 2>&1 \
    || echo "  (do it by hand: remove MultiPasty from the list with the − button)"

echo "→ Launching"
open /Applications/MultiPasty.app

cat <<'MSG'

✅ MultiPasty is installed and running — look for the clipboard icon in the menu bar.

   macOS will ask for the Accessibility permission. Click "Open System Settings"
   and switch MultiPasty on, so it can press ⌘V for you.

   To check: open the MultiPasty menu — the status line must read
   "Accessibility: granted ✓".

MSG
