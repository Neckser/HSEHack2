#!/bin/bash

echo "🛑 Остановка сервисов..."

# Останавливаем Go процессы
if [ -f logs/screener.pid ]; then
    kill $(cat logs/screener.pid) 2>/dev/null
    rm logs/screener.pid
    echo "  ✅ Screener остановлен"
fi

if [ -f logs/notifier.pid ]; then
    kill $(cat logs/notifier.pid) 2>/dev/null
    rm logs/notifier.pid
    echo "  ✅ Notifier остановлен"
fi

# Останавливаем Docker контейнеры
docker-compose down
echo "  ✅ Docker контейнеры остановлены"

echo "✅ Готово!"