"""Original alarms, ringtones and startup sound (numpy only, nothing sampled or remixed).

ALARMS are calm wake-ups (60-96 bpm, soft voices, no drums, start very soft and grow);
each has its own lead instrument and idea:
  Alarm01 Sunrise      string swell + bell melody          Alarm06 Horizon     slow rising synth swells
  Alarm02 Heartbeat    soft 'lub-dub' silk pulses + pad     Alarm07 Drift       flute melody over warm keys
  Alarm03 Meadow       slow harp triplets                   Alarm08 Rain        sparse mallet droplets + strings
  Alarm04 Glass Steps  glass-key steps with ping-pong echo  Alarm09 Chime Tower low bells, call & response
  Alarm05 Music Box    3/4 lullaby on soft bells            Alarm10 First Light gentle synth arpeggio, filter opens

RINGTONES have a mobile-ringtone vibe (98-124 bpm): a catchy 2-bar hook played 3 times,
building each pass (hook -> + soft beat & shaker -> + bass & counter-line), louder/clearer:
  Ring01 Chime Hook (bell)   Ring02 Two-Tone (e-piano stabs)  Ring03 Spark (16th pluck arp)
  Ring04 Groove (swung keys) Ring05 Island (marimba)          Ring06 Whistle (flute hook)
  Ring07 Pop (synth pluck)   Ring08 Orbit (circling synth)    Ring09 Double Ring (bells)
  Ring10 Strum (guitar-like strums + melody)

Startup: a reversed-reverb swell into one wide D-flat add9 chord (strike), deep
foundation, string bloom and a long cinematic tail - confident, not a jingle.
"""
import numpy as np

SR = 48000
RNG = np.random.default_rng(5)
PC = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
      'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}


def N(s):
    return 12 * (int(s[-1]) + 1) + PC[s[:-1]]


def F(s):
    return 440.0 * 2 ** ((N(s) - 69) / 12)


def tx(d):
    return np.arange(max(1, int(d * SR))) / SR


def env(t, d, a=0.005, decay=0.5, sus=0.0, rel=0.08):
    return (1 - np.exp(-t / a)) * (sus + (1 - sus) * np.exp(-t / decay)) * np.clip((d - t) / rel, 0, 1)


# ---------------------------------------------------------------- voices (mono)
def v_silk(f, d, v, vib=0.0, glide=None, decay=None, sus=0.0, a=0.006):
    t = tx(d)
    fc = f if glide is None else f + (glide - f) * np.exp(-t / 0.07)
    fc = fc * (1 + vib * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.3, 0, 1))
    ph = 2 * np.pi * np.cumsum(fc * np.ones_like(t)) / SR
    y = np.sin(ph) + 0.1 * np.sin(2 * ph) + 0.03 * np.sin(3 * ph)
    return y * env(t, d, a, decay or 0.5 * (300 / f) ** 0.3, sus) * v


def v_flute(f, d, v):
    t = tx(d)
    fc = f * (1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.15) / 0.3, 0, 1))
    ph = 2 * np.pi * np.cumsum(fc) / SR
    y = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    n = len(t); X = np.fft.rfft(RNG.normal(0, 1, n)); fr = np.fft.rfftfreq(n, 1 / SR)
    X *= np.exp(-((fr - 2 * f) / (f * 0.6)) ** 2); breath = np.fft.irfft(X, n)
    breath /= np.abs(breath).max() + 1e-9
    return (y + 0.05 * breath) * env(t, d, 0.06, 0.3, 0.85, 0.15) * v


def v_pluck(f, d, v):
    t = tx(d); base = 0.7 * (300 / f) ** 0.3; y = np.zeros_like(t)
    for k in range(1, 11):
        fk = f * k * (1 + 0.0004 * k * k)
        if fk > 8000:
            break
        y += k ** -1.6 * np.sin(2 * np.pi * fk * t) * np.exp(-t / (base / (1 + 0.45 * (k - 1))))
    return y * (1 - np.exp(-t / 0.002)) * np.clip((d - t) / 0.05, 0, 1) * v


def v_keys(f, d, v):
    t = tx(d); idx = (0.45 + 0.35 * v) * np.exp(-t / 0.1)
    y = np.sin(2 * np.pi * f * t + idx * np.sin(4 * np.pi * f * t))
    return y * env(t, d, 0.004, 0.9 * (300 / f) ** 0.35, 0, 0.1) * v


def v_mallet(f, d, v):
    t = tx(d)
    y = (np.sin(2 * np.pi * f * t) * np.exp(-t / 0.45) + 0.22 * np.sin(8 * np.pi * f * t) * np.exp(-t / 0.05))
    return y * (1 - np.exp(-t / 0.002)) * np.clip((d - t) / 0.05, 0, 1) * v


def v_bell(f, d, v):
    t = tx(d)
    y = np.sin(2 * np.pi * f * t + 1.2 * np.exp(-t / 0.25) * np.sin(4 * np.pi * f * t))
    y += 0.12 * np.sin(6 * np.pi * f * t) * np.exp(-t / 0.4)
    return y * env(t, d, 0.003, 1.4 * (300 / f) ** 0.3, 0, 0.2) * v


