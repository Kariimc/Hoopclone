"""Measure whether the arena's sounds are sounds, or just noise with a shape.

    python verify_sfx.py --dir ../../assets/audio
    python verify_sfx.py --dir ../../assets/audio --against /path/to/old

The owner's report on the first sound set was "low quality, just sounds like a
staticy old TV". That is not a matter of taste, it is measurable, so this
measures it rather than asking anyone to listen and agree.

THE THREE NUMBERS

FLATNESS (spectral flatness, 0 to 1). The geometric mean of the power spectrum
over its arithmetic mean. White noise - which is exactly what television static
is - scores 1.0, because every frequency carries the same energy. A struck bell
scores near 0.00x, because its energy sits in a handful of modes. This is the
single number that separates "a sound" from "hiss", and it is the one the first
set failed.

CREST (peak over RMS, in dB). How much punch is left. A transient like a bounce
or a clap should tower over its own average; noise sits flat at about 11 dB. A
low crest on a percussive sound means the hit has been smeared away.

CENTRE (spectral centroid, Hz). Where the weight of the sound sits. Catches a
dribble that has lost its bass or a whistle that is not where a whistle lives.

Each sound is checked against the band its own physics puts it in - a rim and a
crowd cannot be held to the same bar - and every limit below is written next to
the reason for it.
"""
import argparse, os, sys, wave
import numpy as np

# name -> (max flatness, min MOVEMENT dB, min crest dB, centroid low Hz,
#          centroid high Hz, why)
#
# MOVEMENT is the fourth number, and it exists because flatness alone cannot
# tell a crowd from a drone. A hum and a hall full of people can both be
# spectrally narrow; what separates them is that the crowd never holds still.
# It is the spread (standard deviation) of the sound's own loudness across its
# frames, in dB. A held tone sits near 0. Anything built from many small
# independent events breathes, and has to.
EXPECT = {
    "dribble": (0.15, 0.0, 14.0, 120, 2600,
                "a bounce is a struck body: modes plus one sharp transient"),
    "squeak":  (0.20, 0.0, 10.0, 700, 5000,
                "rubber stick-slip has a pitch, so it cannot be broadband"),
    "rim":     (0.02, 0.0, 12.0, 400, 4000,
                "iron rings in a few modes and almost nothing else"),
    "backboard": (0.05, 0.0, 12.0, 150, 2500,
                  "glass rings lower and duller than iron, but still rings"),
    "swish":   (0.35, 2.0, 11.0, 1500, 8000,
                "twelve cords brushed in sequence - textural, but sequenced"),
    "whistle": (0.02, 0.0, 8.0, 2500, 7000,
                "two tuned chambers; anything flat here is escaping air"),
    "buzzer":  (0.02, 0.0, 6.0, 150, 2500,
                "a harmonic stack through a horn cabinet"),
    "crowd_bed": (0.30, 1.5, 8.0, 400, 1400,
                  "hundreds of voices with formants - not a noise bed, not a hum"),
    "crowd_roar": (0.30, 1.5, 9.0, 500, 2000,
                   "the same voices shouting, so brighter but still voices"),
}


def read_wav(path):
    with wave.open(path) as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError("expected 16-bit, got %d-bit" % (sw * 8))
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def measure(x, sr):
    win = 2048
    hop = 512
    if len(x) < win:
        x = np.pad(x, (0, win - len(x)))
    w = np.hanning(win)
    flats, cents, energies, levels = [], [], [], []
    for i in range(0, len(x) - win, hop):
        seg = x[i:i + win] * w
        if np.sqrt(np.mean(seg ** 2)) < 1e-4:
            continue                      # silence has no spectrum worth reading
        p = np.abs(np.fft.rfft(seg)) ** 2 + 1e-20
        flats.append(np.exp(np.mean(np.log(p))) / np.mean(p))
        f = np.fft.rfftfreq(win, 1.0 / sr)
        cents.append(float(np.sum(f * p) / np.sum(p)))
        energies.append(float(np.sum(p)))
        levels.append(20.0 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9))
    if not flats:
        return 1.0, 0.0, 0.0, 0.0
    e = np.array(energies)
    e = e / (e.sum() or 1.0)
    # Weight by energy: the loud part of a sound is the part anyone hears.
    flat = float(np.sum(np.array(flats) * e))
    cent = float(np.sum(np.array(cents) * e))
    rms = float(np.sqrt(np.mean(x ** 2))) or 1e-9
    crest = 20.0 * np.log10((float(np.max(np.abs(x))) or 1e-9) / rms)
    move = float(np.std(np.array(levels))) if len(levels) > 2 else 0.0
    return flat, crest, cent, move


def base_name(fname):
    stem = os.path.splitext(fname)[0]
    if stem.rsplit("_", 1)[-1].isdigit():
        stem = stem.rsplit("_", 1)[0]
    return stem


def scan(d):
    out = {}
    for f in sorted(os.listdir(d)):
        if not f.endswith(".wav"):
            continue
        x, sr = read_wav(os.path.join(d, f))
        out[f] = measure(x, sr)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--against", help="an older set, to print the change")
    args = ap.parse_args()

    now = scan(args.dir)
    before = scan(args.against) if args.against else {}
    if not now:
        print("SFX-CHECK: no .wav files in %s" % args.dir)
        return 1

    print("SFX-CHECK: %d files in %s" % (len(now), args.dir))
    print("SFX-CHECK: flatness 1.0 = television static, 0.0 = a pure tone; "
          "move 0 dB = a held drone")
    fails = []
    for f, (flat, crest, cent, move) in now.items():
        base = base_name(f)
        exp = EXPECT.get(base)
        note = ""
        if base in before or f in before:
            b = before.get(f) or before.get(base)
            note = "   was flat %.3f" % b[0]
        if exp is None:
            print("SFX-CHECK:   %-16s flat %.3f  crest %5.1f dB  centre %6.0f Hz  "
                  "move %4.1f dB   (no expectation set)%s"
                  % (f, flat, crest, cent, move, note))
            continue
        max_flat, min_move, min_crest, lo, hi, why = exp
        bad = []
        if flat > max_flat:
            bad.append("flat %.3f > %.3f" % (flat, max_flat))
        if move < min_move:
            bad.append("move %.1f < %.1f dB, a drone not a texture" % (move, min_move))
        if crest < min_crest:
            bad.append("crest %.1f < %.1f dB" % (crest, min_crest))
        if not (lo <= cent <= hi):
            bad.append("centre %.0f Hz outside %d-%d" % (cent, lo, hi))
        if bad:
            fails.append("%s: %s (%s)" % (f, "; ".join(bad), why))
        print("SFX-CHECK:   %-16s flat %.3f  crest %5.1f dB  centre %6.0f Hz  "
              "move %4.1f dB%s%s"
              % (f, flat, crest, cent, move, note, "   <-- OFF" if bad else ""))

    if fails:
        print("SFX-CHECK: FAIL - %d file(s) outside their band:" % len(fails))
        for line in fails:
            print("SFX-CHECK:   %s" % line)
        return 1
    print("SFX-CHECK: PASS - every sound has structure, punch and the right weight")
    return 0


if __name__ == "__main__":
    sys.exit(main())
