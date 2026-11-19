"""Gentle 'modern remix' of the Windows 11 sound set (numpy + stdlib only).

usage: python -I remix_sounds.py <C:\\Windows\\Media> <startup.wav> <out_dir>

Takes the sounds that ship with Windows 11 and keeps each melody/timing exactly, adding:
  * warm bloom   - octave-down copy washed in a soft reverb (body, depth)
  * shimmer      - octave-up copy, low-passed and washed in reverb (modern sheen, kept quiet)
  * airy space   - short clean plate (pre-delay, low-cut on the tail so it never gets muddy)
  * polish       - gentle top-end smoothing; legacy bright sounds get a stronger roll-off
Octave layers are always in tune with the original, so nothing can clash.
Old Vista/7-era sounds that still ship (Ding, Error, Critical Stop, Battery, Shutdown ...)
are replaced by remixes of their modern Windows 11 counterparts so everything is one family.
Output: 48 kHz / 16-bit stereo, same file names (plus dm\\ dark-mode copies and Startup.wav).
For personal use on your own installs - these are derived from Microsoft's sounds.
"""
import sys, os, wave, glob
import numpy as np

SR = 48000
RNG = np.random.default_rng(11)

# legacy file -> modern Windows 11 sound it should become
LEGACY_MAP = {
    'Windows Ding': 'Windows Background', 'Windows Default': 'Windows Background',
    'Windows Exclamation': 'Windows Background', 'Windows Notify': 'Windows Background',
    'Windows Balloon': 'Windows Background', 'Windows Pop-up Blocked': 'Windows Background',
    'Windows Print complete': 'Windows Background',
    'Speech On': 'Windows Background', 'Speech Off': 'Windows Background', 'Speech Sleep': 'Windows Background',
    'Speech Disambiguation': 'Windows Background', 'Speech Misrecognition': 'Windows Background',
    'Windows Critical Stop': 'Windows Foreground', 'Windows Error': 'Windows Foreground',
    'Windows Battery Low': 'Windows Hardware Remove', 'Windows Logoff Sound': 'Windows Hardware Remove',
    'Windows Shutdown': 'Windows Hardware Remove',
    'Windows Battery Critical': 'Windows Hardware Fail',
    'Windows Unlock': 'Windows Hardware Insert', 'Windows Logon': 'Windows Hardware Insert',
    'Windows Proximity Connection': 'Windows Hardware Insert',
    'Windows Proximity Notification': 'Windows Notify Messaging',
    'Windows Ringin': 'Windows Notify Messaging', 'Windows Ringout': 'Windows Notify Messaging',
}
# modern Windows 11 sounds (already warm): standard polish
MODERN = {'Windows Background', 'Windows Foreground', 'Windows Hardware Fail', 'Windows Hardware Insert',
          'Windows Hardware Remove', 'Windows Notify Calendar', 'Windows Notify Email',
          'Windows Notify Messaging', 'Windows Notify System Generic', 'Windows Message Nudge',
          'Windows User Account Control'}


# ---------------------------------------------------------------- io
def load(path):
    with wave.open(path) as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    a = np.frombuffer(raw, {1: np.uint8, 2: '<i2', 4: '<i4'}[sw]).astype(np.float64)
    a = (a - 128) / 128 if sw == 1 else a / 2 ** (8 * sw - 1)
    a = a.reshape(-1, ch)
    if ch == 1:
        a = np.repeat(a, 2, 1)
    return resample(a[:, :2], sr, SR)


def save(path, st):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(st * 32767, -32768, 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------- dsp
def lowpass(x, fc, order=2):
    X = np.fft.rfft(x, axis=0); fr = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1 / np.sqrt(1 + (fr / fc) ** (2 * order)))[:, None]
    return np.fft.irfft(X, len(x), axis=0)


def highpass(x, fc, order=2):
    X = np.fft.rfft(x, axis=0); fr = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1 / np.sqrt(1 + (fc / (fr + 1e-9)) ** (2 * order)))[:, None]
    return np.fft.irfft(X, len(x), axis=0)


def resample(x, sr_in, sr_out):
    """Band-limited resample via FFT (exact for our use)."""
    if sr_in == sr_out:
        return x
    n_out = int(round(len(x) * sr_out / sr_in))
    X = np.fft.rfft(x, axis=0)
    m = n_out // 2 + 1
    Y = np.zeros((m, x.shape[1]), complex)
    k = min(m, X.shape[0]); Y[:k] = X[:k]
    return np.fft.irfft(Y, n_out, axis=0) * (n_out / len(x))


