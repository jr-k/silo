#pragma once

#include <QObject>

class QEvent;

// Sees every mouse press on the main window before Qt Quick delivers it. A view
// that must react to a press landing anywhere (the sidebar drops its selection
// on a click outside) cannot rely on a pointer handler on the root item: once a
// child item grabs the press, handlers on its ancestors never hear about it.
class WindowEvents final : public QObject
{
    Q_OBJECT
public:
    explicit WindowEvents(QObject *parent = nullptr);
    // Starts filtering the window's events (call once the window exists).
    void watch(QObject *window);

signals:
    // Mouse press at window (scene) coordinates.
    void pressed(qreal x, qreal y);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
};
