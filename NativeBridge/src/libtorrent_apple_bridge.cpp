#include "libtorrent_apple_bridge.h"

#include "libtorrent/add_torrent_params.hpp"
#include "libtorrent/alert.hpp"
#include "libtorrent/alert_types.hpp"
#include "libtorrent/address.hpp"
#include "libtorrent/bencode.hpp"
#include "libtorrent/create_torrent.hpp"
#include "libtorrent/hex.hpp"
#include "libtorrent/ip_filter.hpp"
#include "libtorrent/magnet_uri.hpp"
#include "libtorrent/read_resume_data.hpp"
#include "libtorrent/session.hpp"
#include "libtorrent/session_status.hpp"
#include "libtorrent/settings_pack.hpp"
#include "libtorrent/torrent_flags.hpp"
#include "libtorrent/torrent_handle.hpp"
#include "libtorrent/torrent_status.hpp"
#include "libtorrent/version.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <iterator>
#include <unordered_set>
#include <vector>

namespace lt = libtorrent;

struct libtorrent_apple_session {
    std::unique_ptr<lt::session> handle;
    std::vector<libtorrent_apple_alert_t> pending_alerts;
    libtorrent_apple_session_configuration_t configuration;
};

namespace {

std::string config_string(char const *buffer);
int default_alert_mask();

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
        std::string const url = config_string(trackers[index].url);
        auto const is_space = [](unsigned char character) {
            return std::isspace(character) != 0;
        };
        auto const has_non_space = std::find_if_not(url.begin(), url.end(), is_space) != url.end();
        if (!has_non_space) {
            return fail(error_out, -1, "tracker url must not be empty");
        }
    }

    return true;
}

std::string trim_copy(std::string value)
{
    auto const is_space = [](unsigned char character) {
        return std::isspace(character) != 0;
    };

    value.erase(value.begin(), std::find_if_not(value.begin(), value.end(), is_space));
    value.erase(std::find_if_not(value.rbegin(), value.rend(), is_space).base(), value.end());
    return value;
}

bool parse_port(std::string const &value, int *port_out)
{
    if (port_out == nullptr || value.empty()) {
        return false;
    }

    char *end = nullptr;
    long const parsed = std::strtol(value.c_str(), &end, 10);
    if (end == nullptr || *end != '\0') {
        return false;
    }

    if (parsed <= 0 || parsed > std::numeric_limits<std::uint16_t>::max()) {
        return false;
    }

    *port_out = static_cast<int>(parsed);
    return true;
}

bool parse_dht_bootstrap_node(
    std::string const &raw_node,
    std::pair<std::string, int> *node_out,
    libtorrent_apple_error_t *error_out
)
{
    if (node_out == nullptr) {
        return fail(error_out, -1, "internal error: node_out must not be null");
    }

    std::string const node = trim_copy(raw_node);
    if (node.empty()) {
        return fail(error_out, -1, "dht bootstrap node must not be empty");
    }

    std::string host;
    std::string port_text;
    if (node.front() == '[') {
        std::size_t const right_bracket = node.find(']');
        if (right_bracket == std::string::npos || right_bracket <= 1) {
            return fail(error_out, -1, "invalid dht bootstrap node format (expected [ipv6]:port)");
        }

        host = node.substr(1, right_bracket - 1);
        if (right_bracket + 1 >= node.size() || node[right_bracket + 1] != ':') {
            return fail(error_out, -1, "invalid dht bootstrap node format (missing port)");
        }
        port_text = node.substr(right_bracket + 2);
    } else {
        std::size_t const colon = node.rfind(':');
        if (colon == std::string::npos || colon == 0 || colon + 1 >= node.size()) {
            return fail(error_out, -1, "invalid dht bootstrap node format (expected host:port)");
        }

        host = node.substr(0, colon);
        port_text = node.substr(colon + 1);
    }

    host = trim_copy(host);
    port_text = trim_copy(port_text);

    int port = 0;
    if (host.empty() || !parse_port(port_text, &port)) {
        return fail(error_out, -1, "invalid dht bootstrap node port");
    }

    *node_out = std::make_pair(host, port);
    return true;
}