def _saw(f, t, fc, n_max=24, detune=(-0.006, 0.006)):
    y = np.zeros_like(t)
    for dt in detune:
        ff = f * (1 + dt); ph = RNG.uniform(0, 6.28)
        for k in range(1, n_max + 1):
            if ff * k > 9000:
                break
            y += (1 / k) * np.sin(2 * np.pi * ff * k * t + ph * k) / (1 + (ff * k / fc) ** 4)
    return y / len(detune)


def v_synth(f, d, v, fc_lo=500, fc_hi=3000, ftau=0.15, sus=0.0, decay=0.35, a=0.004):
    t = tx(d)
    return _saw(f, t, fc_lo + (fc_hi - fc_lo) * np.exp(-t / ftau)) * env(t, d, a, decay, sus, 0.08) * v * 0.6


def v_strings(f, d, v, fc=1500):
    t = tx(d)
    return _saw(f, t, fc, 16, (-0.007, 0.0, 0.0065)) * env(t, d, 0.25, 1.0, 1.0, 0.45) * v * 0.55


def v_sub(f, d, v):
    t = tx(d)
    return (np.sin(2 * np.pi * f * t) + 0.12 * np.sin(4 * np.pi * f * t)) * env(t, d, 0.01, 0.55, 0, 0.08) * v


def v_kick(f, d, v):
    t = tx(min(d, 0.35))
    fc = 45 + 75 * np.exp(-t / 0.035)
    return np.sin(2 * np.pi * np.cumsum(fc) / SR) * np.exp(-t / 0.16) * (1 - np.exp(-t / 0.001)) * v


def v_shaker(f, d, v):
    n = int(0.08 * SR); t = tx(0.08)
    X = np.fft.rfft(RNG.normal(0, 1, n)); fr = np.fft.rfftfreq(n, 1 / SR)
    X *= np.exp(-((np.log(fr + 1) - np.log(4200)) ** 2) / 0.12)
    y = np.fft.irfft(X, n); y /= np.abs(y).max() + 1e-9
    return y * np.exp(-t / 0.025) * v * 0.5


VOICES = dict(silk=v_silk, flute=v_flute, pluck=v_pluck, keys=v_keys, mallet=v_mallet, bell=v_bell,
              synth=v_synth, strings=v_strings, sub=v_sub, kick=v_kick, shaker=v_shaker)


# ---------------------------------------------------------------- sequencer
class Seq:
    def __init__(self, bpm, beats, tail=3.0, swing=0.0, accel=None, ramp=None):
        self.bpm, self.beats, self.swing, self.ramp = bpm, beats, swing, ramp
        if accel:                                       # tempo glides bpm -> accel over the piece
            b = np.linspace(0, beats, 4001)
            bpm_b = bpm + (accel - bpm) * b / beats
            self._tb = np.concatenate([[0], np.cumsum(60 / bpm_b[:-1] * np.diff(b))]); self._b = b
        else:
            self._b = None
        self.total = self.t(beats) + tail
        self.L = np.zeros(int(self.total * SR) + SR); self.R = np.zeros_like(self.L)
        self.fx = []

    def t(self, beat):
        if self.swing:
            whole, frac = divmod(beat, 1.0)
            if abs(frac - 0.5) < 1e-6:
                beat = whole + 0.5 + self.swing
        if self._b is not None:
            return float(np.interp(beat, self._b, self._tb))
        return beat * 60 / self.bpm

    def note(self, beat, pitch, dur, vel=1.0, voice='silk', pan=0.0, **kw):
        f = F(pitch) if isinstance(pitch, str) else pitch
        if self.ramp:                                   # alarms: grow from ramp -> 1.0
            vel *= self.ramp + (1 - self.ramp) * min(1.0, beat / (self.beats * 0.75))
        d = max(0.05, self.t(beat + dur) - self.t(beat))
        y = VOICES[voice](f, d, vel, **kw)
        i = int(self.t(beat) * SR); gl = np.cos((pan + 1) * np.pi / 4) * 1.41; gr = np.sin((pan + 1) * np.pi / 4) * 1.41
        n = min(len(y), len(self.L) - i - 40)
        self.L[i:i + n] += y[:n] * gl
        self.R[i + 20:i + 20 + n] += y[:n] * gr                     # 0.4 ms -> natural width

    def chord(self, beat, pitches, dur, vel=1.0, voice='keys', spread=0.5, roll=0.0, **kw):
        k = len(pitches)
        for j, p in enumerate(pitches):
            pan = (-spread + 2 * spread * j / max(1, k - 1)) if k > 1 else 0
            self.note(beat + j * roll, p, dur, vel, voice, pan, **kw)

    def mix(self):
        return np.stack([self.L, self.R], 1)


