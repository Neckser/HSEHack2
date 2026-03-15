#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
echo -e "${BLUE}│   🤖 AI Bully Agent - Запуск        │${NC}"
echo -e "${BLUE}└─────────────────────────────────────┘${NC}"

# Функция проверки ошибок
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Ошибка: $1${NC}"
        exit 1
    fi
}

# 1. Проверяем наличие Docker
echo -e "\n${GREEN}📦 Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker не установлен${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker найден${NC}"

# 2. Проверяем наличие Go
echo -e "\n${GREEN}🦫 Проверка Go...${NC}"
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Go не установлен${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Go найден${NC}"

# 3. Создаем необходимые папки
echo -e "\n${GREEN}📁 Создание папок...${NC}"
mkdir -p screenshots logs bin
echo -e "${GREEN}✅ Папки созданы${NC}"

# 4. Проверяем наличие .env файла
echo -e "\n${GREEN}🔑 Проверка .env файла...${NC}"
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env файл не найден${NC}"
    echo "Создаю шаблон .env..."
    cat > .env << EOF
# ===== ОБЩИЕ НАСТРОЙКИ =====
USER_ID=hackathon-participant

# ===== RABBITMQ =====
RABBITMQ_URL_HOST=amqp://guest:guest@localhost:5672
RABBITMQ_URL_DOCKER=amqp://guest:guest@rabbitmq:5672

# ===== АНАЛИЗАТОР =====
OPENROUTER_API_KEY=твой_ключ_сюда
MODEL_NAME=openai/gpt-4o
POLL_INTERVAL_SECONDS=15
DEBUG=true

# ===== СКРИНШОТЕР =====
CAPTURE_INTERVAL=5m
EOF
    echo -e "${RED}⚠️  Пожалуйста, отредактируй .env и добавь свой OPENROUTER_API_KEY${NC}"
    exit 1
fi
echo -e "${GREEN}✅ .env найден${NC}"

# Загружаем переменные из .env
source .env

# 5. Проверяем API ключ
if [ "$OPENROUTER_API_KEY" = "твой_ключ_сюда" ] || [ -z "$OPENROUTER_API_KEY" ]; then
    echo -e "${RED}❌ OPENROUTER_API_KEY не установлен в .env файле${NC}"
    exit 1
fi

# 6. Останавливаем старые контейнеры
echo -e "\n${GREEN}🛑 Остановка старых контейнеров...${NC}"
docker-compose down --remove-orphans 2>/dev/null
echo -e "${GREEN}✅ Готово${NC}"

# 7. Запускаем Docker сервисы (RabbitMQ и Analyzer)
echo -e "\n${GREEN}🐳 Запуск Docker сервисов...${NC}"
# Передаем переменные из .env в docker-compose
export RABBITMQ_URL_DOCKER MODEL_NAME OPENROUTER_API_KEY POLL_INTERVAL_SECONDS DEBUG
docker-compose up -d --build
check_error "Не удалось запустить Docker сервисы"

# 8. Ждем пока RabbitMQ полностью запустится
echo -e "\n${GREEN}⏳ Ожидание RabbitMQ...${NC}"
sleep 10

# 9. Проверяем что RabbitMQ работает
if ! curl -s http://localhost:15672 > /dev/null; then
    echo -e "${RED}❌ RabbitMQ не запустился${NC}"
    docker-compose logs rabbitmq
    exit 1
fi
echo -e "${GREEN}✅ RabbitMQ работает (порт 5672, веб-интерфейс: http://localhost:15672)${NC}"

# 10. Собираем Go сервисы
echo -e "\n${GREEN}🔨 Сборка Go сервисов...${NC}"

cd services/screener
go mod tidy
go build -o ../../bin/screener main.go
check_error "Ошибка сборки screener"

cd ../notifier
go mod tidy
go build -o ../../bin/notifier main.go
check_error "Ошибка сборки notifier"

cd ../..
echo -e "${GREEN}✅ Go сервисы собраны${NC}"

# 11. Запускаем сервисы на хосте (с переменными из .env)
echo -e "\n${GREEN}🚀 Запуск сервисов на хосте...${NC}"

# Запускаем screener
echo -e "${BLUE}📸 Запуск Screener...${NC}"
export RABBITMQ_URL="$RABBITMQ_URL_HOST"  # для хоста используем localhost
export USER_ID CAPTURE_INTERVAL
./bin/screener > logs/screener.log 2>&1 &
SCREENER_PID=$!
echo -e "${GREEN}  ✅ Screener PID: $SCREENER_PID${NC}"

# Запускаем notifier
echo -e "${BLUE}🔔 Запуск Notifier...${NC}"
export RABBITMQ_URL="$RABBITMQ_URL_HOST"  # для хоста используем localhost
./bin/notifier > logs/notifier.log 2>&1 &
NOTIFIER_PID=$!
echo -e "${GREEN}  ✅ Notifier PID: $NOTIFIER_PID${NC}"

# Сохраняем PID'ы
echo "$SCREENER_PID" > logs/screener.pid
echo "$NOTIFIER_PID" > logs/notifier.pid

echo -e "\n${GREEN}┌─────────────────────────────────────┐${NC}"
echo -e "${GREEN}│   ✅ ВСЕ СЕРВИСЫ ЗАПУЩЕНЫ          │${NC}"
echo -e "${GREEN}└─────────────────────────────────────┘${NC}"
echo -e "\n${BLUE}📊 Информация:${NC}"
echo "  • Screener PID: $SCREENER_PID"
echo "  • Notifier PID: $NOTIFIER_PID"
echo "  • RabbitMQ UI: http://localhost:15672 (guest/guest)"
echo "  • Логи: папка ./logs/"
echo -e "\n${YELLOW}📝 Для просмотра логов:${NC}"
echo "  tail -f logs/screener.log"
echo "  tail -f logs/notifier.log"
echo -e "\n${RED}🛑 Для остановки:${NC}"
echo "  ./stop.sh"