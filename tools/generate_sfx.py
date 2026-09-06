"""Bake the game's original synthesized effects once, outside the game runtime.

Run `python tools/generate_sfx.py` after editing NOTES. Each effect, including its
note timing, is one mono WAV. Godot imports these as QOA for small web downloads.
No third-party packages, recordings, or runtime sound synthesis are needed.
"""

import math
from pathlib import Path
import struct
import wave

SAMPLE_RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/sfx"
# delay, start Hz, end Hz, duration, waveform, gain, frequency sweep
NOTES = {'eco_dash': [(0.0, 240.0, 620.0, 0.34, 'sine', 0.28, True),
              (0.24, 659.25, 659.25, 0.16, 'sine', 0.25, False),
              (0.38, 880.0, 880.0, 0.22, 'sine', 0.22, False)],
 'wind_path': [(0.0, 920.0, 260.0, 0.46, 'sine', 0.22, True),
               (0.16, 380.0, 1050.0, 0.42, 'sine', 0.19, True),
               (0.46, 740.0, 740.0, 0.18, 'sine', 0.18, False)],
 'lightning_leap': [(0.0, 1280.0, 1280.0, 0.055, 'square', 0.34, False),
                    (0.07, 820.0, 820.0, 0.07, 'square', 0.3, False),
                    (0.15, 1640.0, 1640.0, 0.05, 'square', 0.28, False),
                    (0.18, 260.0, 90.0, 0.3, 'saw', 0.25, True)],
 'solar_charge': [(0.0, 330.0, 660.0, 0.42, 'sine', 0.24, True),
                  (0.22, 523.25, 523.25, 0.42, 'sine', 0.2, False),
                  (0.25, 659.25, 659.25, 0.4, 'sine', 0.18, False),
                  (0.28, 783.99, 783.99, 0.38, 'sine', 0.17, False)],
 'starlight_charge': [(0.0, 880.0, 880.0, 0.13, 'sine', 0.2, False),
                      (0.12, 1174.66, 1174.66, 0.15, 'sine', 0.22, False),
                      (0.25, 1318.51, 1318.51, 0.17, 'sine', 0.2, False),
                      (0.4, 1760.0, 1760.0, 0.25, 'sine', 0.18, False)],
 'purifying_wave': [(0.0, 260.0, 720.0, 0.55, 'sine', 0.25, True),
                    (0.18, 920.0, 920.0, 0.1, 'sine', 0.17, False),
                    (0.31, 1120.0, 1120.0, 0.09, 'sine', 0.15, False),
                    (0.44, 1380.0, 1380.0, 0.12, 'sine', 0.14, False)],
 'earth_barrier': [(0.0, 150.0, 72.0, 0.3, 'saw', 0.34, True),
                   (0.14, 110.0, 110.0, 0.24, 'square', 0.25, False),
                   (0.31, 196.0, 196.0, 0.34, 'sine', 0.24, False)],
 'forest_supply': [(0.0, 329.63, 329.63, 0.18, 'sine', 0.2, False),
                   (0.13, 440.0, 440.0, 0.18, 'sine', 0.2, False),
                   (0.26, 523.25, 523.25, 0.2, 'sine', 0.22, False),
                   (0.41, 659.25, 659.25, 0.26, 'sine', 0.2, False)],
 'recycle_salvage': [(0.0, 420.0, 420.0, 0.12, 'square', 0.18, False),
                     (0.12, 560.0, 560.0, 0.12, 'square', 0.18, False),
                     (0.24, 700.0, 700.0, 0.12, 'square', 0.18, False),
                     (0.38, 420.0, 420.0, 0.24, 'sine', 0.24, False)],
 'mycelium_harvest': [(0.0, 190.0, 460.0, 0.48, 'sine', 0.24, True),
                      (0.22, 493.88, 493.88, 0.22, 'sine', 0.18, False),
                      (0.42, 739.99, 739.99, 0.28, 'sine', 0.19, False)],
 'skill_default': [(0.0, 300.0, 720.0, 0.42, 'sine', 0.25, True)],
 'dice': [(0, 520, 520, 0.08, 'square', 0.4, False),
          (0.08, 660, 660, 0.08, 'square', 0.4, False)],
 'move': [(0, 440, 440, 0.06, 'sine', 0.4, False)],
 'correct': [(0, 523.25, 523.25, 0.1, 'sine', 0.4, False),
             (0.1, 659.25, 659.25, 0.1, 'sine', 0.4, False),
             (0.2, 783.99, 783.99, 0.25, 'sine', 0.4, False)],
 'wrong': [(0, 220, 220, 0.2, 'saw', 0.4, False),
           (0.15, 180, 180, 0.3, 'saw', 0.4, False)],
 'ladder': [(0.0, 400, 400, 0.08, 'sine', 0.4, False),
            (0.06, 520, 520, 0.08, 'sine', 0.4, False),
            (0.12, 640, 640, 0.08, 'sine', 0.4, False),
            (0.18, 760, 760, 0.08, 'sine', 0.4, False),
            (0.24, 880, 880, 0.08, 'sine', 0.4, False)],
 'slide': [(0.0, 700, 700, 0.08, 'saw', 0.4, False),
           (0.06, 600, 600, 0.08, 'saw', 0.4, False),
           (0.12, 500, 500, 0.08, 'saw', 0.4, False),
           (0.18, 400, 400, 0.08, 'saw', 0.4, False),
           (0.24, 300, 300, 0.08, 'saw', 0.4, False)]}


def render(notes):
    length = max(int(delay * SAMPLE_RATE) + int(duration * SAMPLE_RATE)
                 for delay, _, _, duration, _, _, _ in notes)
    samples = [0.0] * length
    for delay, start, end, duration, shape, gain, sweep in notes:
        offset = int(delay * SAMPLE_RATE)
        count = int(duration * SAMPLE_RATE)
        phase = 0.0
        for i in range(count):
            progress = i / max(count - 1, 1)
            if sweep:
                phase += math.tau * (start + (end - start) * progress) / SAMPLE_RATE
            else:
                phase = math.tau * start * i / SAMPLE_RATE
            value = math.sin(phase)
            if shape == "square":
                value = 0.75 if value > 0 else -0.75
            elif shape == "saw":
                value = 0.75 * (2 * ((phase / math.tau) % 1) - 1)
            attack = min(1.0, i / (SAMPLE_RATE * (0.015 if sweep else 0.012)))
            release = (1 - progress) ** 0.7 if sweep else 1 - i / count
            # End every note at zero, including the short square/saw notes.
            release *= min(1.0, (count - 1 - i) / (SAMPLE_RATE * 0.003))
            samples[offset + i] += value * gain * attack * release
    peak = max(abs(value) for value in samples)
    attenuation = min(1.0, 0.9 / max(peak, 0.00001))
    return b"".join(struct.pack("<h", round(value * attenuation * 32767)) for value in samples)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, notes in NOTES.items():
        target = OUTPUT / f"{name}.wav"
        with wave.open(str(target), "wb") as wav:
            wav.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
            wav.writeframes(render(notes))
        total += target.stat().st_size
    print(f"Baked {len(NOTES)} effects: {total:,} source bytes; web export uses QOA imports.")


if __name__ == "__main__":
    main()
