import time
from pathlib import Path
from datetime import datetime

import mss
import mss.tools

SCREENSHOT_DIR = "screens"
INTERVAL = 10
MAX_FILES = 6


def ensure_folder():
    Path(SCREENSHOT_DIR).mkdir(exist_ok=True)


def cleanup_old_files():
    files = sorted(
        Path(SCREENSHOT_DIR).glob("*.png"),
        key=lambda p: p.stat().st_mtime
    )

    if len(files) > MAX_FILES:
        for file_path in files[:-MAX_FILES]:
            try:
                file_path.unlink()
                print("deleted:", file_path)
            except Exception as e:
                print("cleanup error:", e)


def take_screenshot():
    ensure_folder()

    with mss.mss() as sct:
        monitor = sct.monitors[1]
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = Path(SCREENSHOT_DIR) / f"screen_{timestamp}.png"

        shot = sct.grab(monitor)
        mss.tools.to_png(shot.rgb, shot.size, output=str(filename))

        print("saved:", filename)
        cleanup_old_files()


def run_loop():
    print("Screenshot service started")

    while True:
        try:
            take_screenshot()
        except Exception as e:
            print("screenshot error:", e)

        time.sleep(INTERVAL)


if __name__ == "__main__":
    run_loop()
