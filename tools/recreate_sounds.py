"""Premium sound set: every Windows sound gets its OWN motif, played on a smooth voice.

usage: python -I recreate_sounds.py <C:\\Windows\\Media> <startup.wav> <out_dir>

Design rules
  * one unique motif per event (checked at run time) - no two events sound alike
  * meaning in the shape: rising = connect/on/success, falling = remove/off/error,
    a lifted 'question' = asks you something, pulses = urgent, glides = window motion
  * core Windows 11 motifs kept (notification G3-D4, info F3-C4, error G4-D4, device G4<->D5,
    calendar C4-F4-G4, message C5-G4, startup F#3-C#4-G#4) - same key family (F/C/G)
  * 'silk' voice: sine-pure with a whisper of harmonics, 6-10 ms rounded attack, gentle
    chorus, no noise / no saturation, smooth top-end roll-off, short clean plate
  * loudness matched by perceived level (RMS), with per-category offsets
  * dark-mode copies (dm\\) rendered darker and 3 dB quieter
Alarms, ringtones and the paper 'recycle' sound keep their own melodies (gentle remix).
"""
import sys, os, glob, importlib.util
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('remix_sounds', os.path.join(HERE, 'remix_sounds.py'))
rx = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(rx)

SR = 48000
RNG = np.random.default_rng(21)
NOTE = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3,
        'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}


def hz(n):
    return 440.0 * 2 ** ((NOTE[n[:-1]] + 12 * (int(n[-1]) - 4)) / 12)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


