#pragma once

#include <QQuickImageProvider>

// Serves recolored Fluent/Iconify SVG icons to QML through image://icon/<name>/<rrggbb>.
class IconProvider final : public QQuickImageProvider
{
public:
    IconProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
