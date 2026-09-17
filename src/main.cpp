#include <QGuiApplication>
#include <QIcon>
#include <cstdio>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QKeySequence>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExpression>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSysInfo>
#include <QTimer>
#include <QVariantMap>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QtWebEngineQuick>

#ifdef Q_OS_UNIX
#include <QSocketNotifier>
#include <csignal>
#include <unistd.h>
#endif

#ifndef SILO_VERSION_STRING
#define SILO_VERSION_STRING "0.0.0"
#endif
#ifndef SILO_GIT_SHA
#define SILO_GIT_SHA ""
#endif

#ifdef Q_OS_UNIX
// Ctrl+C in the terminal that launched Silo (`make run`), `kill`, or a closing
// terminal must go through the normal Qt shutdown: Chromium writes cookies and
// site storage in batches and only flushes the rest when the profile is torn
// down, so dying on the signal loses the last minutes of logins. The handler
// just writes a byte; the event loop picks it up and quits cleanly.
namespace {
int signalPipe[2] = {-1, -1};

void onQuitSignal(int)
{
    const char byte = 1;
    (void)!::write(signalPipe[1], &byte, 1);
}

void installQuitSignals(QObject *parent)
{
    if (::pipe(signalPipe) != 0)
        return;
    auto *notifier = new QSocketNotifier(signalPipe[0], QSocketNotifier::Read, parent);
    QObject::connect(notifier, &QSocketNotifier::activated, parent, [notifier] {
        char byte;
        (void)!::read(signalPipe[0], &byte, 1);
        notifier->setEnabled(false);
        QCoreApplication::quit();
    });
    struct sigaction action {};
    action.sa_handler = onQuitSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    for (int signal : {SIGINT, SIGTERM, SIGHUP})
        sigaction(signal, &action, nullptr);
}
} // namespace
#endif

#include "AppStore.h"
#include "CsvModel.h"
#include "FaviconProvider.h"
#include "FileInspector.h"
#include "IconProvider.h"
#include "SessionStore.h"
#include "TabsModel.h"
#include "TerminalSession.h"
#include "PasswordManager.h"
#include "Vault.h"
#include "ThemeController.h"

