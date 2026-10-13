"""Generate short looping PCM alarm tones for Android raw resources."""
from math import exp, pi, sin
from pathlib import Path
import struct
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / "android/app/src/main/res/raw"
ROOT.mkdir(parents=True, exist_ok=True)


def tone(name, seconds, sample):
    with wave.open(str(ROOT / f"{name}.wav"), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        frames = bytearray()
        for i in range(int(seconds * RATE)):
            t = i / RATE
            value = max(-1.0, min(1.0, sample(t)))
            frames.extend(struct.pack("<h", int(value * 18000)))
        file.writeframes(frames)


tone("bell", 2.4, lambda t: (sin(2*pi*740*t) + .5*sin(2*pi*1480*t) + .25*sin(2*pi*2220*t)) * exp(-2.6*(t % 1.2)) * .55)
tone("digital", 1.8, lambda t: (.45*sin(2*pi*900*t) + .25*sin(2*pi*1350*t)) if (t % .6) < .38 else 0)
tone("beep", 1.5, lambda t: .6*sin(2*pi*800*t) if (t % .5) < .25 else 0)
tone("wakeup", 3.0, lambda t: .5*sin(2*pi*(480 + 100*(t % 1.0))*t) * min(1, (t % 1.0)*3) if (t % 1.5) < 1 else 0)