bool parse_dht_bootstrap_nodes(
    std::string const &raw_nodes,
    std::vector<std::pair<std::string, int>> *nodes_out,
    libtorrent_apple_error_t *error_out
)
{
    if (nodes_out == nullptr) {
        return fail(error_out, -1, "internal error: nodes_out must not be null");
    }

    nodes_out->clear();
    if (raw_nodes.empty()) {
        return true;
    }

    std::unordered_set<std::string> seen_nodes;
    std::size_t start = 0;
    while (start <= raw_nodes.size()) {
        std::size_t const separator = raw_nodes.find(',', start);
        std::string const segment = separator == std::string::npos
            ? raw_nodes.substr(start)
            : raw_nodes.substr(start, separator - start);
        std::string const trimmed = trim_copy(segment);
        if (!trimmed.empty()) {
            std::pair<std::string, int> parsed_node;
            if (!parse_dht_bootstrap_node(trimmed, &parsed_node, error_out)) {
                return false;
            }

            std::string const key = parsed_node.first + ":" + std::to_string(parsed_node.second);
            if (seen_nodes.insert(key).second) {
                nodes_out->push_back(parsed_node);
            }
        }

        if (separator == std::string::npos) {
            break;
        }

        start = separator + 1;
    }

    return true;
}

template <std::size_t N>
void apply_prefix_range(
    std::array<unsigned char, N> *first,
    std::array<unsigned char, N> *last,
    int prefix_bits
)
{
    if (first == nullptr || last == nullptr) {
        return;
    }

    int remaining_bits = std::max(prefix_bits, 0);
    for (std::size_t index = 0; index < N; ++index) {
        if (remaining_bits >= 8) {
            remaining_bits -= 8;
            continue;
        }

        if (remaining_bits <= 0) {
            (*first)[index] = 0x00;
            (*last)[index] = 0xFF;
            continue;
        }

        unsigned char const mask = static_cast<unsigned char>(0xFFu << (8 - remaining_bits));
        (*first)[index] = static_cast<unsigned char>((*first)[index] & mask);
        (*last)[index] = static_cast<unsigned char>((*last)[index] | static_cast<unsigned char>(~mask));
        remaining_bits = 0;
    }
}

bool parse_cidr_range(
    std::string const &raw_cidr,
    std::pair<lt::address, lt::address> *range_out,
    libtorrent_apple_error_t *error_out
)
{
    if (range_out == nullptr) {
        return fail(error_out, -1, "internal error: range_out must not be null");
    }

    std::string const cidr = trim_copy(raw_cidr);
    if (cidr.empty()) {
        return fail(error_out, -1, "peer filter CIDR must not be empty");
    }

    std::size_t const slash = cidr.find('/');
    std::string const address_part = trim_copy(slash == std::string::npos ? cidr : cidr.substr(0, slash));
    std::string const prefix_part = slash == std::string::npos ? "" : trim_copy(cidr.substr(slash + 1));

    lt::error_code parse_error;
    lt::address const parsed_address = lt::make_address(address_part, parse_error);
    if (parse_error) {
        return fail(error_out, parse_error.value(), "invalid peer filter CIDR address");
    }

    int max_bits = parsed_address.is_v4() ? 32 : 128;
    int prefix_bits = max_bits;
    if (!prefix_part.empty()) {
        char *end = nullptr;
        long const parsed_prefix = std::strtol(prefix_part.c_str(), &end, 10);
        if (end == nullptr || *end != '\0' || parsed_prefix < 0 || parsed_prefix > max_bits) {
            return fail(error_out, -1, "invalid peer filter CIDR prefix");
        }
        prefix_bits = static_cast<int>(parsed_prefix);
    }

    if (parsed_address.is_v4()) {
        std::array<unsigned char, 4> first = parsed_address.to_v4().to_bytes();
        std::array<unsigned char, 4> last = first;
        apply_prefix_range(&first, &last, prefix_bits);
        *range_out = std::make_pair(lt::address_v4(first), lt::address_v4(last));
        return true;
    }

    std::array<unsigned char, 16> first = parsed_address.to_v6().to_bytes();
    std::array<unsigned char, 16> last = first;
    apply_prefix_range(&first, &last, prefix_bits);
    *range_out = std::make_pair(lt::address_v6(first), lt::address_v6(last));
    return true;
}

