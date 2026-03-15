@echo off
setlocal enabledelayedexpansion

:: Цвета для вывода (в Windows немного сложнее, но можно использовать цвета)
echo.
echo ┌─────────────────────────────────────┐
echo │   🤖 AI Bully Agent - Запуск        │
echo └─────────────────────────────────────┘
echo.

:: Функция проверки ошибок (в бат-файлах своя логика)
set "ERROR_FLAG=0"

:: Определяем архитектуру
echo 📦 Проверка системы...
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    echo ✅ 64-битная система
) else if "%PROCESSOR_ARCHITECTURE%"=="x86" (
    echo ✅ 32-битная система
) else (
    echo ❌ Неизвестная архитектура
    exit /b 1
)

:: 1. Проверяем наличие Docker
echo.
echo 📦 Проверка Docker...
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Docker не установлен
    echo Установи Docker: https://docs.docker.com/desktop/windows/install/
    exit /b 1
) else (
    echo ✅ Docker найден
)

:: 2. Проверяем наличие Go
echo.
echo 🦫 Проверка Go...
go version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Go не установлен
    echo Установи Go: https://golang.org/dl/
    exit /b 1
) else (
    echo ✅ Go найден
)

:: 3. Проверяем PowerShell (должен быть всегда)
echo.
echo 🔍 Проверка PowerShell...
powershell -Command "Get-ExecutionPolicy" >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ PowerShell не найден или недоступен
    exit /b 1
) else (
    echo ✅ PowerShell найден
    
    :: Проверяем политику выполнения скриптов
    for /f "tokens=*" %%i in ('powershell -Command "Get-ExecutionPolicy"') do set EXEC_POLICY=%%i
    echo    Текущая политика: !EXEC_POLICY!
    if "!EXEC_POLICY!"=="Restricted" (
        echo ⚠️  Политика выполнения скриптов ограничена
        echo    Рекомендуется запустить PowerShell от администратора:
        echo    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    )
)

:: 4. Создаем необходимые папки
echo.
echo 📁 Создание папок...
if not exist screenshots mkdir screenshots
if not exist logs mkdir logs
if not exist bin mkdir bin
echo ✅ Папки созданы

:: 5. Проверяем наличие .env файла
echo.
echo 🔑 Проверка .env файла...
if not exist .env (
    echo ❌ .env файл не найден
    echo Создаю шаблон .env...
    
    (
        echo # ===== ОБЩИЕ НАСТРОЙКИ =====
        echo USER_ID=hackathon-participant
        echo.
        echo # ===== RABBITMQ =====
        echo RABBITMQ_URL_HOST=amqp://guest:guest@localhost:5672
        echo RABBITMQ_URL_DOCKER=amqp://guest:guest@rabbitmq:5672
        echo.
        echo # ===== АНАЛИЗАТОР =====
        echo OPENROUTER_API_KEY=твой_ключ_сюда
        echo MODEL_NAME=openai/gpt-4o
        echo POLL_INTERVAL_SECONDS=15
        echo DEBUG=true
        echo.
        echo # ===== СКРИНШОТЕР =====
        echo CAPTURE_INTERVAL=30s
    ) > .env
    
    echo ⚠️  Пожалуйста, отредактируй .env и добавь свой OPENROUTER_API_KEY
    exit /b 1
)
echo ✅ .env найден

:: Загружаем переменные из .env
for /f "tokens=1,2 delims==" %%a in (.env) do (
    if not "%%a"=="" if not "%%a:~0,1"=="#" (
        set "%%a=%%b"
    )
)

:: 6. Проверяем API ключ
echo.
if "%OPENROUTER_API_KEY%"=="твой_ключ_сюда" (
    echo ❌ OPENROUTER_API_KEY не установлен в .env файле
    exit /b 1
)
if "%OPENROUTER_API_KEY%"=="" (
    echo ❌ OPENROUTER_API_KEY не установлен в .env файле
    exit /b 1
)
echo ✅ API ключ проверен

:: 7. Останавливаем старые контейнеры
echo.
echo 🛑 Остановка старых контейнеров...
docker-compose down --remove-orphans 2>nul
echo ✅ Готово

:: 8. Запускаем Docker сервисы (RabbitMQ и Analyzer)
echo.
echo 🐳 Запуск Docker сервисов...
set RABBITMQ_URL_DOCKER=%RABBITMQ_URL_DOCKER%
set MODEL_NAME=%MODEL_NAME%
set OPENROUTER_API_KEY=%OPENROUTER_API_KEY%
set POLL_INTERVAL_SECONDS=%POLL_INTERVAL_SECONDS%
set DEBUG=%DEBUG%

docker-compose up -d --build
if %errorlevel% neq 0 (
    echo ❌ Не удалось запустить Docker сервисы
    exit /b 1
)

:: 9. Ждем пока RabbitMQ запустится
echo.
echo ⏳ Ожидание RabbitMQ...
timeout /t 10 /nobreak >nul

:: 10. Проверяем RabbitMQ
echo.
curl -s http://localhost:15672 >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ RabbitMQ не запустился
    docker-compose logs rabbitmq
    exit /b 1
) else (
    echo ✅ RabbitMQ работает ^(порт 5672, веб-интерфейс: http://localhost:15672^)
)

:: 11. Собираем Go сервисы
echo.
echo 🔨 Сборка Go сервисов...

cd services\screener
go mod tidy
go build -o ..\..\bin\screener.exe main.go
if %errorlevel% neq 0 (
    echo ❌ Ошибка сборки screener
    exit /b 1
)

cd ..\notifier
go mod tidy
go build -o ..\..\bin\notifier.exe main.go
if %errorlevel% neq 0 (
    echo ❌ Ошибка сборки notifier
    exit /b 1
)

cd ..\..
echo ✅ Go сервисы собраны

:: 12. Запускаем сервисы на хосте
echo.
echo 🚀 Запуск сервисов на хосте...

:: Запускаем screener
echo.
echo 📸 Запуск Screener...
set RABBITMQ_URL=%RABBITMQ_URL_HOST%
set USER_ID=%USER_ID%
set CAPTURE_INTERVAL=%CAPTURE_INTERVAL%

start /B bin\screener.exe > logs\screener.log 2>&1
set SCREENER_PID=%errorlevel%
echo   ✅ Screener запущен

:: Запускаем notifier
echo.
echo 🔔 Запуск Notifier...
set RABBITMQ_URL=%RABBITMQ_URL_HOST%
start /B bin\notifier.exe > logs\notifier.log 2>&1
set NOTIFIER_PID=%errorlevel%
echo   ✅ Notifier запущен

:: Сохраняем PID'ы (в Windows это сложнее, просто для информации)
echo %SCREENER_PID% > logs\screener.pid 2>nul
echo %NOTIFIER_PID% > logs\notifier.pid 2>nul

echo.
echo ┌─────────────────────────────────────┐
echo │   ✅ ВСЕ СЕРВИСЫ ЗАПУЩЕНЫ          │
echo └─────────────────────────────────────┘
echo.
echo 📊 Информация:
echo   • Screener запущен
echo   • Notifier запущен
echo   • RabbitMQ UI: http://localhost:15672 (guest/guest)
echo   • Логи: папка .\logs\
echo.
echo 📝 Для просмотра логов:
echo   type logs\screener.log
echo   type logs\notifier.log
echo.
echo 🛑 Для остановки:
echo   stop.bat