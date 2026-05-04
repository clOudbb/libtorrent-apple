#include "LibtorrentAppleBridge.h"

#include <dlfcn.h>
#include <stdio.h>

#ifndef LIBTORRENT_APPLE_HAS_SESSION_RUNTIME_SETTINGS
typedef bool (*libtorrent_apple_session_apply_runtime_settings_fn)(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
);

static void *bridge_compat_runtime_settings_symbol(void) {
    return dlsym(RTLD_DEFAULT, "libtorrent_apple_session_apply_runtime_settings");
}

static void bridge_compat_set_error(
    libtorrent_apple_error_t *error_out,
    int32_t code,
    const char *message
) {
    if (error_out == NULL) {
        return;
    }

    error_out->code = code;
    snprintf(error_out->message, sizeof(error_out->message), "%s", message);
}

bool libtorrent_apple_bridge_session_apply_runtime_settings(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
) {
    void *symbol = bridge_compat_runtime_settings_symbol();
    if (symbol != NULL) {
        libtorrent_apple_session_apply_runtime_settings_fn apply_runtime_settings =
            (libtorrent_apple_session_apply_runtime_settings_fn)symbol;
        return apply_runtime_settings(session, settings, error_out);
    }

    bridge_compat_set_error(
        error_out,
        -3,
        "runtime settings require a binary artifact that exports libtorrent_apple_session_apply_runtime_settings"
    );
    return false;
}

bool libtorrent_apple_bridge_supports_session_runtime_settings(void) {
    return bridge_compat_runtime_settings_symbol() != NULL;
}
#endif
