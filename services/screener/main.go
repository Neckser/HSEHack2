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
	"github.com/streadway/amqp" // ← ДОБАВИЛИ
)

type ScreenshotData struct {
	UserID      string    `json:"user_id"`
	Timestamp   time.Time `json:"timestamp"`
	ImageBase64 string    `json:"image_base64"`
	WindowTitle string    `json:"window_title"`
	ProcessName string    `json:"process_name"`
}

func getWindowTitle() string {
	switch runtime.GOOS {
	case "darwin":
		cmd := exec.Command("osascript", "-e",
			"tell application \"System Events\" to get name of first process whose frontmost is true")
		output, err := cmd.Output()
		if err == nil {
			return string(output)
		}
	}
	return "unknown"
}

// takeScreenshotUsingMacOS использует встроенную команду macOS screencapture
func takeScreenshotUsingMacOS(dir string) (string, string, error) {
	// Создаем папку если нет
	os.MkdirAll(dir, 0755)

	// Создаем временный файл
	filename := fmt.Sprintf("screen_%d.png", time.Now().Unix())
	filepath := filepath.Join(dir, filename)

	// Используем встроенную команду macOS screencapture
	// -x = без звука, -t png = формат
	cmd := exec.Command("screencapture", "-x", "-t", "png", filepath)
	if err := cmd.Run(); err != nil {
		return "", "", fmt.Errorf("screencapture failed: %v", err)
	}

	// Проверяем что файл создался
	if _, err := os.Stat(filepath); os.IsNotExist(err) {
		return "", "", fmt.Errorf("screenshot file was not created")
	}

	// Читаем файл для base64
	bytes, err := ioutil.ReadFile(filepath)
	if err != nil {
		return filepath, "", fmt.Errorf("failed to read file: %v", err)
	}

	base64str := base64.StdEncoding.EncodeToString(bytes)

	return filepath, base64str, nil
}

// Для Linux/Windows можно добавить другие реализации
func takeScreenshot(dir string) (string, string, error) {
	switch runtime.GOOS {
	case "darwin":
		return takeScreenshotUsingMacOS(dir)
	default:
		return "", "", fmt.Errorf("OS %s not supported yet", runtime.GOOS)
	}
}

func main() {
	// Загружаем .env если есть
	godotenv.Load()

	// ===== НАСТРОЙКИ RABBITMQ =====
	rabbitURL := os.Getenv("RABBITMQ_URL")
	if rabbitURL == "" {
		rabbitURL = "amqp://guest:guest@localhost:5672" // запасной вариант
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

	// Объявляем очередь для скриншотов
	q, err := ch.QueueDeclare(
		"screenshots", // название очереди
		true,          // durable
		false,         // delete when unused
		false,         // exclusive
		false,         // no-wait
		nil,           // arguments
	)
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

		// ===== ОТПРАВКА В RABBITMQ =====
		msg := ScreenshotData{
			UserID:      userID,
			Timestamp:   time.Now(),
			ImageBase64: base64img,
			WindowTitle: title,
			ProcessName: "macOS",
		}

		body, _ := json.Marshal(msg)

		err = ch.Publish(
			"",     // exchange
			q.Name, // routing key (имя очереди)
			false,  // mandatory
			false,  // immediate
			amqp.Publishing{
				ContentType:  "application/json",
				Body:         body,
				DeliveryMode: amqp.Persistent, // сохранять на диск
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
