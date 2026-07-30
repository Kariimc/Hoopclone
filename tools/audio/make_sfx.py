"""Synthesise the arena's sound set.

    python make_sfx.py --out ../../assets/audio

Writes 16-bit stereo WAVs at 44.1 kHz, peak-normalised, with short fades so
nothing clicks at the edges. Run tools/audio/verify_sfx.py afterwards - it is
the gate that says whether any of this actually worked.

WHY SYNTHESISED. Every free basketball sound pack found needs an account
(itch.io, Gumroad, ZapSplat), and the one generative audio service on hand
refuses standalone sound effects by policy. So these are built - no licence, no
account, exact control over length and level.

WHY THE FIRST ATTEMPT SOUNDED LIKE A BROKEN TELEVISION, which is what the owner
said and he was right. Three faults, all fixed here:

1. EVERY texture was white noise behind a one-pole filter. One pole rolls off at
   6 dB per octave, which barely dents broadband noise - so the crowd, the net
   and the sneakers all came out as hiss with a tilt. Static is, definitionally,
   flat noise. Filters here are proper biquads, and every texture is built from
   structured grains rather than a noise bed.

2. THE CROWD WAS NOISE. A crowd is several thousand human voices. It is
   synthesised here as voices: a glottal pulse at a real speaking pitch through
   three formant resonators, hundreds of them scattered across the loop. Formants
   are what makes a sound read as a person rather than as air.

3. NOTHING WAS IN A ROOM. Every sound was bone dry, and a dry sound in a scene
   that looks like a 20,000-seat arena reads as cheap even when the sound itself
   is fine. There is a synthetic arena impulse response here - early reflections
   off a shoebox plus a band-split decaying tail - and every sound gets a send to
   it, less for things at your feet, more for things across the court.
"""
import argparse, math, os, wave
import numpy as np
from scipy import signal

SR = 44100
RNG = np.random.default_rng(20260730)   # fixed, so the set is reproducible


# ------------------------------------------------------------------ filters

def _sos(kind, f0, q_or_order=2, **kw):
    f0 = min(max(f0, 20.0), SR * 0.49)
    if kind in ("low", "high"):
        return signal.butter(q_or_order, f0, btype=kind, fs=SR, output="sos")
    if kind == "band":
        lo, hi = f0, kw["f1"]
        hi = min(hi, SR * 0.49)
        lo = min(lo, hi * 0.98)
        return signal.butter(q_or_order, [lo, hi], btype="band", fs=SR, output="sos")
    raise ValueError(kind)


def lowpass(x, f, order=2):
    return signal.sosfilt(_sos("low", f, order), x)


def highpass(x, f, order=2):
    return signal.sosfilt(_sos("high", f, order), x)


def bandpass(x, f0, f1, order=2):
    return signal.sosfilt(_sos("band", f0, order, f1=f1), x)


def resonate(x, f0, q):
    """A single sharp resonance - the workhorse for formants and body modes."""
    f0 = min(max(f0, 25.0), SR * 0.48)
    b, a = signal.iirpeak(f0, q, fs=SR)
    return signal.lfilter(b, a, x)


def noise(n):
    return RNG.standard_normal(n)


def env(n, attack, decay, curve=2.0):
    a = max(1, int(attack * SR))
    d = max(1, n - a)
    return np.concatenate([np.linspace(0.0, 1.0, a) ** 0.6,
                           np.linspace(1.0, 0.0, d) ** curve])[:n]


