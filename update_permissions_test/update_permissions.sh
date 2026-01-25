#!/usr/bin/env bash

set -o pipefail
set -e

# Описание:
# управление правами доступа и владельцами файлов/директорий
# Внимание: скрипт меняет системные файлы

# ---------------------------
# DEBUG SWITCH (test/release)
# ---------------------------
DEBUG_FEATURE=true   # true — тестовый режим (разрешить --debug), false — релиз (запретить --debug)

# ---------------------------------------------------------------------------------------------
# СПИСОК ФАЙЛОВ по умолчанию
# ---------------------------------------------------------------------------------------------
MASSIVE_FILES=(
  "/etc/shadow"
  "/etc/passwd"
  "/etc/group"
  "/etc/profile.d/*"
  "/etc/profile"
  "/etc/fstab"
  "/etc/fstab.d"
  "/etc/fstab.pdac"
  "/etc/modprobe.d/*"
  "/etc/rc*"
  "/etc/bash.bashrc"
  "/etc/crontab"
  "/usr/sbin/cron"
  "/usr/sbin/anacron"
  "/var/spool/cron/"
  "/var/spool/cron/crontabs"
  "/root/.profile"
  "/root/.bashrc"
)


# ------------------------------------------------
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ (для обработки аргументов)
# ------------------------------------------------
ARG_VALUE_IMPORT=""                # путь к файлу импорта
ARG_VALUE_EXPORT=""                # путь к файлу экспорта
ARG_VALUE_CHMOD=""                 # chmod mode
ARG_VALUE_CHOWN=""                 # owner:group
ARG_VALUE_CREATE=false             # создавать пользователя/группу
ARG_VALUE_REPORT=false             # показать итоговый список (ls -l)
ARG_VALUE_DEBUG=false              # отладка
ARG_VALUE_HELP=false               # справка
ARG_VALUE_RECURSIVE=""             # либо пусто, либо "-R"

# ВАЖНО: фикс для "--import" / "--export" без значения
ARG_FLAG_IMPORT=false
ARG_FLAG_EXPORT=false

# -------------------------------------------------------------
# Цветовое форматирование (для вывода сообщений) / Логирование
# -------------------------------------------------------------
NORMAL="\e[0m"
GREEN_COLOR="\e[32m"
YELLOW_COLOR="\e[33m"
RED_COLOR="\e[31m"

info()  { printf "${GREEN_COLOR}[OK]${NORMAL} %s\n" "$*"; }
warn()  { printf "${YELLOW_COLOR}[WARN]${NORMAL} %s\n" "$*"; }
error() { printf "${RED_COLOR}[ERROR]${NORMAL} %s\n" "$*"; }

debug() {
  if [[ "${ARG_VALUE_DEBUG}" == true ]]; then
    printf "${YELLOW_COLOR}[DEBUG]${NORMAL} %s\n" "$*"
  fi
}


# -------------------------------
# Имя файла для import/export
# -------------------------------
get_default_file() { echo "$(basename "$0")_output.txt"; }
DEFAULT_FILE_NAME="$(get_default_file)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$SCRIPT_DIR"

# ---------------------------------------
# Справка
# ---------------------------------------
show_help() {
  echo "Использование:"
  echo "sudo $0 [опции]"
  echo
  echo "Опции (key=value):"
  echo " --import[=<file>] Импорт списка файлов из текстового файла (если без значения — ищем дефолтный файл)"
  echo " --export[=<file>] Экспорт текущего списка файлов в текстовый файл (если без значения — в текущий каталог)"
  echo " --chmod=<mode> Применить chmod ко всем файлам (например 600, 644, 0755)"
  echo " --chown=<user:group> Изменить владельца и группу (user:, :group, user:group)"
  echo
  echo "Флаги:"
  echo " --create Создать пользователя/группу, если их ещё нет"
  echo " --report Показать итоговый список (ls -l)"
  echo " --debug Включить отладочные сообщения"
  echo " -R, --recursive Применять изменения рекурсивно (chmod/chown -R)"
  echo " -h, --help Показать справку"
  echo
  echo "Примеры:"
  echo " $0 --chmod=644 --report"
  echo " $0 --chown=root:root --chmod=600"
  echo " $0 --import=file.txt --chmod=644 --export=output.txt --report"
  echo " $0 --chown=tuser:tgroup --create --chmod=650 -R"
}

