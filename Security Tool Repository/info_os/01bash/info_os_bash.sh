#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

# clear

# Скрипт собирает информацию о системе и сохраняет её в файл.
# --hostname : сохранить только имя хоста
# --ip       : сохранить только IP адрес
# --sysinfo  : сохранить сведения об ОС
# --cpu      : сохранить информацию о CPU
# --memory   : сохранить информацию о памяти
# --network  : сохранить сетевую информацию
# --user     : сохранить информацию о пользователе
# --all      : сохранить ВСЮ доступную информацию
# --fresh    : перезаписать файл
# --output <filename|dir> : имя файла или путь к директории для отчета
# --debug : включение отладочных сообщений
# --help : показать справку

# Поведение:
# один ключ = одно действие (можно несколько ключей в одну команду)
# если указан --fresh без других ключей = сохраняем ВСЕ данные о системе
# файл с результатом sysinfo_report.txt сохраняем в текущей директории (где скрипт) или указываем путь для сохранения
# определяем ОС (MacOS или Linux)
# Linux-окружение = проверка, что скрипт запущен от root
# Вывод в файл = дубль в терминале

# -----------------------
# Переменные по-умолчанию
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # определяем директорию, где лежит сам скрипт
OUTPUT_TARGET="" # Сюда записывается путь, если задан ключ --output
OUTPUT_FILE=""   # Полный путь к файлу отчета
FRESH=false      # Нужно перезаписать файл (ключ --fresh)
DEBUG=false      # Отладка (--debug)

DO_HOSTNAME=false
DO_IP=false
DO_SYSINFO=false
DO_CPU=false
DO_MEMORY=false
DO_NETWORK=false
DO_USER=false
DO_ALL=false

# -------------------
# Окрашивание вывода
# -------------------
BOLD="\033[1m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
NORM="\033[0m"


function msg() { echo -e "$*"; }
function info() { msg "${BOLD}INFO:${NORM} $*"; }
function warn() { msg "${YELLOW}WARNING:${NORM} $*"; }
function error() { msg "${RED}ERROR:${NORM} $*"; }
function debug() { [[ "$DEBUG" == true ]] && msg "DEBUG: $*" ; }


# -----------------
# Показать справку
# -----------------
function show_help() {
    cat <<EOF
  Использование: $(basename "$0") [опции]

  Опции:
  --hostname              Сохранить только имя хоста
  --ip                    Сохранить только IP адрес (IPv4)
  --sysinfo               Сохранить только информацию об ОС
  --cpu
  --memory
  --network
  --user
  --all
  --fresh                 Перезаписать файл отчёта (иначе данные дописываются в отчёт)
  --output <file|dir>    Имя файла или путь к директории для отчёта
  --debug                 Включить отладочный вывод
  --help                  Показать справку

  Примеры:
    $(basename "$0") --ip --output=report.txt
    $(basename "$0") --hostname --debug
    $(basename "$0") --fresh --output /home
    $(basename "$0") --all --output /home
EOF
}


# ---------------
# Определение ОС
# ---------------
function detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "mac" ;;
    *)       echo "unknown" ;;
  esac
}

OS_TYPE="$(detect_os)"        # Сохраняем результат
debug "Detected OS: $OS_TYPE"

# ---------------------------------------------
# Функции получения данных (универсальные)
# ---------------------------------------------
# Получение имени хоста
function get_hostname() { hostname || echo "unknown"; }

# Получение IP для Linux
function get_ip_linux() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1 \
  || hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Получение IP для MacOS
function get_ip_mac() {
  for IF in en0 en1 en2; do
    ipconfig getifaddr "$IF" 2>/dev/null && return 0
  done
# fallback - взять IP черзе route
# Извлечь IP через ip command, если установлен brew install iproute2mac
local ip_via_route
  ip_via_route=$(route get 1.1.1.1 2>/dev/null | awk '/src /{print $2}')
  if [[ -n "$ip_via_route" ]] ; then
    echo "$ip_via_route"
    return 0
    fi
    echo "unknown"
}

# Информация об ОС Linux
function get_sysinfo() {
  case "$OS_TYPE" in
    linux)
      [[ -f /etc/os-release ]] && grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
      ;;
    mac) sw_vers ;;
    *) uname -sr ;;
  esac
}

# CPU
function get_cpu() {
  case "$OS_TYPE" in
    linux) lscpu | awk -F: '/Model name|CPU\(s\)/{print $1 ": " $2}' ;;
    mac) sysctl -n machdep.cpu.brand_string ;;
  esac
}

# Память
function get_memory() {
  case "$OS_TYPE" in
    linux) free -h | awk '/Mem:/ {print "Total: "$2", Used: "$3", Free: "$4}' ;;
    mac)
      sysctl hw.memsize | awk '{printf "%.1f GB\n",$2/1024/1024/1024}'
      ;;
  esac
}

# Сеть
function get_network() {
  case "$OS_TYPE" in
    linux) ip addr show ;;
    mac) ifconfig ;;
  esac
}

