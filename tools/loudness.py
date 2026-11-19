"""Final loudness stage: make the set louder for laptop speakers WITHOUT changing the sound.

  * a fixed gain per category (every sound in a category moves by the same amount, so the
    balance between sounds - and the dark-mode copies being softer - is preserved)
  * a transparent look-ahead peak limiter at -1 dBFS that only touches the few peaks that
    would otherwise clip (no EQ, no compression of the body of the sound)

Called by recreate_sounds.py after the set is written; can also be run on a folder of
freshly generated files:  python -I loudness.py <sounds\\set>
"""
import os, sys, glob, wave
import numpy as np

SR = 48000
CEILING = 10 ** (-1 / 20)
MAX_LIMIT_DB = 3.0          # never shave peaks by more than this -> attacks stay intact
DARK_OFFSET = -3.0          # dark-mode copies stay a little softer
# target loudness (RMS of the audible part, dBFS) per role
TARGET = {'system': -18.0, 'urgent': -17.0, 'soft': -21.0, 'tick': -26.0,
          'startup': -16.0, 'alarm': -18.0, 'ring': -15.0}
URGENT = ('Windows Foreground', 'Windows Critical Stop', 'Windows Error', 'Windows Battery Critical',
          'Windows Battery Low', 'Windows Hardware Fail', 'Windows User Account Control')
SOFT = ('Windows Background', 'Windows Default', 'Windows Ding', 'ding', 'Windows Unlock',
        'Windows Pop-up Blocked', 'Windows Exclamation', 'Speech On', 'Speech Off', 'Speech Sleep',
        'Speech Disambiguation', 'Speech Misrecognition', 'Windows Recycle', 'recycle')
TICK = ('Windows Menu Command', 'Windows Navigation Start', 'Windows Feed Discovered',
        'Windows Information Bar', 'Windows Minimize', 'Windows Restore', 'Windows Startup')


def category(name):
    if name == 'Startup':
        return 'startup'
    if name.startswith('Alarm'):
        return 'alarm'
    if name.startswith('Ring'):
        return 'ring'
    if name in URGENT:
        return 'urgent'
    if name in SOFT:
        return 'soft'
    if name in TICK:
        return 'tick'
    return 'system'


def active_rms_db(x):
    """Loudness of the audible part only (ignores silent tails)."""
    env = np.abs(x).max(1)
    act = x[env > env.max() * 0.05]
    return 20 * np.log10(np.sqrt((act ** 2).mean()) + 1e-12)


def read(path):
    with wave.open(path) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), '<i2').reshape(-1, w.getnchannels()).astype(np.float64)
    return a / 32768


def write(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(x.shape[1]); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def _sliding_min(v, n):
    pad = np.concatenate([np.full(n, 1.0), v, np.full(n, 1.0)])
    out = v.copy()
    for k in range(-n, n + 1, max(1, n // 16)):            # coarse but conservative window min
        out = np.minimum(out, pad[n + k:n + k + len(v)])
    return out


def limit(x, ceiling=CEILING, look_ms=5.0, release_ms=120.0):
    """Look-ahead limiter: gain never lets |x| exceed the ceiling; smooth attack/release."""
    peak = np.abs(x).max(1)
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-12))
    if need.min() >= 1.0:
        return x, 0.0
    n = int(look_ms / 1000 * SR)
    g = _sliding_min(need, n)
    k = np.ones(n) / n                                       # smooth the attack ramp
    gp = np.pad(g, (n // 2, n - 1 - n // 2), mode='edge')    # edge padding: no dip at file start/end
    g = np.minimum(np.convolve(gp, k, 'valid'), _sliding_min(need, n // 2 or 1))
    # release: gain may only rise slowly (one-pole), never above what's needed
    a = np.exp(-1.0 / (release_ms / 1000 * SR))
    out = np.empty_like(g); cur = 1.0
    for i, gi in enumerate(g):
        cur = gi if gi < cur else gi + (cur - gi) * a
        out[i] = cur
    y = x * out[:, None]
    y = np.clip(y, -ceiling, ceiling)                        # safety for any residual sample
    return y, float(-20 * np.log10(out.min()))


def finalize(folder, verbose=True):
    paths = sorted(glob.glob(os.path.join(folder, '**', '*.wav'), recursive=True))
    cat_of = {p: category(os.path.splitext(os.path.basename(p))[0]) for p in paths}
    rows = []
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        x = read(path)
        before = active_rms_db(x)
        dark = os.path.basename(os.path.dirname(path)).lower() == 'dm'
        target = TARGET[cat_of[path]] + (DARK_OFFSET if dark else 0.0)
        g_db = target - before
        head = 20 * np.log10(CEILING / (np.abs(x).max() + 1e-12))
        g_db = min(g_db, head + MAX_LIMIT_DB)                 # never needs > 3 dB of peak limiting
        clean = x * 10 ** (g_db / 20)
        y, gr = limit(clean)
        write(path, y)
        after = active_rms_db(y)
        # how much the limiter changed the signal vs a pure volume change (lower = cleaner)
        diff = 20 * np.log10(np.sqrt(((y - clean) ** 2).mean()) / (np.sqrt((clean ** 2).mean()) + 1e-12) + 1e-12)
        over = int((np.abs(y) > CEILING + 1e-6).sum())
        rows.append((os.path.relpath(path, folder), category(name), before, after, gr, diff, over))
    if verbose:
        for cat in TARGET:
            r = [x for x in rows if x[1] == cat]
            if r:
                lo, hi = min(x[3] for x in r), max(x[3] for x in r)
                print(f'{cat:8s} {len(r):3d} files  loudness {lo:6.1f} .. {hi:6.1f} dB (target {TARGET[cat]:.0f}, '
                      f'dark -3)  max peak limiting {max(x[4] for x in r):.1f} dB  samples over ceiling {sum(x[6] for x in r)}')
    return rows


if __name__ == '__main__':
    finalize(sys.argv[1])
