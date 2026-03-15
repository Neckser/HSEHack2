package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"

	"github.com/joho/godotenv"
	"github.com/robfig/cron/v3"
	"github.com/streadway/amqp"
)

type ScreenshotData struct {
	UserID      string    `json:"user_id"`
	Timestamp   time.Time `json:"timestamp"`
	ImageBase64 string    `json:"image_base64"`
	WindowTitle string    `json:"window_title"`
	ProcessName string    `json:"process_name"`
}

// =========================
// ПОЛУЧЕНИЕ НАЗВАНИЯ АКТИВНОГО ОКНА (кросс-платформенно)
// =========================

func getWindowTitle() string {
	switch runtime.GOOS {
	case "darwin": // macOS
		cmd := exec.Command("osascript", "-e",
			"tell application \"System Events\" to get name of first process whose frontmost is true")
		if output, err := cmd.Output(); err == nil {
			return string(output)
		}
	case "linux":
		// Пробуем xdotool (должен быть установлен)
		cmd := exec.Command("xdotool", "getwindowfocus", "getwindowname")
		if output, err := cmd.Output(); err == nil {
			return string(output)
		}
		// Fallback на wmctrl
		cmd = exec.Command("sh", "-c", "wmctrl -a :ACTIVE: -v 2>&1 | grep 'Using window' | awk '{print $NF}'")
		if output, err := cmd.Output(); err == nil {
			return string(output)
		}
	case "windows":
		// PowerShell команда для получения активного окна
		cmd := exec.Command("powershell", "-command",
			"(Get-Process | Where-Object { $_.MainWindowHandle -eq (GetForegroundWindow) }).MainWindowTitle")
		if output, err := cmd.Output(); err == nil {
			return string(output)
		}
	}
	return "unknown"
}

// =========================
// СКРИНШОТЫ (кросс-платформенно)
// =========================

// Для macOS используем встроенную команду screencapture
func takeScreenshotMacOS(dir string) (string, string, error) {
	os.MkdirAll(dir, 0755)

	filename := fmt.Sprintf("screen_%d.png", time.Now().Unix())
	filepath := filepath.Join(dir, filename)

	// -x = без звука, -t png = формат, -T<сек> = задержка (0)
	cmd := exec.Command("screencapture", "-x", "-t", "png", filepath)
	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("screencapture failed: %v", err)
	}

	// Проверяем что файл создался
	if _, err := os.Stat(filepath); os.IsNotExist(err) {
		return "", "", fmt.Errorf("screenshot file was not created")
	}

	bytes, err := ioutil.ReadFile(filepath)
	if err != nil {
		return filepath, "", fmt.Errorf("failed to read file: %v", err)
	}

	base64str := base64.StdEncoding.EncodeToString(bytes)
	return filepath, base64str, nil
}

// Для Linux используем import (imagemagick) или gnome-screenshot
func takeScreenshotLinux(dir string) (string, string, error) {
	os.MkdirAll(dir, 0755)

	filename := fmt.Sprintf("screen_%d.png", time.Now().Unix())
	filepath := filepath.Join(dir, filename)

	// Пробуем разные утилиты для скриншотов в Linux
	var cmd *exec.Cmd

	// Способ 1: import (ImageMagick)
	if _, err := exec.LookPath("import"); err == nil {
		cmd = exec.Command("import", "-window", "root", filepath)
	} else if _, err := exec.LookPath("gnome-screenshot"); err == nil {
		// Способ 2: gnome-screenshot
		cmd = exec.Command("gnome-screenshot", "-f", filepath)
	} else if _, err := exec.LookPath("scrot"); err == nil {
		// Способ 3: scrot
		cmd = exec.Command("scrot", filepath)
	} else {
		return "", "", fmt.Errorf("no screenshot tool found (install imagemagick, gnome-screenshot, or scrot)")
	}

	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("screenshot failed: %v", err)
	}

	// Проверяем что файл создался
	if _, err := os.Stat(filepath); os.IsNotExist(err) {
		return "", "", fmt.Errorf("screenshot file was not created")
	}

	bytes, err := ioutil.ReadFile(filepath)
	if err != nil {
		return filepath, "", fmt.Errorf("failed to read file: %v", err)
	}

	base64str := base64.StdEncoding.EncodeToString(bytes)
	return filepath, base64str, nil
}