# Если аргументов нет - показываем help
if [[ $# -eq 0 ]]; then
  ARG_VALUE_HELP=true
fi

# ________________________________________
# Парсер аргументов (key=value и flags)
#_________________________________________
parse_arg() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --import=*)
        ARG_FLAG_IMPORT=true
        ARG_VALUE_IMPORT="${1#*=}"
        shift
        ;;
      --import)
        ARG_FLAG_IMPORT=true
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
          ARG_VALUE_IMPORT="$2"
          shift 2
        else
          ARG_VALUE_IMPORT=""  # без значения => потом возьмём дефолтный файл
          shift
        fi
        ;;
      --export=*)
        ARG_FLAG_EXPORT=true
        ARG_VALUE_EXPORT="${1#*=}"
        shift
        ;;
      --export)
        ARG_FLAG_EXPORT=true
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
          ARG_VALUE_EXPORT="$2"
          shift 2
        else
          ARG_VALUE_EXPORT=""  # без значения => потом сделаем дефолт в WORKDIR
          shift
        fi
        ;;
      --chmod=*)
        ARG_VALUE_CHMOD="${1#*=}"
        shift
        ;;
      --chmod)
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
          ARG_VALUE_CHMOD="${2:-}"
          shift 2
        else
          error "Не указан mode для --chmod (например: --chmod=644)"
          exit 1
        fi
        ;;
      --chown=*)
        ARG_VALUE_CHOWN="${1#*=}"
        shift
        ;;
      --chown)
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
          ARG_VALUE_CHOWN="$2"
          shift 2
        else
          error "Не указан пользователь и группа для --chown. Формат: user:group (или user:, или :group)."
          exit 1
        fi
        ;;
      --create)
        ARG_VALUE_CREATE=true
        shift
        ;;
      --report)
        ARG_VALUE_REPORT=true
        shift
        ;;
      -R|--recursive)
        ARG_VALUE_RECURSIVE="-R"
        shift
        ;;
      -h|--help)
        ARG_VALUE_HELP=true
        shift
        ;;
      --debug)
        if [[ "$DEBUG_FEATURE" == true ]]; then
          ARG_VALUE_DEBUG=true
          shift
        else
          error "Опция --debug отключена"
          exit 1
        fi
        ;;
      *)
        error "Неизвестная опция: $1"
        exit 1
        ;;
    esac
  done
}

parse_arg "$@"

# _______________________
# Отладка
# _______________________
debug "IMPORT_FLAG=${ARG_FLAG_IMPORT} IMPORT=${ARG_VALUE_IMPORT}"
debug "EXPORT_FLAG=${ARG_FLAG_EXPORT} EXPORT=${ARG_VALUE_EXPORT}"
debug "CHMOD=${ARG_VALUE_CHMOD}"
debug "CHOWN=${ARG_VALUE_CHOWN}"
debug "CREATE=${ARG_VALUE_CREATE}"
debug "REPORT=${ARG_VALUE_REPORT}"
debug "RECURSIVE=${ARG_VALUE_RECURSIVE}"

