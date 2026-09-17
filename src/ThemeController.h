#pragma once

#include <QObject>
#include <QString>

// Persists the user's appearance choice and applies it to the platform via
// QStyleHints so native chrome (title bar, dialogs) follows the app.
class ThemeController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(QStringList modes READ modes CONSTANT)

public:
    explicit ThemeController(QObject *parent = nullptr);

    QString mode() const { return m_mode; }
    void setMode(const QString &mode);
    bool dark() const;
    QStringList modes() const;

signals:
    void modeChanged();
    void darkChanged();

private:
    void apply();

    QString m_mode = QStringLiteral("system");
};
