@echo off
echo 🛑 Остановка сервисов...
echo.

:: Останавливаем Go процессы (screener и notifier)
echo Останавливаю Screener...
taskkill /F /IM screener.exe 2>nul
if %errorlevel% equ 0 (
    echo   ✅ Screener остановлен
) else (
    echo   ⚠️ Screener не найден
)

echo.
echo Останавливаю Notifier...
taskkill /F /IM notifier.exe 2>nul
if %errorlevel% equ 0 (
    echo   ✅ Notifier остановлен
) else (
    echo   ⚠️ Notifier не найден
)

:: Удаляем PID файлы (в Windows они не обязательны, но на всякий случай)
if exist logs\screener.pid del logs\screener.pid
if exist logs\notifier.pid del logs\notifier.pid

echo.
:: Останавливаем Docker контейнеры
echo Останавливаю Docker контейнеры...
docker-compose down
if %errorlevel% equ 0 (
    echo   ✅ Docker контейнеры остановлены
) else (
    echo   ⚠️ Ошибка при остановке Docker контейнеров
)

echo.
echo ✅ Готово!