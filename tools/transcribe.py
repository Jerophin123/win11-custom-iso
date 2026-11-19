"""Transcribe short chime-style sounds into note events (time, midi, level).

STFT peak tracking + onset detection; harmonics of a simultaneous stronger lower note
are dropped (the new instrument regenerates its own harmonics).
"""
import wave
import numpy as np

SR = 48000
NAMES = 'C C# D D# E F F# G G# A A# B'.split()


def name(m):
    return f"{NAMES[m % 12]}{m // 12 - 1}"


def load(path):
    with wave.open(path) as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        a = np.frombuffer(w.readframes(n), {1: np.uint8, 2: '<i2'}[sw]).astype(np.float64)
    a = (a - 128) / 128 if sw == 1 else a / 32768
    a = a.reshape(-1, ch).mean(1)
    if sr != SR:
        n_out = int(round(len(a) * SR / sr))
        X = np.fft.rfft(a); Y = np.zeros(n_out // 2 + 1, complex); k = min(len(Y), len(X)); Y[:k] = X[:k]
        a = np.fft.irfft(Y, n_out) * (n_out / len(a))
    return a


def transcribe(x, fmin=140, fmax=2600, hop=240, win=8192, thresh_db=-34):
    pad = np.concatenate([np.zeros(win // 2), x, np.zeros(win)])
    w = np.hanning(win)
    frames = range(0, len(x), hop)
    fr = np.fft.rfftfreq(win, 1 / SR)
    band = (fr > fmin) & (fr < fmax)
    midi_of_bin = np.full(len(fr), -1)
    midi_of_bin[band] = np.round(69 + 12 * np.log2(fr[band] / 440)).astype(int)
    S = []
    for i in frames:
        mag = np.abs(np.fft.rfft(pad[i:i + win] * w))
        # energy per semitone
        e = np.zeros(128)
        np.maximum.at(e, midi_of_bin[band], mag[band])
        S.append(e)
    S = np.array(S)                                     # frames x 128
    gmax = S.max() + 1e-12
    db = 20 * np.log10(S / gmax + 1e-9)
    events = []
    look = int(0.03 * SR / hop)
    for m in range(128):
        col = db[:, m]
        if col.max() < thresh_db:
            continue
        # local spectral peak in pitch (ignore leakage into neighbour semitones)
        nb = np.maximum(db[:, max(m - 1, 0)], db[:, min(m + 1, 127)])
        active = (col > thresh_db) & (col >= nb)
        i = 0
        while i < len(col):
            if active[i] and (i < look or col[i] - col[max(0, i - look)] > 6 or not active[max(0, i - 1)]):
                j = i
                while j + 1 < len(col) and col[j + 1] >= col[j] - 0.1 and j - i < look * 4:
                    j += 1                                   # climb to the local maximum
                level = col[j]
                end = j
                while end + 1 < len(col) and col[end + 1] > level - 30:
                    end += 1
                events.append([i * hop / SR, m, level, (end - i) * hop / SR])
                i = end + 1
            else:
                i += 1
    events.sort()
    # drop harmonics (12, 19, 24, 28 semitones above) of a stronger note starting together
    keep = []
    for e in events:
        harmonic = any(abs(e[0] - k[0]) < 0.05 and (e[1] - k[1]) in (12, 19, 24, 28, 31) and k[2] > e[2] - 3
                       for k in keep)
        # merge re-triggers of the same note within 60 ms
        dup = any(abs(e[0] - k[0]) < 0.06 and e[1] == k[1] for k in keep)
        if not harmonic and not dup:
            keep.append(e)
    top = max(k[2] for k in keep) if keep else 0
    return [(round(t, 3), m, round(l - top, 1), round(d, 2)) for t, m, l, d in keep if l - top > -24]


if __name__ == '__main__':
    import sys, os
    for p in sys.argv[1:]:
        ev = transcribe(load(p))
        s = '  '.join(f"{t:.2f}s {name(m)}({l:+.0f})" for t, m, l, d in ev)
        print(f"{os.path.basename(p):36s} {s}")
