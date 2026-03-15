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

# Функция определения ОС
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            echo "linux"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS=$(detect_os)
echo -e "${GREEN}💻 Обнаружена ОС: $OS${NC}"

# =========================
# УСТАНОВКА ЗАВИСИМОСТЕЙ ДЛЯ РАЗНЫХ ОС
# =========================

install_dependencies() {
    echo -e "\n${GREEN}📦 Проверка и установка зависимостей...${NC}"
    
    case $OS in
        "macos")
            # macOS - проверяем наличие osascript и screencapture (встроенные)
            if ! command -v osascript &> /dev/null; then
                echo -e "${RED}❌ osascript не найден! Это странно для macOS...${NC}"
                exit 1
            else
                echo -e "${GREEN}✅ osascript найден${NC}"
            fi
            
            if ! command -v screencapture &> /dev/null; then
                echo -e "${RED}❌ screencapture не найден! Это странно для macOS...${NC}"
                exit 1
            else
                echo -e "${GREEN}✅ screencapture найден${NC}"
            fi
            ;;
            
        "linux")
            # Linux - проверяем и устанавливаем нужные пакеты
            echo -e "${YELLOW}🔍 Проверка инструментов для Linux...${NC}"
            
            # Определяем пакетный менеджер
            if command -v apt-get &> /dev/null; then
                PKG_MANAGER="apt"
                INSTALL_CMD="sudo apt-get install -y"
                UPDATE_CMD="sudo apt-get update"
            elif command -v yum &> /dev/null; then
                PKG_MANAGER="yum"
                INSTALL_CMD="sudo yum install -y"
                UPDATE_CMD="sudo yum check-update"
            elif command -v pacman &> /dev/null; then
                PKG_MANAGER="pacman"
                INSTALL_CMD="sudo pacman -S --noconfirm"
                UPDATE_CMD="sudo pacman -Sy"
            else
                echo -e "${RED}❌ Неизвестный пакетный менеджер${NC}"
                exit 1
            fi
            
            # Список пакетов для установки
            PACKAGES=""
            
            # ДЛЯ СКРИНШОТОВ (screener)
            if ! command -v import &> /dev/null && ! command -v gnome-screenshot &> /dev/null && ! command -v scrot &> /dev/null; then
                echo -e "${YELLOW}⚠️ Не найден инструмент для скриншотов${NC}"
                PACKAGES="$PACKAGES imagemagick"
            else
                echo -e "${GREEN}✅ Инструмент для скриншотов найден${NC}"
            fi
            
            # ДЛЯ ПОЛУЧЕНИЯ НАЗВАНИЯ ОКНА (screener)
            if ! command -v xdotool &> /dev/null; then
                echo -e "${YELLOW}⚠️ xdotool не найден (нужен для получения названия окна)${NC}"
                PACKAGES="$PACKAGES xdotool"
            else
                echo -e "${GREEN}✅ xdotool найден${NC}"
            fi
            
            if ! command -v wmctrl &> /dev/null; then
                echo -e "${YELLOW}⚠️ wmctrl не найден (запасной вариант для названия окна)${NC}"
                PACKAGES="$PACKAGES wmctrl"
            else
                echo -e "${GREEN}✅ wmctrl найден${NC}"
            fi
            
            # ДЛЯ УВЕДОМЛЕНИЙ (notifier)
            if ! command -v notify-send &> /dev/null; then
                echo -e "${YELLOW}⚠️ notify-send не найден (нужен для уведомлений)${NC}"
                # В разных дистрибутивах пакет называется по-разному
                case $PKG_MANAGER in
                    "apt") PACKAGES="$PACKAGES libnotify-bin" ;;
                    "yum") PACKAGES="$PACKAGES libnotify" ;;
                    "pacman") PACKAGES="$PACKAGES libnotify" ;;
                esac
            else
                echo -e "${GREEN}✅ notify-send найден${NC}"
            fi
            
            # Устанавливаем всё одной командой
            if [ ! -z "$PACKAGES" ]; then
                echo -e "${YELLOW}📦 Установка: $PACKAGES${NC}"
                $UPDATE_CMD
                $INSTALL_CMD $PACKAGES
                check_error "Не удалось установить пакеты"
                echo -e "${GREEN}✅ Пакеты установлены${NC}"
            else
                echo -e "${GREEN}✅ Все зависимости уже есть${NC}"
            fi
            ;;
            
        "windows")
            # Windows - проверяем PowerShell
            if ! command -v powershell &> /dev/null; then
                echo -e "${RED}❌ PowerShell не найден! Это критично для Windows${NC}"
                exit 1
            else
                echo -e "${GREEN}✅ PowerShell найден${NC}"
            fi
            
            # Проверяем, может ли PowerShell выполнять скрипты
            powershell -Command "Get-ExecutionPolicy" | grep -i "RemoteSigned\|Unrestricted" > /dev/null
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}⚠️ Политика выполнения скриптов PowerShell ограничена${NC}"
                echo "Рекомендуется запустить от имени администратора:"
                echo "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
            else
                echo -e "${GREEN}✅ PowerShell настроен правильно${NC}"
            fi
            ;;
            
        *)
            echo -e "${RED}❌ Неподдерживаемая ОС${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✅ Все зависимости установлены${NC}"
}

