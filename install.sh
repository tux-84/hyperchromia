#!/bin/bash
set -euo pipefail

HYPERCHROMIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\e[1;31m'
  C_GREEN=$'\e[1;32m'
  C_YELLOW=$'\e[1;33m'
  C_RESET=$'\e[0m'
else
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_RESET=""
fi

hy_clear() {
  printf '\033[2J\033[3J\033[H'
}

HY_DIALOG_BIN=""
if command -v dialog >/dev/null 2>&1; then
  HY_DIALOG_BIN="dialog"
elif command -v whiptail >/dev/null 2>&1; then
  HY_DIALOG_BIN="whiptail"
fi

if [ -n "$HY_DIALOG_BIN" ]; then
  exec 3>&1
  HY_INSTALL_CHOICE=$("$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "HyperChromia" \
    --menu "Choose an option:" 12 60 2 \
    1 "Build only (produces factory.img/update.img, no USB)" \
    2 "Create a USB stick (build + flash)" \
    2>&1 1>&3)
  rc=$?
  hy_clear
  [ "$rc" -eq 0 ] || { echo "${C_YELLOW}Cancelled.${C_RESET}" >&2; exit 1; }
else
  echo "${C_RED}HyperChromia${C_RESET}"
  echo "  ${C_GREEN}1)${C_RESET} Build only (produces factory.img/update.img, no USB)"
  echo "  ${C_GREEN}2)${C_RESET} Create a USB stick (build + flash)"
  read -r -p "Select an option [1/2]: " HY_INSTALL_CHOICE
fi

case "$HY_INSTALL_CHOICE" in
  1)
    exec "$HYPERCHROMIA_DIR/scripts/build.sh"
    ;;
  2)
    exec "$HYPERCHROMIA_DIR/scripts/make-usb.sh" "$@"
    ;;
  *)
    echo "${C_YELLOW}Cancelled.${C_RESET}" >&2
    exit 1
    ;;
esac