# ---------------------------------------------------------------- effects
def pingpong(x, delay, fb=0.4, mix=0.3, n=6):
    m = x.mean(1); out = x.copy(); d = int(delay * SR)
    for i in range(1, n + 1):
        ch = 0 if i % 2 else 1
        out[d * i:, ch] += m[:len(m) - d * i] * mix * fb ** (i - 1)
    return out


def tremolo(x, rate, depth):
    t = np.arange(len(x)) / SR
    return x * (1 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)))[:, None]


def autopan(x, rate, depth=0.8):
    t = np.arange(len(x)) / SR; p = depth * np.sin(2 * np.pi * rate * t)
    m = x.mean(1)
    return np.stack([m * np.cos((p + 1) * np.pi / 4), m * np.sin((p + 1) * np.pi / 4)], 1) * 1.41


# ---------------------------------------------------------------- the pieces
# ALARMS: calm wake-ups - slow, soft voices, no drums, start very soft and grow gently.
# Each has its own lead instrument and musical idea.

def sunrise():                                          # Alarm01 - strings swell + bell melody
    s = Seq(66, 16, tail=4, ramp=0.3)
    prog = [['F3', 'C4', 'E4', 'G4'], ['C3', 'G3', 'D4', 'E4'], ['D3', 'A3', 'E4', 'F4'], ['Bb2', 'F3', 'D4', 'A4']]
    mel = [['A4', 'C5', 'E5'], ['G4', 'C5', 'D5'], ['F4', 'A4', 'E5'], ['D5', 'C5', 'A4']]
    for i, (ch, m) in enumerate(zip(prog, mel)):
        s.chord(i * 4, ch, 4.2, 0.45, 'strings', spread=0.6)
        s.note(i * 4, ch[0], 4, 0.4, 'sub')
        for j, (b, p) in enumerate(zip((0, 1.5, 3), m)):
            s.note(i * 4 + b, p, 2, 0.5, 'bell', pan=(-0.3, 0.1, 0.35)[j])
    s.space = (2.4, 0.6, 0.30); return s


def heartbeat():                                        # Alarm02 - soft 'lub-dub' pulses over a pad
    s = Seq(64, 24, tail=4, ramp=0.25)
    pairs = [('D4', 'A4'), ('D4', 'A4'), ('B3', 'F#4'), ('G3', 'D4'), ('A3', 'E4'), ('D4', 'A4')]
    pads = [['D3', 'A3', 'F#4'], ['D3', 'A3', 'F#4'], ['B2', 'F#3', 'D4'], ['G2', 'D3', 'B3'],
            ['A2', 'E3', 'C#4'], ['D3', 'A3', 'F#4']]
    for bar, ((lo, hi), pd) in enumerate(zip(pairs, pads)):
        for b in range(4):
            s.note(bar * 4 + b, lo, 0.5, 0.55, 'silk', -0.15)
            s.note(bar * 4 + b + 0.28, hi, 0.6, 0.4, 'silk', 0.15)
        s.chord(bar * 4, pd, 4.2, 0.28, 'strings', spread=0.5, fc=900)
    s.space = (2.0, 0.5, 0.28); return s


def meadow():                                           # Alarm03 - slow harp triplets
    s = Seq(76, 16, tail=4, ramp=0.3)
    chords = [['C4', 'E4', 'G4', 'B4'], ['A3', 'C4', 'E4', 'G4'], ['F3', 'A3', 'C4', 'E4'], ['G3', 'B3', 'D4', 'G4']]
    order = [0, 1, 2, 3, 2, 1]
    for bar in range(4):
        c = chords[bar]
        for k in range(12):
            s.note(bar * 4 + k / 3, c[order[k % 6]], 1.4, 0.5, 'pluck', pan=-0.5 + order[k % 6] * 0.33)
        s.note(bar * 4, c[0][:-1] + '2', 4, 0.35, 'sub')
    s.space = (2.0, 0.5, 0.28); return s


def glass_steps():                                      # Alarm04 - slow glass-key steps, ping-pong
    s = Seq(80, 24, tail=4, ramp=0.3)
    pairs = [('E5', 'B4'), ('D5', 'A4'), ('C#5', 'A4'), ('D5', 'F#4'), ('B4', 'G4'), ('C#5', 'E4')]
    for bar in range(6):
        hi, lo = pairs[bar]
        for k in (0, 2):
            s.note(bar * 4 + k, hi, 1.2, 0.55, 'keys', pan=-0.7)
            s.note(bar * 4 + k + 1, lo, 1.2, 0.5, 'keys', pan=0.7)
    s.fx.append(lambda x: pingpong(x, 60 / 80 * 0.75, 0.35, 0.2))
    s.space = (1.6, 0.4, 0.2); return s


