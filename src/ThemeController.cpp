#include "ThemeController.h"

#include <QGuiApplication>
#include <QSettings>
#include <QStyleHints>

namespace {
const auto kSettingsKey = QStringLiteral("appearance/mode");
}

ThemeController::ThemeController(QObject *parent) : QObject(parent)
{
    const QString saved = QSettings().value(kSettingsKey).toString();
    if (modes().contains(saved))
        m_mode = saved;

    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged,
            this, &ThemeController::darkChanged);

    apply();
}

QStringList ThemeController::modes() const
{
    return {QStringLiteral("light"), QStringLiteral("dark"), QStringLiteral("system")};
}

void ThemeController::setMode(const QString &mode)
{
    if (mode == m_mode || !modes().contains(mode))
        return;
    m_mode = mode;
    QSettings().setValue(kSettingsKey, m_mode);
    apply();
    emit modeChanged();
}

bool ThemeController::dark() const
{
    return QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
}

void ThemeController::apply()
{
    auto *hints = QGuiApplication::styleHints();
    const bool wasDark = dark();

    if (m_mode == QLatin1String("light"))
        hints->setColorScheme(Qt::ColorScheme::Light);
    else if (m_mode == QLatin1String("dark"))
        hints->setColorScheme(Qt::ColorScheme::Dark);
    else
        hints->unsetColorScheme();

    if (wasDark != dark())
        emit darkChanged();
}
