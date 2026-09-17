#include "IconProvider.h"

#include <QColor>
#include <QFile>
#include <QPainter>
#include <QSvgRenderer>

IconProvider::IconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage IconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const qsizetype separator = id.lastIndexOf(QLatin1Char('/'));
    const QString name = separator < 0 ? id : id.left(separator);
    const QString colorHex = separator < 0 ? QStringLiteral("000000") : id.mid(separator + 1);

    QFile file(QStringLiteral(":/icons/%1.svg").arg(name));
    if (!file.open(QIODevice::ReadOnly)) {
        if (size)
            *size = QSize();
        return {};
    }

    QColor color(QLatin1Char('#') + colorHex);
    if (!color.isValid())
        color = Qt::black;

    QByteArray svg = file.readAll();
    // SVG has no #AARRGGBB notation: use #RRGGBB and carry alpha through fill-opacity.
    svg.replace("currentColor", color.name(QColor::HexRgb).toUtf8());
    if (color.alpha() < 255) {
        const QByteArray opacity = QByteArray::number(color.alphaF(), 'f', 3);
        svg.replace("<svg", "<svg opacity=\"" + opacity + "\"");
    }

    QSvgRenderer renderer(svg);
    QSize target = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : renderer.defaultSize();
    if (target.isEmpty())
        target = QSize(20, 20);

    QImage image(target, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    renderer.render(&painter, QRectF(QPointF(0, 0), QSizeF(target)));
    painter.end();

    if (size)
        *size = target;
    return image;
}