def music_box():                                        # Alarm05 - 3/4 lullaby on soft bells
    s = Seq(96, 36, tail=4, ramp=0.3)
    mel = [['G4', 'B4', 'D5'], ['C5', None, 'B4'], ['A4', 'G4', 'F#4'], ['G4', None, None],
           ['E4', 'G4', 'C5'], ['B4', None, 'A4'], ['G4', 'A4', 'B4'], ['A4', None, None],
           ['G4', 'B4', 'D5'], ['C5', 'B4', 'A4'], ['D5', None, 'F#4'], ['G4', None, None]]
    bass = ['G3', 'C3', 'D3', 'G3', 'C3', 'G3', 'E3', 'D3', 'G3', 'C3', 'D3', 'G3']
    for bar in range(12):
        s.note(bar * 3, bass[bar], 2.8, 0.35, 'silk', -0.3, decay=1.0)
        for b, p in enumerate(mel[bar]):
            if p:
                s.note(bar * 3 + b, p, 2.0 if b == 0 else 1.2, 0.5, 'bell', 0.25)
    s.space = (1.8, 0.45, 0.25); return s


def horizon():                                          # Alarm06 - long synth swells rising slowly
    s = Seq(60, 24, tail=4, ramp=0.3)
    chords = [['C3', 'G3', 'E4'], ['F3', 'C4', 'A4'], ['A2', 'E3', 'C4'], ['G2', 'D3', 'B3'],
              ['C3', 'G3', 'E4'], ['F3', 'A3', 'C4', 'E4']]
    for i, ch in enumerate(chords):
        for j, p in enumerate(ch):
            s.note(i * 4, p, 4.2, 0.45, 'synth', pan=-0.5 + j * 0.33, fc_lo=500, fc_hi=1300, ftau=1.2,
                   sus=0.9, decay=2.0, a=0.6)
        s.note(i * 4 + 1, ch[-1][:-1] + str(int(ch[-1][-1]) + 1), 2.5, 0.18, 'flute')
    s.fx.append(lambda x: tremolo(x, 0.4, 0.15))
    s.space = (2.6, 0.7, 0.32); return s


def drift():                                            # Alarm07 - flute melody over warm keys
    s = Seq(70, 16, tail=4, ramp=0.3)
    chords = [['F3', 'A3', 'C4', 'E4'], ['D3', 'F3', 'A3', 'C4'], ['Bb2', 'D3', 'F3', 'A3'], ['C3', 'E3', 'G3', 'Bb3']]
    mel = [(0, 'C5', 1.5), (1.5, 'A4', 0.5), (2, 'G4', 2), (4, 'A4', 1), (5, 'F4', 3), (8, 'D5', 1.5), (9.5, 'C5', 0.5),
           (10, 'A4', 2), (12, 'G4', 1), (13, 'E4', 1), (14, 'F4', 2)]
    for i, ch in enumerate(chords):
        s.chord(i * 4, ch, 2.0, 0.35, 'keys', spread=0.4, roll=0.04)
        s.chord(i * 4 + 2, ch, 2.0, 0.28, 'keys', spread=0.4, roll=0.04)
    for b, p, d in mel:
        s.note(b, p, d, 0.55, 'flute')
    s.space = (2.2, 0.55, 0.28); return s


def rain():                                             # Alarm08 - sparse mallet droplets over strings
    s = Seq(80, 24, tail=4, ramp=0.3)
    rng = np.random.default_rng(8)
    penta = ['C4', 'D4', 'E4', 'G4', 'A4', 'C5', 'D5', 'E5']
    b = 0.0
    while b < 23:
        s.note(b, penta[rng.integers(len(penta))], 1.5, 0.45 + 0.15 * rng.random(), 'mallet', pan=rng.uniform(-0.7, 0.7))
        b += rng.choice([0.5, 0.75, 1.0, 1.5])
    for i, ch in enumerate([['C3', 'G3', 'E4'], ['A2', 'E3', 'C4'], ['F2', 'C3', 'A3'], ['G2', 'D3', 'B3'],
                            ['C3', 'G3', 'E4'], ['F2', 'C3', 'A3']]):
        s.chord(i * 4, ch, 4.3, 0.3, 'strings', spread=0.6, fc=1000)
    s.space = (2.2, 0.55, 0.3); return s


def chime_tower():                                      # Alarm09 - low bell call & response, big hall
    s = Seq(72, 24, tail=5, ramp=0.3)
    call = [['C4', 'D4', 'E4'], ['E4', 'G4', 'D4']]
    resp = [['G3', 'A3', 'C4'], ['C4', 'A3', 'G3']]
    for ph in range(4):
        c, r = call[ph % 2], resp[ph % 2]
        for k, p in enumerate(c):
            s.note(ph * 6 + k * 0.6, p, 2.5 if k == 2 else 1.4, 0.6, 'bell', pan=-0.4)
        for k, p in enumerate(r):
            s.note(ph * 6 + 3 + k * 0.6, p, 2.5 if k == 2 else 1.4, 0.55, 'bell', pan=0.4)
        s.note(ph * 6, 'C3', 5.8, 0.3, 'strings', fc=900)
    s.space = (3.0, 0.8, 0.36); return s