// Для Windows используем PowerShell
func takeScreenshotWindows(dir string) (string, string, error) {
	os.MkdirAll(dir, 0755)

	filename := fmt.Sprintf("screen_%d.png", time.Now().Unix())
	filepath := filepath.Join(dir, filename)

	// PowerShell скрипт для скриншота через .NET
	psScript := fmt.Sprintf(`
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.X, $screen.Y, 0, 0, $screen.Size)
$bitmap.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png)
`, filepath)

	cmd := exec.Command("powershell", "-command", psScript)
	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("powershell screenshot failed: %v", err)
	}

	// Проверяем что файл создался
	if _, err := os.Stat(filepath); os.IsNotExist(err) {
		return "", "", fmt.Errorf("screenshot file was not created")
	}

	bytes, err := ioutil.ReadFile(filepath)
	if err != nil {
		return filepath, "", fmt.Errorf("failed to read file: %v", err)
	}

	base64str := base64.StdEncoding.EncodeToString(bytes)
	return filepath, base64str, nil
}

// Основная функция скриншота, выбирающая реализацию под ОС
func takeScreenshot(dir string) (string, string, error) {
	switch runtime.GOOS {
	case "darwin":
		return takeScreenshotMacOS(dir)
	case "linux":
		return takeScreenshotLinux(dir)
	case "windows":
		return takeScreenshotWindows(dir)
	default:
		return "", "", fmt.Errorf("OS %s not supported", runtime.GOOS)
	}
}

// =========================
// MAIN
// =========================

func main() {
	// Загружаем .env если есть
	godotenv.Load()

	// ===== НАСТРОЙКИ RABBITMQ =====
	rabbitURL := os.Getenv("RABBITMQ_URL")
	if rabbitURL == "" {
		rabbitURL = "amqp://guest:guest@localhost:5672"
	}

	interval := os.Getenv("CAPTURE_INTERVAL")
	if interval == "" {
		interval = "5m"
	}

	userID := os.Getenv("USER_ID")
	if userID == "" {
		userID = "hacker"
	}

	screenshotDir := "./screenshots"

	// ===== ПОДКЛЮЧЕНИЕ К RABBITMQ =====
	log.Printf("🔌 Подключение к RabbitMQ: %s", rabbitURL)

	conn, err := amqp.Dial(rabbitURL)
	if err != nil {
		log.Fatal("❌ RabbitMQ connection failed:", err)
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		log.Fatal("❌ Channel creation failed:", err)
	}
	defer ch.Close()

	q, err := ch.QueueDeclare("screenshots", true, false, false, false, nil)
	if err != nil {
		log.Fatal("❌ Queue declaration failed:", err)
	}

	log.Printf("📦 Очередь готова: %s", q.Name)
	log.Printf("📸 Screenshot service starting...")
	log.Printf("🕒 Interval: %s", interval)
	log.Printf("📁 Saving to: %s", screenshotDir)
	log.Printf("👤 User: %s", userID)
	log.Printf("💻 OS: %s", runtime.GOOS)

	// Функция скриншота и отправки в RabbitMQ
	job := func() {
		title := getWindowTitle()
		log.Printf("📸 Taking screenshot... (window: %s)", title)

		path, base64img, err := takeScreenshot(screenshotDir)
		if err != nil {
			log.Println("❌ Screenshot failed:", err)
			return
		}

		log.Printf("✅ Saved: %s", path)
		log.Printf("📊 Size: %d bytes", len(base64img))

		// Отправка в RabbitMQ
		msg := ScreenshotData{
			UserID:      userID,
			Timestamp:   time.Now(),
			ImageBase64: base64img,
			WindowTitle: title,
			ProcessName: runtime.GOOS,
		}

		body, _ := json.Marshal(msg)

		err = ch.Publish("", q.Name, false, false,
			amqp.Publishing{
				ContentType:  "application/json",
				Body:         body,
				DeliveryMode: amqp.Persistent,
			})

		if err != nil {
			log.Println("❌ Failed to send to RabbitMQ:", err)
		} else {
			log.Println("📤 Sent to RabbitMQ")
		}
	}

	// Первый сразу
	job()

	// По расписанию
	c := cron.New()
	c.AddFunc("@every "+interval, job)
	c.Start()

	log.Println("🚀 Service running. Press Ctrl+C to stop")
	select {}
}
