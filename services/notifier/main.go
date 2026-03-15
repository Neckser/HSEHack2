package main

import (
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/gen2brain/beeep"
	"github.com/joho/godotenv"
	"github.com/streadway/amqp"
)

// AnalysisResult — структура сообщения из очереди results
type AnalysisResult struct {
	UserID      string `json:"user_id"`
	Message     string `json:"message"` // Текст от AI
	Timestamp   int64  `json:"timestamp"`
	WindowTitle string `json:"window_title"` // Для контекста
}

func main() {
	// Загружаем .env
	godotenv.Load()

	rabbitURL := os.Getenv("RABBITMQ_URL")
	if rabbitURL == "" {
		rabbitURL = "amqp://guest:guest@localhost:5672"
	}

	log.Printf("🔔 Notifier started. Connecting to %s", rabbitURL)
	log.Printf("🥒 Ожидаю 'огурцы' из очереди results...")

	// Подключаемся к RabbitMQ
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

	// Объявляем очередь (должна существовать)
	q, err := ch.QueueDeclare(
		"results", // название очереди
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		log.Fatal("❌ Queue declaration failed:", err)
	}

	// Подписываемся на сообщения
	msgs, err := ch.Consume(
		q.Name, // очередь
		"",     // consumer
		true,   // auto-ack (автоматически подтверждать)
		false,  // exclusive
		false,  // no-local
		false,  // no-wait
		nil,    // args
	)
	if err != nil {
		log.Fatal("❌ Consume failed:", err)
	}

	// Канал для graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Слушаем сообщения в отдельной горутине
	go func() {
		for msg := range msgs {
			var result AnalysisResult
			err := json.Unmarshal(msg.Body, &result)
			if err != nil {
				log.Println("❌ Failed to parse message:", err)
				continue
			}

			// 🥒 ВОТ ТУТ МЫ ВИДИМ, ЧТО ПРИШЛО
			log.Printf("🥒 ОГУРЕЦ! Получено: %s", result.Message)

			// Показываем системное уведомление через beeep
			title := "AI Buller"
			if result.WindowTitle != "" {
				title = title + " (" + result.WindowTitle + ")"
			}

			err = beeep.Notify(title, result.Message, "")
			if err != nil {
				log.Println("⚠️ Failed to show notification:", err)
				// Пробуем без иконки, если проблема в ней
				err = beeep.Notify(title, result.Message, "")
				if err != nil {
					log.Println("⚠️ Second attempt failed:", err)
				}
			} else {
				log.Println("✅ Notification shown")
			}
		}
	}()

	log.Println("🚀 Notifier is running. Press Ctrl+C to stop.")

	// Ждем сигнала остановки
	<-sigChan
	log.Println("👋 Shutting down...")
}