# ---------------------------------------------------------------- the score
# notes: (time, note, velocity) - chord = same time; glide: (time, from, to, velocity)
# level: perceived loudness offset in dB (0 = standard notification level)
S = {
    # --- core Windows 11 motifs ---------------------------------------------------------
    # signature notification - UPGRADED Windows 11 motif: same G3 -> D4 and timing, played on
    # the silk voice, with a soft octave shimmer (D5) on the landing note and a faint warm bed
    'Windows Notify System Generic': dict(notes=[(0, 'G3', 1), (.11, 'D4', .78), (.115, 'D5', .22)],
                                          pad=['G2', 'D3'], total=1.5),
    'Windows Background':            dict(notes=[(0, 'F3', 1), (.12, 'C4', .6)], level=-3),
    'Windows Foreground':            dict(notes=[(0, 'G4', .6), (.10, 'D4', 1)], level=-1),
    'Windows Hardware Insert':       dict(notes=[(0, 'G4', 1), (.09, 'D5', .85)], level=-2),
    'Windows Hardware Remove':       dict(notes=[(0, 'D5', 1), (.09, 'G4', .8)], level=-2),
    'Windows Notify Calendar':       dict(notes=[(0, 'C4', .8), (.11, 'F4', 1), (.24, 'G4', .65)]),
    'Windows Notify Messaging':      dict(notes=[(0, 'C5', 1), (.12, 'G4', .9)]),
    'Windows Message Nudge':         dict(notes=[(0, 'G4', 1), (.015, 'A4', .5), (.03, 'D5', .25)]),
    # --- new, distinct motifs -----------------------------------------------------------
    'Windows Notify Email':          dict(notes=[(0, 'A4', .8), (.06, 'C5', .85), (.12, 'F5', 1)]),
    'Windows User Account Control':  dict(notes=[(0, 'C4', .7), (0, 'G4', .7), (.14, 'D5', 1)],
                                          pad=['C4', 'G4', 'D5']),            # 'may I?' lift
    'Windows Hardware Fail':         dict(notes=[(0, 'G4', 1), (.09, 'F4', .85), (.18, 'C4', .8)],
                                          bright=.6, level=-2),
    'Windows Critical Stop':         dict(notes=[(0, 'A3', 1), (0, 'F3', .8), (.16, 'D3', 1)],
                                          bright=.6, level=0),
    'Windows Error':                 dict(notes=[(0, 'E4', 1), (.10, 'B3', .9)], level=-1),
    'Windows Exclamation':           dict(notes=[(0, 'A4', .9), (.13, 'A4', .75)], level=-2),
    'Windows Default':               dict(notes=[(0, 'C5', .9)], level=-5),
    'Windows Ding':                  dict(notes=[(0, 'E5', .9)], level=-5),
    'Windows Notify':                dict(notes=[(0, 'D4', .9), (.09, 'A4', 1)]),
    'Windows Balloon':               dict(notes=[(0, 'F4', .8), (.08, 'C5', .8)], level=-3),
    'Windows Pop-up Blocked':        dict(notes=[(0, 'G3', .9)], bright=.5, level=-6),
    'Windows Print complete':        dict(notes=[(0, 'C4', .8), (.07, 'E4', .8), (.14, 'G4', .85), (.21, 'C5', 1)]),
    'Windows Battery Low':           dict(notes=[(0, 'E4', 1), (.22, 'C4', .9)], level=-1),
    'Windows Battery Critical':      dict(notes=[(0, 'C4', 1), (.18, 'C4', 1), (.36, 'C4', 1)], level=1),
    'Windows Logon':                 dict(notes=[(0, 'C4', .8), (.12, 'E4', .85), (.24, 'G4', 1)],
                                          pad=['C3', 'G3', 'E4'], total=2.0),
    'Windows Logoff Sound':          dict(notes=[(0, 'G4', 1), (.14, 'E4', .85), (.28, 'C4', .8)], total=1.8),
    'Windows Shutdown':              dict(notes=[(0, 'C5', 1), (.13, 'G4', .9), (.26, 'E4', .85), (.39, 'C4', .8)],
                                          pad=['C3', 'G3', 'C4'], total=2.4),
    'Windows Unlock':                dict(notes=[(0, 'G4', .8), (.06, 'C5', .9)], level=-5),
    'Windows Proximity Connection':  dict(notes=[(0, 'D4', .8), (.08, 'A4', .9), (.16, 'D5', 1)]),
    'Windows Proximity Notification': dict(notes=[(0, 'A4', .9), (.08, 'D5', 1)]),
    'Windows Ringin':                dict(notes=[(0, 'C5', 1), (.12, 'G4', .9), (.5, 'C5', 1), (.62, 'G4', .9)], total=1.6),
    'Windows Ringout':               dict(notes=[(0, 'G4', .9), (.45, 'G4', .9)], level=-3, total=1.2),
    'Speech On':                     dict(notes=[(0, 'C4', .9), (.09, 'G4', 1)], level=-3),
    'Speech Off':                    dict(notes=[(0, 'G4', 1), (.09, 'C4', .9)], level=-3),
    'Speech Sleep':                  dict(notes=[(0, 'E4', .9), (.25, 'C4', .7)], level=-4),
    'Speech Disambiguation':         dict(glide=(0, 'D4', 'A4', 1), level=-3),       # 'which one?'
    'Speech Misrecognition':         dict(notes=[(0, 'A3', .9), (.1, 'F3', .9)], level=-3),
    # tiny UI cues
    'Windows Menu Command':          dict(notes=[(0, 'C6', .5)], tick=True, level=-14),
    'Windows Navigation Start':      dict(notes=[(0, 'G5', .5)], tick=True, level=-16),
    'Windows Feed Discovered':       dict(notes=[(0, 'A5', .5), (.04, 'D6', .5)], tick=True, level=-12),
    'Windows Information Bar':       dict(notes=[(0, 'F5', .5)], tick=True, level=-12),
    'Windows Minimize':              dict(glide=(0, 'G5', 'C5', .6), tick=True, level=-14),
    'Windows Restore':               dict(glide=(0, 'C5', 'G5', .6), tick=True, level=-14),
    'Windows Startup':               dict(notes=[(0, 'B5', .5)], tick=True, level=-12),
    # classic file names
    'chimes':                        dict(notes=[(0, 'G4', .8), (.1, 'C5', .9), (.2, 'E5', 1)]),
    'chord':                         dict(notes=[(0, 'C4', .9), (.01, 'E4', .8), (.02, 'G4', .8), (.03, 'C5', .7)]),
    'ding':                          dict(notes=[(0, 'A5', .9)], level=-5),
    'notify':                        dict(notes=[(0, 'F4', .9), (.1, 'A4', 1)]),
    'ringout':                       dict(notes=[(0, 'D5', .9), (.45, 'D5', .9)], level=-3, total=1.2),
    'tada':                          dict(notes=[(0, 'C4', .8), (.09, 'G4', .85), (.18, 'C5', .9), (.27, 'E5', 1)],
                                          pad=['C3', 'G3', 'E4'], total=2.0),
}
# Startup - ORIGINAL composition (not derived from any Windows or Apple sound), in E-flat major:
# a low E-flat bloom, a rising four-note 'hello' (Bb4 Eb5 F5 G5) that lands on a held G5,
# and a soft IV -> I movement (Ab add9 swelling in, resolving home to E-flat) underneath.
STARTUP = dict(
    notes=[(.20, 'A#4', .60), (.38, 'D#5', .70), (.56, 'F5', .80), (.80, 'G5', 1.0),
           (.80, 'D#5', .35), (1.05, 'G6', .12)],                       # A#=Bb, D#=Eb
    pads=[(0.00, ['D#3', 'A#3', 'G4'], 4.2, 1.0),                       # E-flat home chord
          (0.80, ['G#3', 'D#4', 'A#4', 'C5'], 1.3, 0.8)],               # A-flat add9 passing chord
    sub='D#2', bright=1.05, total=4.2, hall=True)