def first_light():                                      # Alarm10 - gentle 8th-note synth arpeggio, filter opens
    s = Seq(88, 32, tail=3, ramp=0.3)
    arps = [['E3', 'B3', 'E4', 'G4'], ['C3', 'G3', 'C4', 'E4'], ['G3', 'D4', 'G4', 'B4'], ['D3', 'A3', 'D4', 'F#4']]
    for bar in range(8):
        cut = 400 + 1600 * (bar / 7) ** 1.3
        for k in range(8):
            p = arps[bar % 4][(0, 1, 2, 3, 2, 1, 2, 1)[k]]
            s.note(bar * 4 + k * 0.5, p, 0.6, 0.5, 'synth', pan=0.35 * np.sin(k), fc_lo=cut * 0.6, fc_hi=cut, ftau=0.1)
        s.note(bar * 4, arps[bar % 4][0][:-1] + '2', 3.8, 0.45, 'sub')
    s.space = (1.8, 0.45, 0.25); return s


# RINGTONES: mobile-ringtone vibe - a catchy 2-bar hook played 3 times, building each pass:
# pass 1 hook (+ light harmony), pass 2 + soft beat & shaker, pass 3 + bass & counter-line.

def ring_loop(bpm, hook, voice, chords, roots, harmony_voice='keys', swing=0.0, counter=None, **kw):
    s = Seq(bpm, 24, tail=2.5, swing=swing)
    for rep in range(3):
        o = rep * 8
        for b, p, d in hook:
            s.note(o + b, p, d, 0.85, voice, 0.15, **kw)
        for i, ch in enumerate(chords):
            s.chord(o + i * 2, ch, 1.9, 0.28, harmony_voice, spread=0.5, roll=0.02)
        if rep >= 1:
            for k in range(8):
                s.note(o + k, 50, 0.4, 0.7, 'kick')
                s.note(o + k + 0.5, 0, 0.1, 0.22, 'shaker', pan=0.45)
        if rep >= 2:
            for i, r in enumerate(roots):
                s.note(o + i * 2, r, 0.9, 0.6, 'sub'); s.note(o + i * 2 + 1.5, r, 0.4, 0.45, 'sub')
            for b, p, d in (counter or []):
                s.note(o + b, p, d, 0.35, 'silk', -0.35)
    s.space = (1.2, 0.28, 0.18); return s


def chime_hook():                                       # Ring01 - bright bell hook
    hook = [(0, 'C5', .4), (.5, 'E5', .4), (1, 'G4', .4), (1.5, 'C5', .6), (2.5, 'D5', .4), (3, 'E5', .9),
            (4, 'D5', .4), (4.5, 'C5', .4), (5, 'A4', .4), (6, 'G4', .4), (6.75, 'A4', .25), (7, 'C5', .9)]
    return ring_loop(116, hook, 'bell', [['C4', 'E4', 'G4'], ['A3', 'C4', 'E4'], ['F3', 'A3', 'C4'], ['G3', 'B3', 'D4']],
                     ['C2', 'A1', 'F1', 'G1'], counter=[(1, 'G4', 1), (3, 'E4', 1), (5, 'F4', 1), (7, 'D4', 1)])


def two_tone():                                         # Ring02 - 'ring-ring' e-piano stabs + answer
    s = Seq(118, 24, tail=2.5)
    a, b = ['C4', 'E4', 'G4', 'B4'], ['A3', 'C4', 'E4', 'B4']
    for rep in range(3):
        for half in range(2):
            o = rep * 8 + half * 4
            ch = a if half == 0 else b
            for x in (0, 0.5):
                s.chord(o + x, ch, 0.4, 0.75, 'keys', spread=0.4)
            s.note(o + 2, ('G5', 'A5')[half], 0.5, 0.55, 'keys', 0.3)
            s.note(o + 2.5, ('E5', 'E5')[half], 1.0, 0.5, 'keys', 0.3)
            if rep >= 1:
                for k in range(4):
                    s.note(o + k, 50, 0.4, 0.65, 'kick')
            if rep >= 2:
                s.note(o, ch[0][:-1] + '2', 1.5, 0.6, 'sub'); s.note(o + 2.5, ch[0][:-1] + '2', 1.0, 0.45, 'sub')
    s.space = (1.2, 0.26, 0.18); return s


def spark():                                            # Ring03 - 16th-note pluck arpeggio hook
    hook = []
    arps = [['A3', 'C4', 'E4', 'A4'], ['F3', 'A3', 'C4', 'F4'], ['C4', 'E4', 'G4', 'C5'], ['G3', 'B3', 'D4', 'G4']]
    for i, c in enumerate(arps):
        for k, idx in enumerate((0, 1, 2, 3, 2, 3, 1, 2)):
            hook.append((i * 2 + k * 0.25, c[idx], 0.3))
    return ring_loop(112, hook, 'pluck', [], ['A1', 'F1', 'C2', 'G1'],
                     counter=[(0, 'E5', 1.5), (2, 'C5', 1.5), (4, 'E5', 1.5), (6, 'D5', 1.5)])


