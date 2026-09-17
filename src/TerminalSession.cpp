#include "TerminalSession.h"

#include <QCoreApplication>
#include <QDir>
#include <QSocketNotifier>

#ifdef Q_OS_UNIX
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#if defined(Q_OS_MACOS)
#include <util.h>
#else
#include <pty.h>
#endif
#endif

TerminalSession::TerminalSession(QObject *parent) : QObject(parent) {}

TerminalSession::~TerminalSession()
{
    stop();
}

void TerminalSession::setHost(const QString &host)
{
    if (m_host == host)
        return;
    m_host = host;
    emit configChanged();
}

void TerminalSession::setUser(const QString &user)
{
    if (m_user == user)
        return;
    m_user = user;
    emit configChanged();
}

void TerminalSession::setPort(int port)
{
    if (m_port == port)
        return;
    m_port = port;
    emit configChanged();
}

void TerminalSession::setAuthMethod(const QString &method)
{
    if (m_authMethod == method)
        return;
    m_authMethod = method;
    emit configChanged();
}

void TerminalSession::setKeyPath(const QString &path)
{
    if (m_keyPath == path)
        return;
    m_keyPath = path;
    emit configChanged();
}

void TerminalSession::setPassword(const QString &password)
{
    if (m_password == password)
        return;
    m_password = password;
    emit configChanged();
}

void TerminalSession::setTheme(const QVariantMap &theme)
{
    if (m_theme == theme)
        return;
    m_theme = theme;
    emit themeChanged();
}

void TerminalSession::attach(int cols, int rows)
{
    m_cols = qMax(2, cols);
    m_rows = qMax(1, rows);
    if (running())
        resize(m_cols, m_rows);
    else
        start();
}

void TerminalSession::restart()
{
    stop();
    start();
}

#ifdef Q_OS_UNIX

void TerminalSession::start()
{
    if (running())
        return;

    winsize size{};
    size.ws_col = static_cast<unsigned short>(m_cols);
    size.ws_row = static_cast<unsigned short>(m_rows);

    // Prepared before forking: only async-signal-safe calls belong in the child.
    QByteArray target = m_host.trimmed().toUtf8();
    if (!m_user.trimmed().isEmpty())
        target = m_user.trimmed().toUtf8() + '@' + target;
    const QByteArray port = QByteArray::number(m_port > 0 ? m_port : 22);
    QList<QByteArray> args{"ssh", "-tt", "-o", "ServerAliveInterval=30", "-p", port};
    QString keyPath = m_keyPath.trimmed();
    if (keyPath.startsWith(QStringLiteral("~/")))
        keyPath = QDir::homePath() + keyPath.mid(1);
    const bool useKey = m_authMethod == QStringLiteral("key") && !keyPath.isEmpty();
    const bool usePassword = m_authMethod == QStringLiteral("password");
    if (useKey)
        args << "-i" << keyPath.toUtf8() << "-o" << "IdentitiesOnly=yes";
    if (usePassword)
        args << "-o" << "PreferredAuthentications=password,keyboard-interactive"
             << "-o" << "PubkeyAuthentication=no" << "-o" << "NumberOfPasswordPrompts=1";
    args << target;
    QList<char *> argv;
    for (auto &arg : args)
        argv.append(arg.data());
    argv.append(nullptr);
    // The password is handed to ssh through SSH_ASKPASS: this very executable,
    // run with --askpass, prints it (see main.cpp).
    const QByteArray askpass = QCoreApplication::applicationFilePath().toUtf8();
    const QByteArray password = m_password.toUtf8();

    int master = -1;
    const pid_t pid = forkpty(&master, nullptr, nullptr, &size);
    if (pid < 0) {
        emit output(QString::fromUtf8(QByteArray("\r\n[silo] cannot allocate a terminal\r\n").toBase64()));
        return;
    }

    if (pid == 0) {
        // Child: become the ssh client (or a local shell when no host is set).
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        signal(SIGINT, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        if (m_host.trimmed().isEmpty()) {
            const char *shell = getenv("SHELL");
            if (!shell || !*shell)
                shell = "/bin/sh";
            execlp(shell, shell, "-l", static_cast<char *>(nullptr));
        } else {
            if (usePassword) {
                setenv("SILO_SSH_PASSWORD", password.constData(), 1);
                setenv("SSH_ASKPASS", askpass.constData(), 1);
                setenv("SSH_ASKPASS_REQUIRE", "force", 1);
                if (!getenv("DISPLAY"))
                    setenv("DISPLAY", ":0", 1);
            }
            execvp("ssh", argv.data());
        }
        _exit(127);
    }

    m_master = master;
    m_pid = pid;
    m_notifier = new QSocketNotifier(m_master, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &TerminalSession::readAvailable);
    emit runningChanged();
}

void TerminalSession::readAvailable()
{
    char buffer[16384];
    const ssize_t n = ::read(m_master, buffer, sizeof buffer);
    if (n > 0) {
        emit output(QString::fromLatin1(QByteArray(buffer, int(n)).toBase64()));
        return;
    }
    if (n < 0 && (errno == EAGAIN || errno == EINTR))
        return;

    // EOF / EIO: the process is gone.
    int status = 0;
    int code = -1;
    if (m_pid > 0 && waitpid(pid_t(m_pid), &status, WNOHANG) > 0)
        code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    closePty();
    emit output(QString::fromLatin1(
        QByteArray("\r\n\x1b[90m[silo] session closed").append(code >= 0 ? " (exit " + QByteArray::number(code) + ")" : "")
            .append("\x1b[0m\r\n").toBase64()));
    emit finished(code);
    emit runningChanged();
}

void TerminalSession::write(const QString &data)
{
    if (m_master < 0)
        return;
    const QByteArray bytes = data.toUtf8();
    qint64 written = 0;
    while (written < bytes.size()) {
        const ssize_t n = ::write(m_master, bytes.constData() + written, size_t(bytes.size() - written));
        if (n <= 0)
            break;
        written += n;
    }
}

void TerminalSession::resize(int cols, int rows)
{
    m_cols = qMax(2, cols);
    m_rows = qMax(1, rows);
    if (m_master < 0)
        return;
    winsize size{};
    size.ws_col = static_cast<unsigned short>(m_cols);
    size.ws_row = static_cast<unsigned short>(m_rows);
    ioctl(m_master, TIOCSWINSZ, &size);
}

void TerminalSession::stop()
{
    if (m_pid > 0) {
        kill(pid_t(m_pid), SIGHUP);
        int status = 0;
        waitpid(pid_t(m_pid), &status, WNOHANG);
    }
    const bool wasRunning = running();
    closePty();
    if (wasRunning)
        emit runningChanged();
}

void TerminalSession::closePty()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_master >= 0) {
        ::close(m_master);
        m_master = -1;
    }
    m_pid = -1;
}

#else // Windows: ConPTY not wired yet.

void TerminalSession::start()
{
    emit output(QString::fromLatin1(
        QByteArray("\r\n[silo] terminals are not available on this platform yet\r\n").toBase64()));
}
void TerminalSession::readAvailable() {}
void TerminalSession::write(const QString &) {}
void TerminalSession::resize(int cols, int rows) { m_cols = cols; m_rows = rows; }
void TerminalSession::stop() {}
void TerminalSession::closePty() {}

#endif