bool parse_cidr_ranges(
    std::string const &raw_cidrs,
    std::vector<std::pair<lt::address, lt::address>> *ranges_out,
    libtorrent_apple_error_t *error_out
)
{
    if (ranges_out == nullptr) {
        return fail(error_out, -1, "internal error: ranges_out must not be null");
    }

    ranges_out->clear();
    if (raw_cidrs.empty()) {
        return true;
    }

    std::unordered_set<std::string> seen;
    std::size_t start = 0;
    while (start <= raw_cidrs.size()) {
        std::size_t const separator = raw_cidrs.find(',', start);
        std::string const segment = separator == std::string::npos
            ? raw_cidrs.substr(start)
            : raw_cidrs.substr(start, separator - start);
        std::string const trimmed = trim_copy(segment);
        if (!trimmed.empty() && seen.insert(trimmed).second) {
            std::pair<lt::address, lt::address> parsed_range;
            if (!parse_cidr_range(trimmed, &parsed_range, error_out)) {
                return false;
            }
            ranges_out->push_back(parsed_range);
        }

        if (separator == std::string::npos) {
            break;
        }
        start = separator + 1;
    }

    return true;
}

void add_peer_filter_rules(
    lt::ip_filter *filter,
    std::vector<std::pair<lt::address, lt::address>> const &ranges,
    std::uint32_t flags
)
{
    if (filter == nullptr) {
        return;
    }

    for (auto const &range : ranges) {
        filter->add_rule(range.first, range.second, flags);
    }
}

