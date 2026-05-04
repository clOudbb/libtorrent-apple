#ifndef LIBTORRENT_APPLE_BRIDGE_COMPAT_H
#define LIBTORRENT_APPLE_BRIDGE_COMPAT_H

#include <LibtorrentAppleBinary_0_2_10/LibtorrentAppleBinary.h>

#ifndef LIBTORRENT_APPLE_HAS_SESSION_RUNTIME_SETTINGS
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool has_upload_rate_limit;
    int32_t upload_rate_limit;
    bool has_download_rate_limit;
    int32_t download_rate_limit;
    bool has_connections_limit;
    int32_t connections_limit;
    bool has_active_downloads_limit;
    int32_t active_downloads_limit;
    bool has_active_seeds_limit;
    int32_t active_seeds_limit;
    bool has_active_checking_limit;
    int32_t active_checking_limit;
    bool has_active_dht_limit;
    int32_t active_dht_limit;
    bool has_active_tracker_limit;
    int32_t active_tracker_limit;
    bool has_active_lsd_limit;
    int32_t active_lsd_limit;
    bool has_active_limit;
    int32_t active_limit;
    bool has_connection_speed;
    int32_t connection_speed;
    bool has_torrent_connect_boost;
    int32_t torrent_connect_boost;
    bool has_mixed_mode_algorithm;
    int32_t mixed_mode_algorithm;
    bool has_rate_limit_ip_overhead;
    bool rate_limit_ip_overhead;
    bool has_allow_multiple_connections_per_ip;
    bool allow_multiple_connections_per_ip;
    bool has_enable_outgoing_tcp;
    bool enable_outgoing_tcp;
    bool has_enable_incoming_tcp;
    bool enable_incoming_tcp;
    bool has_enable_outgoing_utp;
    bool enable_outgoing_utp;
    bool has_enable_incoming_utp;
    bool enable_incoming_utp;
    bool has_auto_sequential;
    bool auto_sequential;
} libtorrent_apple_bridge_session_runtime_settings_t;

bool libtorrent_apple_bridge_session_apply_runtime_settings(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_bridge_supports_session_runtime_settings(void);

#ifdef __cplusplus
}
#endif
#endif

#endif
