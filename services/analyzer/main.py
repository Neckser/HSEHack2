import os
import json
import base64
import time
from pathlib import Path
from collections import deque
from openai import OpenAI
import pika

# =========================
# НАСТРОЙКИ ИЗ ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# =========================

OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
MODEL_NAME = os.getenv("MODEL_NAME", "openai/gpt-4o")
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672")
MEMORY_SIZE = int(os.getenv("MEMORY_SIZE", "5"))
DEBUG = os.getenv("DEBUG", "true").lower() == "true"

YOUR_PROMPT = """
- определи, что происходит на экране
- учитывай предыдущие 4-5 скриншотов как контекст
- Ты язвительный AI-комментатор. Тон: саркастичный, холодный, пассивно-агрессивный, и агрессивный.
Комментарии короткие, 1–2 фразы. Фокусируйся на действиях и ошибках, следи за тем, чтобы пользователь был всегда продуктивен. Хейти его если он не знает каких-то базовых вещей. Используй мат, но цензурируй его звездочками.
Используй мемы для язвительности.
- не раскрывай пароли, токены, номера карт
"""

# =========================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# =========================
# ТЕПЕРЬ ХРАНИМ DATA URL, А НЕ ПУТИ К ФАЙЛАМ!
memory_store = deque(maxlen=MEMORY_SIZE)

# =========================
# КЛИЕНТ OPENROUTER
# =========================

client = OpenAI(
    api_key=OPENROUTER_API_KEY,
    base_url="https://openrouter.ai/api/v1",
)


# =========================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =========================

def log(*args):
    if DEBUG:
        print("[DEBUG]", *args)


def ensure_api_key():
    if not OPENROUTER_API_KEY or OPENROUTER_API_KEY == "PASTE_YOUR_OPENROUTER_KEY_HERE":
        raise ValueError("Заполни OPENROUTER_API_KEY в коде.")


def is_image_file(path: Path) -> bool:
    return path.suffix.lower() in [".png", ".jpg", ".jpeg", ".webp"]