bool apply_peer_filters(
    lt::session *session,
    std::vector<std::pair<lt::address, lt::address>> const &blocked_ranges,
    std::vector<std::pair<lt::address, lt::address>> const &allowed_ranges,
    libtorrent_apple_error_t *error_out
)
{
    if (session == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    lt::ip_filter filter;
    bool const has_allow_rules = !allowed_ranges.empty();
    bool const has_block_rules = !blocked_ranges.empty();
    bool const has_any_rules = has_allow_rules || has_block_rules;

    if (has_allow_rules) {
        filter.add_rule(
            lt::address_v4(std::array<unsigned char, 4>{0, 0, 0, 0}),
            lt::address_v4(std::array<unsigned char, 4>{255, 255, 255, 255}),
            lt::ip_filter::blocked
        );
        std::array<unsigned char, 16> const v6_min = {};
        std::array<unsigned char, 16> v6_max = {};
        v6_max.fill(0xFF);
        filter.add_rule(lt::address_v6(v6_min), lt::address_v6(v6_max), lt::ip_filter::blocked);
        add_peer_filter_rules(&filter, allowed_ranges, 0);
    }

    if (has_block_rules) {
        add_peer_filter_rules(&filter, blocked_ranges, lt::ip_filter::blocked);
    }

    if (has_any_rules) {
        session->set_ip_filter(filter);
    } else {
        session->set_ip_filter(lt::ip_filter{});
    }

    return true;
}

bool set_non_negative_int_setting(
    lt::settings_pack *settings,
    int key,
    int32_t value,
    bool runtime_mode
)
{
    if (settings == nullptr) {
        return false;
    }

    if (runtime_mode) {
        settings->set_int(key, std::max(value, 0));
    } else if (value > 0) {
        settings->set_int(key, value);
    }

    return true;
}

bool apply_configuration_to_settings(
    libtorrent_apple_session_configuration_t const &configuration,
    lt::settings_pack *settings_out,
    bool runtime_mode,
    libtorrent_apple_error_t *error_out
)
{
    if (settings_out == nullptr) {
        return fail(error_out, -1, "settings_out must not be null");
    }

    lt::settings_pack &settings = *settings_out;

    if (!runtime_mode) {
        std::string const user_agent = config_string(configuration.user_agent);
        settings.set_str(
            lt::settings_pack::user_agent,
            user_agent.empty() ? std::string("libtorrent-apple native bridge libtorrent/") + lt::version() : user_agent
        );

        std::string const handshake_client_version = config_string(configuration.handshake_client_version);
        if (!handshake_client_version.empty()) {
            settings.set_str(lt::settings_pack::handshake_client_version, handshake_client_version);
        }

        std::string listen_interfaces = config_string(configuration.listen_interfaces);
        if (listen_interfaces.empty() && configuration.listen_port > 0) {
            listen_interfaces =
                "0.0.0.0:" + std::to_string(configuration.listen_port)
                + ",[::]:" + std::to_string(configuration.listen_port);
        }

        if (!listen_interfaces.empty()) {
            settings.set_str(lt::settings_pack::listen_interfaces, listen_interfaces);
        }

        settings.set_int(
            lt::settings_pack::alert_mask,
            configuration.alert_mask != 0 ? configuration.alert_mask : default_alert_mask()
        );
    }

    set_non_negative_int_setting(&settings, lt::settings_pack::upload_rate_limit, configuration.upload_rate_limit, runtime_mode);
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::download_rate_limit,
        configuration.download_rate_limit,
        runtime_mode
    );
    if (configuration.share_ratio_limit >= 0) {
        settings.set_int(lt::settings_pack::share_ratio_limit, configuration.share_ratio_limit);
    }
    set_non_negative_int_setting(&settings, lt::settings_pack::connections_limit, configuration.connections_limit, runtime_mode);
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::active_downloads,
        configuration.active_downloads_limit,
        runtime_mode
    );
    set_non_negative_int_setting(&settings, lt::settings_pack::active_seeds, configuration.active_seeds_limit, runtime_mode);
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::active_checking,
        configuration.active_checking_limit,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::active_dht_limit,
        configuration.active_dht_limit,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::active_tracker_limit,
        configuration.active_tracker_limit,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::active_lsd_limit,
        configuration.active_lsd_limit,
        runtime_mode
    );
    set_non_negative_int_setting(&settings, lt::settings_pack::active_limit, configuration.active_limit, runtime_mode);
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::max_queued_disk_bytes,
        configuration.max_queued_disk_bytes,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::send_buffer_low_watermark,
        configuration.send_buffer_low_watermark,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::send_buffer_watermark,
        configuration.send_buffer_watermark,
        runtime_mode
    );
    set_non_negative_int_setting(
        &settings,
        lt::settings_pack::send_buffer_watermark_factor,
        configuration.send_buffer_watermark_factor,
        runtime_mode
    );

    if (!runtime_mode) {
        settings.set_bool(lt::settings_pack::enable_dht, configuration.enable_dht);
        settings.set_bool(lt::settings_pack::enable_lsd, configuration.enable_lsd);
        settings.set_bool(lt::settings_pack::enable_upnp, configuration.enable_upnp);
        settings.set_bool(lt::settings_pack::enable_natpmp, configuration.enable_natpmp);
    }
    settings.set_bool(lt::settings_pack::auto_sequential, configuration.auto_sequential);
    settings.set_bool(lt::settings_pack::prefer_rc4, configuration.prefer_rc4);
    settings.set_bool(lt::settings_pack::proxy_hostnames, configuration.proxy_hostnames);
    settings.set_bool(lt::settings_pack::proxy_peer_connections, configuration.proxy_peer_connections);
    settings.set_bool(lt::settings_pack::proxy_tracker_connections, configuration.proxy_tracker_connections);
    settings.set_int(lt::settings_pack::out_enc_policy, configuration.out_enc_policy);
    settings.set_int(lt::settings_pack::in_enc_policy, configuration.in_enc_policy);
    settings.set_int(lt::settings_pack::allowed_enc_level, configuration.allowed_enc_level);

    std::string const proxy_hostname = config_string(configuration.proxy_hostname);
    std::string const proxy_username = config_string(configuration.proxy_username);
    std::string const proxy_password = config_string(configuration.proxy_password);

    if (runtime_mode || !proxy_hostname.empty()) {
        settings.set_str(lt::settings_pack::proxy_hostname, proxy_hostname);
    }

    if (runtime_mode || !proxy_username.empty()) {
        settings.set_str(lt::settings_pack::proxy_username, proxy_username);
    }

    if (runtime_mode || !proxy_password.empty()) {
        settings.set_str(lt::settings_pack::proxy_password, proxy_password);
    }

    if (runtime_mode) {
        settings.set_int(lt::settings_pack::proxy_port, std::max(configuration.proxy_port, 0));
    } else if (configuration.proxy_port > 0) {
        settings.set_int(lt::settings_pack::proxy_port, configuration.proxy_port);
    }
    settings.set_int(lt::settings_pack::proxy_type, configuration.proxy_type);

    std::string const peer_fingerprint = config_string(configuration.peer_fingerprint);
    if (runtime_mode || !peer_fingerprint.empty()) {
        settings.set_str(lt::settings_pack::peer_fingerprint, peer_fingerprint);
    }

    std::string const dht_bootstrap_nodes = config_string(configuration.dht_bootstrap_nodes);
    if (runtime_mode || !dht_bootstrap_nodes.empty()) {
        settings.set_str(lt::settings_pack::dht_bootstrap_nodes, dht_bootstrap_nodes);
    }

    return true;
}

