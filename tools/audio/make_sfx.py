"""Synthesise the arena's sound set.

Why synthesised rather than downloaded: every free basketball sound-effect pack
found needed an account (itch.io, Gumroad, ZapSplat), and nothing usable was
reachable as a direct download. These sounds are physically simple enough to build
honestly - a dribble is a damped low thud plus a click of noise, a rim is a few
detuned metal partials, a swish is filtered noise with a fast decay - and building
them means no licence, no account, and exact control over length and level.

    python make_sfx.py --out ../../assets/audio

Writes 16-bit stereo WAVs at 44.1 kHz. Every file is peak-normalised and given
short fades so nothing clicks at the edges.
"""
import argparse, math, os, struct, wave
import numpy as np

SR = 44100
RNG = np.random.default_rng(20260729)   # fixed, so the set is reproducible


def env(n, attack, decay, curve=2.0):
    """Attack-then-decay envelope in samples."""
    a = max(1, int(attack * SR))
    d = max(1, n - a)
    return np.concatenate([
        np.linspace(0.0, 1.0, a) ** 0.6,
        (np.linspace(1.0, 0.0, d) ** curve),
    ])[:n]


def lowpass(x, cutoff):
    """One-pole low pass - crude, but exactly right for shaping noise."""
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = a * acc + (1.0 - a) * v
        out[i] = acc
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(n):
    return RNG.standard_normal(n)