# =========================
# ОСНОВНОЙ КОД
# =========================

# 1. Проверяем наличие Docker
echo -e "\n${GREEN}📦 Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker не установлен${NC}"
    echo "Установи Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✅ Docker найден${NC}"

# 2. Проверяем наличие Go
echo -e "\n${GREEN}🦫 Проверка Go...${NC}"
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Go не установлен${NC}"
    echo "Установи Go: https://golang.org/dl/"
    exit 1
fi
echo -e "${GREEN}✅ Go найден${NC}"

# 3. Устанавливаем зависимости для ОС
install_dependencies

# 4. Создаем необходимые папки
echo -e "\n${GREEN}📁 Создание папок...${NC}"
mkdir -p screenshots logs bin
echo -e "${GREEN}✅ Папки созданы${NC}"

# 5. Проверяем наличие .env файла
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
CAPTURE_INTERVAL=30s
EOF
    echo -e "${RED}⚠️  Пожалуйста, отредактируй .env и добавь свой OPENROUTER_API_KEY${NC}"
    exit 1
fi
echo -e "${GREEN}✅ .env найден${NC}"

# Загружаем переменные из .env
source .env

# 6. Проверяем API ключ
if [ "$OPENROUTER_API_KEY" = "твой_ключ_сюда" ] || [ -z "$OPENROUTER_API_KEY" ]; then
    echo -e "${RED}❌ OPENROUTER_API_KEY не установлен в .env файле${NC}"
    exit 1
fi

# 7. Останавливаем старые контейнеры
echo -e "\n${GREEN}🛑 Остановка старых контейнеров...${NC}"
docker-compose down --remove-orphans 2>/dev/null
echo -e "${GREEN}✅ Готово${NC}"

# 8. Запускаем Docker сервисы (RabbitMQ и Analyzer)
echo -e "\n${GREEN}🐳 Запуск Docker сервисов...${NC}"
export RABBITMQ_URL_DOCKER MODEL_NAME OPENROUTER_API_KEY POLL_INTERVAL_SECONDS DEBUG
docker-compose up -d --build
check_error "Не удалось запустить Docker сервисы"

# 9. Ждем пока RabbitMQ полностью запустится
echo -e "\n${GREEN}⏳ Ожидание RabbitMQ...${NC}"
sleep 10

# 10. Проверяем что RabbitMQ работает
if ! curl -s http://localhost:15672 > /dev/null; then
    echo -e "${RED}❌ RabbitMQ не запустился${NC}"
    docker-compose logs rabbitmq
    exit 1
fi
echo -e "${GREEN}✅ RabbitMQ работает (порт 5672, веб-интерфейс: http://localhost:15672)${NC}"

# 11. Собираем Go сервисы
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

# 12. Запускаем сервисы на хосте
echo -e "\n${GREEN}🚀 Запуск сервисов на хосте...${NC}"

# Запускаем screener
echo -e "${BLUE}📸 Запуск Screener...${NC}"
export RABBITMQ_URL="$RABBITMQ_URL_HOST"
export USER_ID CAPTURE_INTERVAL
./bin/screener > logs/screener.log 2>&1 &
SCREENER_PID=$!
echo -e "${GREEN}  ✅ Screener PID: $SCREENER_PID${NC}"

# Запускаем notifier
echo -e "${BLUE}🔔 Запуск Notifier...${NC}"
export RABBITMQ_URL="$RABBITMQ_URL_HOST"
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
