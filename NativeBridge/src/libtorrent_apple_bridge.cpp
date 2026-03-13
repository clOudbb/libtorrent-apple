#include "libtorrent_apple_bridge.h"

#include "libtorrent/add_torrent_params.hpp"
#include "libtorrent/alert.hpp"
#include "libtorrent/alert_types.hpp"
#include "libtorrent/bencode.hpp"
#include "libtorrent/create_torrent.hpp"
#include "libtorrent/hex.hpp"
#include "libtorrent/magnet_uri.hpp"
#include "libtorrent/read_resume_data.hpp"
#include "libtorrent/session.hpp"
#include "libtorrent/settings_pack.hpp"
#include "libtorrent/torrent_flags.hpp"
#include "libtorrent/torrent_handle.hpp"
#include "libtorrent/torrent_status.hpp"
#include "libtorrent/version.hpp"

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <new>
#include <string>
#include <iterator>
#include <vector>

namespace lt = libtorrent;

struct libtorrent_apple_session {
    std::unique_ptr<lt::session> handle;
    std::vector<libtorrent_apple_alert_t> pending_alerts;
};

namespace {

void clear_error(libtorrent_apple_error_t *error_out)
{
    if (error_out == nullptr) {
        return;
    }

    error_out->code = 0;
    std::memset(error_out->message, 0, sizeof(error_out->message));
}

void clear_alert(libtorrent_apple_alert_t *alert_out)
{
    if (alert_out == nullptr) {
        return;
    }

    std::memset(alert_out, 0, sizeof(*alert_out));
}

void clear_byte_buffer(libtorrent_apple_byte_buffer_t *buffer_out)
{
    if (buffer_out == nullptr) {
        return;
    }

    buffer_out->data = nullptr;
    buffer_out->size = 0;
}

void clear_torrent_file(libtorrent_apple_torrent_file_t *file_out)
{
    if (file_out == nullptr) {
        return;
    }

    std::memset(file_out, 0, sizeof(*file_out));
}

void clear_torrent_tracker(libtorrent_apple_torrent_tracker_t *tracker_out)
{
    if (tracker_out == nullptr) {
        return;
    }

    std::memset(tracker_out, 0, sizeof(*tracker_out));
}

void clear_torrent_peer(libtorrent_apple_torrent_peer_t *peer_out)
{
    if (peer_out == nullptr) {
        return;
    }

    std::memset(peer_out, 0, sizeof(*peer_out));
}

void clear_torrent_piece(libtorrent_apple_torrent_piece_t *piece_out)
{
    if (piece_out == nullptr) {
        return;
    }

    std::memset(piece_out, 0, sizeof(*piece_out));
}

bool fail(libtorrent_apple_error_t *error_out, int code, std::string const &message)
{
    if (error_out != nullptr) {
        error_out->code = code;
        std::memset(error_out->message, 0, sizeof(error_out->message));
        std::strncpy(error_out->message, message.c_str(), sizeof(error_out->message) - 1);
    }

    return false;
}

bool fail_buffer(libtorrent_apple_byte_buffer_t *buffer_out, libtorrent_apple_error_t *error_out, int code, std::string const &message)
{
    clear_byte_buffer(buffer_out);
    return fail(error_out, code, message);
}

bool validate_download_priority(int32_t priority, libtorrent_apple_error_t *error_out)
{
    if (priority < 0 || priority > 7) {
        return fail(error_out, -1, "priority must be in the range 0...7");
    }

    return true;
}

std::shared_ptr<lt::torrent_info const> require_torrent_file(
    lt::torrent_handle const &handle,
    libtorrent_apple_error_t *error_out
)
{
    std::shared_ptr<lt::torrent_info const> const torrent_file = handle.torrent_file();
    if (torrent_file == nullptr) {
        fail(error_out, -1, "torrent metadata is not available yet");
        return nullptr;
    }

    return torrent_file;
}

bool validate_file_index(
    lt::torrent_info const &torrent_file,
    int32_t file_index,
    libtorrent_apple_error_t *error_out
)
{
    if (file_index < 0 || file_index >= torrent_file.num_files()) {
        return fail(error_out, -1, "file index is out of range");
    }

    return true;
}

bool validate_piece_index(
    lt::torrent_info const &torrent_file,
    int32_t piece_index,
    libtorrent_apple_error_t *error_out
)
{
    if (piece_index < 0 || piece_index >= torrent_file.num_pieces()) {
        return fail(error_out, -1, "piece index is out of range");
    }

    return true;
}

bool validate_move_flags(int32_t move_flags, libtorrent_apple_error_t *error_out)
{
    if (move_flags < 0 || move_flags > 4) {
        return fail(error_out, -1, "move flags must be in the range 0...4");
    }

    return true;
}

bool validate_tracker_updates(
    libtorrent_apple_torrent_tracker_update_t const *trackers,
    std::size_t tracker_count,
    libtorrent_apple_error_t *error_out
)
{
    if (tracker_count > 0 && trackers == nullptr) {
        return fail(error_out, -1, "trackers must not be null when tracker_count is greater than zero");
    }

    for (std::size_t index = 0; index < tracker_count; ++index) {
        if (trackers[index].url[0] == '\0') {
            return fail(error_out, -1, "tracker url must not be empty");
        }
    }

    return true;
}

int priority_value(lt::download_priority_t priority)
{
    return static_cast<int>(static_cast<std::uint8_t>(priority));
}

int tracker_fail_count(lt::announce_entry const &tracker)
{
    int fail_count = 0;
    for (auto const &endpoint : tracker.endpoints) {
        for (auto const &infohash : endpoint.info_hashes) {
            fail_count = std::max(fail_count, static_cast<int>(infohash.fails));
        }
    }

    return fail_count;
}

std::string tracker_message(lt::announce_entry const &tracker)
{
    for (auto const &endpoint : tracker.endpoints) {
        for (auto const &infohash : endpoint.info_hashes) {
            if (!infohash.message.empty()) {
                return infohash.message;
            }
        }
    }

    return {};
}

std::string endpoint_string(lt::tcp::endpoint const &endpoint)
{
    if (endpoint.address().is_unspecified() && endpoint.port() == 0) {
        return {};
    }

    return endpoint.address().to_string() + ":" + std::to_string(endpoint.port());
}

void copy_fixed_string(char *destination, std::size_t destination_size, std::string const &value)
{
    if (destination == nullptr || destination_size == 0) {
        return;
    }

    std::memset(destination, 0, destination_size);
    std::strncpy(destination, value.c_str(), destination_size - 1);
}

std::string torrent_state_name(lt::torrent_status::state_t state)
{
    switch (state) {
    case lt::torrent_status::checking_files:
        return "checking_files";
    case lt::torrent_status::downloading_metadata:
        return "downloading_metadata";
    case lt::torrent_status::downloading:
        return "downloading";
    case lt::torrent_status::finished:
        return "finished";
    case lt::torrent_status::seeding:
        return "seeding";
    case lt::torrent_status::checking_resume_data:
        return "checking_resume_data";
    default:
        return "unknown";
    }
}

std::string config_string(char const *buffer)
{
    if (buffer == nullptr || buffer[0] == '\0') {
        return {};
    }

    return buffer;
}

std::string info_hash_hex_for_handle(lt::torrent_handle const &handle)
{
    char buffer[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE] = {};
    lt::sha1_hash const best = handle.info_hashes().get_best();
    lt::aux::to_hex({best.data(), lt::sha1_hash::size()}, buffer);
    buffer[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE - 1] = '\0';
    return buffer;
}

bool parse_info_hash_hex(char const *value, lt::sha1_hash *out_hash)
{
    if (value == nullptr || out_hash == nullptr) {
        return false;
    }

    if (std::strlen(value) != LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE - 1) {
        return false;
    }

    lt::sha1_hash hash;
    if (!lt::aux::from_hex({value, LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE - 1}, hash.data())) {
        return false;
    }

    *out_hash = hash;
    return true;
}

lt::torrent_handle find_torrent_handle(libtorrent_apple_session_t *session, char const *info_hash_hex)
{
    if (session == nullptr || session->handle == nullptr || info_hash_hex == nullptr) {
        return lt::torrent_handle();
    }

    lt::sha1_hash requested_hash;
    if (!parse_info_hash_hex(info_hash_hex, &requested_hash)) {
        return lt::torrent_handle();
    }

    for (lt::torrent_handle const &handle : session->handle->get_torrents()) {
        if (!handle.is_valid()) {
            continue;
        }

        if (handle.info_hashes().get_best() == requested_hash) {
            return handle;
        }
    }

    return lt::torrent_handle();
}

bool write_torrent_status(lt::torrent_handle const &handle, libtorrent_apple_torrent_status_t *status_out)
{
    if (status_out == nullptr) {
        return false;
    }

    std::memset(status_out, 0, sizeof(*status_out));

    if (!handle.is_valid()) {
        return false;
    }

    lt::torrent_status const status = handle.status();

    status_out->valid = true;
    status_out->paused = (status.flags & lt::torrent_flags::paused) != lt::torrent_flags_t{};
    status_out->progress = status.progress;
    status_out->state_code = static_cast<int32_t>(status.state);
    status_out->download_rate = status.download_rate;
    status_out->upload_rate = status.upload_rate;
    status_out->num_peers = status.num_peers;
    status_out->num_seeds = status.num_seeds;
    status_out->total_download = status.total_download;
    status_out->total_upload = status.total_upload;
    status_out->total_size = status.total_wanted;

    copy_fixed_string(status_out->info_hash, sizeof(status_out->info_hash), info_hash_hex_for_handle(handle));
    copy_fixed_string(status_out->state, sizeof(status_out->state), torrent_state_name(status.state));
    copy_fixed_string(status_out->name, sizeof(status_out->name), status.name);
    copy_fixed_string(
        status_out->error_message,
        sizeof(status_out->error_message),
        status.errc ? status.errc.message() : std::string{}
    );

    return true;
}

int default_alert_mask()
{
    lt::alert_category_t const mask = lt::alert_category::status | lt::alert_category::error;
    return static_cast<int>(static_cast<std::uint32_t>(mask));
}

std::string info_hash_hex_for_info_hashes(lt::info_hash_t const &info_hashes)
{
    lt::sha1_hash const best = info_hashes.get_best();
    if (best.is_all_zeros()) {
        return {};
    }

    char buffer[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE] = {};
    lt::aux::to_hex({best.data(), lt::sha1_hash::size()}, buffer);
    buffer[LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE - 1] = '\0';
    return buffer;
}

libtorrent_apple_alert_t make_alert_snapshot(lt::alert const &alert)
{
    libtorrent_apple_alert_t snapshot = {};
    snapshot.has_alert = true;
    snapshot.type_code = alert.type();

    copy_fixed_string(snapshot.name, sizeof(snapshot.name), alert.what());
    copy_fixed_string(snapshot.message, sizeof(snapshot.message), alert.message());

    if (auto const *removed_alert = lt::alert_cast<lt::torrent_removed_alert>(&alert)) {
        copy_fixed_string(
            snapshot.info_hash,
            sizeof(snapshot.info_hash),
            info_hash_hex_for_info_hashes(removed_alert->info_hashes)
        );
    } else {
        auto const *torrent_alert = dynamic_cast<lt::torrent_alert const *>(&alert);
        if (torrent_alert != nullptr && torrent_alert->handle.is_valid()) {
            copy_fixed_string(
                snapshot.info_hash,
                sizeof(snapshot.info_hash),
                info_hash_hex_for_handle(torrent_alert->handle)
            );
        }
    }

    return snapshot;
}

bool copy_resume_data_to_buffer(
    lt::entry const &resume_data,
    libtorrent_apple_byte_buffer_t *buffer_out,
    libtorrent_apple_error_t *error_out
)
{
    if (buffer_out == nullptr) {
        return fail(error_out, -1, "buffer_out must not be null");
    }

    std::vector<char> encoded;
    lt::bencode(std::back_inserter(encoded), resume_data);

    if (encoded.empty()) {
        return fail_buffer(buffer_out, error_out, -1, "resume data buffer was empty");
    }

    std::size_t const byte_count = encoded.size();
    auto *allocated = static_cast<std::uint8_t *>(std::malloc(byte_count));
    if (allocated == nullptr) {
        return fail_buffer(buffer_out, error_out, -2, "failed to allocate resume data buffer");
    }

    std::memcpy(allocated, encoded.data(), byte_count);
    buffer_out->data = allocated;
    buffer_out->size = byte_count;
    return true;
}

} // namespace

