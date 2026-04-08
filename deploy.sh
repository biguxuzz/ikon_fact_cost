#!/usr/bin/env bash
# Скрипт деплоя расширения ikon_cost_Доработки в тестовую базу
# Требуется bash (дерево PID, pgrep). Запуск: bash deploy.sh

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Ошибка: запустите через bash: bash deploy.sh" >&2
    exit 1
fi

set -e # Остановить при ошибке

EXTENSION_NAME="ikon_cost_Доработки"
REPO_DIR="/mnt/e/git/ikon_fact_cost"

# Платформа 1С: полный путь к 1cv8s (версия каталога платформы, не номер расширения из Configuration.xml). Переопределение: export PATH_1CV8S=...
PATH_1CV8S="${PATH_1CV8S:-/opt/1cv8/x86_64/8.3.27.1936/1cv8s}"

# Путь к информационной базе для ключа /S (как в списке баз). Переопределение: export DEPLOY_INFOBASE_PATH=...
DEPLOY_INFOBASE_PATH="${DEPLOY_INFOBASE_PATH:-PGORODILOV.WSL/TEST_ERP_BRZ_01}"

# Максимальное время ожидания одного шага DESIGNER (секунды). Переопределение: export DEPLOY_STEP_TIMEOUT_SEC=7200
DEPLOY_STEP_TIMEOUT_SEC="${DEPLOY_STEP_TIMEOUT_SEC:-3600}"

# Подстрока из /S (каталог ИБ). Доп. ожидание: процессы 1cv8/1cv8s с этой ИБ и пакетным ключом (не ragent: у него в cmdline нет /1cv8s ).
# Отключить доп. ожидание: export DEPLOY_INFOBASE_MARKER=
DEPLOY_INFOBASE_MARKER="${DEPLOY_INFOBASE_MARKER:-TEST_ERP_BRZ_01}"

# Есть ли ещё пакетный клиент по этой ИБ (дерево PID уже пусто, а работа в оторванном процессе).
# Не используем простой grep «1cv8» — совпадает путь /opt/1cv8/... у ragent/rphost.
deploy_infobase_batch_client_busy() {
    local m="${DEPLOY_INFOBASE_MARKER:-}"
    [ -n "$m" ] || return 1
    pgrep -af -- "$m" 2>/dev/null \
        | grep -E '[/](1cv8s|1cv8)[[:space:]]' \
        | grep -iE 'DESIGNER|/UpdateDBCfg|/LoadConfigFromFiles|/ReduceEventLogSize|/DumpCfg' \
        | grep -q .
}

# Человекочитаемая длительность по числу секунд
fmt_duration() {
    local s=$1
    if [ "$s" -lt 60 ]; then
        echo "${s} с"
    elif [ "$s" -lt 3600 ]; then
        echo "$((s / 60)) мин $((s % 60)) с"
    else
        echo "$((s / 3600)) ч $(((s % 3600) / 60)) мин $((s % 60)) с"
    fi
}

# 1cv8s часто сразу завершается, оставляя работу потомкам — ждём всё дерево PID (корень + рекурсивно дети по pgrep -P).
# Возвращает код выхода корневого процесса (или 124 при таймауте).
wait_for_process_tree_with_timeout() {
    local root_pid="$1"
    local max_sec="${2:-3600}"
    local deadline
    deadline=$(( $(date +%s) + max_sec ))
    local -A watched=()
    local root_waited=0
    local root_exit=0
    local p c any st

    watched[$root_pid]=1

    # Быстрый захват потомков. Не выходим из цикла при смерти корня: иначе при короткоживущем корне
    # (шаги 2–4) burst обрывается до обхода дерева и ожидание сразу завершается — шаги идут «пачкой».
    local burst
    for burst in $(seq 1 300); do
        for p in "${!watched[@]}"; do
            if kill -0 "$p" 2>/dev/null; then
                while IFS= read -r c; do
                    [ -n "$c" ] && watched[$c]=1
                done < <(pgrep -P "$p" 2>/dev/null || true)
            fi
        done
        sleep 0.01
    done

    while true; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "Ошибка: превышено время ожидания дерева процессов (корень PID=${root_pid}, ${max_sec} с)" >&2
            return 124
        fi

        # Корень-зомби (прямой потомок shell) — обязательно wait, иначе kill -0 «жив» вечно
        if [ "$root_waited" -eq 0 ] && kill -0 "$root_pid" 2>/dev/null && [ -r "/proc/${root_pid}/stat" ]; then
            st=$(awk '{print $3}' "/proc/${root_pid}/stat" 2>/dev/null || echo "")
            if [ "$st" = "Z" ]; then
                if wait "$root_pid"; then
                    root_exit=0
                else
                    root_exit=$?
                fi
                root_waited=1
            fi
        fi

        for p in "${!watched[@]}"; do
            if kill -0 "$p" 2>/dev/null; then
                while IFS= read -r c; do
                    [ -n "$c" ] && watched[$c]=1
                done < <(pgrep -P "$p" 2>/dev/null || true)
            fi
        done

        if [ "$root_waited" -eq 0 ] && ! kill -0 "$root_pid" 2>/dev/null; then
            if wait "$root_pid"; then
                root_exit=0
            else
                root_exit=$?
            fi
            root_waited=1
        fi

        any=0
        for p in "${!watched[@]}"; do
            if kill -0 "$p" 2>/dev/null; then
                any=1
                break
            fi
        done

        # Дерево пусто, но ещё жив пакетный 1cv8/1cv8s с этой ИБ (шаги 2–4 часто отрываются от дерева PID)
        if [ "$any" -eq 0 ] && [ -n "${DEPLOY_INFOBASE_MARKER:-}" ]; then
            if deploy_infobase_batch_client_busy; then
                any=1
            fi
        fi

        if [ "$any" -eq 0 ]; then
            return "$root_exit"
        fi

        if kill -0 "$root_pid" 2>/dev/null && [ "$root_waited" -eq 0 ]; then
            sleep 0.05
        else
            sleep 0.2
        fi
    done
}

