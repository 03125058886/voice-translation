import io
import wave
import struct
import numpy as np


def pcm_to_wav(pcm_bytes: bytes, sample_rate: int = 16000, channels: int = 1) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


def wav_to_pcm(wav_bytes: bytes) -> tuple[bytes, int, int]:
    """Returns (pcm_bytes, sample_rate, channels)."""
    buf = io.BytesIO(wav_bytes)
    with wave.open(buf, "rb") as wf:
        sample_rate = wf.getframerate()
        channels = wf.getnchannels()
        pcm = wf.readframes(wf.getnframes())
    return pcm, sample_rate, channels


def resample_pcm(pcm_bytes: bytes, from_rate: int, to_rate: int) -> bytes:
    if from_rate == to_rate:
        return pcm_bytes
    samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32)
    ratio = to_rate / from_rate
    new_len = int(len(samples) * ratio)
    resampled = np.interp(
        np.linspace(0, len(samples), new_len),
        np.arange(len(samples)),
        samples,
    ).astype(np.int16)
    return resampled.tobytes()


def compute_rms(pcm_bytes: bytes) -> float:
    if not pcm_bytes:
        return 0.0
    samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32)
    return float(np.sqrt(np.mean(samples ** 2)) / 32768.0)


def normalize_audio(pcm_bytes: bytes, target_rms: float = 0.1) -> bytes:
    samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32)
    rms = np.sqrt(np.mean(samples ** 2)) / 32768.0
    if rms < 1e-6:
        return pcm_bytes
    gain = min(target_rms / rms, 4.0)
    normalized = np.clip(samples * gain, -32768, 32767).astype(np.int16)
    return normalized.tobytes()
