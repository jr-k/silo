#!/usr/bin/env sh
# Downloads the browser-side libraries used by the Live mode viewers
# (xterm.js for SSH terminals, Ace for editable text files) into web/vendor.
set -eu

cd "$(dirname "$0")/.."
mkdir -p web/vendor

XTERM_VERSION="5.5.0"
XTERM_FIT_VERSION="0.10.0"
ACE_VERSION="1.36.5"

fetch() {
    url="$1"
    target="$2"
    curl -fsSL "$url" -o "$target"
    echo "fetched $target"
}

fetch "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js" web/vendor/xterm.js
fetch "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/css/xterm.css" web/vendor/xterm.css
fetch "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${XTERM_FIT_VERSION}/lib/addon-fit.js" web/vendor/addon-fit.js

# Ace editor (editable text/code viewer): core, search box, themes and the modes
# FileInspector::languageFor can map to.
mkdir -p web/vendor/ace
ACE_BASE="https://cdn.jsdelivr.net/npm/ace-builds@${ACE_VERSION}/src-min-noconflict"
ACE_FILES="ace.js ext-searchbox.js theme-github.js theme-tomorrow_night.js"
for mode in text json yaml javascript typescript php python ruby golang rust java kotlin swift \
            c_cpp objectivec csharp sh powershell sql xml html css scss less markdown ini toml \
            dockerfile makefile groovy lua perl r dart scala graphqlschema protobuf diff; do
    ACE_FILES="$ACE_FILES mode-${mode}.js"
done
for file in $ACE_FILES; do
    [ -s "web/vendor/ace/${file}" ] && continue
    fetch "${ACE_BASE}/${file}" "web/vendor/ace/${file}"
done
