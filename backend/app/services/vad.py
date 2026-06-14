import numpy as np
from typing import Tuple
from app.config import settings


class VoiceActivityDetector:
    """Energy-based VAD with adaptive threshold and smoothing."""

    def __init__(
        self,
        sample_rate: int = 16000,
        frame_ms: int = 30,
        silence_threshold_ms: int = 800,
        min_speech_ms: int = 300,
        energy_threshold: float = 0.02,
    ):
        self.sample_rate = sample_rate
        self.frame_ms = frame_ms
        self.silence_threshold_ms = silence_threshold_ms
        self.min_speech_ms = min_speech_ms
        self.energy_threshold = energy_threshold

        # Track accumulated time in ms instead of frame counts so the VAD
        # works correctly regardless of the incoming chunk size.
        self._silence_ms = 0
        self._speech_ms = 0
        self._is_speech = False
        self._speech_buffer: list[bytes] = []
        self._noise_level = energy_threshold
        self._adaptation_rate = 0.01

        # For onset detection: require 2 consecutive speech chunks
        self._onset_count = 0

    def _compute_energy(self, pcm_bytes: bytes) -> float:
        if len(pcm_bytes) < 2:
            return 0.0
        samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32)
        rms = np.sqrt(np.mean(samples ** 2)) / 32768.0
        return float(rms)

    def _chunk_ms(self, pcm_bytes: bytes) -> float:
        """Actual duration in ms for the given PCM bytes."""
        n_samples = len(pcm_bytes) // 2  # 16-bit = 2 bytes per sample
        return (n_samples / self.sample_rate) * 1000.0

    def _adapt_threshold(self, energy: float, is_speech: bool):
        if not is_speech:
            self._noise_level = (
                (1 - self._adaptation_rate) * self._noise_level
                + self._adaptation_rate * energy
            )
            self.energy_threshold = max(0.015, self._noise_level * 3.0)

    def process_frame(self, pcm_bytes: bytes) -> Tuple[bool, bool, bytes | None]:
        """
        Returns: (is_speech_active, speech_ended, completed_audio)
        completed_audio is non-None only when a speech segment finishes.
        """
        energy = self._compute_energy(pcm_bytes)
        frame_is_speech = energy > self.energy_threshold
        chunk_duration_ms = self._chunk_ms(pcm_bytes)

        self._adapt_threshold(energy, frame_is_speech)

        if frame_is_speech:
            self._silence_ms = 0
            if not self._is_speech:
                self._onset_count += 1
                if self._onset_count >= 2:
                    self._is_speech = True
                    self._speech_buffer = []
                    self._speech_ms = 0
            if self._is_speech:
                self._speech_buffer.append(pcm_bytes)
                self._speech_ms += chunk_duration_ms
        else:
            self._onset_count = 0
            if self._is_speech:
                self._speech_buffer.append(pcm_bytes)
                self._silence_ms += chunk_duration_ms
                if self._silence_ms >= self.silence_threshold_ms:
                    self._is_speech = False
                    self._silence_ms = 0
                    audio = b"".join(self._speech_buffer)
                    self._speech_buffer = []
                    if self._speech_ms >= self.min_speech_ms:
                        return False, True, audio
                    return False, False, None

        return self._is_speech, False, None

    def reset(self):
        self._is_speech = False
        self._silence_ms = 0
        self._speech_ms = 0
        self._onset_count = 0
        self._speech_buffer = []

    def flush(self) -> bytes | None:
        """Force-end current speech segment."""
        if self._speech_buffer:
            audio = b"".join(self._speech_buffer)
            self._speech_buffer = []
            self._is_speech = False
            self._silence_ms = 0
            self._speech_ms = 0
            return audio
        return None