REMIX_ONLY = ('Windows Recycle', 'recycle')
_tspec = importlib.util.spec_from_file_location('tones', os.path.join(HERE, 'tones.py'))
tones = importlib.util.module_from_spec(_tspec); _tspec.loader.exec_module(tones)


def motif_key(spec):
    if 'glide' in spec:
        g = spec['glide']; return ('glide', g[1], g[2])
    return tuple((round(t, 2), n) for t, n, _ in spec['notes'])


def check_unique():
    seen = {}
    for name, spec in S.items():
        k = motif_key(spec)
        if k in seen:
            raise SystemExit(f'Duplicate motif: {name} == {seen[k]}')
        seen[k] = name


# ---------------------------------------------------------------- the silk voice
def silk(f, dur, vel, bright=1.0, tick=False):
    """Smooth premium tone: sine core, whisper of harmonics, rounded attack, gentle chorus."""
    t = t_axis(dur)
    if tick:
        decay, attack = 0.045, 0.002
    else:
        decay, attack = 0.42 * (300 / f) ** 0.3, 0.007
    idx = 0.35 * bright * vel * np.exp(-t / 0.04)                    # brief definition only
    env = (1 - np.exp(-t / attack)) * np.exp(-t / decay)
    voices = []
    for cents, ph in ((-2.5, 0.0), (2.5, 0.35)):                    # chorus pair -> L / R (mono-safe)
        ff = f * 2 ** (cents / 1200)
        core = np.sin(2 * np.pi * ff * t + ph + idx * np.sin(2 * np.pi * ff * t))
        harm = (0.10 * bright) * np.sin(4 * np.pi * ff * t + ph) * np.exp(-t / (decay * 0.6))
        warm = 0.12 * np.sin(np.pi * ff * t) * np.exp(-t / (decay * 1.2))   # soft sub-octave
        voices.append((core + harm + warm) * env * vel)
    return voices


def glide_tone(f0, f1, dur, vel, tick=False):
    t = t_axis(dur)
    s = np.clip(t / (0.09 if tick else 0.22), 0, 1); s = s * s * (3 - 2 * s)
    fc = f0 * (f1 / f0) ** s
    ph = 2 * np.pi * np.cumsum(fc) / SR
    decay = 0.06 if tick else 0.35
    env = (1 - np.exp(-t / 0.006)) * np.exp(-t / decay)
    y = (np.sin(ph) + 0.08 * np.sin(2 * ph)) * env * vel
    return [y, np.roll(y, int(0.0004 * SR))]


def pad(notes, dur, fc=1100):
    t = t_axis(dur); y = np.zeros_like(t)
    for n in notes:
        f = hz(n)
        for det in (-0.004, 0.004):
            ff = f * (1 + det); ph = RNG.uniform(0, 6.28)
            for k in range(1, 10):
                y += (1 / k) * np.sin(2 * np.pi * ff * k * t + ph * k) / (1 + (ff * k / fc) ** 4)
    env = np.minimum(1, t / 0.25) ** 2 * np.clip((dur - t) / (dur * 0.7), 0, 1) ** 2
    return y * env


PLATE = rx.ir(0.9, 0.18, 6000, 0.018, 300)
HALL = rx.ir(2.6, 0.60, 5000, 0.030, 200)


def widen(x, g):
    m, s = (x[:, 0] + x[:, 1]) / 2, (x[:, 0] - x[:, 1]) / 2 * g
    return np.stack([m + s, m - s], 1)


