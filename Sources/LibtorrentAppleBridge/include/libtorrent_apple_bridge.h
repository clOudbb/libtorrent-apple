#ifndef LIBTORRENT_APPLE_NATIVE_BRIDGE_H
#define LIBTORRENT_APPLE_NATIVE_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE 41
#define LIBTORRENT_APPLE_STATE_NAME_SIZE 64
#define LIBTORRENT_APPLE_TORRENT_NAME_SIZE 256
#define LIBTORRENT_APPLE_USER_AGENT_SIZE 160
#define LIBTORRENT_APPLE_HANDSHAKE_CLIENT_VERSION_SIZE 96
#define LIBTORRENT_APPLE_LISTEN_INTERFACES_SIZE 256
#define LIBTORRENT_APPLE_ALERT_NAME_SIZE 96
#define LIBTORRENT_APPLE_ALERT_MESSAGE_SIZE 512
#define LIBTORRENT_APPLE_TORRENT_FILE_NAME_SIZE 256
#define LIBTORRENT_APPLE_TORRENT_FILE_PATH_SIZE 768
#define LIBTORRENT_APPLE_TORRENT_TRACKER_URL_SIZE 512
#define LIBTORRENT_APPLE_TORRENT_TRACKER_MESSAGE_SIZE 256
#define LIBTORRENT_APPLE_TORRENT_PEER_CLIENT_SIZE 160
#define LIBTORRENT_APPLE_TORRENT_PEER_ENDPOINT_SIZE 128
#define LIBTORRENT_APPLE_PROXY_HOSTNAME_SIZE 256
#define LIBTORRENT_APPLE_PROXY_USERNAME_SIZE 128
#define LIBTORRENT_APPLE_PROXY_PASSWORD_SIZE 128
#define LIBTORRENT_APPLE_ERROR_MESSAGE_SIZE 512
#define LIBTORRENT_APPLE_DEFAULT_ALERT_MASK 65

typedef struct libtorrent_apple_session libtorrent_apple_session_t;

typedef struct {
    int32_t code;
    char message[LIBTORRENT_APPLE_ERROR_MESSAGE_SIZE];
} libtorrent_apple_error_t;

typedef struct {
    int32_t listen_port;
    int32_t alert_mask;
    int32_t upload_rate_limit;
    int32_t download_rate_limit;
    int32_t connections_limit;
    int32_t active_downloads_limit;
    int32_t active_seeds_limit;
    int32_t active_checking_limit;
    int32_t active_dht_limit;
    int32_t active_tracker_limit;
    int32_t active_lsd_limit;
    int32_t active_limit;
    int32_t max_queued_disk_bytes;
    int32_t send_buffer_low_watermark;
    int32_t send_buffer_watermark;
    int32_t send_buffer_watermark_factor;
    int32_t proxy_type;
    int32_t proxy_port;
    int32_t out_enc_policy;
    int32_t in_enc_policy;
    int32_t allowed_enc_level;
    bool enable_dht;
    bool enable_lsd;
    bool enable_upnp;
    bool enable_natpmp;
    bool prefer_rc4;
    bool proxy_hostnames;
    bool proxy_peer_connections;
    bool proxy_tracker_connections;
    bool auto_sequential;
    char user_agent[LIBTORRENT_APPLE_USER_AGENT_SIZE];
    char handshake_client_version[LIBTORRENT_APPLE_HANDSHAKE_CLIENT_VERSION_SIZE];
    char listen_interfaces[LIBTORRENT_APPLE_LISTEN_INTERFACES_SIZE];
    char proxy_hostname[LIBTORRENT_APPLE_PROXY_HOSTNAME_SIZE];
    char proxy_username[LIBTORRENT_APPLE_PROXY_USERNAME_SIZE];
    char proxy_password[LIBTORRENT_APPLE_PROXY_PASSWORD_SIZE];
} libtorrent_apple_session_configuration_t;

typedef struct {
    bool valid;
    bool paused;
    double progress;
    int32_t state_code;
    int32_t download_rate;
    int32_t upload_rate;
    int32_t num_peers;
    int32_t num_seeds;
    int64_t total_download;
    int64_t total_upload;
    int64_t total_size;
    char info_hash[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE];
    char state[LIBTORRENT_APPLE_STATE_NAME_SIZE];
    char name[LIBTORRENT_APPLE_TORRENT_NAME_SIZE];
    char error_message[LIBTORRENT_APPLE_ERROR_MESSAGE_SIZE];
} libtorrent_apple_torrent_status_t;

typedef struct {
    bool has_alert;
    int32_t type_code;
    char info_hash[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE];
    char name[LIBTORRENT_APPLE_ALERT_NAME_SIZE];
    char message[LIBTORRENT_APPLE_ALERT_MESSAGE_SIZE];
} libtorrent_apple_alert_t;