def groove():                                           # Ring04 - swung e-piano hook
    hook = [(0, 'A4', .4), (.5, 'C5', .4), (1, 'E5', .6), (1.75, 'D5', .4), (2.5, 'C5', .4), (3, 'A4', .8),
            (4, 'G4', .4), (4.5, 'A4', .4), (5, 'C5', .6), (6, 'D5', .4), (6.5, 'E5', 1.2)]
    return ring_loop(98, hook, 'keys', [['F3', 'A3', 'C4', 'E4'], ['E3', 'G3', 'B3', 'D4'],
                                        ['D3', 'F3', 'A3', 'C4'], ['C3', 'E3', 'G3', 'B3']],
                     ['F1', 'E1', 'D1', 'C2'], harmony_voice='keys', swing=0.12,
                     counter=[(1, 'C4', 1), (3, 'B3', 1), (5, 'A3', 1), (7, 'G3', 1)])


def island():                                           # Ring05 - syncopated marimba tune
    hook = [(0, 'G4', .5), (.75, 'A4', .5), (1.5, 'C5', .6), (2.5, 'D5', .4), (3, 'C5', .6), (4, 'E5', .5),
            (4.75, 'D5', .5), (5.5, 'C5', .5), (6.5, 'A4', .9)]
    return ring_loop(108, hook, 'mallet', [['C4', 'E4', 'G4'], ['A3', 'C4', 'E4'], ['F3', 'A3', 'C4'], ['G3', 'B3', 'D4']],
                     ['C2', 'A1', 'F1', 'G1'], harmony_voice='pluck',
                     counter=[(1, 'E4', .8), (3, 'C4', .8), (5, 'A3', .8), (7, 'B3', .8)])


def whistle():                                          # Ring06 - whistle-like flute hook
    hook = [(0, 'G4', .45), (.5, 'B4', .45), (1, 'D5', .9), (2, 'B4', .45), (2.5, 'C5', .45), (3, 'A4', .9),
            (4, 'G4', .45), (4.5, 'A4', .45), (5, 'B4', .45), (5.5, 'D5', .45), (6, 'E5', .9), (7, 'D5', .9)]
    return ring_loop(108, hook, 'flute', [['G3', 'B3', 'D4'], ['C4', 'E4', 'G4'], ['A3', 'C4', 'E4'], ['D4', 'F#4', 'A4']],
                     ['G1', 'C2', 'A1', 'D2'], harmony_voice='pluck',
                     counter=[(1.5, 'D4', .5), (3.5, 'E4', .5), (5.5, 'C4', .5), (7.5, 'F#4', .5)])


def pop_pluck():                                        # Ring07 - upbeat synth-pluck pop hook
    hook = [(0, 'E4', .4), (.5, 'G4', .4), (1, 'B4', .6), (1.75, 'A4', .5), (2.5, 'G4', .4), (3, 'E4', .8),
            (4, 'C5', .4), (4.5, 'B4', .4), (5, 'G4', .6), (5.75, 'A4', .5), (6.5, 'B4', 1.2)]
    return ring_loop(122, hook, 'synth', [['E3', 'G3', 'B3'], ['C3', 'E3', 'G3'], ['G3', 'B3', 'D4'], ['D3', 'F#3', 'A3']],
                     ['E1', 'C2', 'G1', 'D2'], harmony_voice='keys', fc_lo=700, fc_hi=2600, ftau=0.08,
                     counter=[(2, 'B4', 1), (6, 'D5', 1)])


def orbit():                                            # Ring08 - circling synth arpeggio + bell accents
    hook = []
    arps = [['D4', 'F4', 'A4', 'C5'], ['Bb3', 'D4', 'F4', 'A4'], ['C4', 'E4', 'G4', 'C5'], ['A3', 'C4', 'E4', 'A4']]
    for i, c in enumerate(arps):
        for k, idx in enumerate((0, 1, 2, 3, 2, 1, 2, 3)):
            hook.append((i * 2 + k * 0.25, c[idx], 0.28))
    s = ring_loop(124, hook, 'synth', [], ['D2', 'Bb1', 'C2', 'A1'], fc_lo=700, fc_hi=2200, ftau=0.05,
                  counter=[(0, 'E5', 1.5), (2, 'D5', 1.5), (4, 'E5', 1.5), (6, 'C5', 1.5)])
    s.fx.append(lambda x: autopan(x, 0.45, 0.8)); return s


def double_ring():                                      # Ring09 - modern double-strike bell rings
    s = Seq(100, 24, tail=3)
    chords = [['G4', 'B4', 'D5'], ['A4', 'C5', 'E5'], ['F#4', 'A4', 'D5'], ['G4', 'B4', 'E5']]
    for rep in range(3):
        for i, ch in enumerate(chords[:2] if rep % 2 == 0 else chords[2:]):
            o = rep * 8 + i * 4
            for x in (0, 0.2):
                s.chord(o + x, ch, 1.2, 0.7, 'bell', spread=0.5)
            s.note(o + 2, ch[2], 0.5, 0.45, 'bell', 0.4); s.note(o + 2.5, ch[1], 1.0, 0.4, 'bell', -0.4)
            if rep >= 1:
                s.note(o, 50, 0.4, 0.6, 'kick'); s.note(o + 2, 50, 0.4, 0.6, 'kick')
            if rep >= 2:
                s.note(o, ch[0][:-1] + '2', 3, 0.5, 'sub')
    s.space = (1.6, 0.4, 0.22); return s


