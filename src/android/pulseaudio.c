/*
 * Droidspaces v6 - PulseAudio Server and Socket Manager
 *
 * Manages the PulseAudio daemon lifecycle on Android (spawning, logging, and
 * stopping) and host-to-container socket bridging.
 *
 * Copyright (C) 2026 ravindu644 <droidcasts@protonmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define _GNU_SOURCE
#include "droidspace.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

/* ---- helpers ---------------------------------------------------------- */

#define PA_DEFAULT_PA TX11_PREFIX "/etc/pulse/default.pa"
#define PA_AAUDIO_LINE "load-module module-aaudio-sink"
#define PA_ALWAYS_LINE "load-module module-always-sink"
#define PA_SLES_LINE "load-module module-sles-sink"
#define PA_CK_LINE "load-module module-console-kit"

/*
 * Patch Termux's default.pa so module-aaudio-sink loads before
 * module-always-sink. Without this ordering, module-always-sink spawns a
 * null-sink fallback (seeing no real sink yet), then tries to async-unload it
 * via D-Bus once AAudio appears -- but there is no system bus on Android, so
 * the deferred unload wedges PulseAudio's mainloop permanently.
 *
 * Idempotent: if already patched, returns immediately.
 */
static void patch_default_pa(void) {
  FILE *f = fopen(PA_DEFAULT_PA, "r");
  if (!f) {
    ds_warn("[PulseAudio] cannot open %s for patching: %s", PA_DEFAULT_PA,
            strerror(errno));
    return;
  }

  /* Slurp the whole file */
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  rewind(f);
  char *buf = malloc((size_t)sz + 1);
  if (!buf) {
    fclose(f);
    return;
  }
  size_t rd = fread(buf, 1, (size_t)sz, f);
  fclose(f);
  buf[rd] = '\0';

  /* Check if already patched: aaudio line must appear before always-sink
   * and console-kit must be commented out. */
  char *pos_aaudio = strstr(buf, PA_AAUDIO_LINE);
  char *pos_always = strstr(buf, PA_ALWAYS_LINE);
  int ck_active = 0;
  char *p = buf;
  while ((p = strstr(p, PA_CK_LINE)) != NULL) {
    /* walk back to start of line to check for leading '#' */
    char *sol = p;
    while (sol > buf && *(sol - 1) != '\n')
      sol--;
    if (*sol != '#') {
      ck_active = 1;
      break;
    }
    p++;
  }

  if (pos_aaudio && pos_always && pos_aaudio < pos_always && !ck_active) {
    ds_log("[PulseAudio] default.pa already patched, skipping");
    free(buf);
    return;
  }

  ds_log("[PulseAudio] patching %s ...", PA_DEFAULT_PA);

  /* Write to a tmp file then rename atomically */
  char tmp[PATH_MAX];
  snprintf(tmp, sizeof(tmp), "%s.ds_tmp", PA_DEFAULT_PA);
  FILE *out = fopen(tmp, "w");
  if (!out) {
    ds_warn("[PulseAudio] cannot write tmp patch file: %s", strerror(errno));
    free(buf);
    return;
  }

  char *line = buf;
  int injected = 0;
  while (*line) {
    char *nl = strchr(line, '\n');
    size_t len = nl ? (size_t)(nl - line + 1) : strlen(line);

    /* Comment out module-sles-sink (broken on most Android devices) */
    if (strncmp(line, PA_SLES_LINE, strlen(PA_SLES_LINE)) == 0) {
      fputc('#', out);
      ds_log("[PulseAudio] commented out " PA_SLES_LINE);
    }

    /* Comment out module-console-kit: no D-Bus system bus on Android,
     * loading it blocks PA's mainloop on a futex waiting for a D-Bus reply
     * that never comes. */
    if (strncmp(line, PA_CK_LINE, strlen(PA_CK_LINE)) == 0) {
      fputc('#', out);
      ds_log("[PulseAudio] commented out " PA_CK_LINE);
    }

    /* Inject aaudio load just before always-sink */
    if (!injected &&
        strncmp(line, PA_ALWAYS_LINE, strlen(PA_ALWAYS_LINE)) == 0) {
      fprintf(out, PA_AAUDIO_LINE "\n");
      injected = 1;
      ds_log("[PulseAudio] injected " PA_AAUDIO_LINE " before " PA_ALWAYS_LINE);
    }

    fwrite(line, 1, len, out);
    line += len;
  }
  fclose(out);
  free(buf);

  if (rename(tmp, PA_DEFAULT_PA) != 0) {
    ds_warn("[PulseAudio] failed to rename patched file: %s", strerror(errno));
    unlink(tmp);
    return;
  }

  ds_log("[PulseAudio] default.pa patched successfully");
}