def render(spec, dark=False):
    tick = spec.get('tick', False)
    total = spec.get('total', 0.5 if tick else 1.4)
    bright = spec.get('bright', 1.0) * (0.7 if dark else 1.0)
    L = np.zeros(int(total * SR)); R = np.zeros_like(L)

    def put(sig, at, pan):
        i = int(at * SR); gl = np.cos((pan + 1) * np.pi / 4) * 1.41; gr = np.sin((pan + 1) * np.pi / 4) * 1.41
        a, b = sig[0][: len(L) - i], sig[1][: len(R) - i]
        L[i:i + len(a)] += a * gl; R[i:i + len(b)] += b * gr

    if 'glide' in spec:
        at, a, b, v = spec['glide']
        put(glide_tone(hz(a), hz(b), total - at, v, tick), at, 0.0)
    else:
        notes = sorted({n for _, n, _ in spec['notes']}, key=hz)
        span = max(1, len(notes) - 1)
        for at, n, v in spec['notes']:
            pan = (-0.45 + 0.9 * notes.index(n) / span) if len(notes) > 1 else 0.0
            put(silk(hz(n), total - at, v, bright, tick), at, pan)
    if spec.get('pad'):
        p = pad(spec['pad'], total, fc=900 if dark else 1200) * 0.03
        put([p, p], 0.02, 0.0)
    for at, notes_, dur, lvl in spec.get('pads', []):                   # timed chord beds
        p = pad(notes_, dur, fc=900 if dark else 1300) * 0.03 * lvl
        put([p, np.roll(p, int(0.0006 * SR))], at, 0.0)
    if spec.get('sub'):                                                  # soft low foundation
        t = t_axis(total)
        sw = np.sin(2 * np.pi * hz(spec['sub']) * t) * np.minimum(1, t / 0.5) ** 2 \
            * np.clip((total - t) / (total * 0.6), 0, 1) ** 2 * 0.12
        put([sw, sw], 0.0, 0.0)
    x = np.stack([L, R], 1)
    space = HALL if spec.get('hall') else PLATE
    wet = 0.30 if spec.get('hall') else (0.12 if tick else 0.20)
    dry = np.concatenate([x, np.zeros((len(space), 2))])
    w = rx.conv(x, space)[: len(dry)]
    w = widen(np.concatenate([w, np.zeros((len(dry) - len(w), 2))]), 1.5)
    out = dry + wet * w * 1.5
    out = rx.highpass(out, 80)
    out = rx.lowpass(out, 3200 if dark else 4500, 2)                 # smooth, never shrill
    env = np.abs(out).max(1)
    last = np.nonzero(env > env.max() * 10 ** (-50 / 20))[0][-1] + 1
    out = out[:last]
    fd = min(len(out), int(0.05 * SR)); out[-fd:] *= np.linspace(1, 0, fd)[:, None]
    return out


def set_loudness(y, level_db, dark):
    """Match perceived loudness: RMS over the first 400 ms -> -26 dBFS + offset."""
    seg = y[: int(0.4 * SR)].mean(1)
    rms = np.sqrt((seg ** 2).mean()) + 1e-12
    target = 10 ** ((-26 + level_db - (3 if dark else 0)) / 20)
    y = y * target / rms
    pk = np.abs(y).max()
    return y * (10 ** (-1 / 20) / pk) if pk > 10 ** (-1 / 20) else y


def main(media, startup, out):
    check_unique()
    tones.check_unique()
    count = 0
    for sub in ('', 'dm'):
        dark = sub == 'dm'
        for f in sorted(glob.glob(os.path.join(media, sub, '*.wav'))):
            base = os.path.splitext(os.path.basename(f))[0]
            if base in S:
                spec = S[base]
                y = set_loudness(render(spec, dark), spec.get('level', 0), dark)
                how = 'own motif'
            elif base in tones.TONES:
                y = tones.render(base, rx)
                how = f'original composition: "{tones.TONES[base][0]}"'
            elif base.startswith(REMIX_ONLY):
                y, how = rx.remix(rx.load(f), legacy=True), 'gentle remix (keeps its melody)'
            else:
                print(f'!! no motif for {base} - left unchanged'); continue
            rx.save(os.path.join(out, sub, os.path.basename(f)), y)
            count += 1
            print(f'{os.path.join(sub, os.path.basename(f)):42s} {len(y) / SR:4.2f}s  {how}')
    y = tones.startup(rx)
    rx.save(os.path.join(out, 'Startup.wav'), y)
    print(f'{"Startup.wav":42s} {len(y) / SR:4.2f}s  original "Windows 12" startup (styles of 95 to 11 + macOS, F-sharp major)')
    print(f'{count + 1} files, {len(S)} unique motifs')
    # louder for laptop speakers, same sound: fixed gain per category + transparent limiter
    _lspec = importlib.util.spec_from_file_location('loudness', os.path.join(HERE, 'loudness.py'))
    loud = importlib.util.module_from_spec(_lspec); _lspec.loader.exec_module(loud)
    loud.finalize(out)
    # navigation UI sounds (*.raw, mono 16-bit 48 kHz) - replace the old ones too
    _rspec = importlib.util.spec_from_file_location('raw_sounds', os.path.join(HERE, 'raw_sounds.py'))
    raw = importlib.util.module_from_spec(_rspec); _rspec.loader.exec_module(raw)
    for name, y in raw.make().items():
        np.clip(np.round(y * 32767), -32768, 32767).astype('<i2').tofile(os.path.join(out, name))
    print('11 navigation UI sounds (*.raw) written')


if __name__ == '__main__':
    main(*sys.argv[1:4])
