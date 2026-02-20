#!/bin/bash
# Скрипт деплоя расширения ikon_cost_Доработки в тестовую базу

set -e  # Остановить при ошибке

echo "=== Деплой ikon_cost_Доработки в TEST_ERP_BRZ_01 ==="
echo "[1/3] Загрузка конфигурации из файлов..."

/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /LoadConfigFromFiles /mnt/e/git/ikon_fact_cost \
    -Extension ikon_cost_Доработки

if [ $? -eq 0 ]; then
    echo "[1/3] Загрузка конфигурации завершена успешно"
else
    echo "[1/3] Ошибка при загрузке конфигурации!"
    exit 1
fi

echo "[2/3] Обновление структуры БД..."
sleep 60

/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /UpdateDBCfg \
    -Extension ikon_cost_Доработки

if [ $? -eq 0 ]; then
    echo "[2/3] Обновление структуры БД завершено успешно"
else
    echo "[2/3] Ошибка при обновлении структуры БД!"
    exit 1
fi

echo "[3/3] Очистка журнала регистрации..."
sleep 60

/opt/1cv8/x86_64/8.3.27.1936/1cv8s DESIGNER \
    /S PGORODILOV.WSL/TEST_ERP_BRZ_01 \
    /NAdmin \
    /ReduceEventLogSize $(date -d tomorrow +%Y-%m-%d)

if [ $? -eq 0 ]; then
    echo "[3/3] Очистка журнала регистрации завершена"
else
    echo "[3/3] Ошибка при очистке журнала регистрации!"
    exit 1
fi

echo "=== Деплой завершен успешно ==="
