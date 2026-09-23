pragma Singleton
import QtQuick

// Everything the UI needs to know about leaf item types:
//   "web"  -> url is an http(s) address, opened in a browser tab
//   "ssh"  -> url is ssh://user@host:port, opened in a terminal tab
//   "file" -> url is a local path, opened in a viewer tab
QtObject {
    id: types

    readonly property var all: ["web", "ssh", "file"]

    function label(type) {
        switch (type) {
        case "ssh": return "SSH terminal"
        case "file": return "File"
        default: return "Web page"
        }
    }

    // Lower-case form used inside sentences ("New SSH terminal")
    function noun(type) {
        switch (type) {
        case "ssh": return "SSH terminal"
        case "file": return "file"
        default: return "web page"
        }
    }

    function description(type) {
        switch (type) {
        case "ssh": return "Open a terminal connected to a remote host"
        case "file": return "View a local document, image, video, sound or code file"
        default: return "Open a website in a browser tab"
        }
    }

    // Accent colour of the default glyph for that type
    function color(type, url) {
        switch (type) {
        case "ssh": return Theme.terminal
        case "file": return Theme.file
        default: return Theme.link
        }
    }

    // ------------------------------------------------------------------ files
    function fileKind(path) {
        var name = String(path || "").split(/[\\/]/).pop().toLowerCase()
        var dot = name.lastIndexOf(".")
        var ext = dot >= 0 ? name.substring(dot + 1) : ""
        if (ext === "pdf") return "pdf"
        if (ext === "csv" || ext === "tsv") return "csv"
        if (["png","jpg","jpeg","gif","webp","bmp","svg","ico","tif","tiff","heic","avif"].indexOf(ext) >= 0) return "image"
        if (["mp4","m4v","mov","webm","mkv","avi","mpg","mpeg"].indexOf(ext) >= 0) return "video"
        if (["mp3","m4a","aac","flac","wav","ogg","oga","opus","aiff","aif"].indexOf(ext) >= 0) return "audio"
        if (["json","jsonc","yaml","yml","js","mjs","cjs","jsx","ts","tsx","php","py","rb","go","rs","java","kt","kts",
             "swift","c","h","cpp","cc","cxx","hpp","hh","m","mm","cs","sh","bash","zsh","fish","ps1","sql","html","htm",
             "xml","svg","plist","css","scss","less","ini","toml","cfg","conf","env","mk","cmake","gradle","lua","pl",
             "r","dart","scala","vue","qml","graphql","proto","diff","patch"].indexOf(ext) >= 0) return "code"
        if (["txt","log","md","markdown","rtf"].indexOf(ext) >= 0 || name === "makefile" || name === "dockerfile") return "text"
        return "other"
    }

    // Glyph name for the default icon. `variant` is "20" (lists) or "24" (tiles).
    function glyph(type, url, variant) {
        var v = variant || "20"
        if (type === "ssh")
            return v === "24" ? "fluent-window-console-20-filled" : "fluent-window-console-20-regular"
        if (type === "file") {
            switch (fileKind(url)) {
            case "pdf": return "fluent-document-pdf-" + v + "-regular"
            case "csv": return "fluent-table-" + v + "-regular"
            case "image": return "fluent-image-" + v + "-regular"
            case "video": return "fluent-video-clip-" + v + "-regular"
            case "audio": return "fluent-music-note-2-" + v + "-regular"
            case "code": return "fluent-code-" + v + "-regular"
            case "text": return "fluent-document-text-" + v + "-regular"
            default: return "fluent-document-" + v + "-regular"
            }
        }
        return v === "24" ? "fluent-globe-24-filled" : "fluent-globe-20-regular"
    }

    // Short secondary line shown under tiles / in tooltips
    function subtitle(type, url) {
        var u = String(url || "")
        if (u.length === 0)
            return ""
        if (type === "ssh") {
            var s = parseSsh(u)
            return (s.user.length > 0 ? s.user + "@" : "") + s.host + (s.port !== 22 ? ":" + s.port : "")
        }
        if (type === "file")
            return u.split(/[\\/]/).pop()
        return u.replace(/^https?:\/\//, "").split("/")[0]
    }

    // ------------------------------------------------------------------ web
    // Web address as typed by the user: "example.com/x" or "localhost:8080" get an
    // https:// scheme, anything with an explicit scheme is kept as is.
    function normalizeWebUrl(text) {
        var u = String(text || "").trim()
        if (u.length === 0)
            return ""
        var hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(u) || /^(about|data|mailto|javascript):/i.test(u)
        return hasScheme ? u : "https://" + u
    }

    // ------------------------------------------------------------------ ssh
    function parseSsh(url) {
        var result = { user: "", host: "", port: 22 }
        var s = String(url || "").trim().replace(/^ssh:\/\//, "")
        var at = s.lastIndexOf("@")
        if (at >= 0) {
            result.user = s.substring(0, at)
            s = s.substring(at + 1)
        }
        var colon = s.lastIndexOf(":")
        if (colon >= 0 && /^\d+$/.test(s.substring(colon + 1))) {
            result.port = parseInt(s.substring(colon + 1))
            s = s.substring(0, colon)
        }
        result.host = s
        return result
    }

    function buildSsh(user, host, port) {
        var p = parseInt(port)
        if (isNaN(p) || p <= 0) p = 22
        return "ssh://" + (String(user).trim().length > 0 ? String(user).trim() + "@" : "")
                + String(host).trim() + (p !== 22 ? ":" + p : "")
    }
}
