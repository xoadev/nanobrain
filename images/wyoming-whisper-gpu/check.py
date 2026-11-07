"""Runs inside the image, with no GPU, what every transcription runs before reaching CUDA.

A library missing from the distroless stage, onnxruntime needed after all, or a PyAV that
faster-whisper cannot call (av 19 dropped the `metadata_errors` argument it passes) fails here,
while the server would still start and pass its health check.
"""

import io
import wave

import ctranslate2
import faster_whisper
import wyoming_faster_whisper.__main__  # noqa: F401 - the server's own imports must resolve

SAMPLE_RATE = 16000
ONE_SECOND_OF_SILENCE = bytes(2 * SAMPLE_RATE)

wav = io.BytesIO()
with wave.open(wav, "wb") as writer:
    writer.setnchannels(1)
    writer.setsampwidth(2)
    writer.setframerate(SAMPLE_RATE)
    writer.writeframes(ONE_SECOND_OF_SILENCE)
wav.seek(0)

samples = faster_whisper.decode_audio(wav)
assert len(samples) == SAMPLE_RATE, f"decoded {len(samples)} samples from 1 s, not {SAMPLE_RATE}"
print(f"ctranslate2 {ctranslate2.__version__}: decodes audio")