def octave(x, up):
    """Pitch-shift by an octave (speed change): in tune by definition."""
    if up:
        return resample(lowpass(x, SR / 4.4, 4), SR, SR // 2)[: len(x)]   # play 2x faster
    return resample(x, SR, SR * 2)                                         # play 2x slower


def ir(seconds, decay, damp, predelay, lowcut):
    n = int(seconds * SR); t = np.arange(n) / SR
    chans = []
    for _ in range(2):
        e = RNG.normal(0, 1, n) * np.exp(-t / decay)
        e[: int(predelay * SR)] = 0
        chans.append(e)
    h = np.stack(chans, 1)
    h = highpass(lowpass(h, damp, 1), lowcut, 1)
    return h / np.sqrt((h ** 2).sum(0, keepdims=True))


PLATE = ir(1.2, 0.22, 7000, 0.022, 250)     # airy, clean space
BLOOM = ir(1.6, 0.36, 3500, 0.030, 120)     # warm wash for the octave-down layer
SHIM = ir(1.4, 0.30, 6000, 0.040, 600)
SMALL = ir(0.6, 0.10, 6000, 0.010, 300)     # for tiny UI clicks


def conv(x, h):
    n = len(x) + len(h) - 1; N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N, axis=0) * np.fft.rfft(h, N, axis=0), N, axis=0)[:n]


def audible_len(x):
    env = np.abs(x).max(1)
    return (np.nonzero(env > env.max() * 0.01)[0][-1] + 1) / SR


def remix(x, legacy=False):
    peak_in = np.abs(x).max() + 1e-12
    tail = len(BLOOM)
    dry = np.concatenate([x, np.zeros((tail, 2))])
    def fit(y):
        y = y[: len(dry)]
        return np.concatenate([y, np.zeros((len(dry) - len(y), 2))])
    if audible_len(x) < 0.3:                                       # tiny UI click: light touch only
        out = dry + 0.15 * fit(conv(x, SMALL))
        out = lowpass(highpass(out, 80), 4000, 2)
    else:
        space = fit(conv(x, PLATE))
        bloom = fit(conv(lowpass(octave(x, up=False), 2500), BLOOM))
        shim = fit(conv(lowpass(octave(x, up=True), 6000), SHIM))
        out = dry + 0.20 * space + 0.10 * bloom + 0.04 * shim
        out = highpass(out, 60)
        out = lowpass(out, 5000 if legacy else 10000, 1)           # polish / tame legacy brightness
    # trim silent tail, short fade, keep Windows' original loudness
    env = np.abs(out).max(1)
    last = np.nonzero(env > env.max() * 10 ** (-50 / 20))[0][-1] + 1
    out = out[:last]
    f = min(len(out), int(0.05 * SR)); out[-f:] *= np.linspace(1, 0, f)[:, None]
    return out * (peak_in / (np.abs(out).max() + 1e-12))


# ---------------------------------------------------------------- main
def main(media, startup, out):
    done = 0
    for sub in ('', 'dm'):
        files = sorted(glob.glob(os.path.join(media, sub, '*.wav')))
        cache = {}
        for f in files:
            name = os.path.splitext(os.path.basename(f))[0]
            src_name = LEGACY_MAP.get(name)
            if src_name:
                src_path = os.path.join(media, sub, src_name + '.wav')
                if not os.path.exists(src_path):                     # dm folder has only modern files
                    src_path = os.path.join(media, src_name + '.wav')
                if src_path not in cache:
                    cache[src_path] = remix(load(src_path))
                y = cache[src_path] * (10 ** (-3 / 20) if sub == 'dm' else 1)
                how = f'<- {src_name}'
            else:
                y = remix(load(f), legacy=name not in MODERN)
                how = 'remix' + ('' if name in MODERN else ' (softened)')
            save(os.path.join(out, sub, os.path.basename(f)), y)
            done += 1
            print(f'{os.path.join(sub, os.path.basename(f)):42s} {len(y) / SR:4.2f}s  {how}')
    y = remix(load(startup))
    save(os.path.join(out, 'Startup.wav'), y)
    print(f'{"Startup.wav":42s} {len(y) / SR:4.2f}s  remix of the Windows 11 startup sound')
    print(f'{done + 1} files')


if __name__ == '__main__':
    main(*sys.argv[1:4])
