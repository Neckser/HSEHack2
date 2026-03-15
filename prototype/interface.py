import tkinter as tk
from queue import Queue, Empty

WIDTH = 820
MARGIN = 16
RIGHT_OFFSET = 120
DURATION = 15000

TITLE_FONT = ("Segoe UI", 20, "bold")
BODY_FONT = ("Segoe UI", 16)

BG_COLOR = "#1c1c20"
FG_COLOR = "white"

PADDING_X = 28
PADDING_Y = 20

queue = Queue()


def show_toast(text: str):
    if text is not None:
        queue.put(str(text))


def start_ui():
    root = tk.Tk()
    root.withdraw()
    root.overrideredirect(True)
    root.attributes("-topmost", True)
    root.configure(bg=BG_COLOR)

    outer = tk.Frame(root, bg=BG_COLOR, padx=PADDING_X, pady=PADDING_Y)
    outer.pack(fill="both", expand=True)

    title = tk.Label(
        outer,
        text="AI Buller",
        fg=FG_COLOR,
        bg=BG_COLOR,
        font=TITLE_FONT,
        anchor="w",
        justify="left",
    )
    title.pack(fill="x", anchor="w")

    body = tk.Message(
        outer,
        text="",
        fg=FG_COLOR,
        bg=BG_COLOR,
        font=BODY_FONT,
        anchor="w",
        justify="left",
        width=WIDTH - (PADDING_X * 2),
    )
    body.pack(fill="x", anchor="w", pady=(10, 0))

    hide_job = None
    current_text = None

    def hide_toast():
        nonlocal hide_job, current_text
        root.withdraw()
        hide_job = None
        current_text = None

    def prepare_text(text: str) -> str:
        text = " ".join(str(text).split())
        if len(text) > 900:
            text = text[:897].rstrip() + "..."
        return text

    def show_text(text: str):
        nonlocal hide_job, current_text

        formatted = prepare_text(text)

        if formatted == current_text:
            return

        current_text = formatted

        screen_w = root.winfo_screenwidth()
        screen_h = root.winfo_screenheight()

        max_w = min(WIDTH, screen_w - RIGHT_OFFSET - MARGIN * 2)
        if max_w < 300:
            max_w = 300

        text_width = max_w - (PADDING_X * 2)
        body.config(text=formatted, width=text_width)

        root.update_idletasks()

        req_h = (
            title.winfo_reqheight()
            + body.winfo_reqheight()
            + PADDING_Y * 2
            + 14
        )
        req_h = min(req_h, screen_h - 2 * MARGIN)

        x = screen_w - max_w - RIGHT_OFFSET
        y = MARGIN

        if x < MARGIN:
            x = MARGIN

        root.geometry(f"{max_w}x{req_h}+{x}+{y}")
        root.deiconify()
        root.lift()
        root.attributes("-topmost", True)

        if hide_job is not None:
            try:
                root.after_cancel(hide_job)
            except Exception:
                pass

        hide_job = root.after(DURATION, hide_toast)

    def poll_queue():
        latest = None

        while True:
            try:
                latest = queue.get_nowait()
            except Empty:
                break

        if latest is not None:
            show_text(latest)

        root.after(150, poll_queue)

    poll_queue()
    root.mainloop()
