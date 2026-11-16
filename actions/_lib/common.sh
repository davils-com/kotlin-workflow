#!/usr/bin/env bash
# Shared by every script of the actions.

# jq.exe writes CRLF on a Windows runner, and the carriage return would become part of every
# value a script reads from it.
jq() {
  command jq "$@" | tr -d '\r'
}
