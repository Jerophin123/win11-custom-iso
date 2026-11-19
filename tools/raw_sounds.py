"""Replacements for Windows' navigation UI sounds (C:\\Windows\\Media\\*_48000Hz.raw).

Format matches the originals exactly: headerless 16-bit little-endian PCM, MONO, 48 kHz,
similar length and level (peaks ~ -21 dBFS). Same 'silk' voice as the rest of the set.

usage: python -I raw_sounds.py <out_dir>
"""
import os, sys, importlib.util
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_s = importlib.util.spec_from_file_location('recreate_sounds', os.path.join(HERE, 'recreate_sounds.py'))
rs = importlib.util.module_from_spec(_s); _s.loader.exec_module(rs)
SR = 48000
PEAK = 10 ** (-21 / 20)
SMALL = rs.rx.ir(0.4, 0.06, 6000, 0.008, 300)


def mono_of(pair):
    return (pair[0] + pair[1]) / 2


def place(buf, sig, at):
    i = int(at * SR); n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n]


def tick(note, dur):
    return mono_of(rs.silk(rs.hz(note), dur, 0.9, tick=True))


def tone(note, dur, vel=1.0):
    return mono_of(rs.silk(rs.hz(note), dur, vel))


def glide(a, b, dur, tick_=False):
    return mono_of(rs.glide_tone(rs.hz(a), rs.hz(b), dur, 1.0, tick_))


def finish(x, wet=0.10):
    st = np.stack([x, x], 1)
    w = rs.rx.conv(st, SMALL)[: len(st)]
    y = (st + wet * w * 1.5).mean(1)
    y = rs.rx.lowpass(rs.rx.highpass(y[:, None], 90), 4500, 2)[:, 0]
    f = min(len(y), int(0.01 * SR)); y[-f:] *= np.linspace(1, 0, f)
    return y * PEAK / (np.abs(y).max() + 1e-12)


def make():
    out = {}
    for k, n in enumerate(['C5', 'D5', 'E5', 'G5', 'A5']):          # focus ticks, each its own pitch
        d = 0.045
        out[f'Focus{k}_48000Hz.raw'] = finish(tick(n, d), wet=0.05)
    b = np.zeros(int(0.33 * SR)); place(b, tone('E5', 0.3, 0.8), 0); place(b, tone('G5', 0.25, 0.9), 0.06)
    out['MoveNext_48000Hz.raw'] = finish(b)
    b = np.zeros(int(0.37 * SR)); place(b, tone('G5', 0.3, 0.8), 0); place(b, tone('E5', 0.3, 0.9), 0.06)
    out['MovePrevious_48000Hz.raw'] = finish(b)
    b = np.zeros(int(0.51 * SR)); place(b, tone('C5', 0.5, 0.7), 0); place(b, tone('G5', 0.5, 0.6), 0)
    place(b, tone('E5', 0.45, 0.9), 0.07)
    out['Invoke_48000Hz.raw'] = finish(b)
    out['GoBack_48000Hz.raw'] = finish(glide('G5', 'C5', 0.66))
    out['Show_48000Hz.raw'] = finish(glide('C5', 'G5', 0.82) + 0.25 * glide('G5', 'D6', 0.82), wet=0.18)
    out['Hide_48000Hz.raw'] = finish(glide('E5', 'A4', 0.64), wet=0.15)
    return out


if __name__ == '__main__':
    od = sys.argv[1]
    os.makedirs(od, exist_ok=True)
    for name, y in make().items():
        np.clip(np.round(y * 32767), -32768, 32767).astype('<i2').tofile(os.path.join(od, name))
        print(f'{name:28s} {len(y) / SR * 1000:5.0f} ms  peak {20 * np.log10(np.abs(y).max()):5.1f} dBFS  mono 16-bit 48 kHz')