typedef struct {
    uint8_t *data;
    size_t size;
} libtorrent_apple_byte_buffer_t;

typedef struct {
    int32_t index;
    int32_t priority;
    bool wanted;
    int64_t size;
    int64_t downloaded;
    char name[LIBTORRENT_APPLE_TORRENT_FILE_NAME_SIZE];
    char path[LIBTORRENT_APPLE_TORRENT_FILE_PATH_SIZE];
} libtorrent_apple_torrent_file_t;

typedef struct {
    int32_t tier;
    int32_t fail_count;
    int32_t source_mask;
    bool verified;
    char url[LIBTORRENT_APPLE_TORRENT_TRACKER_URL_SIZE];
    char message[LIBTORRENT_APPLE_TORRENT_TRACKER_MESSAGE_SIZE];
} libtorrent_apple_torrent_tracker_t;

typedef struct {
    int32_t tier;
    char url[LIBTORRENT_APPLE_TORRENT_TRACKER_URL_SIZE];
} libtorrent_apple_torrent_tracker_update_t;

typedef struct {
    int32_t flags;
    int32_t source_mask;
    int32_t download_rate;
    int32_t upload_rate;
    int32_t queue_bytes;
    int64_t total_download;
    int64_t total_upload;
    double progress;
    bool is_seed;
    char endpoint[LIBTORRENT_APPLE_TORRENT_PEER_ENDPOINT_SIZE];
    char client[LIBTORRENT_APPLE_TORRENT_PEER_CLIENT_SIZE];
} libtorrent_apple_torrent_peer_t;

typedef struct {
    int32_t index;
    int32_t priority;
    int32_t availability;
    bool downloaded;
} libtorrent_apple_torrent_piece_t;

const char *libtorrent_apple_bridge_version(void);
bool libtorrent_apple_bridge_is_available(void);

libtorrent_apple_session_configuration_t libtorrent_apple_session_configuration_default(void);

bool libtorrent_apple_session_create(
    const libtorrent_apple_session_configuration_t *configuration,
    libtorrent_apple_session_t **session_out,
    libtorrent_apple_error_t *error_out
);

void libtorrent_apple_session_destroy(libtorrent_apple_session_t *session);

bool libtorrent_apple_session_add_magnet(
    libtorrent_apple_session_t *session,
    const char *magnet_uri,
    const char *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_add_torrent_file(
    libtorrent_apple_session_t *session,
    const char *torrent_file_path,
    const char *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_add_resume_data(
    libtorrent_apple_session_t *session,
    const uint8_t *resume_data,
    size_t resume_data_size,
    const char *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_pause_torrent(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_resume_torrent(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_remove_torrent(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    bool remove_data,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_get_torrent_status(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_torrent_status_t *status_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_session_pop_alert(
    libtorrent_apple_session_t *session,
    libtorrent_apple_alert_t *alert_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_export_resume_data(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_byte_buffer_t *buffer_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_export_torrent_file(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_byte_buffer_t *buffer_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_file_count(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_get_files(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_torrent_file_t *files_out,
    size_t files_capacity,
    size_t *files_count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_set_file_priority(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    int32_t file_index,
    int32_t priority,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_set_sequential_download(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    bool enabled,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_force_recheck(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_force_reannounce(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    int32_t seconds,
    int32_t tracker_index,
    bool ignore_min_interval,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_move_storage(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    const char *download_path,
    int32_t move_flags,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_piece_count(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_get_piece_priorities(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    uint8_t *priorities_out,
    size_t priorities_capacity,
    size_t *priorities_count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_set_piece_priority(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    int32_t piece_index,
    int32_t priority,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_set_piece_deadline(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    int32_t piece_index,
    int32_t deadline_milliseconds,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_reset_piece_deadline(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    int32_t piece_index,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_tracker_count(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_get_trackers(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_torrent_tracker_t *trackers_out,
    size_t trackers_capacity,
    size_t *trackers_count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_replace_trackers(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    const libtorrent_apple_torrent_tracker_update_t *trackers,
    size_t tracker_count,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_add_tracker(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    const libtorrent_apple_torrent_tracker_update_t *tracker,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_peer_count(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_get_peers(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_torrent_peer_t *peers_out,
    size_t peers_capacity,
    size_t *peers_count_out,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_torrent_get_pieces(
    libtorrent_apple_session_t *session,
    const char *info_hash_hex,
    libtorrent_apple_torrent_piece_t *pieces_out,
    size_t pieces_capacity,
    size_t *pieces_count_out,
    libtorrent_apple_error_t *error_out
);

void libtorrent_apple_byte_buffer_free(libtorrent_apple_byte_buffer_t *buffer);

#ifdef __cplusplus
}
#endif

#endif
