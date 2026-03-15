import os
import time
import base64
from pathlib import Path
from collections import deque

from openai import OpenAI


# =========================
# ЗАПОЛНИ ЭТИ ПОЛЯ
# =========================

OPENROUTER_API_KEY = ""

MODEL_NAME = "openai/gpt-5.4"

YOUR_PROMPT = """
- определи, что происходит на экране
- учитывай предыдущие 4-5 скриншотов как контекст
-Ты язвительный AI-комментатор. Тон: саркастичный, холодный, пассивно-агрессивный, и агрессивый.
Комментарии короткие, 1–2 фразы. Фокусируйся на действиях и ошибках, следи за тем, чтобы пользователь был всегда продуктивен. Хейти его если он не знает каких-то базовых вещей. Используй мат, но цензурируй его звездочками.
Используй мемы для язвительности.
- не раскрывай пароли, токены, номера карт
"""


# =========================
# НАСТРОЙКИ
# =========================

SCREENSHOT_DIR = "screens"
POLL_INTERVAL_SECONDS = 15
MEMORY_SIZE = 5
DEBUG = True


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
    mime_type = guess_mime_type(image_path)

    with open(image_path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("utf-8")

    return f"data:{mime_type};base64,{encoded}"


def get_latest_image_path(folder: str) -> str | None:
    folder_path = Path(folder)

    if not folder_path.exists():
        return None

    files = [f for f in folder_path.iterdir() if f.is_file() and is_image_file(f)]
    if not files:
        return None

    files.sort(key=lambda x: x.stat().st_mtime)
    return str(files[-1])


def build_messages(current_image_path: str, memory_paths: list[str]) -> list[dict]:
    content = []

    content.append({
        "type": "text",
        "text": YOUR_PROMPT.strip()
    })

    if memory_paths:
        content.append({
            "type": "text",
            "text": (
                f"Ниже приложены {len(memory_paths)} предыдущих скриншотов. "
                f"Используй их только как контекст, чтобы понять динамику происходящего."
            )
        })

        for idx, old_path in enumerate(memory_paths, start=1):
            content.append({
                "type": "text",
                "text": f"Предыдущий скриншот #{idx}"
            })
            content.append({
                "type": "image_url",
                "image_url": {
                    "url": image_to_data_url(old_path)
                }
            })

    content.append({
        "type": "text",
        "text": "Текущий скриншот"
    })
    content.append({
        "type": "image_url",
        "image_url": {
            "url": image_to_data_url(current_image_path)
        }
    })

    return [
        {
            "role": "user",
            "content": content
        }
    ]


def call_model(current_image_path: str, memory_paths: list[str]) -> str:
    messages = build_messages(current_image_path, memory_paths)

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


def analyze_single_file(image_path: str, memory_store: deque) -> str:
    previous_images = list(memory_store)
    result = call_model(image_path, previous_images)
    memory_store.append(image_path)
    return result


def watch_folder():
    ensure_api_key()

    memory_store = deque(maxlen=MEMORY_SIZE)
    last_seen_path = None

    print(f"Слежу за папкой: {SCREENSHOT_DIR}")
    print(f"Модель: {MODEL_NAME}")
    print(f"Интервал: {POLL_INTERVAL_SECONDS} сек.")
    print(f"Память: {MEMORY_SIZE} скриншотов")
    print("-" * 50)

    while True:
        try:
            latest = get_latest_image_path(SCREENSHOT_DIR)

            if latest is None:
                log("В папке нет скриншотов.")
            elif latest != last_seen_path:
                print(f"\n[NEW] {latest}")
                answer = analyze_single_file(latest, memory_store)
                print("[MODEL]", answer)
                last_seen_path = latest
            else:
                log("Новых файлов нет.")

        except Exception as e:
            print("[ERROR]", repr(e))

        time.sleep(POLL_INTERVAL_SECONDS)


def test_one_file(image_path: str):
    ensure_api_key()

    if not Path(image_path).exists():
        raise FileNotFoundError(f"Файл не найден: {image_path}")

    memory_store = deque(maxlen=MEMORY_SIZE)
    answer = analyze_single_file(image_path, memory_store)

    print("\n=== RESULT ===")
    print(answer)


if __name__ == "__main__":
    # Для теста одного файла:
    #test_one_file("screens/screen.png")

    # Для постоянного отслеживания папки:
    #
    watch_folder()