def modes(n, freqs, decays, amps, detune=0.0):
    """Sum of decaying sines - how a struck solid actually rings.

    `detune` pairs each mode with a twin a fraction of a hertz away. Real metal
    is never perfectly symmetrical, so its modes come in close pairs that beat
    slowly against each other. Without it a rim reads as an electronic buzz."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        out += a * np.sin(2.0 * math.pi * f * t + RNG.uniform(0, 6.28)) * np.exp(-t / d)
        if detune:
            f2 = f * (1.0 + detune * RNG.uniform(0.4, 1.6))
            out += a * 0.7 * np.sin(2.0 * math.pi * f2 * t + RNG.uniform(0, 6.28)) \
                * np.exp(-t / (d * 0.9))
    return out


# ------------------------------------------------------------------- the room

def arena_ir(seconds=2.2):
    """A synthetic impulse response for a big indoor arena.

    Early reflections first - forty discrete taps between 9 and 95 ms, standing
    in for the floor, the near stands and the roof, each duller than the last
    because a surface absorbs treble before it absorbs bass. Then a decaying
    tail, split into three bands with different decay times (2.4 s low, 1.6 s
    mid, 0.8 s high), which is how a real hall behaves and why a single
    exponential always sounds like a spring."""
    n = int(seconds * SR)
    ir = np.zeros(n)
    ir[0] = 1.0
    for i in range(40):
        t = RNG.uniform(0.009, 0.095)
        k = int(t * SR)
        if k < n:
            ir[k] += RNG.choice([-1.0, 1.0]) * (0.55 / (1.0 + 26.0 * t))

    t = np.arange(n) / SR
    tail = np.zeros(n)
    for t60, f_lo, f_hi, amp in ((2.4, 20, 300, 1.0),
                                 (1.6, 300, 2000, 0.75),
                                 (0.8, 2000, 9000, 0.4)):
        band = bandpass(noise(n), f_lo, f_hi, order=2)
        tail += band * np.exp(-6.9078 * t / t60) * amp
    # Hold the tail back until the early reflections have had their say.
    tail *= np.clip((t - 0.02) / 0.06, 0.0, 1.0)
    ir = ir + tail * 0.22
    return ir / (np.sqrt(np.sum(ir ** 2)) or 1.0)


IR = None


def room(x, send=0.18):
    """Mix a dry sound with the arena's response to it."""
    global IR
    if send <= 0.0:
        return x
    if IR is None:
        IR = arena_ir()
    wet = signal.fftconvolve(x, IR)[:len(x)]
    m = np.max(np.abs(wet)) or 1.0
    return x * (1.0 - send * 0.5) + wet / m * (np.max(np.abs(x)) or 1.0) * send


# ------------------------------------------------------------------- voices

# Vowel formants in Hz, from the standard measured tables. Three resonances is
# the minimum that reads as a human throat rather than a filtered hiss.
VOWELS = [(730, 1090, 2440), (530, 1840, 2480), (570, 840, 2410),
          (270, 2290, 3010), (440, 1020, 2240), (300, 870, 2240)]


def voice_grain(n, f0=None, effort=0.5):
    """One person, for a fraction of a second.

    A glottal pulse train at a real speaking pitch, shaped by three formants.
    `effort` runs from murmur to shout: it lifts the pitch, brightens the source
    and opens the throat, which is exactly what a crowd does when the ball goes
    in."""
    f0 = f0 if f0 is not None else RNG.uniform(95.0, 240.0) * (1.0 + 0.5 * effort)
    t = np.arange(n) / SR
    # Slight pitch drift, or every voice sounds like the same synthesiser.
    drift = 1.0 + 0.03 * np.sin(2.0 * math.pi * RNG.uniform(1.5, 5.0) * t + RNG.uniform(0, 6.3))
    phase = np.cumsum(2.0 * math.pi * f0 * drift / SR)
    # Band-limited pulse: harmonics falling off more slowly the louder the voice.
    src = np.zeros(n)
    tilt = 1.6 - 0.7 * effort
    for h in range(1, 40):
        if f0 * h > SR * 0.45:
            break
        src += np.sin(phase * h) / (h ** tilt)
    src += noise(n) * (0.05 + 0.12 * effort)          # breath

    f1, f2, f3 = VOWELS[RNG.integers(len(VOWELS))]
    jitter = RNG.uniform(0.9, 1.12)
    out = resonate(src, f1 * jitter, 9.0) * 1.0
    out += resonate(src, f2 * jitter, 11.0) * 0.55
    out += resonate(src, f3 * jitter, 13.0) * 0.3
    return out * env(n, RNG.uniform(0.03, 0.10), 0.3, RNG.uniform(1.1, 2.2))


