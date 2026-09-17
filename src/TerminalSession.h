#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

class QSocketNotifier;

// One interactive shell running in a pseudo-terminal: `ssh user@host -p port`,
// or the local shell when no host is given. Exposed to the xterm.js page through
// QWebChannel: output() carries raw bytes as base64, write() takes what the user typed.
class TerminalSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY configChanged)
    Q_PROPERTY(QString user READ user WRITE setUser NOTIFY configChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY configChanged)
    // "" (ssh defaults: agent, ~/.ssh keys, ssh_config), "password" or "key"
    Q_PROPERTY(QString authMethod READ authMethod WRITE setAuthMethod NOTIFY configChanged)
    Q_PROPERTY(QString keyPath READ keyPath WRITE setKeyPath NOTIFY configChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY configChanged)
    // [program, args…]: run this instead of ssh / the login shell (password manager sign-in flows)
    Q_PROPERTY(QStringList command READ command WRITE setCommand NOTIFY configChanged)
    // Colours/font handed to xterm.js (bg, fg, cursor, selection, fontFamily, fontSize…).
    Q_PROPERTY(QVariantMap theme READ theme WRITE setTheme NOTIFY themeChanged)

public:
    explicit TerminalSession(QObject *parent = nullptr);
    ~TerminalSession() override;

    bool running() const { return m_pid > 0; }
    QString host() const { return m_host; }
    QString user() const { return m_user; }
    int port() const { return m_port; }
    QString authMethod() const { return m_authMethod; }
    QString keyPath() const { return m_keyPath; }
    QString password() const { return m_password; }
    QStringList command() const { return m_command; }
    void setCommand(const QStringList &command);
    QVariantMap theme() const { return m_theme; }
    void setHost(const QString &host);
    void setUser(const QString &user);
    void setPort(int port);
    void setAuthMethod(const QString &method);
    void setKeyPath(const QString &path);
    void setPassword(const QString &password);
    void setTheme(const QVariantMap &theme);

    // Called by the page once xterm.js knows its size; (re)starts the process.
    Q_INVOKABLE void attach(int cols, int rows);
    Q_INVOKABLE void write(const QString &data);
    Q_INVOKABLE void resize(int cols, int rows);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void restart();

signals:
    void output(const QString &base64);
    void finished(int exitCode);
    void runningChanged();
    void configChanged();
    void themeChanged();

private:
    void start();
    void readAvailable();
    void closePty();

    QString m_host;
    QString m_user;
    int m_port = 22;
    QString m_authMethod;
    QString m_keyPath;
    QString m_password;
    QStringList m_command;
    QVariantMap m_theme;
    int m_cols = 80;
    int m_rows = 24;
    int m_master = -1;
    qint64 m_pid = -1;
    QSocketNotifier *m_notifier = nullptr;
};
