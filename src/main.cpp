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
#include <QTimer>
#include <QtWebEngineQuick/QtWebEngineQuick>

#include "AppStore.h"
#include "CsvModel.h"
#include "FaviconProvider.h"
#include "FileInspector.h"
#include "IconProvider.h"
#include "SessionStore.h"
#include "TabsModel.h"
#include "TerminalSession.h"
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
    QIcon applicationIcon;
    applicationIcon.addFile(QStringLiteral(":/app/logo-64.png"));
    applicationIcon.addFile(QStringLiteral(":/app/logo-512.png"));
    QGuiApplication::setWindowIcon(applicationIcon);

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    qmlRegisterType<TerminalSession>("Silo.Backend", 1, 0, "TerminalSession");
    qmlRegisterType<CsvModel>("Silo.Backend", 1, 0, "CsvModel");

    ThemeController themeController;
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
    engine.rootContext()->setContextProperty(QStringLiteral("tabsHub"), &tabsHub);
    engine.rootContext()->setContextProperty(QStringLiteral("files"), &fileInspector);
    engine.rootContext()->setContextProperty(QStringLiteral("sessionStore"), &sessionStore);
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