def crowd_layer(n, count, effort, dur_lo, dur_hi, gain_lo, gain_hi, when=None):
    """Scatter `count` voices across n samples. `when` biases where they land."""
    out = np.zeros(n)
    for _ in range(count):
        length = int(RNG.uniform(dur_lo, dur_hi) * SR)
        if length >= n:
            continue
        pos = RNG.uniform(0.0, 1.0) if when is None else float(np.clip(when(), 0.0, 1.0))
        start = int(pos * (n - length))
        out[start:start + length] += voice_grain(length, effort=effort) \
            * RNG.uniform(gain_lo, gain_hi)
    return out


# --------------------------------------------------------------- the sounds

def dribble(hardness=1.0):
    """Ball on hardwood.

    Three things happen at once and the old version only had one of them: the
    ball's air cavity thumps around 80 Hz, the floor PANEL rings (sprung maple
    over a void - that hollow note is most of what you actually recognise), and
    the rubber skin slaps."""
    n = int(0.26 * SR)
    ball = modes(n, [76 * hardness, 152 * hardness], [0.055, 0.032], [1.0, 0.35])
    ball *= env(n, 0.0012, 0.14, 2.4)

    floor = modes(n, [186, 317, 543, 780], [0.075, 0.055, 0.035, 0.022],
                  [0.85, 0.5, 0.28, 0.15], detune=0.004)
    floor *= env(n, 0.0008, 0.10, 2.8) * 0.55

    slap = bandpass(noise(n), 900.0, 5200.0, order=2) * env(n, 0.0003, 0.022, 6.0) * 0.45
    tick = highpass(noise(n), 6500.0, order=2) * env(n, 0.0002, 0.007, 9.0) * 0.22
    return room(ball + floor + slap + tick, send=0.16)


def squeak():
    """Sneaker on a polished floor.

    Rubber does not slide, it grabs and releases hundreds of times a second -
    stick-slip. That is why a squeak has a pitch at all, and why it wavers. Built
    as a resonant chirp whose amplitude is chopped by an irregular slip rate."""
    n = int(0.30 * SR)
    t = np.arange(n) / SR
    sweep = RNG.uniform(700, 950) + RNG.uniform(1100, 1900) * (t / t[-1]) ** 0.65
    phase = np.cumsum(2.0 * math.pi * sweep / SR)
    tone = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)

    slip_rate = RNG.uniform(70.0, 130.0)
    slip = 0.62 + 0.38 * signal.sawtooth(2.0 * math.pi * slip_rate * t, 0.35)
    slip *= 1.0 + 0.25 * np.sin(2.0 * math.pi * RNG.uniform(7, 15) * t)

    grit = bandpass(noise(n), 1800.0, 6000.0, order=2) * 0.20
    out = (tone * slip + grit) * env(n, 0.018, 0.26, 1.7)
    return room(out, send=0.14)


def rim():
    """Iron rim: bright inharmonic modes, paired so they beat, plus the strike."""
    n = int(0.9 * SR)
    ring = modes(n, [418, 706, 1174, 1633, 2418, 3210, 4390],
                 [0.55, 0.40, 0.30, 0.22, 0.15, 0.10, 0.07],
                 [1.0, 0.85, 0.6, 0.45, 0.3, 0.2, 0.12], detune=0.0016)
    ring *= env(n, 0.0004, 0.75, 1.1)
    strike = bandpass(noise(n), 1500.0, 9000.0, order=2) * env(n, 0.0002, 0.012, 8.0) * 0.5
    return room(ring + strike, send=0.34)