# Запускает 1cv8s DESIGNER в фоне и ждёт завершения дерева процессов (корневой PID и все потомки).
run_designer_and_wait() {
    local pid
    "$@" &
    pid=$!
    echo "    (корневой PID: ${pid}, ожидание дерева процессов, таймаут ${DEPLOY_STEP_TIMEOUT_SEC} с)"
    wait_for_process_tree_with_timeout "$pid" "$DEPLOY_STEP_TIMEOUT_SEC"
}

# Чтение версии расширения из Configuration.xml
VERSION=$(grep -oP '(?<=<Version>)[^<]*' "${REPO_DIR}/Configuration.xml" | head -1 | tr -d '\n')

if [ -z "$VERSION" ]; then
    echo "Ошибка: не удалось прочитать версию из Configuration.xml"
    exit 1
fi

echo "=== Деплой ${EXTENSION_NAME} v${VERSION} в ${DEPLOY_INFOBASE_PATH} ==="

DEPLOY_START_TS=$(date +%s)

echo "[1/4] Загрузка конфигурации из файлов..."
STEP_START_TS=$(date +%s)
if run_designer_and_wait "${PATH_1CV8S}" DESIGNER \
    /S "${DEPLOY_INFOBASE_PATH}" \
    /NAdmin \
    /LoadConfigFromFiles "${REPO_DIR}" \
    -Extension "${EXTENSION_NAME}"; then
    STEP_SEC=$(( $(date +%s) - STEP_START_TS ))
    echo "[1/4] Загрузка конфигурации завершена успешно (шаг: $(fmt_duration "$STEP_SEC"))"
else
    echo "[1/4] Ошибка при загрузке конфигурации!"
    exit 1
fi

echo "[2/4] Обновление структуры БД..."
STEP_START_TS=$(date +%s)
if run_designer_and_wait "${PATH_1CV8S}" DESIGNER \
    /S "${DEPLOY_INFOBASE_PATH}" \
    /NAdmin \
    /UpdateDBCfg \
    -Extension "${EXTENSION_NAME}"; then
    STEP_SEC=$(( $(date +%s) - STEP_START_TS ))
    echo "[2/4] Обновление структуры БД завершено успешно (шаг: $(fmt_duration "$STEP_SEC"))"
else
    echo "[2/4] Ошибка при обновлении структуры БД!"
    exit 1
fi

echo "[3/4] Очистка журнала регистрации..."
STEP_START_TS=$(date +%s)
if run_designer_and_wait "${PATH_1CV8S}" DESIGNER \
    /S "${DEPLOY_INFOBASE_PATH}" \
    /NAdmin \
    /ReduceEventLogSize "$(date -d tomorrow +%Y-%m-%d)"; then
    STEP_SEC=$(( $(date +%s) - STEP_START_TS ))
    echo "[3/4] Очистка журнала регистрации завершена (шаг: $(fmt_duration "$STEP_SEC"))"
else
    echo "[3/4] Ошибка при очистке журнала регистрации!"
    exit 1
fi

echo "[4/4] Выгрузка расширения в файл (артефакт сборки для прод)..."
STEP_START_TS=$(date +%s)
if run_designer_and_wait "${PATH_1CV8S}" DESIGNER \
    /S "${DEPLOY_INFOBASE_PATH}" \
    /NAdmin \
    /DumpCfg "./.bin/${EXTENSION_NAME}_${VERSION}.cfe" -Extension "${EXTENSION_NAME}"; then
    STEP_SEC=$(( $(date +%s) - STEP_START_TS ))
    echo "[4/4] Выгрузка завершена успешно: ./.bin/${EXTENSION_NAME}_${VERSION}.cfe (шаг: $(fmt_duration "$STEP_SEC"))"
else
    echo "[4/4] Ошибка при выгрузке!"
    exit 1
fi

DEPLOY_TOTAL_SEC=$(( $(date +%s) - DEPLOY_START_TS ))
echo "=== Деплой завершен успешно (всего: $(fmt_duration "$DEPLOY_TOTAL_SEC")) ==="
