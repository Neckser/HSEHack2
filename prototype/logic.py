import os
import time
import base64
from pathlib import Path
from collections import deque

from openai import OpenAI
from interface import show_toast

OPENROUTER_API_KEY = "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"
MODEL_NAME = "openai/gpt-5.4"

YOUR_PROMPT = """
- определи, что происходит на экране
- учитывай предыдущие 4-5 скриншотов как контекст
- Ты язвительный AI-комментатор. Тон: саркастичный, холодный, пассивно-агрессивный, и агрессивый.
Комментарии короткие, 1–2 фразы, не больше абзаца. Фокусируйся на действиях и ошибках, следи за тем, чтобы пользователь был всегда продуктивен. Хейти его если он не знает каких-то базовых вещей. Используй мат, но цензурируй его звездочками.
Когда ссылаешься на контекст не упоминай это, просто ссылайся
- не раскрывай пароли, токены, номера карт
"""

SCREENSHOT_DIR = "screens"
POLL_INTERVAL_SECONDS = 10
MEMORY_SIZE = 5
DEBUG = True

if not OPENROUTER_API_KEY:
    raise RuntimeError("OPENROUTER_API_KEY not set")

client = OpenAI(
    api_key=OPENROUTER_API_KEY,
    base_url="https://openrouter.ai/api/v1",
)


def log(*args):
    if DEBUG:
        print("[DEBUG]", *args)


def is_image_file(path: Path) -> bool:
    return path.suffix.lower() in [".png", ".jpg", ".jpeg", ".webp"]


def image_to_data_url(image_path: str) -> str:
    with open(image_path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("utf-8")
    return f"data:image/png;base64,{encoded}"


def get_latest_image_path(folder: str):
    folder_path = Path(folder)

    if not folder_path.exists():
        return None

    files = [f for f in folder_path.iterdir() if f.is_file() and is_image_file(f)]
    if not files:
        return None

    files.sort(key=lambda x: x.stat().st_mtime)
    return str(files[-1])


def call_model(current_image_path: str, memory_paths: list[str]):
    content = [
        {"type": "text", "text": YOUR_PROMPT},
        {"type": "text", "text": "Текущий скриншот"},
        {
            "type": "image_url",
            "image_url": {"url": image_to_data_url(current_image_path)},
        },
    ]

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": content}],
            temperature=0.7,
            max_tokens=200,
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        log("model error:", repr(e))
        return None


def watch_folder():
    memory_store = deque(maxlen=MEMORY_SIZE)
    last_seen_path = None

    print("Watching folder:", SCREENSHOT_DIR)

    while True:
        try:
            latest = get_latest_image_path(SCREENSHOT_DIR)

            if latest and latest != last_seen_path:
                print("NEW:", latest)

                answer = call_model(latest, list(memory_store))
                memory_store.append(latest)

                if answer:
                    print("MODEL:", answer)
                    show_toast(answer)
                else:
                    print("MODEL: no response")

                last_seen_path = latest

        except Exception as e:
            log("watch error:", repr(e))

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    watch_folder()
