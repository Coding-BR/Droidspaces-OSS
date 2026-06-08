/*
 * Droidspaces - Wayland compositor JNI bridge
 *
 * Headless entry point into the trierarch compositor for Droidspaces.
 * Only three functions: start, stop, isRunning.
 *
 * No render thread, no ANativeWindow, no EGL surface — the compositor
 * creates the Wayland socket and dispatches protocol messages on its own
 * internal event loop.  The container's own display manager (Sway, KDE,
 * etc.) is the rendering client.
 *
 * JNI class: com.droidspaces.app.wayland.WaylandManager
 *
 * Copyright (C) 2026 ravindu644 <droidcasts@protonmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <stdlib.h>
#include "compositor.h"

#define TAG "DroidspacesWayland"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* Global compositor instance — one per app process. */
static wayland_server_t *g_server = NULL;
static pthread_mutex_t   g_lock   = PTHREAD_MUTEX_INITIALIZER;

/* ---- dispatch thread ------------------------------------------------------ */

/*
 * Drives the Wayland event loop.  libwayland-server is not thread-safe for
 * send operations but wl_event_loop_dispatch() is safe to call from a
 * dedicated thread as long as nothing else calls it concurrently.
 */
static volatile int g_dispatch_running = 0;
static pthread_t    g_dispatch_thread;

static void *dispatch_loop(void *arg) {
    (void)arg;
    LOGI("dispatch thread started");
    while (g_dispatch_running) {
        pthread_mutex_lock(&g_lock);
        wayland_server_t *srv = g_server;
        pthread_mutex_unlock(&g_lock);

        if (!srv) break;
        compositor_dispatch_timeout(srv, 16); /* ~60 Hz */
    }
    LOGI("dispatch thread exiting");
    return NULL;
}

/* ---- JNI exports ---------------------------------------------------------- */

JNIEXPORT void JNICALL
Java_com_droidspaces_app_wayland_WaylandManager_nativeStart(
        JNIEnv *env, jobject thiz,
        jstring j_runtime_dir, jstring j_socket_name)
{
    (void)thiz;

    pthread_mutex_lock(&g_lock);
    if (g_server) {
        /* Already running — idempotent. */
        pthread_mutex_unlock(&g_lock);
        LOGI("compositor already running, ignoring start");
        return;
    }

    const char *runtime_dir  = (*env)->GetStringUTFChars(env, j_runtime_dir,  NULL);
    const char *socket_name  = (*env)->GetStringUTFChars(env, j_socket_name,  NULL);

    if (!runtime_dir || !socket_name) {
        if (runtime_dir) (*env)->ReleaseStringUTFChars(env, j_runtime_dir, runtime_dir);
        if (socket_name) (*env)->ReleaseStringUTFChars(env, j_socket_name, socket_name);
        pthread_mutex_unlock(&g_lock);
        LOGE("null runtime_dir or socket_name");
        return;
    }

    LOGI("starting compositor: runtime_dir=%s socket=%s", runtime_dir, socket_name);
    g_server = compositor_create_named(runtime_dir, socket_name);

    (*env)->ReleaseStringUTFChars(env, j_runtime_dir, runtime_dir);
    (*env)->ReleaseStringUTFChars(env, j_socket_name, socket_name);

    if (!g_server) {
        pthread_mutex_unlock(&g_lock);
        LOGE("compositor_create_named failed");
        return;
    }

    /* Start the dispatch thread. */
    g_dispatch_running = 1;
    if (pthread_create(&g_dispatch_thread, NULL, dispatch_loop, NULL) != 0) {
        LOGE("failed to create dispatch thread");
        compositor_destroy(g_server);
        g_server = NULL;
        g_dispatch_running = 0;
        pthread_mutex_unlock(&g_lock);
        return;
    }

    pthread_mutex_unlock(&g_lock);
    LOGI("compositor started");
}

JNIEXPORT void JNICALL
Java_com_droidspaces_app_wayland_WaylandManager_nativeStop(
        JNIEnv *env, jobject thiz)
{
    (void)env;
    (void)thiz;

    pthread_mutex_lock(&g_lock);
    if (!g_server) {
        pthread_mutex_unlock(&g_lock);
        return;
    }
    g_dispatch_running = 0;
    wayland_server_t *srv = g_server;
    g_server = NULL;
    pthread_mutex_unlock(&g_lock);

    pthread_join(g_dispatch_thread, NULL);
    compositor_destroy(srv);
    LOGI("compositor stopped");
}

JNIEXPORT jboolean JNICALL
Java_com_droidspaces_app_wayland_WaylandManager_nativeIsRunning(
        JNIEnv *env, jobject thiz)
{
    (void)env;
    (void)thiz;
    pthread_mutex_lock(&g_lock);
    jboolean running = (g_server != NULL) ? JNI_TRUE : JNI_FALSE;
    pthread_mutex_unlock(&g_lock);
    return running;
}