def strum():                                            # Ring10 - rhythmic guitar-like strums + melody
    s = Seq(104, 24, tail=2.5)
    chords = [['G3', 'B3', 'D4', 'G4'], ['D3', 'A3', 'D4', 'F#4'], ['E3', 'B3', 'E4', 'G4'], ['C3', 'G3', 'C4', 'E4']]
    mel = [(0, 'B4', .9), (1, 'D5', .45), (1.5, 'B4', .45), (2, 'A4', 1.8), (4, 'B4', .9), (5, 'G4', .45),
           (5.5, 'A4', .45), (6, 'B4', .9), (7, 'D5', .9)]
    for rep in range(3):
        o = rep * 8
        for i, ch in enumerate(chords):
            for x, v in ((0, 0.6), (0.75, 0.45), (1.5, 0.5)):
                s.chord(o + i * 2 + x, ch, 0.7, v, 'pluck', spread=0.6, roll=0.025)
        for b, p, d in mel:
            s.note(o + b, p, d, 0.7 if rep else 0.6, 'silk', 0.15)
        if rep >= 1:
            for k in range(8):
                s.note(o + k, 50, 0.4, 0.6, 'kick'); s.note(o + k + 0.5, 0, 0.1, 0.2, 'shaker', pan=0.4)
        if rep >= 2:
            for i, ch in enumerate(chords):
                s.note(o + i * 2, ch[0][:-1] + '2', 1.8, 0.55, 'sub')
    s.space = (1.2, 0.28, 0.18); return s


TONES = {
    'Alarm01': ('Sunrise', sunrise), 'Alarm02': ('Heartbeat', heartbeat), 'Alarm03': ('Meadow', meadow),
    'Alarm04': ('Glass Steps', glass_steps), 'Alarm05': ('Music Box', music_box), 'Alarm06': ('Horizon', horizon),
    'Alarm07': ('Drift', drift), 'Alarm08': ('Rain', rain), 'Alarm09': ('Chime Tower', chime_tower),
    'Alarm10': ('First Light', first_light),
    'Ring01': ('Chime Hook', chime_hook), 'Ring02': ('Two-Tone', two_tone), 'Ring03': ('Spark', spark),
    'Ring04': ('Groove', groove), 'Ring05': ('Island', island), 'Ring06': ('Whistle', whistle),
    'Ring07': ('Pop', pop_pluck), 'Ring08': ('Orbit', orbit), 'Ring09': ('Double Ring', double_ring),
    'Ring10': ('Strum', strum),
}


def check_unique():
    fns = [fn for _, fn in TONES.values()]
    if len(set(fns)) != len(fns):
        raise SystemExit('Two tones share the same composition')


def master(x, rx, space, lp=6000, rms_db=-21):
    size, decay, wet = space
    ir = rx.ir(size, decay, 5500, 0.022, 250)
    w = rx.conv(x, ir)[: len(x)]
    m, s = (w[:, 0] + w[:, 1]) / 2, (w[:, 0] - w[:, 1]) / 2 * 1.4
    out = x + wet * np.stack([m + s, m - s], 1) * 1.5
    out = rx.lowpass(rx.highpass(out, 40), lp, 2)
    env_ = np.abs(out).max(1)
    last = np.nonzero(env_ > env_.max() * 10 ** (-55 / 20))[0][-1] + 1
    out = out[:last]
    fd = min(len(out), int(0.25 * SR)); out[-fd:] *= np.linspace(1, 0, fd)[:, None]
    rms = np.sqrt((out.mean(1) ** 2).mean()) + 1e-12
    out *= 10 ** (rms_db / 20) / rms
    pk = np.abs(out).max()
    return out * (10 ** (-1 / 20) / pk) if pk > 10 ** (-1 / 20) else out


def render(name, rx):
    s = TONES[name][1]()
    x = s.mix()
    for fx in s.fx:
        x = fx(x)
    if name.startswith('Alarm'):                       # calm: softer top, quieter overall
        return master(x, rx, s.space, lp=4500, rms_db=-24)
    return master(x, rx, s.space, lp=7000, rms_db=-19)  # ringtone: clear, cuts through


