import re


def normalize_phone(phone: str) -> str:
    """Normalize to E.164-ish format. Pakistan numbers default to +92."""
    if not phone:
        return phone
    p = re.sub(r"[\s\-()]", "", phone.strip())
    if p.startswith("00"):
        p = "+" + p[2:]
    if not p.startswith("+"):
        p = "+92" + p.lstrip("0")
    return p