bool check_runtime_configuration_change(
    bool changed,
    char const *field_name,
    libtorrent_apple_error_t *error_out
)
{
    if (!changed) {
        return true;
    }

    return fail(
        error_out,
        -1,
        std::string("runtime apply does not support changing ") + field_name + "; recreate the session instead"
    );
}

bool runtime_configuration_is_supported(
    libtorrent_apple_session_configuration_t const &current,
    libtorrent_apple_session_configuration_t const &requested,
    libtorrent_apple_error_t *error_out
)
{
    if (!check_runtime_configuration_change(current.listen_port != requested.listen_port, "listen_port", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(current.alert_mask != requested.alert_mask, "alert_mask", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(current.enable_dht != requested.enable_dht, "enable_dht", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(current.enable_lsd != requested.enable_lsd, "enable_lsd", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(current.enable_upnp != requested.enable_upnp, "enable_upnp", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(current.enable_natpmp != requested.enable_natpmp, "enable_natpmp", error_out)) {
        return false;
    }
    if (!check_runtime_configuration_change(
            config_string(current.user_agent) != config_string(requested.user_agent),
            "user_agent",
            error_out
        ))
    {
        return false;
    }
    if (!check_runtime_configuration_change(
            config_string(current.handshake_client_version) != config_string(requested.handshake_client_version),
            "handshake_client_version",
            error_out
        ))
    {
        return false;
    }
    if (!check_runtime_configuration_change(
            config_string(current.listen_interfaces) != config_string(requested.listen_interfaces),
            "listen_interfaces",
            error_out
        ))
    {
        return false;
    }

    return true;
}

void add_dht_bootstrap_nodes(
    lt::session *session,
    std::vector<std::pair<std::string, int>> const &nodes
)
{
    if (session == nullptr) {
        return;
    }

    for (auto const &node : nodes) {
        session->add_dht_node(node);
    }
}

std::vector<lt::announce_entry> deduplicated_tracker_entries(
    libtorrent_apple_torrent_tracker_update_t const *trackers,
    std::size_t tracker_count
)
{
    std::vector<lt::announce_entry> entries;
    entries.reserve(tracker_count);

    std::unordered_set<std::string> seen_urls;
    for (std::size_t index = 0; index < tracker_count; ++index) {
        std::string const url = trim_copy(config_string(trackers[index].url));
        if (url.empty() || !seen_urls.insert(url).second) {
            continue;
        }

        lt::announce_entry entry(url);
        entry.tier = trackers[index].tier;
        entries.push_back(std::move(entry));
    }

    return entries;
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
    configuration.share_ratio_limit = -1;
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
        if (!apply_configuration_to_settings(effective_configuration, &settings, false, error_out)) {
            return false;
        }

        std::vector<std::pair<std::string, int>> dht_bootstrap_nodes;
        if (!parse_dht_bootstrap_nodes(
                config_string(effective_configuration.dht_bootstrap_nodes),
                &dht_bootstrap_nodes,
                error_out
            ))
        {
            return false;
        }
        std::vector<std::pair<lt::address, lt::address>> blocked_cidrs;
        if (!parse_cidr_ranges(
                config_string(effective_configuration.peer_blocked_cidrs),
                &blocked_cidrs,
                error_out
            ))
        {
            return false;
        }
        std::vector<std::pair<lt::address, lt::address>> allowed_cidrs;
        if (!parse_cidr_ranges(
                config_string(effective_configuration.peer_allowed_cidrs),
                &allowed_cidrs,
                error_out
            ))
        {
            return false;
        }

        auto wrapper = std::make_unique<libtorrent_apple_session_t>();
        wrapper->handle = std::make_unique<lt::session>(lt::session_params(settings));
        wrapper->configuration = effective_configuration;
        add_dht_bootstrap_nodes(wrapper->handle.get(), dht_bootstrap_nodes);
        if (!apply_peer_filters(wrapper->handle.get(), blocked_cidrs, allowed_cidrs, error_out)) {
            return false;
        }
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

bool libtorrent_apple_session_apply_configuration(
    libtorrent_apple_session_t *session,
    libtorrent_apple_session_configuration_t const *configuration,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    if (configuration == nullptr) {
        return fail(error_out, -1, "configuration must not be null");
    }

    if (!runtime_configuration_is_supported(session->configuration, *configuration, error_out)) {
        return false;
    }

    try {
        lt::settings_pack settings;
        if (!apply_configuration_to_settings(*configuration, &settings, true, error_out)) {
            return false;
        }

        std::vector<std::pair<std::string, int>> dht_bootstrap_nodes;
        if (!parse_dht_bootstrap_nodes(
                config_string(configuration->dht_bootstrap_nodes),
                &dht_bootstrap_nodes,
                error_out
            ))
        {
            return false;
        }
        std::vector<std::pair<lt::address, lt::address>> blocked_cidrs;
        if (!parse_cidr_ranges(
                config_string(configuration->peer_blocked_cidrs),
                &blocked_cidrs,
                error_out
            ))
        {
            return false;
        }
        std::vector<std::pair<lt::address, lt::address>> allowed_cidrs;
        if (!parse_cidr_ranges(
                config_string(configuration->peer_allowed_cidrs),
                &allowed_cidrs,
                error_out
            ))
        {
            return false;
        }

        session->handle->apply_settings(settings);
        add_dht_bootstrap_nodes(session->handle.get(), dht_bootstrap_nodes);
        if (!apply_peer_filters(session->handle.get(), blocked_cidrs, allowed_cidrs, error_out)) {
            return false;
        }
        session->configuration = *configuration;
        return true;
    } catch (std::exception const &exception) {
        return fail(error_out, -2, exception.what());
    }
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

bool libtorrent_apple_session_get_stats(
    libtorrent_apple_session_t *session,
    libtorrent_apple_session_stats_t *stats_out,
    libtorrent_apple_error_t *error_out
)
{
    clear_error(error_out);

    if (stats_out == nullptr) {
        return fail(error_out, -1, "stats_out must not be null");
    }

    std::memset(stats_out, 0, sizeof(*stats_out));

    if (session == nullptr || session->handle == nullptr) {
        return fail(error_out, -1, "session must not be null");
    }

    auto const clamp_int32 = [](std::int64_t value) {
        if (value > std::numeric_limits<int32_t>::max()) {
            return std::numeric_limits<int32_t>::max();
        }
        if (value < std::numeric_limits<int32_t>::min()) {
            return std::numeric_limits<int32_t>::min();
        }
        return static_cast<int32_t>(value);
    };

    try {
        lt::session_status const session_status = session->handle->status();
        std::int64_t total_peers = 0;
        std::int64_t total_seeds = 0;

        for (lt::torrent_handle const &handle : session->handle->get_torrents()) {
            if (!handle.is_valid()) {
                continue;
            }

            lt::torrent_status const status = handle.status();
            total_peers += std::max(status.num_peers, 0);
            total_seeds += std::max(status.num_seeds, 0);
        }

        stats_out->download_rate = clamp_int32(session_status.download_rate);
        stats_out->upload_rate = clamp_int32(session_status.upload_rate);
        stats_out->total_connections = clamp_int32(session_status.num_peers);
        stats_out->total_peers = clamp_int32(total_peers);
        stats_out->total_seeds = clamp_int32(total_seeds);
        stats_out->dht_enabled = session->configuration.enable_dht;
        stats_out->dht_node_count = clamp_int32(session_status.dht_nodes);
        return true;
    } catch (std::exception const &exception) {
        std::memset(stats_out, 0, sizeof(*stats_out));
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
        std::vector<lt::announce_entry> const updated_trackers = deduplicated_tracker_entries(trackers, tracker_count);
        handle.replace_trackers(updated_trackers);
        if (!updated_trackers.empty()) {
            handle.post_trackers();
        }
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
    return libtorrent_apple_torrent_add_trackers(
        session,
        info_hash_hex,
        tracker,
        tracker != nullptr ? 1 : 0,
        true,
        error_out
    );
}

bool libtorrent_apple_torrent_add_trackers(
    libtorrent_apple_session_t *session,
    char const *info_hash_hex,
    libtorrent_apple_torrent_tracker_update_t const *trackers,
    size_t tracker_count,
    bool force_reannounce,
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
        std::vector<lt::announce_entry> const unique_updates = deduplicated_tracker_entries(trackers, tracker_count);
        std::unordered_set<std::string> existing_urls;
        for (lt::announce_entry const &existing : handle.trackers()) {
            existing_urls.insert(trim_copy(existing.url));
        }

        std::size_t added_count = 0;
        for (lt::announce_entry const &entry : unique_updates) {
            if (!existing_urls.insert(trim_copy(entry.url)).second) {
                continue;
            }

            handle.add_tracker(entry);
            added_count += 1;
        }

        if (force_reannounce && added_count > 0) {
            handle.post_trackers();
        }
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