# ---------------------------------------------------------------- startup
def startup(rx):
    """'Windows 12' startup - an ORIGINAL composition that walks through the styles of past
    startup sounds without copying any of their melodies or recordings:
      0.0-1.1 s  95-style ambient pad swell with soft shimmer sparkles + reversed swell
      0.55-1.1s  Vista/7-style quick glassy rising flourish into the hit
      1.1 s      macOS-style single big, confident chord strike (the centrepiece)
      1.1 s+     2000/XP/98-style string sweep, warm piano body, bright rising air
      1.6-2.4 s  soft echo of the Windows 11 rising-fifths idea (re-performed)
    Key F-sharp major (shared by Windows 11's motif and the Mac chime); the voicing is our own:
    stacked fifths + ninth + major third.
    """
    total, hit = 6.6, 1.10
    L = np.zeros(int(total * SR)); R = np.zeros_like(L)
    rng = np.random.default_rng(95)

    def put(y, at, pan=0.0, haas=0, gain=1.0):
        i = int(at * SR); gl = np.cos((pan + 1) * np.pi / 4) * 1.41; gr = np.sin((pan + 1) * np.pi / 4) * 1.41
        n = min(len(y), len(L) - i - haas)
        L[i:i + n] += y[:n] * gl * gain; R[i + haas:i + haas + n] += y[:n] * gr * gain

    # Neutral, grounded character: no flute sparkles, no bells, open-fifth voicing with only a
    # low, quiet third for warmth, more low-mid weight, darker top.

    # --- 1) 95-style ambient opening: low, dark pad swell (no sparkles)
    t = tx(hit + 0.4)
    for p, pan in (('F#2', -0.5), ('C#3', 0.5), ('F#3', -0.2), ('C#4', 0.2)):
        y = _saw(F(p), t, 650, 10) * (np.clip(t / hit, 0, 1) ** 2) * np.clip((hit + 0.4 - t) / 0.4, 0, 1)
        put(y, 0.0, pan, gain=0.12)

    # --- 2) Vista/7-style flourish, re-voiced as a low-mid filtered-synth sweep into the hit
    for k, p in enumerate(['F#3', 'C#4', 'F#4', 'G#4']):
        put(v_synth(F(p), 1.2, 0.4 + 0.08 * k, fc_lo=500, fc_hi=1800, ftau=0.25, decay=0.5),
            hit - 0.42 + k * 0.1, -0.45 + 0.3 * k)

    # --- 3) macOS-style centrepiece: one wide, confident chord strike - open fifths + ninth,
    #        the major third (A#3) kept low and quiet just for warmth
    voicing = [('F#1', .3), ('F#2', .45), ('C#3', .85), ('G#3', .9), ('A#3', .35), ('C#4', 1), ('F#4', 1), ('G#4', .75)]
    pans = [0, 0, -0.3, 0.3, 0.0, -0.45, 0.45, 0.15]
    strike = np.zeros((int(4.0 * SR), 2))
    for k, ((p, g), pan) in enumerate(zip(voicing, pans)):
        f = F(p); d = 5.2
        y = (0.45 * v_keys(f, d, 0.6) + 0.55 * v_silk(f, d, 0.65, decay=1.9 * (300 / f) ** 0.25)
             + 0.35 * v_synth(f, d, 0.6, fc_lo=700, fc_hi=1600, ftau=0.6, sus=0.5, decay=1.5, a=0.01))
        put(y, hit + k * 0.008, pan, haas=10 + 3 * k, gain=g)
        gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        n = min(len(y), len(strike)); strike[:n, 0] += y[:n] * gl * g; strike[:n, 1] += y[:n] * gr * g

    # reversed-reverb swell pulling into the strike
    hall = rx.ir(3.2, 0.85, 5000, 0.02, 180)
    wet = rx.conv(strike, hall)[: int(1.0 * SR)]
    rev = wet[::-1] * np.linspace(0, 1, len(wet))[:, None] ** 2
    i0 = int(hit * SR) - len(rev)
    L[i0:i0 + len(rev)] += rev[:, 0] * 0.4; R[i0:i0 + len(rev)] += rev[:, 1] * 0.4

    # --- 4) 2000/XP/98 layers: lower string sweep, warm piano body, solid foundation
    for p, pan in (('F#2', -0.6), ('C#3', 0.6), ('G#3', -0.3), ('C#4', 0.3)):
        put(v_strings(F(p), 4.6, 0.4, fc=1100), hit - 0.1, pan)
    put(v_keys(F('F#3'), 4.0, 0.5), hit + 0.02, 0.0, gain=0.7)
    t = tx(total)
    sub = np.sin(2 * np.pi * F('F#1') * t) * np.clip((t - 0.5) / 0.6, 0, 1) ** 2 * np.exp(-np.clip(t - hit, 0, None) / 1.8)
    put(sub * 0.2, 0.0)

    # --- 5) Windows 11 nod: rising fifths, re-performed an octave lower
    for k, p in enumerate(['F#3', 'C#4', 'G#4']):
        put(v_silk(F(p), 2.4, 0.25, decay=0.9), hit + 0.55 + k * 0.3, (-0.4, 0.0, 0.4)[k])

    x = np.concatenate([np.stack([L, R], 1), np.zeros((int(2.5 * SR), 2))])   # room for the tail
    return master(x, rx, (3.0, 0.8, 0.30), lp=5000, rms_db=-21)