/*
 * Resolve the Termux UID from packages.list.
 * Returns the UID on success, -1 on failure.
 * PulseAudio needs to run as the Termux app UID so Android's audio HAL
 * grants it access to OpenSL ES / AAudio.
 */
static int pa_resolve_termux_uid(void) {
  int uid = ds_resolve_termux_uid();
  if (uid < 0)
    return -1;

  if (access(TX11_PULSE_BIN, F_OK) != 0) {
    ds_warn("PulseAudio: binary not found at %s. Is pulseaudio installed in "
            "Termux?",
            TX11_PULSE_BIN);
    return -1;
  }
  return uid;
}

/* ---- daemon child ----------------------------------------------------- */

struct pulse_args {
  int uid;
};

/*
 * Set up the forked child, perform the SELinux dance, and exec PulseAudio.
 * ready_fd: O_CLOEXEC write-end; EOF on execv success, byte on failure.
 * This function never returns on success.
 */
static void pulse_child_wrapper(int ready_fd, void *user_data) {
  struct pulse_args *args = (struct pulse_args *)user_data;

  /* Ignore hangups, keyboard interrupts, and broken pipes to keep the daemon
   * alive through terminal disconnects. SIGTERM is our shutdown signal. */
  signal(SIGHUP, SIG_IGN);
  signal(SIGINT, SIG_IGN);
  signal(SIGQUIT, SIG_IGN);
  signal(SIGPIPE, SIG_IGN);

  /* Make PulseAudio unkillable by the OOM killer.
   * Must be done while still root, before privilege drop. */
  ds_oom_protect();

  /* Set up the Termux environment before dropping privileges */
  setenv("TMPDIR", TX11_PREFIX "/tmp", 1);
  setenv("HOME", TX11_HOME, 1);
  setenv("PREFIX", TX11_PREFIX, 1);
  setenv("PULSE_SERVER", "unix:" TX11_PULSE_SOCKET, 1);

  /* Ensure the tmp directory exists (root creates it before priv drop) */
  mkdir_p(TX11_PREFIX "/tmp", 0755);

  /* Stay in droidspacesd (permissive) -- no domain transition needed.
   * untrusted_app_27 blocks execv of Termux binaries under enforcing. */
  ds_selinux_enter_domain();

  /* Drop root -> Termux UID. */
  if (ds_drop_privileges(args->uid) < 0) {
    perror("[PulseAudio] privilege drop failed");
    if (write(ready_fd, "\x01", 1) < 0) { /* ignore */
    }
    _exit(1);
  }

  fprintf(stdout, "[PulseAudio] uid=%d socket=%s\n", (int)getuid(),
          TX11_PULSE_SOCKET);
  fflush(stdout);

  /* Launch PulseAudio in non-daemon foreground mode.
   * - module-native-protocol-unix: UNIX socket at our custom path
   * - --exit-idle-time=-1: never exit on idle (we manage lifecycle ourselves)
   * - --daemonize=no: stay in foreground so our log relay captures all output
   * module-aaudio-sink is loaded by default.pa (patched at startup).
   */
  char *argv[] = {
      TX11_PULSE_BIN,
      "--load=module-native-protocol-unix socket=" TX11_PULSE_SOCKET
      " auth-anonymous=1",
      "--exit-idle-time=-1",
      "--daemonize=no",
      "--log-target=stderr",
      "--use-pid-file=false",
      "--disallow-exit",
      NULL,
  };

  execv(argv[0], argv);
  perror("[PulseAudio] execv");
  if (write(ready_fd, "\x01", 1) < 0) { /* ignore */
  }
  _exit(1);
}

/* ---- pactl post-start helper ------------------------------------------ */

/*
 * Run 'pactl set-default-sink AAudio_sink' once the socket is up.
 * Forked as a short-lived child; parent doesn't wait -- fire and forget.
 */
