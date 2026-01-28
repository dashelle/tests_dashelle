#!/bin/bash
clear

set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'


# Скрипт собирает информацию о системе и сохраняет её в файл.

# Поддерживаемые ключи:
# --hostname : сохранить только имя хоста
# --ip : сохранить только IP адрес
# --sysinfo : сохранить  только сведения об ОС
# --fresh : перезаписать файл (по умолчанию - дописывать)
# --output <filename> : имя файл или путь к директории для отчёта
# --debug : включение отладочных сообщений
# --help : показать справку

# Поведение:
# - если указан хотя бы один из ключей (--hostname, --ip, --sysinfo) => выполняются только эти действия (можно несколько)
# - если указан только --fresh (и больше нет других действий) => сохраняются ВСЕ доступные данные (и hostname, и ip, и sysinfo)
# - файл результата: если указать путь к директории, то сохраняем в ней с именем sysinfo_report.txt,
# если указано имя файла, то сохраняем туда (если без / - в той же директории, где находится скрипт)
# - на Linux, проверяем, что скрипт запущен от root (если нет, то выводим ошибку)
# - вывод который пишется в файл, дублируется в терминале
# - корректно определяем MacOs или Linux, вычисляем IP соответствующими командами

# -----------------------
# Переменные по-умочанию
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # определяем директорию, где лежит сам скрипт
OUTPUT_TARGET="" # Сюда записывается путь, если задач ключ --output
OUTPUT_FILE=""   # Полный путь к файлу отчета
FRESH=false      # Нужно перезаписать файл (ключ --fresh)
DEBUG=false      # Отладка (--debug)

# Какие действия выполняем (если пусто, то означает, что нет явного действия)
DO_HOSTNAME=false # Собираем данные о hostname
DO_IP=false       # Собираем данные об IP
DO_SYSINFO=false  # Собираем системную инфу

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
function debug() { if [[ "$DEBUG" == true ]]; then
  msg "DEBUG: $*"
  fi
}


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
  --fresh                 Перезаписать файл отчёта (иначе данные дописываются в отчёт)
  --output <path|file>    Имя файла или путь к директории для отчёта
  --debug                 Включить отладочный вывод
  --help                  Показать справку

  Примеры:
    $(basename "$0") --ip --output=report.txt
    $(basename "$0") --hostname --debug
    $(basename "$0") --fresh --output /tmp
EOF
}


# ---------------
# Определение ОС
# ---------------
function detect_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo Unknown)"
    case "$uname_s" in
      Linux*)  echo "linux" ;;
      Darwin*) echo "mac" ;;
      *)       echo "unknown" ;;
    esac
}

OS_TYPE="$(detect_os)"        # Сохраняем результат
debug "Detected OS: $OS_TYPE"

# ------------------------
# Функции получения данных
# ------------------------
# Получение имени хоста
function get_hostname() {
  hostname 2>/dev/null || echo "unknown" ;
}

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
function get_sysinfo_linux() {
  if [[ -f /etc/os-sysinfo ]] ; then
    cat /etc/os-sysinfo
  elif [[ -f /etc/os-release ]] ; then
   # вывод PRETTY_NAME
    grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null || awk -F= '/^NAME=|^VERSION=/{print}' /etc/os-release
  else
    uname -sr
  fi
}

# Информация об MacOs
function get_sysinfo_mac() {
  if command -v sw_vers >/dev/null 2>&1; then
    sw_vers
  else
    uname -sr
  fi
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
    --help|-h)
     show_help; exit 0
    ;;
    --hostname)
      DO_HOSTNAME=true; shift ;;
    --ip)
      DO_IP=true; shift ;;
    --sysinfo)
      DO_SYSINFO=true; shift ;;
    --fresh)
      FRESH=true; shift ;;
    --debug)
      DEBUG=true; shift ;;
    --output)
      shift
      if [[ -z "${1:-}" ]]; then
        error "--output требует аргумента"; exit 1
      fi
      OUTPUT_TARGET="$1"; shift ;;
    --output=*)
      OUTPUT_TARGET="${1#*=}"; shift ;;
    *)
      error "Неизвестный параметр: $1"; show_help; exit 1 ;;
  esac
done

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
    error "Требуется root при запуске на Linux. Выполните: sudo $0 ..."
    exit 1
  fi
fi

# ----------------------
# Подготовка OUTPUT_FILE
# ----------------------
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
TIMESTAMP="$(date '+%F %T')"
  {
    echo "--- Отчет $(basename "$0") $TIMESTAMP ---"

    if $DO_HOSTNAME; then
      HN="$(get_hostname)"
      echo "HOSTNAME: $HN"
    fi

    if $DO_IP; then
      if [[ "$OS_TYPE" == "mac" ]]; then
       IP_ADDR="$(get_ip_mac)"
      else
        IP_ADDR="$(get_ip_linux)"
      fi
      echo "IP: ${IP_ADDR:-unknown}"
    fi

  if $DO_SYSINFO; then
    if [[ "$OS_TYPE" == "mac" ]]; then
      echo "SYSTEM:"
      get_sysinfo_mac | sed 's/^/ /'
    else
      echo "SYSTEM:"
      get_sysinfo_linux | sed 's/^/ /'
    fi
  fi

  echo
  } | tee -a "$OUTPUT_FILE"

  info "Запись завершена: $OUTPUT_FILE"
  debug "Конец выполнения"
  exit 0