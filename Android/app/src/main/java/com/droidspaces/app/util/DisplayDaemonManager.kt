package com.droidspaces.app.util

import com.topjohnwu.superuser.Shell

object DisplayDaemonManager {
    private const val SOCKET_PATH = "/data/local/tmp/display_daemon.sock"
    private const val DEFAULT_DAEMON = "/data/local/Droidspaces/bin/display_daemon"
    private const val PATCHED_DAEMON = "/data/local/tmp/display_daemon_patched"

    fun prepare() {
        stop()
        start()
        launchConsumer()
    }

    fun start() {
        val command = """
            rm -f $SOCKET_PATH
            daemon="$DEFAULT_DAEMON"
            if [ -x "$PATCHED_DAEMON" ]; then daemon="$PATCHED_DAEMON"; fi
            "${'$'}daemon" > /dev/null 2>&1 &
        """.trimIndent()
        Shell.cmd(command).exec()
    }

    fun launchConsumer() {
        Shell.cmd("am start -n com.anland.consumer/.MainActivity > /dev/null 2>&1 || true").exec()
    }

    fun startKde(containerName: String) {
        val quotedName = ContainerCommandBuilder.quote(containerName)
        val command = """
            ${Constants.DROIDSPACES_BINARY_PATH} --name=$quotedName run sh -lc 'if [ -x /opt/anland/startup.sh ]; then nohup bash /opt/anland/startup.sh >/tmp/anland-kde.log 2>&1 & elif [ -x /usr/local/bin/startanland-kde.sh ]; then nohup bash /usr/local/bin/startanland-kde.sh >/tmp/anland-kde.log 2>&1 & else exit 0; fi'
        """.trimIndent()
        Shell.cmd(command).exec()
        launchConsumer()
    }

    fun stop() {
        Shell.cmd("pkill -f display_daemon || true; rm -f $SOCKET_PATH").exec()
    }
}
