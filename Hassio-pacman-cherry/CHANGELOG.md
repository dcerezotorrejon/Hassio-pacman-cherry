# Changelog

## 0.2.1

- Fix syntax error in `env.sh` (`es}` instead of `esac` in `bashio::config` fallback).
- Fix unbound variable error (`info: unbound variable`) when running in standalone Docker without Home Assistant Supervisor by conditionally loading `bashio.sh` only when `SUPERVISOR_TOKEN` is present.

## 0.2.0

- Added standalone Docker support for running in Portainer or Docker Compose.
- Configured environment variables (`PKGBUILD_REPO_URL`, `POLL_INTERVAL`, `LOG_LEVEL`, `PORT`) with automatic `bashio` fallbacks.
- Added root Dockerfile and docker-compose template.

## 0.1.9

- Added pacman mirror update
## 0.1.8

- Fix removing when PKGBUILD were deleted
## 0.1.7

- Minimal improvement

## 0.1.6

- Added automatic base database regeneration on any change (compilation, deletion or addition).
- Introduced `CHANGED` flag to track compilation events.
- Updated builder logic to set flags appropriately and ensure repo‑add runs when necessary.
- Minor refactoring for clarity.

## 0.1.5

- Fix invalid `-s` option syntax in git command execution
- Centralize shared environment variables into `/env.sh`
- Improve Caddy process auto-recovery inside the execution loop

## 0.1.4

- Change folders to private folder /data

## 0.1.3

- Several optimizations

## 0.1.1

- Change in builder scripts

## 0.1.0

- Change base to arch linux

## 0.0.2

- Fix several issues in real device

## 0.0.1

- Base configuration of a pacman repo based on a PKGBUILD repository
