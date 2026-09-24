#include "WindowEvents.h"

#include <QEvent>
#include <QMouseEvent>

WindowEvents::WindowEvents(QObject *parent) : QObject(parent) {}

void WindowEvents::watch(QObject *window)
{
    if (window)
        window->installEventFilter(this);
}

bool WindowEvents::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::MouseButtonPress) {
        const QPointF pos = static_cast<QMouseEvent *>(event)->position();
        emit pressed(pos.x(), pos.y());
    }
    return QObject::eventFilter(watched, event);
}
