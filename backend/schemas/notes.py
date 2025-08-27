def validate_create_note(data: dict) -> tuple[str, int]:
    text = (data.get("text") or "").strip()
    if not text:
        raise ValueError("text required")
    try:
        hours = int(data.get("hours", 24))
    except Exception:
        hours = 24
    hours = min(168, max(1, hours))
    return text, hours