# _______________________
# ВАЛИДАЦИЯ chmod mode:
# _______________________
validate_chmod_mode() {
  local mode="$1"
  [[ -z "$mode" ]] && return 1
  [[ ${#mode} -ne 3 && ${#mode} -ne 4 ]] && return 1
[[ "$mode" =~ ^0?[1-7][0-7]{2}$ ]] || return 1
  return 0
}

# _____________________________________________________________________
# ИМПОРТ _ ИЗ файла списка файлов (заменяет MASSIVE_FILES)
# _____________________________________________________________________
resolve_default_import_file() {
  if [[ -f "$WORKDIR/$DEFAULT_FILE_NAME" ]]; then
    echo "$WORKDIR/$DEFAULT_FILE_NAME"; return 0
  fi
  if [[ -f "$HOME/$DEFAULT_FILE_NAME" ]]; then
    echo "$HOME/$DEFAULT_FILE_NAME"; return 0
  fi
  return 1
}

import_from_file() {
  local file="$1"
  local -a new_list=()
  local line=""

  if [[ ! -f "$file" ]]; then
    error "Файл импорта не найден: $file"
    return 1
  fi

  if [[ ! -s "$file" ]]; then
    warn "Файл импорта пуст, используем список файлов по умолчанию"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    new_list+=("$line")
  done < "$file"

  if [[ ${#new_list[@]} -eq 0 ]]; then
    warn "Файл импорта не содержит пути, используем список файлов по умолчанию"
    return 0
  fi

  MASSIVE_FILES=("${new_list[@]}")
  info "Импорт выполнен: ${#MASSIVE_FILES[@]}"
  return 0
}

# _____________________________________________________________________
# ЭКСПОРТ _ В файл списка файлов
# _____________________________________________________________________
create_export_file() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"

  if ! mkdir -p "$dir"; then
    error "Не удалось создать папку для экспорта: $dir"
    return 1
  fi

  if ! printf "%s\n" "${MASSIVE_FILES[@]}" > "$file"; then
    error "Не удалось записать файл экспорта: $file (проверьте права записи)"
    return 1
  fi

  info "Экспорт выполнен: $file"
  return 0
}

# -----------------------------------------------------------------------------
# USERS/GROUP
# -----------------------------------------------------------------------------
user_exist()  { id -u "$1" >/dev/null 2>&1; }
group_exist() { getent group "$1" >/dev/null 2>&1; }

create_new_group() {
  local g="$1"
  [[ -z "$g" ]] && return 0

  if ! group_exist "$g"; then
    info "Группа не существует, создаю: $g"
    groupadd "$g" || { warn "Не удалось создать группу: $g"; return 1; }
  else
    info "Группа уже существует: $g"
  fi
}

create_new_user() {
  local u="$1"
  [[ -z "$u" ]] && return 0

  if ! user_exist "$u"; then
    info "Пользователь не существует, создаю: $u"
    useradd -m "$u" || { warn "Не удалось создать пользователя: $u"; return 1; }
  else
    info "Пользователь уже существует: $u"
  fi
}

create_user_and_group() {
  local user=""
  local group=""

  if [[ -z "$ARG_VALUE_CHOWN" ]]; then
    user="tuser"
    group="tgroup"
    info "--create без --chown: создаю пользователя/группу по умолчанию: ${user}:${group}"
    create_new_group "$group" || return 1
    create_new_user "$user" || return 1
    return 0
  fi

  if [[ "$ARG_VALUE_CHOWN" == *:* ]]; then
    user="${ARG_VALUE_CHOWN%%:*}"
    group="${ARG_VALUE_CHOWN#*:}"
  else
    user="$ARG_VALUE_CHOWN"
    group=""
  fi

  [[ -n "$group" ]] && create_new_group "$group" || true
  [[ -n "$user"  ]] && create_new_user  "$user"  || true
  return 0
}

# ---------------------------
# EXPAND GLOBS SAFELY
# ---------------------------
expand_targets() {
  local pattern="$1"
  local -a matches=()

  while IFS= read -r m; do
    matches+=("$m")
  done < <(compgen -G "$pattern" || true)

  [[ ${#matches[@]} -eq 0 ]] && return 1
  printf "%s\n" "${matches[@]}"
}

# --------------------
# CHOWN
# --------------------
set_chown() {
  local owner_group="$1"
  local rec="$2"
  local user=""
  local group=""

  [[ -z "$owner_group" ]] && { error "set_chown: не задано значение (например, user:group)"; return 1; }

  if [[ "$owner_group" == *:* ]]; then
    user="${owner_group%%:*}"
    group="${owner_group#*:}"
  else
    user="$owner_group"
    group=""
  fi

if [[ "$ARG_VALUE_CREATE" != true ]]; then
  [[ -n "$user"  ]] && ! user_exist "$user"  && { error "Пользователь не существует: $user. Используйте --create"; return 1; }
  [[ -n "$group" ]] && ! group_exist "$group" && { error "Группа не существует: $group. Используйте --create"; return 1; }
fi

  local path="" target=""
  local had_any=false

  for path in "${MASSIVE_FILES[@]}"; do
    while IFS= read -r target; do
      had_any=true

      [[ -d "$target" && "$rec" ]] && continue

      if [[ -n "$rec" ]]; then
  debug "chown $rec $owner_group $target"
  if [[ "$ARG_VALUE_DEBUG" == true ]]; then
    chown $rec "$owner_group" "$target" || warn "chown не выполнен: $target"
  else
    chown $rec "$owner_group" "$target" 2>/dev/null || warn "chown не выполнен: $target"
  fi
else
  debug "chown $owner_group $target"
  if [[ "$ARG_VALUE_DEBUG" == true ]]; then
    chown "$owner_group" "$target" || warn "chown не выполнен: $target"
  else
    chown "$owner_group" "$target" 2>/dev/null || warn "chown не выполнен: $target"
  fi
fi

    done < <(expand_targets "$path" || true)
  done

  [[ "$had_any" == false ]] && warn "Нет доступных путей для chown (шаблоны не совпали или нет прав)"
  return 0
}

# --------------------
# CHMOD
# --------------------
set_chmod() {
  local mode="$1"
  local rec="$2"

  [[ -z "$mode" ]] && { error "set_chmod: не задано значение (например, 644)"; return 1; }

  if ! validate_chmod_mode "$mode"; then
    error "Некорректный mode для chmod: $mode"
    return 1
  fi

  local path="" target=""
  local had_any=false

  for path in "${MASSIVE_FILES[@]}"; do
    while IFS= read -r target; do
      had_any=true

[[ -d "$target" && -z "$rec" ]] && continue

      if [[ -n "$rec" ]]; then
        debug "chmod $rec $mode $target"
        if [[ "$ARG_VALUE_DEBUG" == true ]]; then
          chmod $rec "$mode" "$target" || warn "chmod не выполнен: $target"
        else
          chmod $rec "$mode" "$target" 2>/dev/null || warn "chmod не выполнен: $target"
        fi
      else
        debug "chmod $mode $target"
        if [[ "$ARG_VALUE_DEBUG" == true ]]; then
          chmod "$mode" "$target" || warn "chmod не выполнен: $target"
        else
          chmod "$mode" "$target" 2>/dev/null || warn "chmod не выполнен: $target"
        fi
      fi

    done < <(expand_targets "$path" || true)
  done

  [[ "$had_any" == false ]] && warn "Нет доступных путей для chmod (шаблоны не совпали или нет прав)"
  return 0
}

# --------------------
# Отчёт (REPORT)
# --------------------
show_report() {
  printf "${YELLOW_COLOR}Итоговый список файлов (ls -l):${NORMAL}\n"

  local path="" target=""
  local has_output=false

  for path in "${MASSIVE_FILES[@]}"; do
    while IFS= read -r target; do
      if ls -l "$target"; then
        has_output=true
      else
        warn "Не удалось показать: $target"
      fi
    done < <(expand_targets "$path" || true)
  done

  [[ "$has_output" == false ]] && warn "Список файлов пуст/недоступен или шаблоны не совпали"
}


# ------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------------

# HELP — до ROOT-CHECK (чтобы help работал без sudo)
if [[ "$ARG_VALUE_HELP" == true ]]; then
  show_help
  exit 0
fi

# ROOT CHECK
if [[ $EUID -ne 0 ]]; then
  error "Ошибка! скрипт должен быть запущен от root."
  printf "Пример запуска: sudo %s --chmod=600 --report\n" "$0"
  exit 1
fi

# Безопасность: предупреждение, если не используем --import
if [[ "$ARG_FLAG_IMPORT" != true ]]; then
  warn "Не указан --import. Будет использован системный список MASSIVE_FILES (опасно)."
fi

# IMPORT
if [[ "$ARG_FLAG_IMPORT" == true ]]; then
  if [[ -z "$ARG_VALUE_IMPORT" ]]; then
    if DEFAULT_IMPORT="$(resolve_default_import_file)"; then
      ARG_VALUE_IMPORT="$DEFAULT_IMPORT"
    else
      error "Файл импорта не найден: $WORKDIR/$DEFAULT_FILE_NAME и $HOME/$DEFAULT_FILE_NAME"
      exit 1
    fi
  fi

  if import_from_file "$ARG_VALUE_IMPORT"; then
    info "Импорт выполнен из $ARG_VALUE_IMPORT"
  else
    exit 1
  fi
fi


# CREATE (валидация+действие)
if [[ "$ARG_VALUE_CREATE" == true && -z "$ARG_VALUE_CHOWN" ]]; then
  error "--create нельзя использовать без --chown"
  exit 1
fi

if [[ "$ARG_VALUE_CREATE" == true ]]; then
  create_user_and_group || exit 1
fi


# CHOWN
if [[ -n "$ARG_VALUE_CHOWN" ]]; then
  info "Применяю chown..."
  set_chown "$ARG_VALUE_CHOWN" "$ARG_VALUE_RECURSIVE" || exit 1
fi

# CHMOD
if [[ -n "$ARG_VALUE_CHMOD" ]]; then
  info "Применяю chmod..."
  set_chmod "$ARG_VALUE_CHMOD" "$ARG_VALUE_RECURSIVE" || exit 1
fi

# EXPORT
if [[ "$ARG_FLAG_EXPORT" == true ]]; then
  if [[ -z "$ARG_VALUE_EXPORT" ]]; then
    ARG_VALUE_EXPORT="$WORKDIR/$DEFAULT_FILE_NAME"
  fi
  info "Экспорт в $ARG_VALUE_EXPORT"
  create_export_file "$ARG_VALUE_EXPORT" || exit 1
fi

# REPORT
if [[ "$ARG_VALUE_REPORT" == true ]]; then
  show_report
fi