# Пользователь
function get_user_info() {
  echo "User: $(whoami)"
  id
}

# --------------------------
# Полная информация (ALL)
# --------------------------
function get_full_system_info() {
cat <<EOF
HOSTNAME: $(get_hostname)
IP: $(get_ip)

SYSTEM:
$(get_sysinfo)

CPU:
$(get_cpu)

MEMORY:
$(get_memory)

NETWORK:
$(get_network)

USER:
$(get_user_info)
EOF
}

# ----------
# Аргументы
# ----------
# Если нет аргументов => выводим справку
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) DO_HOSTNAME=true ;;
    --ip) DO_IP=true ;;
    --sysinfo) DO_SYSINFO=true ;;
    --cpu) DO_CPU=true ;;
    --memory) DO_MEMORY=true ;;
    --network) DO_NETWORK=true ;;
    --user) DO_USER=true ;;
    --all) DO_ALL=true ;;
    --fresh) FRESH=true ;;
    --debug) DEBUG=true ;;
    --output) shift; OUTPUT_TARGET="${1:-}";;
    --output=*) OUTPUT_TARGET="${1#*=}" ;;
    --help) show_help; exit 0 ;;
    *) error "Неизвестный параметр: $1"; exit 1 ;;
  esac
  shift
done

# --------------------------
# Логика выбора действий
# --------------------------
if $DO_ALL; then
  DO_HOSTNAME=true
  DO_IP=true
  DO_SYSINFO=true
  DO_CPU=true
  DO_MEMORY=true
  DO_NETWORK=true
  DO_USER=true
fi

debug "Flags: DO_HOSTNAME=$DO_HOSTNAME DO_IP=$DO_IP DO_SYSINFO=$DO_SYSINFO FRESH=$FRESH OUTPUT_TARGET='$OUTPUT_TARGET'"

# --------------------------------------------------------------------------
# Если не указано ни одно из действий, но указан --fresh => собрать всё (all)
# Если ни одного действия и не --fresh => предупреждение и выход
# --------------------------------------------------------------------------
if ! $DO_HOSTNAME && ! $DO_IP && ! $DO_SYSINFO; then
  if $FRESH; then
    DO_HOSTNAME=true
    DO_IP=true
    DO_SYSINFO=true
    debug "--fresh без явных действий => собираем все данные"
  else
    warn "Не указано действие (например, --ip или --hostname). Для подсказки используйте --help."
    exit 1
  fi
fi

# ---------------------------------------
# Проверка прав: Linux? => требуем root
# ---------------------------------------
if [[ "$OS_TYPE" == 'linux' ]]; then
  if [[ "$EUID" -ne 0 ]]; then
    error "В Linux требуется root. Выполните: sudo $0 ..."
    exit 1
  fi
fi

# ------------------------------------
# Подготовка OUTPUT_FILE / ОТЧЁТ
# ------------------------------------
if [[ -n "$OUTPUT_TARGET" ]]; then
  if [[ -d "$OUTPUT_TARGET" ]]; then
    OUTPUT_FILE="$OUTPUT_TARGET/sysinfo_report.txt"
  else
  # если указать пусть с / => используем его
    if [[ "$OUTPUT_TARGET" == */* ]]; then
      OUTPUT_FILE="$OUTPUT_TARGET"
    else
  # если файл без пути => сохраняем в папке скрипта
    OUTPUT_FILE="$SCRIPT_DIR/$OUTPUT_TARGET"
    fi
  fi
else
  OUTPUT_FILE="$SCRIPT_DIR/sysinfo_report.txt"
fi

debug "Output file resolved to: $OUTPUT_FILE"

# Создаем директорию для файла
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
  debug "Directory $OUTPUT_DIR does not exist - пытаемся создать"
  mkdir -p "$OUTPUT_DIR" || { error "Не удалось создать директорию $OUTPUT_DIR"; exit 1; }
fi

# ------------------------------------------------------
# Если FRESH => перезаписываем, иначе создаём/дописываем
# ------------------------------------------------------
if $FRESH; then
  : > "$OUTPUT_FILE"
else
  touch "$OUTPUT_FILE"
fi

# --------------------
# Сбор и запись данных
# --------------------
{
echo "--- REPORT $(date '+%F %T') ---"

$DO_HOSTNAME && echo "HOSTNAME: $(get_hostname)"
$DO_IP && echo "IP: $(get_ip)"
$DO_SYSINFO && echo -e "SYSTEM:\n$(get_sysinfo)"
$DO_CPU && echo -e "CPU:\n$(get_cpu)"
$DO_MEMORY && echo "MEMORY: $(get_memory)"
$DO_NETWORK && echo -e "NETWORK:\n$(get_network)"
$DO_USER && echo -e "USER:\n$(get_user_info)"

  echo
  } | tee -a "$OUTPUT_FILE"

  info "Готово: $OUTPUT_FILE"
  debug "Конец выполнения"
  exit 0