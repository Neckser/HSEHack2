import threading

from interface import start_ui
from logic import watch_folder
from screenshot import run_loop


def start_screenshot_service():
    print("[LAUNCHER] screenshot service started")
    run_loop()


def start_ai_service():
    print("[LAUNCHER] AI analysis started")
    watch_folder()


def main():
    print("AI Desktop Agent starting...")
    print("--------------------------------")

    screenshot_thread = threading.Thread(
        target=start_screenshot_service,
        daemon=True
    )

    ai_thread = threading.Thread(
        target=start_ai_service,
        daemon=True
    )

    screenshot_thread.start()
    ai_thread.start()

    print("[LAUNCHER] services running")

    # Tkinter должен жить в главном потоке
    start_ui()


if __name__ == "__main__":
    main()