// SSH_ASKPASS helper used by TerminalSession for password logins: ssh runs
// `Silo --askpass "<prompt>"` and reads our stdout. Host-key confirmations are
// answered "yes", everything else gets the password passed through the environment.
static int runAskpass(int argc, char *argv[])
{
    const QByteArray prompt = argc >= 3 ? QByteArray(argv[2]) : QByteArray();
    const QByteArray answer = prompt.contains("(yes/no") ? QByteArray("yes") : qgetenv("SILO_SSH_PASSWORD");
    fwrite(answer.constData(), 1, size_t(answer.size()), stdout);
    fputc('\n', stdout);
    fflush(stdout);
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc >= 2 && qstrcmp(argv[1], "--askpass") == 0)
        return runAskpass(argc, argv);

    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Silo"));
    QGuiApplication::setOrganizationName(QStringLiteral("Silo"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("silo.app"));
    QGuiApplication::setApplicationVersion(QStringLiteral(SILO_VERSION_STRING));
    QIcon applicationIcon;
    applicationIcon.addFile(QStringLiteral(":/app/logo-64.png"));
    applicationIcon.addFile(QStringLiteral(":/app/logo-512.png"));
    QGuiApplication::setWindowIcon(applicationIcon);
#ifdef Q_OS_UNIX
    installQuitSignals(&app);
#endif

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    qmlRegisterType<TerminalSession>("Silo.Backend", 1, 0, "TerminalSession");
    qmlRegisterType<CsvModel>("Silo.Backend", 1, 0, "CsvModel");

    ThemeController themeController;
    PasswordManager passwordManager;
    Vault vault;
    AppStore store;
    SessionStore sessionStore;
    TabsHub tabsHub(&store, &sessionStore);
    FaviconFetcher faviconFetcher;
    FileInspector fileInspector;
    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine.addImageProvider(QStringLiteral("siteicon"), new FaviconProvider(&faviconFetcher));
    engine.rootContext()->setContextProperty(QStringLiteral("appStore"), &store);
    engine.rootContext()->setContextProperty(QStringLiteral("themeController"), &themeController);
    engine.rootContext()->setContextProperty(QStringLiteral("passwords"), &passwordManager);
    engine.rootContext()->setContextProperty(QStringLiteral("vault"), &vault);
    engine.rootContext()->setContextProperty(QStringLiteral("tabsHub"), &tabsHub);
    engine.rootContext()->setContextProperty(QStringLiteral("files"), &fileInspector);
    engine.rootContext()->setContextProperty(QStringLiteral("sessionStore"), &sessionStore);
    // Read-only facts for Settings > About.
    const QVariantMap appInfo{
        {QStringLiteral("version"), QGuiApplication::applicationVersion()},
        {QStringLiteral("commit"), QStringLiteral(SILO_GIT_SHA)},
        {QStringLiteral("qtVersion"), QString::fromLatin1(qVersion())},
        {QStringLiteral("chromiumVersion"), QString::fromLatin1(qWebEngineChromiumVersion())},
        {QStringLiteral("os"), QSysInfo::prettyProductName()},
        {QStringLiteral("arch"), QSysInfo::currentCpuArchitecture()},
        {QStringLiteral("repository"), QStringLiteral("https://github.com/jr-k/silo")},
    };
    engine.rootContext()->setContextProperty(QStringLiteral("appInfo"), appInfo);
    engine.loadFromModule(QStringLiteral("Silo"), QStringLiteral("Main"));

    if (engine.rootObjects().isEmpty())
        return -1;

    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());

    // Dev aid: SILO_DEBUG_EVAL="<js>" runs in Main.qml's context shortly after startup.
    const QByteArray debugEval = qgetenv("SILO_DEBUG_EVAL");
    if (!debugEval.isEmpty() && window) {
        QTimer::singleShot(600, window, [window, debugEval] {
            QQmlExpression expression(qmlContext(window), window, QString::fromUtf8(debugEval));
            expression.evaluate();
            if (expression.hasError())
                qWarning() << "SILO_DEBUG_EVAL:" << expression.error().toString();
        });
    }

    // Dev aid: SILO_DEBUG_KEYS="Return,Escape,a" sends real key presses to the
    // focused item after SILO_DEBUG_EVAL ran (one key per comma-separated token),
    // SILO_DEBUG_KEYS_DELAY ms after startup (default 1000).
    const QByteArray debugKeys = qgetenv("SILO_DEBUG_KEYS");
    if (!debugKeys.isEmpty() && window) {
        const int keysDelay = qMax(1000, qEnvironmentVariableIntValue("SILO_DEBUG_KEYS_DELAY"));
        QTimer::singleShot(keysDelay, window, [window, debugKeys] {
            for (const QByteArray &token : debugKeys.split(',')) {
                const QString name = QString::fromUtf8(token.trimmed());
                if (name.isEmpty())
                    continue;
                const QKeySequence sequence(name);
                const int key = sequence.isEmpty() ? name.at(0).unicode() : sequence[0].key();
                const QString text = name.length() == 1 ? name : QString();
                QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, text);
                QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, text);
                QCoreApplication::sendEvent(window, &press);
                QCoreApplication::sendEvent(window, &release);
            }
        });
    }

    // Dev aid: SILO_DEBUG_CLICK="x,y" sends a left click at window coordinates,
    // SILO_DEBUG_CLICK_DELAY ms after startup (default 1500).
    const QByteArray debugClick = qgetenv("SILO_DEBUG_CLICK");
    if (!debugClick.isEmpty() && window) {
        const int clickDelay = qMax(1000, qEnvironmentVariableIntValue("SILO_DEBUG_CLICK_DELAY"));
        QTimer::singleShot(clickDelay, window, [window, debugClick] {
            const QList<QByteArray> parts = debugClick.split(',');
            if (parts.size() != 2)
                return;
            const QPointF pos(parts[0].trimmed().toDouble(), parts[1].trimmed().toDouble());
            const QPointF global = window->mapToGlobal(pos);
            QMouseEvent press(QEvent::MouseButtonPress, pos, pos, global, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            QMouseEvent release(QEvent::MouseButtonRelease, pos, pos, global, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            QCoreApplication::sendEvent(window, &press);
            QCoreApplication::sendEvent(window, &release);
        });
    }

    // Dev aid: SILO_SCREENSHOT=/path/out.png grabs the main window and exits.
    const QByteArray screenshotPath = qgetenv("SILO_SCREENSHOT");
    if (!screenshotPath.isEmpty() && window) {
        const int delay = qMax(500, qEnvironmentVariableIntValue("SILO_SCREENSHOT_DELAY"));
        QTimer::singleShot(delay > 500 ? delay : 2200, window, [window, screenshotPath] {
            window->grabWindow().save(QString::fromUtf8(screenshotPath));
            QGuiApplication::quit();
        });
    }

    return app.exec();
}
