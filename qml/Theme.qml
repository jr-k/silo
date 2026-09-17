pragma Singleton
import QtQuick

// Design tokens for Silo. `dark` follows the effective platform color scheme,
// which ThemeController forces (light/dark) or leaves to the OS (system).
QtObject {
    id: theme

    readonly property bool dark: Application.styleHints.colorScheme === Qt.ColorScheme.Dark

    // ------------------------------------------------------------------ palettes
    readonly property QtObject lightPalette: QtObject {
        readonly property color windowBg: "#F3F3F3"
        readonly property color surface: "#FFFFFF"
        readonly property color surfaceAlt: "#F9F9F9"
        readonly property color controlBg: "#FBFBFB"
        readonly property color controlHover: "#F3F3F3"
        readonly property color controlPressed: "#EBEBEB"
        readonly property color border: "#E5E5E5"
        readonly property color borderStrong: "#D6D6D6"
        readonly property color divider: "#EAEAEA"

        readonly property color text: "#1A1A1A"
        readonly property color textSecondary: "#5F5F5F"
        readonly property color textTertiary: "#8E8E8E"
        readonly property color textDisabled: "#A6A6A6"
        readonly property color textOnAccent: "#FFFFFF"

        readonly property color accent: "#0067C0"
        readonly property color accentHover: "#1975C5"
        readonly property color accentPressed: "#005FB0"
        readonly property color accentDisabled: "#9AC0E5"
        readonly property color accentSoft: "#E6F1FB"
        readonly property color accentSoftBorder: "#B9D6F2"

        readonly property color hover: "#0A000000"
        readonly property color pressed: "#14000000"
        readonly property color selection: "#DCEBF9"
        readonly property color selectionHover: "#D0E4F6"
        readonly property color selectionBorder: "#A4CBEC"
        readonly property color dropTarget: "#CFE5F8"
        readonly property color marqueeFill: "#1F0067C0"
        readonly property color marqueeBorder: "#990067C0"

        readonly property color fieldBg: "#FBFBFB"
        readonly property color fieldBgFocused: "#FFFFFF"
        readonly property color fieldUnderline: "#8A8A8A"
        readonly property color menuBg: "#F9F9F9"
        readonly property color overlay: "#33000000"

        readonly property color folder: "#F5C242"
        readonly property color folderDark: "#DBA51E"
        readonly property color link: "#2B7CD3"
        readonly property color destructive: "#C42B1C"
        readonly property color terminal: "#3A9D5D"
        readonly property color file: "#8A63D2"
        readonly property color terminalBg: "#1E1E1E"
        readonly property color terminalFg: "#E6E6E6"
    }

    readonly property QtObject darkPalette: QtObject {
        readonly property color windowBg: "#202020"
        readonly property color surface: "#2B2B2B"
        readonly property color surfaceAlt: "#262626"
        readonly property color controlBg: "#2D2D2D"
        readonly property color controlHover: "#353535"
        readonly property color controlPressed: "#282828"
        readonly property color border: "#3A3A3A"
        readonly property color borderStrong: "#474747"
        readonly property color divider: "#373737"

        readonly property color text: "#FFFFFF"
        readonly property color textSecondary: "#C7C7C7"
        readonly property color textTertiary: "#8F8F8F"
        readonly property color textDisabled: "#6E6E6E"
        readonly property color textOnAccent: "#0B1A26"

        readonly property color accent: "#60CDFF"
        readonly property color accentHover: "#7AD5FF"
        readonly property color accentPressed: "#4FB9E9"
        readonly property color accentDisabled: "#3A6B85"
        readonly property color accentSoft: "#1E3646"
        readonly property color accentSoftBorder: "#2F5A75"

        readonly property color hover: "#0FFFFFFF"
        readonly property color pressed: "#0AFFFFFF"
        readonly property color selection: "#2B3F52"
        readonly property color selectionHover: "#324A61"
        readonly property color selectionBorder: "#3F6A8C"
        readonly property color dropTarget: "#1F4B6B"
        readonly property color marqueeFill: "#3360CDFF"
        readonly property color marqueeBorder: "#B360CDFF"

        readonly property color fieldBg: "#2F2F2F"
        readonly property color fieldBgFocused: "#1F1F1F"
        readonly property color fieldUnderline: "#9A9A9A"
        readonly property color menuBg: "#2C2C2C"
        readonly property color overlay: "#73000000"

        readonly property color folder: "#F8CB5A"
        readonly property color folderDark: "#DBA51E"
        readonly property color link: "#6CB8FF"
        readonly property color destructive: "#FF99A4"
        readonly property color terminal: "#6CCB8B"
        readonly property color file: "#B79CF0"
        readonly property color terminalBg: "#1A1A1A"
        readonly property color terminalFg: "#E6E6E6"
    }

    readonly property QtObject palette: dark ? darkPalette : lightPalette

    // ------------------------------------------------------------------ color tokens
    readonly property color windowBg: palette.windowBg
    readonly property color surface: palette.surface
    readonly property color surfaceAlt: palette.surfaceAlt
    readonly property color controlBg: palette.controlBg
    readonly property color controlHover: palette.controlHover
    readonly property color controlPressed: palette.controlPressed
    readonly property color border: palette.border
    readonly property color borderStrong: palette.borderStrong
    readonly property color divider: palette.divider

    readonly property color text: palette.text
    readonly property color textSecondary: palette.textSecondary
    readonly property color textTertiary: palette.textTertiary
    readonly property color textDisabled: palette.textDisabled
    readonly property color textOnAccent: palette.textOnAccent

    readonly property color accent: palette.accent
    readonly property color accentHover: palette.accentHover
    readonly property color accentPressed: palette.accentPressed
    readonly property color accentDisabled: palette.accentDisabled
    readonly property color accentSoft: palette.accentSoft
    readonly property color accentSoftBorder: palette.accentSoftBorder

    readonly property color hover: palette.hover
    readonly property color pressed: palette.pressed
    readonly property color selection: palette.selection
    readonly property color selectionHover: palette.selectionHover
    readonly property color selectionBorder: palette.selectionBorder
    readonly property color dropTarget: palette.dropTarget
    readonly property color marqueeFill: palette.marqueeFill
    readonly property color marqueeBorder: palette.marqueeBorder

    readonly property color fieldBg: palette.fieldBg
    readonly property color fieldBgFocused: palette.fieldBgFocused
    readonly property color fieldUnderline: palette.fieldUnderline
    readonly property color menuBg: palette.menuBg
    readonly property color overlay: palette.overlay

    readonly property color folder: palette.folder
    readonly property color folderDark: palette.folderDark
    readonly property color link: palette.link
    readonly property color destructive: palette.destructive
    readonly property color terminal: palette.terminal
    readonly property color file: palette.file
    readonly property color terminalBg: palette.terminalBg
    readonly property color terminalFg: palette.terminalFg

    // ------------------------------------------------------------------ shape & type
    readonly property int radiusSmall: 4
    readonly property int radius: 6
    readonly property int radiusLarge: 8

    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeCaption: 11
    readonly property int fontSizeTitle: 20

    readonly property int animationFast: 80
    readonly property int animationNormal: 160

    readonly property string fontFamily: Qt.platform.os === "windows"
                                         ? "Segoe UI Variable Text"
                                         : Qt.application.font.family
}