def partials(n, freqs, decays, amps):
    """Sum of decaying sines - how a struck metal object actually rings."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2.0 * math.pi * f * t) * np.exp(-t / d)
    return out


def stereo(x, width=0.25):
    """Slight decorrelation so a mono source does not sit dead centre."""
    delay = int(0.0009 * SR)
    r = np.concatenate([np.zeros(delay), x[:-delay]]) if delay else x.copy()
    return np.stack([x, x * (1.0 - width) + r * width], axis=1)


def finish(x, peak=0.9, fade=0.004):
    f = max(1, int(fade * SR))
    if x.shape[0] > 2 * f:
        ramp = np.linspace(0.0, 1.0, f)
        x[:f] *= ramp[:, None] if x.ndim == 2 else ramp
        x[-f:] *= ramp[::-1, None] if x.ndim == 2 else ramp[::-1]
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(path, x):
    x = finish(np.asarray(x, dtype=np.float64))
    if x.ndim == 1:
        x = stereo(x)
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("SFX: %-22s %5.2fs  %6.1f KB" % (os.path.basename(path),
          len(data) / SR, os.path.getsize(path) / 1024.0))


# ---------------------------------------------------------------- the sounds

def dribble(hardness=1.0):
    """Ball on hardwood: a damped low thud, a mid knock, and a click of contact."""
    n = int(0.20 * SR)
    body = partials(n, [78 * hardness, 155 * hardness, 240],
                    [0.045, 0.030, 0.018], [1.0, 0.45, 0.2])
    knock = lowpass(noise(n), 1400.0) * env(n, 0.0004, 0.05, 5.0) * 0.5
    click = highpass(noise(n), 3500.0) * env(n, 0.0002, 0.012, 8.0) * 0.35
    return (body * env(n, 0.001, 0.12, 2.4)) + knock + click


def squeak():
    """Sneaker on a polished floor: narrow noise sliding up in pitch."""
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    sweep = 900.0 + 1500.0 * (t / t[-1]) ** 0.7
    phase = np.cumsum(2.0 * math.pi * sweep / SR)
    tone = np.sin(phase) * 0.6 + np.sin(2.0 * phase) * 0.2
    grit = highpass(noise(n), 2000.0) * 0.35
    return (tone + grit) * env(n, 0.02, 0.22, 1.6)


def rim():
    """Iron rim: bright inharmonic partials, quick but ringing."""
    n = int(0.7 * SR)
    return partials(n,
        [430, 712, 1183, 1620, 2410, 3180],
        [0.42, 0.30, 0.22, 0.16, 0.10, 0.07],
        [1.0, 0.8, 0.6, 0.45, 0.3, 0.2]) * env(n, 0.0005, 0.6, 1.2)


def backboard():
    """Glass: lower, duller and shorter than the rim."""
    n = int(0.45 * SR)
    ring = partials(n, [210, 348, 560, 905], [0.16, 0.12, 0.09, 0.06],
                    [1.0, 0.7, 0.4, 0.25])
    thud = lowpass(noise(n), 700.0) * env(n, 0.0005, 0.08, 4.0) * 0.7
    return ring * env(n, 0.0005, 0.35, 1.6) + thud


def swish():
    """Net: a short brush of high noise, no tone at all."""
    n = int(0.34 * SR)
    body = highpass(noise(n), 2200.0)
    body = body * env(n, 0.008, 0.30, 2.2)
    tail = highpass(noise(n), 5000.0) * env(n, 0.05, 0.26, 3.0) * 0.4
    return body + tail


def whistle():
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    warble = 1.0 + 0.012 * np.sin(2.0 * math.pi * 22.0 * t)
    tone = np.sin(2.0 * math.pi * 2650.0 * t * warble)
    tone += 0.5 * np.sin(2.0 * math.pi * 3900.0 * t * warble)
    air = highpass(noise(n), 4000.0) * 0.25
    return (tone + air) * env(n, 0.02, 0.5, 1.3)


def buzzer():
    n = int(1.3 * SR)
    t = np.arange(n) / SR
    saw = 2.0 * (t * 240.0 - np.floor(t * 240.0 + 0.5))
    saw += 2.0 * (t * 241.7 - np.floor(t * 241.7 + 0.5))
    return lowpass(saw, 2600.0) * env(n, 0.006, 1.2, 0.7)


def crowd_bed(seconds=12.0):
    """A seamless loop of arena murmur: pink-ish noise with slow swells and a
    scatter of individual voices, so it does not read as static hiss."""
    n = int(seconds * SR)
    base = lowpass(noise(n), 900.0)
    base += lowpass(noise(n), 220.0) * 1.6         # low room rumble
    base += highpass(lowpass(noise(n), 3000.0), 900.0) * 0.35

    t = np.arange(n) / SR
    swell = 1.0
    for f, a in [(0.07, 0.18), (0.13, 0.12), (0.31, 0.06)]:
        swell = swell + a * np.sin(2.0 * math.pi * f * t + f * 11.0)
    voices = np.zeros(n)
    for _ in range(70):
        start = RNG.integers(0, n - SR)
        length = int(RNG.uniform(0.25, 0.9) * SR)
        seg = highpass(lowpass(noise(length), 1800.0), 300.0)
        voices[start:start + length] += seg * env(length, 0.08, 0.7, 1.4) * RNG.uniform(0.1, 0.35)

    out = base * swell + voices
    # Cross-fade the tail into the head so the loop has no seam.
    x = int(0.6 * SR)
    ramp = np.linspace(0.0, 1.0, x)
    out[:x] = out[:x] * ramp + out[-x:] * ramp[::-1]
    return out[:-x]


def crowd_roar(seconds=3.2):
    """The reaction to a made basket: a fast surge, then a decay back toward the bed."""
    n = int(seconds * SR)
    base = lowpass(noise(n), 1500.0) + lowpass(noise(n), 300.0) * 1.4
    base += highpass(lowpass(noise(n), 4000.0), 1200.0) * 0.5
    shape = np.concatenate([
        np.linspace(0.25, 1.0, int(0.35 * SR)) ** 0.5,
        np.linspace(1.0, 0.3, n - int(0.35 * SR)) ** 1.6,
    ])[:n]
    claps = np.zeros(n)
    for _ in range(140):
        i = int(RNG.uniform(0.15, 0.95) * n)
        L = int(0.03 * SR)
        if i + L < n:
            claps[i:i + L] += highpass(noise(L), 2500.0) * env(L, 0.0005, 0.02, 6.0) * RNG.uniform(0.2, 0.7)
    return base * shape + claps * 0.6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)

    # Three dribbles at different hardness so a repeated bounce never sounds
    # like the same sample firing over and over.
    for i, h in enumerate([0.92, 1.0, 1.1], start=1):
        write(os.path.join(out, "dribble_%d.wav" % i), dribble(h))
    for i in range(1, 4):
        write(os.path.join(out, "squeak_%d.wav" % i), squeak())
    write(os.path.join(out, "rim.wav"), rim())
    write(os.path.join(out, "backboard.wav"), backboard())
    write(os.path.join(out, "swish.wav"), swish())
    write(os.path.join(out, "whistle.wav"), whistle())
    write(os.path.join(out, "buzzer.wav"), buzzer())
    write(os.path.join(out, "crowd_bed.wav"), crowd_bed())
    write(os.path.join(out, "crowd_roar.wav"), crowd_roar())


if __name__ == "__main__":
    main()