extern "C" {

const char *libtorrent_apple_bridge_version(void)
{
    return lt::version();
}

bool libtorrent_apple_bridge_is_available(void)
{
    return true;
}

libtorrent_apple_session_configuration_t libtorrent_apple_session_configuration_default(void)
{
    libtorrent_apple_session_configuration_t configuration = {};
    configuration.alert_mask = LIBTORRENT_APPLE_DEFAULT_ALERT_MASK;
    configuration.enable_dht = true;
    configuration.enable_lsd = true;
    configuration.enable_upnp = true;
    configuration.enable_natpmp = true;
    configuration.out_enc_policy = static_cast<int32_t>(lt::settings_pack::enc_policy::pe_enabled);
    configuration.in_enc_policy = static_cast<int32_t>(lt::settings_pack::enc_policy::pe_enabled);
    configuration.allowed_enc_level = static_cast<int32_t>(lt::settings_pack::enc_level::pe_both);
    return configuration;
}

bool libtorrent_apple_session_create(
    libtorrent_apple_session_configuration_t const *configuration,
    libtorrent_apple_session_t **session_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session_out == nullptr) {
        return fail(error_out, -1, "session_out must not be null");
    }

    *session_out = nullptr;

    libtorrent_apple_session_configuration_t effective_configuration =
        configuration != nullptr ? *configuration : libtorrent_apple_session_configuration_default();

    try {
        lt::settings_pack settings;
        std::string const user_agent = config_string(effective_configuration.user_agent);
        settings.set_str(
            lt::settings_pack::user_agent,
            user_agent.empty() ? std::string("libtorrent-apple native bridge libtorrent/") + lt::version() : user_agent
        );

        std::string const handshake_client_version = config_string(effective_configuration.handshake_client_version);
        if (!handshake_client_version.empty()) {
            settings.set_str(lt::settings_pack::handshake_client_version, handshake_client_version);
        }

        std::string listen_interfaces = config_string(effective_configuration.listen_interfaces);
        if (listen_interfaces.empty() && effective_configuration.listen_port > 0) {
            listen_interfaces =
                "0.0.0.0:" + std::to_string(effective_configuration.listen_port)
                + ",[::]:" + std::to_string(effective_configuration.listen_port);
        }

        if (!listen_interfaces.empty()) {
            settings.set_str(lt::settings_pack::listen_interfaces, listen_interfaces);
        }

        settings.set_int(
            lt::settings_pack::alert_mask,
            effective_configuration.alert_mask != 0 ? effective_configuration.alert_mask : default_alert_mask()
        );

        if (effective_configuration.upload_rate_limit > 0) {
            settings.set_int(lt::settings_pack::upload_rate_limit, effective_configuration.upload_rate_limit);
        }

        if (effective_configuration.download_rate_limit > 0) {
            settings.set_int(lt::settings_pack::download_rate_limit, effective_configuration.download_rate_limit);
        }

        if (effective_configuration.connections_limit > 0) {
            settings.set_int(lt::settings_pack::connections_limit, effective_configuration.connections_limit);
        }

        if (effective_configuration.active_downloads_limit > 0) {
            settings.set_int(lt::settings_pack::active_downloads, effective_configuration.active_downloads_limit);
        }

        if (effective_configuration.active_seeds_limit > 0) {
            settings.set_int(lt::settings_pack::active_seeds, effective_configuration.active_seeds_limit);
        }

        if (effective_configuration.active_checking_limit > 0) {
            settings.set_int(lt::settings_pack::active_checking, effective_configuration.active_checking_limit);
        }

        if (effective_configuration.active_dht_limit > 0) {
            settings.set_int(lt::settings_pack::active_dht_limit, effective_configuration.active_dht_limit);
        }

        if (effective_configuration.active_tracker_limit > 0) {
            settings.set_int(lt::settings_pack::active_tracker_limit, effective_configuration.active_tracker_limit);
        }

        if (effective_configuration.active_lsd_limit > 0) {
            settings.set_int(lt::settings_pack::active_lsd_limit, effective_configuration.active_lsd_limit);
        }

        if (effective_configuration.active_limit > 0) {
            settings.set_int(lt::settings_pack::active_limit, effective_configuration.active_limit);
        }

        if (effective_configuration.max_queued_disk_bytes > 0) {
            settings.set_int(lt::settings_pack::max_queued_disk_bytes, effective_configuration.max_queued_disk_bytes);
        }

        if (effective_configuration.send_buffer_low_watermark > 0) {
            settings.set_int(
                lt::settings_pack::send_buffer_low_watermark,
                effective_configuration.send_buffer_low_watermark
            );
        }

        if (effective_configuration.send_buffer_watermark > 0) {
            settings.set_int(
                lt::settings_pack::send_buffer_watermark,
                effective_configuration.send_buffer_watermark
            );
        }

        if (effective_configuration.send_buffer_watermark_factor > 0) {
            settings.set_int(
                lt::settings_pack::send_buffer_watermark_factor,
                effective_configuration.send_buffer_watermark_factor
            );
        }

        settings.set_bool(lt::settings_pack::enable_dht, effective_configuration.enable_dht);
        settings.set_bool(lt::settings_pack::enable_lsd, effective_configuration.enable_lsd);
        settings.set_bool(lt::settings_pack::enable_upnp, effective_configuration.enable_upnp);
        settings.set_bool(lt::settings_pack::enable_natpmp, effective_configuration.enable_natpmp);
        settings.set_bool(lt::settings_pack::auto_sequential, effective_configuration.auto_sequential);
        settings.set_bool(lt::settings_pack::prefer_rc4, effective_configuration.prefer_rc4);
        settings.set_bool(lt::settings_pack::proxy_hostnames, effective_configuration.proxy_hostnames);
        settings.set_bool(
            lt::settings_pack::proxy_peer_connections,
            effective_configuration.proxy_peer_connections
        );
        settings.set_bool(
            lt::settings_pack::proxy_tracker_connections,
            effective_configuration.proxy_tracker_connections
        );
        settings.set_int(lt::settings_pack::out_enc_policy, effective_configuration.out_enc_policy);
        settings.set_int(lt::settings_pack::in_enc_policy, effective_configuration.in_enc_policy);
        settings.set_int(lt::settings_pack::allowed_enc_level, effective_configuration.allowed_enc_level);

        std::string const proxy_hostname = config_string(effective_configuration.proxy_hostname);
        std::string const proxy_username = config_string(effective_configuration.proxy_username);
        std::string const proxy_password = config_string(effective_configuration.proxy_password);

        if (!proxy_hostname.empty()) {
            settings.set_str(lt::settings_pack::proxy_hostname, proxy_hostname);
        }

        if (!proxy_username.empty()) {
            settings.set_str(lt::settings_pack::proxy_username, proxy_username);
        }

        if (!proxy_password.empty()) {
            settings.set_str(lt::settings_pack::proxy_password, proxy_password);
        }

        if (effective_configuration.proxy_port > 0) {
            settings.set_int(lt::settings_pack::proxy_port, effective_configuration.proxy_port);
        }

        settings.set_int(lt::settings_pack::proxy_type, effective_configuration.proxy_type);

        auto wrapper = std::make_unique<libtorrent_apple_session_t>();
        wrapper->handle = std::make_unique<lt::session>(lt::session_params(settings));
        *session_out = wrapper.release();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

void libtorrent_apple_session_destroy(libtorrent_apple_session_t *session)
{
    delete session;
}

bool libtorrent_apple_session_add_magnet(
    libtorrent_apple_session_t *session,
    char const *magnet_uri,
    char const *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    if (magnet_uri == nullptr || magnet_uri[0] == '\0') {
        return fail(error_out, -1, "magnet_uri must not be empty");
    }

    if (download_path == nullptr || download_path[0] == '\0') {
        return fail(error_out, -1, "download_path must not be empty");
    }

    if (info_hash_hex_out == nullptr || info_hash_hex_out_capacity < LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE) {
        return fail(error_out, -1, "info_hash_hex_out must have room for 41 bytes");
    }

    lt::error_code error_code;
    lt::add_torrent_params params = lt::parse_magnet_uri(magnet_uri, error_code);

    if (error_code) {
        return fail(error_out, error_code.value(), error_code.message());
    }

    params.save_path = download_path;

    try {
        lt::torrent_handle const handle = session->handle->add_torrent(std::move(params), error_code);
        if (error_code) {
            return fail(error_out, error_code.value(), error_code.message());
        }

        copy_fixed_string(info_hash_hex_out, info_hash_hex_out_capacity, info_hash_hex_for_handle(handle));
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_add_torrent_file(
    libtorrent_apple_session_t *session,
    char const *torrent_file_path,
    char const *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    if (torrent_file_path == nullptr || torrent_file_path[0] == '\0') {
        return fail(error_out, -1, "torrent_file_path must not be empty");
    }

    if (download_path == nullptr || download_path[0] == '\0') {
        return fail(error_out, -1, "download_path must not be empty");
    }

    if (info_hash_hex_out == nullptr || info_hash_hex_out_capacity < LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE) {
        return fail(error_out, -1, "info_hash_hex_out must have room for 41 bytes");
    }

    lt::error_code error_code;
    lt::add_torrent_params params;
    params.ti = std::make_shared<lt::torrent_info>(std::string(torrent_file_path), error_code);

    if (error_code || params.ti == nullptr) {
        return fail(error_out, error_code.value(), error_code.message());
    }

    params.save_path = download_path;

    try {
        lt::torrent_handle const handle = session->handle->add_torrent(std::move(params), error_code);
        if (error_code) {
            return fail(error_out, error_code.value(), error_code.message());
        }

        copy_fixed_string(info_hash_hex_out, info_hash_hex_out_capacity, info_hash_hex_for_handle(handle));
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_add_resume_data(
    libtorrent_apple_session_t *session,
    std::uint8_t const *resume_data,
    size_t resume_data_size,
    char const *download_path,
    char *info_hash_hex_out,
    size_t info_hash_hex_out_capacity,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    if (resume_data == nullptr || resume_data_size == 0) {
        return fail(error_out, -1, "resume_data must not be empty");
    }

    if (download_path == nullptr || download_path[0] == '\0') {
        return fail(error_out, -1, "download_path must not be empty");
    }

    if (info_hash_hex_out == nullptr || info_hash_hex_out_capacity < LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE) {
        return fail(error_out, -1, "info_hash_hex_out must have room for 41 bytes");
    }

    lt::error_code error_code;
    lt::add_torrent_params params = lt::read_resume_data(
        lt::span<char const>(
            reinterpret_cast<char const *>(resume_data),
            static_cast<std::ptrdiff_t>(resume_data_size)
        ),
        error_code
    );

    if (error_code) {
        return fail(error_out, error_code.value(), error_code.message());
    }

    params.save_path = download_path;

    try {
        lt::torrent_handle const handle = session->handle->add_torrent(std::move(params), error_code);
        if (error_code) {
            return fail(error_out, error_code.value(), error_code.message());
        }

        copy_fixed_string(info_hash_hex_out, info_hash_hex_out_capacity, info_hash_hex_for_handle(handle));
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_pause_torrent(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        handle.unset_flags(lt::torrent_flags::auto_managed);
        handle.pause();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_resume_torrent(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        handle.unset_flags(lt::torrent_flags::auto_managed);
        handle.resume();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_remove_torrent(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    bool remove_data,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        session->handle->remove_torrent(
            handle,
            remove_data ? lt::session_handle::delete_files : lt::remove_flags_t{}
        );
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_get_torrent_status(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_status_t *status_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (status_out == nullptr) {
        return fail(error_out, -1, "status_out must not be null");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        std::memset(status_out, 0, sizeof(*status_out));
        return fail(error_out, -1, "torrent not found");
    }

    try {
        if (!write_torrent_status(handle, status_out)) {
            return fail(error_out, -1, "failed to read torrent status");
        }
        return true;
    } catch (std::exception const &exception) {
        std::memset(status_out, 0, sizeof(*status_out));
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_session_pop_alert(
    libtorrent_apple_session_t *session,
    libtorrent_apple_alert_t *alert_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);
    clear_alert(alert_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    if (alert_out == nullptr) {
        return fail(error_out, -1, "alert_out must not be null");
    }

    try {
        if (session->pending_alerts.empty()) {
            std::vector<lt::alert *> alerts;
            session->handle->pop_alerts(&alerts);

            session->pending_alerts.reserve(alerts.size());
            for (lt::alert *alert : alerts) {
                if (alert == nullptr) {
                    continue;
                }

                session->pending_alerts.push_back(make_alert_snapshot(*alert));
            }
        }

        if (session->pending_alerts.empty()) {
            return true;
        }

        *alert_out = session->pending_alerts.front();
        session->pending_alerts.erase(session->pending_alerts.begin());
        return true;
    } catch (std::exception const &exception) {
        clear_alert(alert_out);
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_export_resume_data(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_byte_buffer_t *buffer_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);
    clear_byte_buffer(buffer_out);

    if (buffer_out == nullptr) {
        return fail(error_out, -1, "buffer_out must not be null");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail_buffer(buffer_out, error_out, -1, "torrent not found");
    }

    try {
        return copy_resume_data_to_buffer(handle.write_resume_data(), buffer_out, error_out);
    } catch (std::exception const &exception) {
        return fail_buffer(buffer_out, error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_export_torrent_file(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_byte_buffer_t *buffer_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);
    clear_byte_buffer(buffer_out);

    if (buffer_out == nullptr) {
        return fail(error_out, -1, "buffer_out must not be null");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail_buffer(buffer_out, error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = handle.torrent_file();
        if (torrent_file == nullptr) {
            return fail_buffer(buffer_out, error_out, -1, "torrent metadata is not available yet");
        }

        lt::create_torrent const torrent_builder(*torrent_file);
        return copy_resume_data_to_buffer(torrent_builder.generate(), buffer_out, error_out);
    } catch (std::exception const &exception) {
        return fail_buffer(buffer_out, error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_file_count(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (count_out == nullptr) {
        return fail(error_out, -1, "count_out must not be null");
    }

    *count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        *count_out = static_cast<size_t>(torrent_file->num_files());
        return true;
    } catch (std::exception const &exception) {
        *count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_get_files(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_file_t *files_out,
    size_t files_capacity,
    size_t *files_count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (files_count_out == nullptr) {
        return fail(error_out, -1, "files_count_out must not be null");
    }

    *files_count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        lt::file_storage const &storage = torrent_file->files();
        int const file_count = storage.num_files();
        *files_count_out = static_cast<size_t>(file_count);

        if (files_capacity < static_cast<size_t>(file_count)) {
            return fail(error_out, -1, "files_out capacity was smaller than the number of torrent files");
        }

        if (file_count > 0 && files_out == nullptr) {
            return fail(error_out, -1, "files_out must not be null when the torrent has files");
        }

        std::vector<std::int64_t> const file_progress = handle.file_progress();
        std::vector<lt::download_priority_t> const file_priorities = handle.get_file_priorities();

        for (int index = 0; index < file_count; ++index) {
            lt::file_index_t const file_index{index};
            libtorrent_apple_torrent_file_t &file_snapshot = files_out[index];
            clear_torrent_file(&file_snapshot);

            int const priority = index < static_cast<int>(file_priorities.size())
                ? priority_value(file_priorities[static_cast<std::size_t>(index)])
                : priority_value(lt::default_priority);

            file_snapshot.index = index;
            file_snapshot.priority = priority;
            file_snapshot.wanted = priority > 0;
            file_snapshot.size = storage.file_size(file_index);
            file_snapshot.downloaded =
                index < static_cast<int>(file_progress.size()) ? file_progress[static_cast<std::size_t>(index)] : 0;
            copy_fixed_string(file_snapshot.name, sizeof(file_snapshot.name), std::string(storage.file_name(file_index)));
            copy_fixed_string(file_snapshot.path, sizeof(file_snapshot.path), storage.file_path(file_index));
        }

        return true;
    } catch (std::exception const &exception) {
        if (files_out != nullptr) {
            for (size_t index = 0; index < files_capacity; ++index) {
                clear_torrent_file(&files_out[index]);
            }
        }
        *files_count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_set_file_priority(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    int32_t file_index,
    int32_t priority,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (!validate_download_priority(priority, error_out)) {
        return false;
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        if (!validate_file_index(*torrent_file, file_index, error_out)) {
            return false;
        }

        handle.file_priority(
            lt::file_index_t{file_index},
            lt::download_priority_t{static_cast<std::uint8_t>(priority)}
        );
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_set_sequential_download(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    bool enabled,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        if (enabled) {
            handle.set_flags(lt::torrent_flags::sequential_download);
        } else {
            handle.unset_flags(lt::torrent_flags::sequential_download);
        }
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_force_recheck(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        handle.force_recheck();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_force_reannounce(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    int32_t seconds,
    int32_t tracker_index,
    bool ignore_min_interval,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (seconds < 0) {
        return fail(error_out, -1, "seconds must not be negative");
    }

    if (tracker_index < -1) {
        return fail(error_out, -1, "tracker_index must be -1 or greater");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        handle.force_reannounce(
            seconds,
            tracker_index,
            ignore_min_interval ? lt::torrent_handle::ignore_min_interval : lt::torrent_handle::reannounce_flags_t{}
        );
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_move_storage(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    char const *download_path,
    int32_t move_flags,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (download_path == nullptr || download_path[0] == '\0') {
        return fail(error_out, -1, "download_path must not be empty");
    }

    if (!validate_move_flags(move_flags, error_out)) {
        return false;
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        handle.move_storage(download_path, static_cast<lt::move_flags_t>(move_flags));
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_piece_count(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (count_out == nullptr) {
        return fail(error_out, -1, "count_out must not be null");
    }

    *count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        *count_out = static_cast<size_t>(torrent_file->num_pieces());
        return true;
    } catch (std::exception const &exception) {
        *count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_get_piece_priorities(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    uint8_t *priorities_out,
    size_t priorities_capacity,
    size_t *priorities_count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (priorities_count_out == nullptr) {
        return fail(error_out, -1, "priorities_count_out must not be null");
    }

    *priorities_count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        std::vector<lt::download_priority_t> const priorities = handle.get_piece_priorities();
        *priorities_count_out = priorities.size();

        if (priorities_capacity < priorities.size()) {
            return fail(error_out, -1, "priorities_out capacity was smaller than the number of torrent pieces");
        }

        if (!priorities.empty() && priorities_out == nullptr) {
            return fail(error_out, -1, "priorities_out must not be null when piece priorities exist");
        }

        for (size_t index = 0; index < priorities.size(); ++index) {
            priorities_out[index] = static_cast<std::uint8_t>(priorities[index]);
        }

        return true;
    } catch (std::exception const &exception) {
        *priorities_count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_set_piece_priority(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    int32_t piece_index,
    int32_t priority,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (!validate_download_priority(priority, error_out)) {
        return false;
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        if (!validate_piece_index(*torrent_file, piece_index, error_out)) {
            return false;
        }

        handle.piece_priority(
            lt::piece_index_t{piece_index},
            lt::download_priority_t{static_cast<std::uint8_t>(priority)}
        );
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_set_piece_deadline(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    int32_t piece_index,
    int32_t deadline_milliseconds,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (deadline_milliseconds < 0) {
        return fail(error_out, -1, "deadline_milliseconds must not be negative");
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        if (!validate_piece_index(*torrent_file, piece_index, error_out)) {
            return false;
        }

        handle.set_piece_deadline(lt::piece_index_t{piece_index}, deadline_milliseconds);
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_reset_piece_deadline(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    int32_t piece_index,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        if (!validate_piece_index(*torrent_file, piece_index, error_out)) {
            return false;
        }

        handle.reset_piece_deadline(lt::piece_index_t{piece_index});
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_tracker_count(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (count_out == nullptr) {
        return fail(error_out, -1, "count_out must not be null");
    }

    *count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        *count_out = handle.trackers().size();
        return true;
    } catch (std::exception const &exception) {
        *count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_get_trackers(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_tracker_t *trackers_out,
    size_t trackers_capacity,
    size_t *trackers_count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (trackers_count_out == nullptr) {
        return fail(error_out, -1, "trackers_count_out must not be null");
    }

    *trackers_count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::vector<lt::announce_entry> const trackers = handle.trackers();
        *trackers_count_out = trackers.size();

        if (trackers_capacity < trackers.size()) {
            return fail(error_out, -1, "trackers_out capacity was smaller than the number of torrent trackers");
        }

        if (!trackers.empty() && trackers_out == nullptr) {
            return fail(error_out, -1, "trackers_out must not be null when trackers exist");
        }

        for (size_t index = 0; index < trackers.size(); ++index) {
            libtorrent_apple_torrent_tracker_t &tracker_snapshot = trackers_out[index];
            lt::announce_entry const &tracker = trackers[index];
            clear_torrent_tracker(&tracker_snapshot);

            tracker_snapshot.tier = tracker.tier;
            tracker_snapshot.fail_count = tracker_fail_count(tracker);
            tracker_snapshot.source_mask = tracker.source;
            tracker_snapshot.verified = tracker.verified;
            copy_fixed_string(tracker_snapshot.url, sizeof(tracker_snapshot.url), tracker.url);
            copy_fixed_string(tracker_snapshot.message, sizeof(tracker_snapshot.message), tracker_message(tracker));
        }

        return true;
    } catch (std::exception const &exception) {
        if (trackers_out != nullptr) {
            for (size_t index = 0; index < trackers_capacity; ++index) {
                clear_torrent_tracker(&trackers_out[index]);
            }
        }
        *trackers_count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_replace_trackers(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_tracker_update_t const *trackers,
    size_t tracker_count,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (!validate_tracker_updates(trackers, tracker_count, error_out)) {
        return false;
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::vector<lt::announce_entry> updated_trackers;
        updated_trackers.reserve(tracker_count);

        for (size_t index = 0; index < tracker_count; ++index) {
            lt::announce_entry entry(trackers[index].url);
            entry.tier = trackers[index].tier;
            updated_trackers.push_back(std::move(entry));
        }

        handle.replace_trackers(updated_trackers);
        handle.post_trackers();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_add_tracker(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_tracker_update_t const *tracker,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (!validate_tracker_updates(tracker, tracker != nullptr ? 1 : 0, error_out)) {
        return false;
    }

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        lt::announce_entry entry(tracker->url);
        entry.tier = tracker->tier;
        handle.add_tracker(entry);
        handle.post_trackers();
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_peer_count(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    size_t *count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (count_out == nullptr) {
        return fail(error_out, -1, "count_out must not be null");
    }

    *count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::vector<lt::peer_info> peers;
        handle.get_peer_info(peers);
        *count_out = peers.size();
        return true;
    } catch (std::exception const &exception) {
        *count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_get_peers(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_peer_t *peers_out,
    size_t peers_capacity,
    size_t *peers_count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (peers_count_out == nullptr) {
        return fail(error_out, -1, "peers_count_out must not be null");
    }

    *peers_count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::vector<lt::peer_info> peers;
        handle.get_peer_info(peers);
        *peers_count_out = peers.size();

        if (peers_capacity < peers.size()) {
            return fail(error_out, -1, "peers_out capacity was smaller than the number of torrent peers");
        }

        if (!peers.empty() && peers_out == nullptr) {
            return fail(error_out, -1, "peers_out must not be null when peers exist");
        }

        for (size_t index = 0; index < peers.size(); ++index) {
            libtorrent_apple_torrent_peer_t &peer_snapshot = peers_out[index];
            lt::peer_info const &peer = peers[index];
            clear_torrent_peer(&peer_snapshot);

            peer_snapshot.flags = static_cast<int32_t>(static_cast<std::uint32_t>(peer.flags));
            peer_snapshot.source_mask = static_cast<int32_t>(static_cast<std::uint8_t>(peer.source));
            peer_snapshot.download_rate = peer.payload_down_speed;
            peer_snapshot.upload_rate = peer.payload_up_speed;
            peer_snapshot.queue_bytes = peer.queue_bytes;
            peer_snapshot.total_download = peer.total_download;
            peer_snapshot.total_upload = peer.total_upload;
            peer_snapshot.progress = peer.progress;
            peer_snapshot.is_seed = (peer.flags & lt::peer_info::seed) != lt::peer_flags_t{};
            copy_fixed_string(peer_snapshot.endpoint, sizeof(peer_snapshot.endpoint), endpoint_string(peer.ip));
            copy_fixed_string(peer_snapshot.client, sizeof(peer_snapshot.client), peer.client);
        }

        return true;
    } catch (std::exception const &exception) {
        if (peers_out != nullptr) {
            for (size_t index = 0; index < peers_capacity; ++index) {
                clear_torrent_peer(&peers_out[index]);
            }
        }
        *peers_count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

bool libtorrent_apple_torrent_get_pieces(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_piece_t *pieces_out,
    size_t pieces_capacity,
    size_t *pieces_count_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (pieces_count_out == nullptr) {
        return fail(error_out, -1, "pieces_count_out must not be null");
    }

    *pieces_count_out = 0;

    lt::torrent_handle const handle = find_torrent_handle(session, info_hash_hex);
    if (!handle.is_valid()) {
        return fail(error_out, -1, "torrent not found");
    }

    try {
        std::shared_ptr<lt::torrent_info const> const torrent_file = require_torrent_file(handle, error_out);
        if (torrent_file == nullptr) {
            return false;
        }

        std::vector<lt::download_priority_t> const priorities = handle.get_piece_priorities();
        std::vector<int> availability;
        handle.piece_availability(availability);
        lt::torrent_status const status = handle.status(lt::torrent_handle::query_pieces);

        int const piece_count = torrent_file->num_pieces();
        *pieces_count_out = static_cast<size_t>(piece_count);

        if (pieces_capacity < static_cast<size_t>(piece_count)) {
            return fail(error_out, -1, "pieces_out capacity was smaller than the number of torrent pieces");
        }

        if (piece_count > 0 && pieces_out == nullptr) {
            return fail(error_out, -1, "pieces_out must not be null when pieces exist");
        }

        for (int index = 0; index < piece_count; ++index) {
            libtorrent_apple_torrent_piece_t &piece_snapshot = pieces_out[index];
            clear_torrent_piece(&piece_snapshot);

            piece_snapshot.index = index;
            piece_snapshot.priority = index < static_cast<int>(priorities.size())
                ? priority_value(priorities[static_cast<std::size_t>(index)])
                : priority_value(lt::default_priority);
            piece_snapshot.availability =
                index < static_cast<int>(availability.size()) ? availability[static_cast<std::size_t>(index)] : 0;
            piece_snapshot.downloaded =
                index < status.pieces.size() ? status.pieces[lt::piece_index_t{index}] : false;
        }

        return true;
    } catch (std::exception const &exception) {
        if (pieces_out != nullptr) {
            for (size_t index = 0; index < pieces_capacity; ++index) {
                clear_torrent_piece(&pieces_out[index]);
            }
        }
        *pieces_count_out = 0;
        return fail(error_out, -2, exception.what());
    }
}

void libtorrent_apple_byte_buffer_free(libtorrent_apple_byte_buffer_t *buffer)
{
    if (buffer == nullptr) {
        return;
    }

    std::free(buffer->data);
    buffer->data = nullptr;
    buffer->size = 0;
}

} // extern "C"