def backboard():
    """Tempered glass: lower and far more damped than iron, plus mount rattle."""
    n = int(0.55 * SR)
    panel = modes(n, [204, 341, 552, 889, 1290], [0.20, 0.15, 0.11, 0.07, 0.05],
                  [1.0, 0.7, 0.42, 0.25, 0.15], detune=0.003)
    panel *= env(n, 0.0006, 0.40, 1.7)
    thud = lowpass(noise(n), 520.0, order=2) * env(n, 0.0005, 0.07, 4.0) * 0.8
    rattle = bandpass(noise(n), 2200.0, 7000.0, order=2) * env(n, 0.001, 0.05, 5.0) * 0.18
    return room(panel + thud + rattle, send=0.30)


def swish():
    """The net.

    Not one brush of noise: the ball passes twelve nylon cords in sequence, each
    a tiny scrape a few milliseconds apart, and each scrape is brighter at the
    top of the net than the bottom. Built as that sequence, which is why it now
    has a shape instead of a hiss."""
    n = int(0.42 * SR)
    out = np.zeros(n)
    for i in range(12):
        at = int((0.02 + 0.019 * i + RNG.uniform(-0.004, 0.004)) * SR)
        length = int(RNG.uniform(0.030, 0.065) * SR)
        if at + length >= n:
            break
        hi = 7500.0 - 380.0 * i
        scrape = bandpass(noise(length), max(900.0, hi * 0.35), hi, order=2)
        out[at:at + length] += scrape * env(length, 0.002, 0.05, 3.0) \
            * RNG.uniform(0.5, 1.0) * (1.0 - 0.04 * i)
    # The cords themselves flick - a faint pitched flutter under the scrapes.
    flick = modes(n, [430, 640, 910], [0.05, 0.04, 0.03], [0.25, 0.18, 0.1])
    flick *= env(n, 0.03, 0.30, 2.4)
    return room(out + flick, send=0.26)


def whistle():
    """A pealess referee whistle.

    Two chambers tuned a little apart, which is what makes the sound cut - the
    two tones beat against each other and the ear cannot ignore it. Plus the
    chiff of air at the start, before the chambers speak."""
    n = int(0.62 * SR)
    t = np.arange(n) / SR
    warble = 1.0 + 0.006 * np.sin(2.0 * math.pi * 26.0 * t)
    speak = np.clip(t / 0.03, 0.0, 1.0)          # chambers take a moment to sound
    tone = np.sin(2.0 * math.pi * 3180.0 * t * warble) * 1.0
    tone += np.sin(2.0 * math.pi * 4235.0 * t * warble) * 0.85
    tone += np.sin(2.0 * math.pi * 6360.0 * t * warble) * 0.22
    tone *= speak
    chiff = bandpass(noise(n), 2500.0, 9000.0, order=2) * env(n, 0.004, 0.06, 5.0) * 0.35
    body = bandpass(noise(n), 2800.0, 5200.0, order=2) * 0.10 * speak
    return room((tone + body) * env(n, 0.012, 0.55, 1.2) + chiff, send=0.40)


def buzzer():
    """The horn. A harmonic stack through a cabinet, not a raw sawtooth."""
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, a in ((233.0, 1.0), (349.0, 0.55), (466.0, 0.4), (699.0, 0.22),
                 (932.0, 0.14), (1165.0, 0.08)):
        out += a * np.sin(2.0 * math.pi * f * t * (1.0 + 0.0009 * np.sin(2 * math.pi * 5.5 * t)))
    out = resonate(out, 520.0, 2.5) * 0.6 + out * 0.7        # horn cabinet
    out = lowpass(out, 4200.0, order=2)
    shape = np.clip(t / 0.012, 0.0, 1.0) * np.clip((1.32 - t) / 0.08, 0.0, 1.0)
    return room(out * shape, send=0.45)


