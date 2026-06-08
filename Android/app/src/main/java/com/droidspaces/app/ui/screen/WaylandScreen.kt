package com.droidspaces.app.ui.screen

import android.os.SystemClock
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.droidspaces.app.wayland.WaylandDisplayView
import com.droidspaces.app.wayland.WaylandManager
import com.droidspaces.app.wayland.WaylandSurface

/**
 * Fullscreen Wayland compositor display.
 *
 * Design: matches ContainerTerminalScreen — surfaceContainerLow TopAppBar,
 * back pops without stopping the compositor.
 *
 * Bottom toolbar provides: fullscreen toggle, software keyboard toggle,
 * ESC / TAB / CTRL / ALT, and arrow keys — all routed via nativeOnKeyEvent.
 *
 * Fullscreen: hides the TopAppBar so the compositor fills the display.
 * Back in fullscreen exits fullscreen first, then navigates back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WaylandScreen(onNavigateBack: () -> Unit) {
    val isRunning     = WaylandManager.isRunning
    var isFullscreen  by remember { mutableStateOf(false) }

    BackHandler {
        if (isFullscreen) isFullscreen = false else onNavigateBack()
    }

    Column(modifier = Modifier.fillMaxSize()) {

        // ── TopAppBar (hidden in fullscreen) ────────────────────────────────
        AnimatedVisibility(
            visible = !isFullscreen,
            enter   = expandVertically(),
            exit    = shrinkVertically(),
        ) {
            Column {
                TopAppBar(
                    title = {
                        Text(
                            "Wayland Display",
                            style    = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onNavigateBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                        }
                    },
                    actions = {
                        val chipColor = if (isRunning) MaterialTheme.colorScheme.primaryContainer
                                        else          MaterialTheme.colorScheme.errorContainer
                        val textColor = if (isRunning) MaterialTheme.colorScheme.onPrimaryContainer
                                        else          MaterialTheme.colorScheme.onErrorContainer
                        Surface(
                            shape    = MaterialTheme.shapes.small,
                            color    = chipColor,
                            modifier = Modifier.padding(end = 12.dp),
                        ) {
                            Text(
                                if (isRunning) "Live" else "Stopped",
                                color      = textColor,
                                style      = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                modifier   = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                    ),
                )
                HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            }
        }

        // ── Display area ─────────────────────────────────────────────────────
        Box(
            modifier          = Modifier.fillMaxWidth().weight(1f).background(MaterialTheme.colorScheme.surface),
            contentAlignment  = Alignment.Center,
        ) {
            if (isRunning) {
                WaylandDisplayView(modifier = Modifier.fillMaxSize())
            } else {
                CompositorOffPlaceholder(onNavigateBack)
            }
        }

        // ── Bottom toolbar ───────────────────────────────────────────────────
        if (isRunning) {
            WaylandKeyboardBar(
                isFullscreen       = isFullscreen,
                onFullscreenToggle = { isFullscreen = !isFullscreen },
            )
        }
    }
}

// ── Bottom keyboard bar ──────────────────────────────────────────────────────

@Composable
private fun WaylandKeyboardBar(
    isFullscreen: Boolean,
    onFullscreenToggle: () -> Unit,
) {
    Surface(
        color         = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp,
    ) {
        Column {
            HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom))
                    .height(52.dp)
                    .padding(horizontal = 4.dp),
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                // Fullscreen
                WlIconKey(
                    icon    = if (isFullscreen) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                    desc    = if (isFullscreen) "Exit fullscreen" else "Fullscreen",
                    onClick = onFullscreenToggle,
                )

                VerticalDivider(modifier = Modifier.height(26.dp), color = MaterialTheme.colorScheme.outlineVariant)

                // Special keys
                WlTextKey("ESC",  KeyEvent.KEYCODE_ESCAPE)
                WlTextKey("TAB",  KeyEvent.KEYCODE_TAB)
                WlTextKey("CTRL", KeyEvent.KEYCODE_CTRL_LEFT)
                WlTextKey("ALT",  KeyEvent.KEYCODE_ALT_LEFT)
                WlTextKey("SUP",  KeyEvent.KEYCODE_META_LEFT)

                VerticalDivider(modifier = Modifier.height(26.dp), color = MaterialTheme.colorScheme.outlineVariant)

                // Arrow keys
                WlIconKey(Icons.Default.KeyboardArrowUp,    "↑", keyCode = KeyEvent.KEYCODE_DPAD_UP)
                WlIconKey(Icons.Default.KeyboardArrowDown,  "↓", keyCode = KeyEvent.KEYCODE_DPAD_DOWN)
                WlIconKey(Icons.Default.KeyboardArrowLeft,  "←", keyCode = KeyEvent.KEYCODE_DPAD_LEFT)
                WlIconKey(Icons.Default.KeyboardArrowRight, "→", keyCode = KeyEvent.KEYCODE_DPAD_RIGHT)
            }
        }
    }
}

@Composable
private fun RowScope.WlTextKey(label: String, keyCode: Int) {
    TextButton(
        onClick         = { sendKey(keyCode) },
        modifier        = Modifier.weight(1f).fillMaxHeight(),
        shape           = RoundedCornerShape(8.dp),
        contentPadding  = PaddingValues(0.dp),
    ) {
        Text(
            label,
            fontSize   = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color      = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines   = 1,
        )
    }
}

@Composable
private fun RowScope.WlIconKey(
    icon: ImageVector,
    desc: String,
    keyCode: Int? = null,
    onClick: (() -> Unit)? = null,
) {
    IconButton(
        onClick  = onClick ?: { if (keyCode != null) sendKey(keyCode) },
        modifier = Modifier.weight(1f).fillMaxHeight(),
    ) {
        Icon(icon, desc, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun sendKey(keyCode: Int) {
    val t = (SystemClock.uptimeMillis() and 0x7FFF_FFFFL).toInt()
    WaylandSurface.nativeOnKeyEvent(keyCode, true,  t)
    WaylandSurface.nativeOnKeyEvent(keyCode, false, t + 1)
}

// ── Compositor-off placeholder ───────────────────────────────────────────────

@Composable
private fun CompositorOffPlaceholder(onNavigateBack: () -> Unit) {
    Column(
        horizontalAlignment   = Alignment.CenterHorizontally,
        verticalArrangement   = Arrangement.spacedBy(16.dp),
        modifier              = Modifier.padding(32.dp),
    ) {
        Icon(
            Icons.Default.DesktopWindows,
            null,
            modifier = Modifier.size(48.dp),
            tint     = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
        Text("Wayland compositor is not running", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(
            "Enable it in Settings → Wayland Compositor, then come back here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = onNavigateBack, shape = MaterialTheme.shapes.medium) {
            Text("Go Back", fontWeight = FontWeight.SemiBold)
        }
    }
}
