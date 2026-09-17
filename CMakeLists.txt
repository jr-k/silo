cmake_minimum_required(VERSION 3.21)

project(SiloQt VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Network Quick QuickControls2 Svg WebEngineQuick WebChannelQuick Multimedia)
qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

qt_add_executable(Silo
    src/main.cpp
    src/AppStore.cpp
    src/AppStore.h
    src/IconProvider.cpp
    src/IconProvider.h
    src/FaviconProvider.cpp
    src/FaviconProvider.h
    src/ThemeController.cpp
    src/ThemeController.h
    src/TabsModel.cpp
    src/TabsModel.h
    src/SessionStore.cpp
    src/SessionStore.h
    src/TerminalSession.cpp
    src/TerminalSession.h
    src/FileInspector.cpp
    src/FileInspector.h
    src/CsvModel.cpp
    src/CsvModel.h
)

if(APPLE)
    set(SILO_MACOS_ICON "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo/logo-1000.icns")
    set_source_files_properties("${SILO_MACOS_ICON}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_sources(Silo PRIVATE "${SILO_MACOS_ICON}")
elseif(WIN32)
    target_sources(Silo PRIVATE icons/logo/silo.rc)
endif()

set_source_files_properties(qml/Theme.qml qml/DragState.qml qml/Session.qml qml/ItemTypes.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(Silo
    URI Silo
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/DragState.qml
        qml/Session.qml
        qml/ItemTypes.qml
        qml/Icon.qml
        qml/SiteIcon.qml
        qml/ItemIcon.qml
        qml/ModeSwitch.qml
        qml/WorkingView.qml
        qml/TabPage.qml
        qml/WebPage.qml
        qml/TerminalPage.qml
        qml/FilePage.qml
        qml/FileInfoCard.qml
        qml/CsvView.qml
        qml/OpenAllDialog.qml
        qml/SiloButton.qml
        qml/CommandButton.qml
        qml/IconButton.qml
        qml/SiloTextField.qml
        qml/SiloMenu.qml
        qml/SiloMenuItem.qml
        qml/SiloDialog.qml
        qml/Badge.qml
        qml/WorkspaceSwitcher.qml
        qml/WorkspaceDialog.qml
        qml/WorkspaceTransfer.qml
        qml/IconPicker.qml
        qml/Sidebar.qml
        qml/DirectoryView.qml
        qml/ItemDialog.qml
        qml/DeleteDialog.qml
        qml/SidebarToggle.qml
        qml/TextEditor.qml
        qml/SettingsButton.qml
        qml/SettingsDialog.qml
)

file(GLOB SILO_ICON_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/icons/*.svg")
qt_add_resources(Silo "silo_icons"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/icons"
    FILES ${SILO_ICON_FILES}
)

set(SILO_APP_ICON_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo/logo-64.png"
    "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo/logo-512.png"
)
qt_add_resources(Silo "silo_app_icons"
    PREFIX "/app"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo"
    FILES ${SILO_APP_ICON_FILES}
)

file(GLOB SILO_WEB_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/web/*.html"
    "${CMAKE_CURRENT_SOURCE_DIR}/web/vendor/*"
    "${CMAKE_CURRENT_SOURCE_DIR}/web/vendor/ace/*")
qt_add_resources(Silo "silo_web"
    PREFIX "/web"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/web"
    FILES ${SILO_WEB_FILES}
)

target_link_libraries(Silo
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Network
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Svg
        Qt6::WebEngineQuick
        Qt6::WebChannelQuick
        Qt6::Multimedia
)

set_target_properties(Silo PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "Silo"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.jessym.silo"
    MACOSX_BUNDLE_ICON_FILE "logo-1000.icns"
)

install(TARGETS Silo
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
