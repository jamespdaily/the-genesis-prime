#!/bin/bash
# Stands in for dev/play_service/state.sh in the dashboard's tests that do not
# read the play service: prints one fixed report, so a dashboard that
# subscribes a page never runs the developer's real podman.
printf '%s\n' \
  machine=up \
  server=running \
  server_revision=9d2015a0 \
  server_address=192.168.1.5 \
  database=running \
  database_ready=yes \
  game_connections=0 \
  held=no \
  update_lock=free \
  live_lock=free \
  'updater_last_line=2026-11-20 02:41:58 play-service: replacing genesis-play'
