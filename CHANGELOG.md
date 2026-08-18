# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Updated libtorrent from 2.1.0 to 2.1.1.
- Updated OpenSSL-Universal from 3.6.2000 (OpenSSL 3.6.2) to 3.6.3000 (OpenSSL 3.6.3).

## [0.3.0] - 2026-07-22

### Changed

- Updated libtorrent from 2.0.13 to 2.1.0.
- Updated the Boost headers used by the binary build from 1.76.0 to 1.91.0.
- Switched the native build from C++14 to C++17 while retaining the existing libtorrent ABI 1 bridge compatibility.
- Disabled WebTorrent support and its additional native dependencies; standard BitTorrent functionality and HTTP, HTTPS, and UDP trackers remain available.
