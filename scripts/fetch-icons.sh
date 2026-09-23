#!/usr/bin/env sh
# Downloads the Fluent UI icons used by Silo from the Iconify API and stores
# them as SVG files (fill="currentColor") in icons/. Re-run after adding a
# name to the list below.
set -eu

cd "$(dirname "$0")/.."
mkdir -p icons

ICONS="
fluent:add-20-regular
fluent:add-24-regular
fluent:arrow-left-20-regular
fluent:arrow-up-20-regular
fluent:checkmark-20-filled
fluent:chevron-down-12-regular
fluent:chevron-down-20-regular
fluent:chevron-right-12-regular
fluent:chevron-right-16-regular
fluent:color-20-regular
fluent:delete-20-regular
fluent:edit-20-regular
fluent:emoji-20-regular
fluent:folder-20-filled
fluent:folder-24-filled
fluent:folder-48-regular
fluent:folder-add-20-regular
fluent:folder-arrow-up-24-filled
fluent:folder-open-20-filled
fluent:folder-open-20-regular
fluent:globe-20-regular
fluent:globe-24-filled
fluent:grid-20-regular
fluent:apps-list-20-regular
fluent:home-20-regular
fluent:image-add-20-regular
fluent:link-20-regular
fluent:open-20-regular
fluent:rename-20-regular
fluent:search-20-regular
fluent:select-all-on-20-regular
fluent:dismiss-20-regular
fluent:weather-sunny-20-regular
fluent:weather-moon-20-regular
fluent:desktop-20-regular
fluent:dark-theme-20-regular
fluent:checkmark-20-regular
fluent:wrench-20-regular
fluent:window-20-regular
fluent:dismiss-16-regular
fluent:arrow-right-20-regular
fluent:arrow-clockwise-20-regular
fluent:globe-16-regular
fluent:tab-desktop-multiple-20-regular
fluent:folder-open-24-regular
fluent:panel-left-contract-20-regular
fluent:panel-left-expand-20-regular
fluent:copy-20-regular
fluent:clipboard-paste-20-regular
fluent:window-console-20-regular
fluent:window-console-20-filled
fluent:document-20-regular
fluent:document-24-regular
fluent:document-pdf-20-regular
fluent:document-pdf-24-regular
fluent:image-20-regular
fluent:image-24-regular
fluent:video-clip-20-regular
fluent:video-clip-24-regular
fluent:music-note-2-20-regular
fluent:music-note-2-24-regular
fluent:code-20-regular
fluent:code-24-regular
fluent:document-text-20-regular
fluent:document-text-24-regular
fluent:play-20-filled
fluent:pause-20-filled
fluent:speaker-2-20-regular
fluent:link-20-regular
fluent:server-20-regular
fluent:key-20-regular
fluent:password-20-regular
fluent:document-key-20-regular
fluent:eye-20-regular
fluent:eye-off-20-regular
fluent:table-20-regular
fluent:table-24-regular
fluent:lock-closed-20-regular
fluent:settings-20-regular
fluent:lock-open-20-regular
fluent:chevron-right-20-regular
fluent:checkbox-checked-20-regular
fluent:checkbox-unchecked-20-regular
fluent:table-insert-row-20-regular
fluent:table-delete-row-20-regular
fluent:table-insert-column-20-regular
fluent:table-delete-column-20-regular
fluent:edit-20-regular
fluent:text-align-left-20-regular
fluent:search-20-regular
fluent:arrow-sort-20-regular
fluent:arrow-sort-up-20-regular
fluent:arrow-sort-down-20-regular
fluent:arrow-export-20-regular
fluent:arrow-import-20-regular
fluent:arrow-download-20-regular
fluent:document-arrow-right-20-regular
fluent:save-20-regular
fluent:prohibited-20-regular
fluent:shield-keyhole-20-regular
fluent:person-20-regular
fluent:arrow-sync-20-regular
fluent:sign-out-20-regular
fluent:plug-connected-20-regular
fluent:plug-disconnected-20-regular
fluent:more-horizontal-20-regular
fluent:vault-20-regular
fluent:cloud-arrow-down-20-regular
fluent:info-20-regular
fluent:error-circle-20-regular
fluent:arrow-undo-20-regular
fluent:dismiss-square-multiple-20-regular
"

for icon in $ICONS; do
    prefix="${icon%%:*}"
    name="${icon#*:}"
    target="icons/${prefix}-${name}.svg"
    [ -s "$target" ] && continue
    if ! curl -fsSL "https://api.iconify.design/${prefix}/${name}.svg" -o "$target" 2>/dev/null; then
        # Iconify rate-limited (429): fall back to the Fluent npm package on jsdelivr,
        # whose paths carry no fill so they inherit currentColor like the Iconify ones.
        npm_name=$(echo "$name" | tr '-' '_')
        curl -fsSL "https://cdn.jsdelivr.net/npm/@fluentui/svg-icons/icons/${npm_name}.svg" -o "$target"
        perl -pi -e 's/<path /<path fill="currentColor" /g; s/fill="#212121"/fill="currentColor"/g' "$target"
    fi
    if ! head -c 4 "$target" | grep -q '<svg'; then
        echo "Invalid icon payload for ${icon}" >&2
        rm -f "$target"
        exit 1
    fi
    echo "fetched ${target}"
done
