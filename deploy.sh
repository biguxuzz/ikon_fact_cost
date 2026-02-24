#!/bin/bash
# Скрипт деплоя расширения ikon_cost_Доработки в тестовую базу

set -e # Остановить при ошибке

# Чтение версии расширения из Configuration.xml через Python
VERSION=$(grep -oP '(?<=Version>)[^<]*' /mnt/e/git/ikon_fact_cost/Configuration.xml | head -1 | tr -d '\n')

if [ -z "$VERSION" ]; then
    echo "Ошибка: не удалось прочитать версию из Configuration.xml"
    exit 1
fi

echo "=== Деплой ikon_cost_Доработки v${VERSION} в TEST_ERP_BRZ_01 ==="

echo "[1/4] Загрузка конфигурации из файлов..."
/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /LoadConfigFromFiles /mnt/e/git/ikon_fact_cost \
    -Extension ikon_cost_Доработки

if [ $? -eq 0 ]; then
    echo "[1/4] Загрузка конфигурации завершена успешно"
else
    echo "[1/4] Ошибка при загрузке конфигурации!"
    exit 1
fi

sleep 60

echo "[2/4] Обновление структуры БД..."
/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /UpdateDBCfg \
    -Extension ikon_cost_Доработки

if [ $? -eq 0 ]; then
    echo "[2/4] Обновление структуры БД завершено успешно"
else
    echo "[2/4] Ошибка при обновлении структуры БД!"
    exit 1
fi

sleep 60

echo "[3/4] Очистка журнала регистрации..."
/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /ReduceEventLogSize $(date -d tomorrow +%Y-%m-%d)

if [ $? -eq 0 ]; then
    echo "[3/4] Очистка журнала регистрации завершена"
else
    echo "[3/4] Ошибка при очистке журнала регистрации!"
    exit 1
fi

sleep 60

echo "[4/4] Выгрузка расширения в файл (артефакт сборки для прод)..."
/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /DumpCfg ./.bin/ikon_cost_Доработки_${VERSION}.cfe -Extension ikon_cost_Доработки

if [ $? -eq 0 ]; then
    echo "[4/4] Выгрузка завершена успешно: ./.bin/ikon_cost_Доработки_${VERSION}.cfe"
else
    echo "[4/4] Ошибка при выгрузке!"
    exit 1
fi

echo "=== Деплой завершен успешно ==="