def crowd_bed(seconds=12.0):
    """Twelve seconds of arena murmur that loops without a seam.

    Roughly nine hundred overlapping voices, plus the low room tone a full
    building always has, plus slow swells so attention drifts the way a real
    crowd's does. Convolved with the arena so it sits behind the court rather
    than on top of the speakers."""
    n = int(seconds * SR)
    voices = crowd_layer(n, 900, effort=0.12, dur_lo=0.18, dur_hi=0.7,
                         gain_lo=0.05, gain_hi=0.22)
    # Distance: nobody in the murmur is close, so the treble is gone.
    voices = lowpass(voices, 5000.0, order=2)

    # Kept deliberately small. An earlier pass had the rumble at 0.5 and the
    # whole bed measured as a drone - flatness 0.000, centre of weight at 314 Hz,
    # which is a hum, not a building full of people.
    rumble = lowpass(noise(n), 150.0, order=2) * 0.16
    air = bandpass(noise(n), 250.0, 2400.0, order=2) * 0.16

    t = np.arange(n) / SR
    swell = 1.0
    for f, a in ((0.07, 0.20), (0.13, 0.12), (0.29, 0.07)):
        swell = swell + a * np.sin(2.0 * math.pi * f * t + f * 11.0)

    out = room((voices + rumble + air) * swell, send=0.30)
    x = int(0.7 * SR)
    ramp = np.linspace(0.0, 1.0, x)
    out[:x] = out[:x] * ramp + out[-x:] * ramp[::-1]
    return out[:-x]


def crowd_roar(seconds=3.4):
    """The reaction to a made basket.

    The same voices, but shouting - higher, brighter, throats open - arriving in
    a rush and thinning out. Claps are modelled as the cupped hand they come
    from: a short burst through a cavity resonance around 1.2 kHz, not a white
    tick."""
    n = int(seconds * SR)

    def early():
        return RNG.beta(1.6, 3.2)      # most voices arrive in the first second

    shout = crowd_layer(n, 700, effort=0.85, dur_lo=0.25, dur_hi=0.9,
                        gain_lo=0.08, gain_hi=0.30, when=early)
    murmur = crowd_layer(n, 250, effort=0.3, dur_lo=0.2, dur_hi=0.6,
                         gain_lo=0.04, gain_hi=0.14)

    claps = np.zeros(n)
    for _ in range(220):
        i = int(np.clip(early(), 0.0, 0.98) * n)
        L = int(0.045 * SR)
        if i + L < n:
            burst = bandpass(noise(L), 700.0, 6000.0, order=2)
            burst = resonate(burst, RNG.uniform(950.0, 1600.0), 4.0)
            claps[i:i + L] += burst * env(L, 0.0004, 0.03, 6.0) * RNG.uniform(0.15, 0.6)

    t = np.arange(n) / SR
    shape = np.clip(t / 0.30, 0.0, 1.0) ** 0.6 * np.exp(-np.maximum(t - 0.5, 0.0) / 1.5)
    rumble = lowpass(noise(n), 160.0, order=2) * 0.10
    voices = shout + murmur * 0.6
    # Shouting is not just louder, it is brighter - an open throat pushes energy
    # up. Without this lift the roar measured darker than the murmur it is
    # supposed to erupt out of, which is backwards.
    voices = voices + bandpass(voices, 1600.0, 7000.0, order=2) * 0.9
    return room((voices + claps * 1.3 + rumble) * shape, send=0.26)


# ------------------------------------------------------------------- output

def stereo(x, width=0.3):
    """Slight decorrelation so a mono source does not sit dead centre."""
    d = int(0.0011 * SR)
    r = np.concatenate([np.zeros(d), x[:-d]]) if d else x.copy()
    return np.stack([x, x * (1.0 - width) + r * width], axis=1)


def finish(x, peak=0.92, fade=0.004):
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
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("SFX: %-22s %5.2fs  %7.1f KB" % (os.path.basename(path),
          len(x) / SR, os.path.getsize(path) / 1024.0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)

    # Variants so a repeated bounce or step never fires the identical file twice.
    for i, h in enumerate([0.93, 1.0, 1.09], start=1):
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