def guess_mime_type(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".png":
        return "image/png"
    if suffix in [".jpg", ".jpeg"]:
        return "image/jpeg"
    if suffix == ".webp":
        return "image/webp"
    return "application/octet-stream"


def image_to_data_url(image_path: str) -> str:
    """Конвертирует файл в data URL"""
    mime_type = guess_mime_type(image_path)

    with open(image_path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("utf-8")

    return f"data:{mime_type};base64,{encoded}"


def base64_to_data_url(base64_data: str) -> str:
    """Конвертирует base64 строку в data URL (для хранения в памяти)"""
    return f"data:image/png;base64,{base64_data}"


def save_temp_image(base64_data: str, timestamp: int) -> str:
    """Сохраняет base64 во временный файл и возвращает путь"""
    temp_dir = Path("/tmp/screenshots")
    temp_dir.mkdir(exist_ok=True, parents=True)
    
    filename = f"screen_{timestamp}.png"
    filepath = temp_dir / filename
    
    image_data = base64.b64decode(base64_data)
    with open(filepath, "wb") as f:
        f.write(image_data)
    
    return str(filepath)


def build_messages(current_image_path: str, memory_urls: list[str]) -> list[dict]:
    """Строит сообщения для API, используя data URL из памяти"""
    content = []

    content.append({
        "type": "text",
        "text": YOUR_PROMPT.strip()
    })

    if memory_urls:
        content.append({
            "type": "text",
            "text": (
                f"Ниже приложены {len(memory_urls)} предыдущих скриншотов. "
                f"Используй их только как контекст, чтобы понять динамику происходящего."
            )
        })

        for idx, old_url in enumerate(memory_urls, start=1):
            content.append({
                "type": "text",
                "text": f"Предыдущий скриншот #{idx}"
            })
            content.append({
                "type": "image_url",
                "image_url": {
                    "url": old_url  # Используем URL из памяти
                }
            })

    content.append({
        "type": "text",
        "text": "Текущий скриншот"
    })
    content.append({
        "type": "image_url",
        "image_url": {
            "url": image_to_data_url(current_image_path)  # Текущий из файла
        }
    })

    return [
        {
            "role": "user",
            "content": content
        }
    ]


def call_model(current_image_path: str, memory_urls: list[str]) -> str:
    """Вызывает модель с учетом истории из memory_urls"""
    messages = build_messages(current_image_path, memory_urls)

    response = client.chat.completions.create(
        model=MODEL_NAME,
        messages=messages,
        temperature=0.7,
        max_tokens=200,
    )

    text = response.choices[0].message.content
    if not text:
        return ""

    return text.strip()


def analyze_single_file(image_path: str, memory_urls: deque, current_base64: str) -> str:
    """
    Анализирует файл с учетом истории.
    memory_urls содержит data URL предыдущих скриншотов
    """
    previous_urls = list(memory_urls)
    result = call_model(image_path, previous_urls)
    
    # Добавляем текущий скриншот в историю как data URL (НЕ путь к файлу!)
    current_url = base64_to_data_url(current_base64)
    memory_urls.append(current_url)
    
    return result


# =========================
# ОБРАБОТЧИК СООБЩЕНИЙ ИЗ RABBITMQ
# =========================

def process_rabbit_message(ch, method, properties, body):
    """Обработчик сообщений из RabbitMQ"""
    global memory_store
    
    try:
        # Получаем данные от скринера
        data = json.loads(body)
        
        print(f"\n📥 Получен скриншот от {data.get('user_id', 'unknown')}")
        print(f"🪟 Окно: {data.get('window_title', 'unknown')}")
        
        # Сохраняем временный файл (только для текущего анализа)
        timestamp = int(time.time())
        image_path = save_temp_image(data['image_base64'], timestamp)
        
        # Анализируем через OpenRouter (передаем и base64 для истории)
        print("🤔 Анализирую...")
        result = analyze_single_file(image_path, memory_store, data['image_base64'])
        
        print(f"💬 Результат: {result}")
        
        # Отправляем результат в очередь results для notifier
        try:
            # Создаем отдельный канал для отправки
            result_ch = ch.connection.channel()
            result_ch.queue_declare(queue='results', durable=True)
            
            result_data = {
                'user_id': data.get('user_id'),
                'message': result,
                'timestamp': timestamp,
                'window_title': data.get('window_title')
            }
            
            result_ch.basic_publish(
                exchange='',
                routing_key='results',
                body=json.dumps(result_data),
                properties=pika.BasicProperties(
                    content_type='application/json',
                    delivery_mode=2  # persistent
                )
            )
            result_ch.close()
            print("📤 Результат отправлен в очередь results")
            
        except Exception as e:
            print(f"[ERROR] Ошибка отправки результата: {e}")
        
        # Удаляем временный файл (он больше не нужен)
        try:
            os.remove(image_path)
            print(f"🗑️ Временный файл удален")
        except Exception as e:
            print(f"⚠️ Не удалось удалить файл: {e}")
        
        # Подтверждаем обработку сообщения
        ch.basic_ack(delivery_tag=method.delivery_tag)
        
    except Exception as e:
        print(f"[ERROR] {e}")
        import traceback
        traceback.print_exc()
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


# =========================
# ЗАПУСК
# =========================

if __name__ == "__main__":
    ensure_api_key()
    
    print(f"🔌 Подключение к RabbitMQ: {RABBITMQ_URL}")
    
    try:
        # Подключаемся к RabbitMQ
        params = pika.URLParameters(RABBITMQ_URL)
        connection = pika.BlockingConnection(params)
        channel = connection.channel()
        
        # Объявляем очереди
        channel.queue_declare(queue='screenshots', durable=True)
        channel.queue_declare(queue='results', durable=True)
        
        # Берем по одному сообщению
        channel.basic_qos(prefetch_count=1)
        
        # Подписываемся на очередь скриншотов
        channel.basic_consume(
            queue='screenshots',
            on_message_callback=process_rabbit_message
        )
        
        print("🚀 Analyzer запущен. Ожидание скриншотов из RabbitMQ...")
        print("-" * 50)
        
        # Начинаем слушать
        channel.start_consuming()
        
    except KeyboardInterrupt:
        print("\n🛑 Остановлен")
    except Exception as e:
        print(f"❌ Ошибка: {e}")