static void run_pactl_set_default(int uid) {
  pid_t p = fork();
  if (p < 0)
    return;
  if (p == 0) {
    /* Redirect to /dev/null -- we don't need pactl output in the log */
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
      close(devnull);
    }

    /* Stay in droidspacesd (permissive) */
    ds_selinux_enter_domain();
    if (ds_drop_privileges(uid) < 0) {
      _exit(1);
    }

    setenv("PULSE_SERVER", "unix:" TX11_PULSE_SOCKET, 1);
    setenv("HOME", TX11_HOME, 1);

    char *argv[] = {TX11_PACTL_BIN, "set-default-sink", TX11_PULSE_DEFAULT_SINK,
                    NULL};
    execv(TX11_PACTL_BIN, argv);
    _exit(1);
  }
  /* Parent: reap to avoid zombie. We don't care about exit code. */
  waitpid(p, NULL, 0);
}

/* ---- spawn ------------------------------------------------------------ */

static pid_t spawn_pulse(int uid) {
  struct pulse_args args = {.uid = uid};
  return ds_spawn_daemon(pulse_child_wrapper, &args, "pulse.log", "PulseAudio",
                         "PulseAudio");
}

/* ---- public API ------------------------------------------------------- */

int ds_pulse_daemon_start(struct ds_config *cfg) {
  if (!cfg || !cfg->pulseaudio || !is_android())
    return -1;
  if (getuid() != 0) {
    ds_error("[PulseAudio] not running as root");
    return -1;
  }

  /* Reuse existing global daemon if still alive */
  pid_t existing = ds_daemon_read_pid("pulse.ppid");
  if (existing > 0) {
    ds_log("PulseAudio: daemon already running (PID %d)", (int)existing);
    cfg->pulse_pid = existing;
    return 1;
  }

  int uid = pa_resolve_termux_uid();
  if (uid < 0)
    return -1;

  /* Clean up stale socket from a previous crashed run */
  unlink(TX11_PULSE_SOCKET);

  /* Ensure default.pa loads aaudio before always-sink to avoid null-sink wedge
   */
  patch_default_pa();
  ds_log("[PulseAudio] launching daemon (uid=%d)", uid);
  pid_t child = spawn_pulse(uid);
  if (child <= 0)
    return -1;

  cfg->pulse_pid = child;
  ds_daemon_write_pid("pulse.ppid", child);

  /* Wait for the UNIX socket to appear, then set the default sink.
   * If PA hasn't created the socket in 3s (or dies), pactl is skipped. */
  if (wait_for_socket_or_death(child, TX11_PULSE_SOCKET, 3000, 100000) == 0) {
    ds_log("[PulseAudio] socket appeared - setting default sink to %s",
           TX11_PULSE_DEFAULT_SINK);
    run_pactl_set_default(uid);
  } else {
    ds_warn("PulseAudio: socket did not appear in 3s - skipping pactl");
  }

  return 0;
}

void ds_pulse_daemon_stop(struct ds_config *cfg) {
  if (!cfg)
    return;
  ds_global_daemon_stop(check_pulse_needs, cfg->pulse_pid, &cfg->pulse_pid,
                        "pulse.ppid", TX11_PULSE_SOCKET, "[PulseAudio]");
}

/* ---- socket bridge ---------------------------------------------------- */

int ds_setup_pulse_socket(struct ds_config *cfg) {
  if (!is_android() || !cfg->pulseaudio)
    return 0;

  /* Post-pivot_root: host filesystem is under /.old_root.
   * TX11_PULSE_SOCKET lives in TX11_PREFIX/tmp, accessed via
   * DS_TERMUX_TMP_OLDROOT, exactly like the VirGL socket. */
  char src[PATH_MAX];
  snprintf(src, sizeof(src), "%s/.pulse-socket", DS_TERMUX_TMP_OLDROOT);

  struct stat st;
  if (stat(src, &st) != 0) {
    ds_warn("PulseAudio: socket not found at %s - skipping socket bridge", src);
    return 0;
  }

  uid_t uid = st.st_uid;

  if (ds_bind_mount_socket(src, DS_PULSE_SOCKET, uid, "PulseAudio") < 0)
    return 0;

  ds_log("PulseAudio: socket bind-mounted into container");

  /* Inject PULSE_SERVER so all processes inside the container find the daemon
   */
  setenv("PULSE_SERVER", "unix:" DS_PULSE_SOCKET, 1);

  return 0;
}
