"""Synthesize AquaCraft's original sound effects (16-bit mono WAV, 48 kHz) from noise and oscillators."""
from pathlib import Path
import wave
import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"
rng = np.random.default_rng(7)


def env(n, attack, decay_power=2.0):
    t = np.linspace(0, 1, n)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * (1 - t) ** decay_power


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandnoise(n, lo, hi):
    return highpass(lowpass(rng.standard_normal(n), hi), lo)


def crunch(n, grains, lo, hi, grain_len=0.012):
    out = np.zeros(n)
    for _ in range(grains):
        start = int(rng.uniform(0, 0.7) * n)
        g = int(SR * grain_len * rng.uniform(0.5, 1.5))
        if start + g >= n:
            continue
        out[start:start + g] += bandnoise(g, lo, hi) * env(g, 0.05, 3) * rng.uniform(0.3, 1.0)
    return out


def norm(x, peak=0.8):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def save(name, x, peak=0.8):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def tone(n, f0, f1, decay=3.0):
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    ph = np.cumsum(2 * np.pi * f / SR)
    return np.sin(ph) * env(n, 0.01, decay)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    n = int(SR * 0.35)
    save("break_grass", crunch(n, 26, 900, 6000) + bandnoise(n, 400, 3000) * env(n, 0.02, 4) * 0.4)
    save("break_stone", crunch(n, 14, 300, 2600, 0.02) + tone(n, 180, 120, 6) * 0.3 + bandnoise(n, 200, 1500) * env(n, 0.005, 6) * 0.5)
    save("break_wood", tone(n, 260, 190, 5) * 0.7 + tone(n, 520, 400, 7) * 0.25 + crunch(n, 8, 300, 2000, 0.02) * 0.6)
    save("break_sand", crunch(n, 40, 1200, 8000, 0.008) * 0.8 + bandnoise(n, 800, 5000) * env(n, 0.03, 3) * 0.5)
    g = int(SR * 0.6)
    glass = sum(tone(g, f, f * 0.98, 4 + i) * (0.5 / (i + 1)) for i, f in enumerate([2300, 3150, 4100, 5200]))
    save("break_glass", glass + crunch(g, 30, 3000, 12000, 0.006) * 0.7)
    s = int(SR * 0.5)
    splash = bandnoise(s, 300, 4000) * env(s, 0.03, 2.5) + crunch(s, 20, 800, 5000, 0.02) * 0.4
    save("splash", splash, 0.7)
    p = int(SR * 0.16)
    save("place", tone(p, 150, 90, 6) * 0.8 + bandnoise(p, 200, 2500) * env(p, 0.005, 8) * 0.6)
    for name, lo, hi, grains in [("step_grass", 900, 5000, 10), ("step_stone", 300, 2500, 5), ("step_wood", 250, 1800, 4), ("step_sand", 1200, 7000, 16)]:
        q = int(SR * 0.14)
        x = crunch(q, grains, lo, hi, 0.01)
        if name == "step_wood":
            x += tone(q, 210, 170, 8) * 0.5
        if name == "step_stone":
            x += tone(q, 160, 130, 10) * 0.25
        save(name, x, 0.55)
    c = int(SR * 0.06)
    save("click", tone(c, 1400, 1100, 8) * 0.6 + tone(c, 2800, 2200, 10) * 0.2, 0.5)
    land = int(SR * 0.2)
    save("land", tone(land, 110, 70, 5) + bandnoise(land, 100, 1200) * env(land, 0.005, 6) * 0.6, 0.6)
    # Seamless wind loop: filtered noise with slow gusts; the loop point is cross-faded.
    L = SR * 12
    w = lowpass(rng.standard_normal(L + SR), 700)
    w = highpass(w, 60)
    t = np.arange(L + SR) / SR
    gust = 0.55 + 0.25 * np.sin(2 * np.pi * t / 12 * 2) + 0.2 * np.sin(2 * np.pi * t / 12 * 5 + 1.3)
    w *= gust
    fade = np.linspace(0, 1, SR)
    loop = w[:L].copy()
    loop[:SR] = w[:SR] * fade + w[L:L + SR] * (1 - fade)
    save("wind_loop", loop, 0.35)
    # Day birds: a few short chirps across 10 seconds.
    B = SR * 10
    birds = np.zeros(B)
    for _ in range(9):
        st = int(rng.uniform(0, 9.4) * SR)
        f = rng.uniform(2600, 4200)
        for k in range(int(rng.integers(2, 5))):
            d = int(SR * rng.uniform(0.05, 0.11))
            s0 = st + k * int(SR * 0.13)
            if s0 + d < B:
                birds[s0:s0 + d] += tone(d, f * rng.uniform(1.0, 1.25), f * rng.uniform(0.8, 1.0), 2) * rng.uniform(0.4, 1.0)
    save("birds", birds, 0.3)
    # Night crickets loop.
    C = SR * 8
    tt = np.arange(C) / SR
    chirp = np.sin(2 * np.pi * 4700 * tt) * (np.sin(2 * np.pi * 28 * tt) > 0.2) * ((tt * 1.25) % 1 < 0.35)
    chirp2 = np.sin(2 * np.pi * 5100 * tt) * (np.sin(2 * np.pi * 31 * tt + 1) > 0.3) * (((tt + 0.47) * 1.1) % 1 < 0.3)
    save("crickets", chirp * 0.6 + chirp2 * 0.4, 0.18)
    # Survival effects.
    q = int(SR * 0.09)
    save("pop", tone(q, 900, 1500, 5) * 0.7 + tone(q, 1800, 2900, 7) * 0.2, 0.45)
    b = int(SR * 0.45)
    snap = crunch(b, 18, 1500, 9000, 0.008) + tone(b, 620, 240, 4) * 0.5 + bandnoise(b, 500, 4000) * env(b, 0.002, 7) * 0.6
    save("tool_break", snap, 0.75)
    hh = int(SR * 0.22)
    save("hurt", tone(hh, 300, 170, 3) * 0.8 + bandnoise(hh, 200, 1800) * env(hh, 0.01, 4) * 0.35, 0.7)
    g = int(SR * 0.7)
    growl = tone(g, 95, 70, 1.5) * (0.6 + 0.4 * np.sin(np.arange(g) / SR * 2 * np.pi * 9)) + bandnoise(g, 60, 600) * env(g, 0.2, 1.5) * 0.5
    save("growl", growl, 0.6)
    ht = int(SR * 0.12)
    save("hit", bandnoise(ht, 150, 2500) * env(ht, 0.003, 6) + tone(ht, 140, 90, 6) * 0.6, 0.7)
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
