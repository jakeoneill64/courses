import math

import numpy as np
from matplotlib.colors import LinearSegmentedColormap

from omhfig import C, Diagram, plot, save, setup


def thrust_stand():
    d = Diagram(168, 80)
    d.text(3, 76, "Mechanical", size=8.4, weight="bold", color=C["muted"], ha="left")
    d.text(84, 76, "Measurement chain", size=8.4, weight="bold", color=C["muted"], ha="left")
    d.line((2, 6), (74, 6), color=C["muted"], lw=1.2)
    d.rect(6, 6, 14, 24, fill=C["grey"], edge=C["muted"], lw=0.9, z=2)
    d.text(13, 13, "heavy\nbase", size=6.8, color=C["muted"])
    d.box(20, 24, 34, 6, "load cell", kind="navy_t", size=7.2, radius=0.6)
    d.rect(40, 30, 18, 2.4, fill=C["amber_t"], edge=C["amber"], lw=0.9, z=3)
    d.box(43, 32.4, 12, 8.6, "motor", kind="grey", size=7.0, radius=0.8)
    d.line((49, 41), (49, 45), color=C["ink"], lw=1.4, z=4)
    d.line((29, 45), (69, 45), color=C["ink"], lw=2.6, z=5)
    d.circle(49, 45, 1.3, kind="navy")
    for x in (35, 49, 63):
        d.arrow((x, 48.5), (x, 60), color=C["navy"], lw=0.9, dashed=True, mutation=6)
    d.text(49, 64.5, "air blown upward:\nkeep two propeller diameters clear", size=6.8, color=C["navy"])
    d.arrow((51, 22.6), (51, 12), color=C["coral"], lw=1.6, mutation=8)
    d.text(53.5, 15.5, "thrust presses the\nfree end down, like a\nmass on the platform", size=6.6, color=C["coral"], ha="left")
    d.text(60, 33, "calibration\nmasses go here", size=6.4, color=C["amber"], ha="left")

    lipo = d.box(82, 60, 18, 10, "3S LiPo", kind="navy", size=7.8)
    sh = d.box(106, 62, 16, 6, "1 mΩ shunt", kind="coral_t", size=6.8, radius=0.8)
    esc = d.box(128, 60, 16, 10, "ESC", kind="grey", size=7.8)
    mot = d.box(150, 60, 16, 10, "motor", kind="grey", size=7.6)
    d.arrow(lipo.e, sh.w_, color=C["coral"], lw=2.0, mutation=7)
    d.arrow(sh.e, esc.w_, color=C["coral"], lw=2.0, mutation=7)
    d.arrow(esc.e, mot.w_, color=C["coral"], lw=1.2, mutation=6)
    d.text(147, 72, "3 phases", size=6.4, color=C["muted"])
    ina = d.box(104, 40, 20, 9, "INA228", kind="navy_t", size=7.8)
    d.line(sh.bottom(0.25), (ina.x + 5, ina.y + ina.h), color=C["navy"], lw=0.8)
    d.line(sh.bottom(0.75), (ina.x + 15, ina.y + ina.h), color=C["navy"], lw=0.8)
    d.text(103, 55.5, "Kelvin\nsense pair", size=6.2, color=C["navy"], ha="right")
    pi = d.box(82, 14, 22, 12, "Raspberry Pi 5", kind="navy", size=7.6)
    ads = d.box(110, 15.5, 18, 9, "ADS1220", kind="navy_t", size=7.6)
    lc = d.box(136, 15.5, 22, 9, "load cell", kind="plain", size=7.4, weight="normal")
    d.path([pi.top(0.5), (93, 44.5), ina.w_], color=C["ink"], lw=0.9, mutation=6)
    d.text(91.5, 36, "I²C", size=6.8, color=C["muted"], ha="right")
    d.path([pi.top(0.86), (100.9, 33), (136, 33), esc.bottom()], color=C["purple"], lw=0.9, mutation=6)
    d.text(118, 35, "servo PWM", size=6.8, color=C["purple"])
    d.arrow(pi.e, ads.w_, both=True, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(107, 23.2, "SPI", size=6.6, color=C["muted"])
    d.arrow(lc.w_, ads.e, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(132, 23.2, "bridge", size=6.6, color=C["muted"])
    sc = d.box(150, 38, 16, 9, "scope", kind="plain", size=7.4, weight="normal")
    d.arrow(mot.bottom(), sc.top(), color=C["muted"], lw=0.8, dashed=True, mutation=5.5)
    d.text(147.5, 52.5, "one phase:\nspeed", size=6.2, color=C["muted"], ha="right")
    d.save("u3-thrust-stand")


def foc():
    d = Diagram(168, 72)
    d.group(40, 12, 100, 54, "", color=C["purple"])
    d.text(42, 14.5, "runs once per PWM period, started by the ADC", size=6.8, color=C["purple"], weight="bold", ha="left")
    d.circle(8, 50, 2.2, kind="plain")
    d.text(8, 50, "Σ", size=6.6)
    d.arrow((0.5, 50), (5.8, 50), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(2.5, 53.5, r"$\omega^*$", size=8)
    sp = d.box(14, 45.5, 18, 9, "speed PI", kind="navy_t", size=7.6)
    d.arrow((10.2, 50), sp.w_, color=C["ink"], lw=0.9, mutation=5.5)
    cur = d.box(46, 42, 26, 16, "current PI", sub="d and q axes", kind="navy", size=7.8)
    d.arrow(sp.e, cur.left(0.5), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(38.5, 53.5, r"$i_q^*$", size=8)
    d.arrow((59, 70), cur.top(), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(61, 67.5, r"$i_d^* = 0$", size=8, ha="left")
    ip = d.box(84, 45.5, 20, 9, "inverse Park", kind="navy_t", size=7.4)
    d.arrow(cur.e, ip.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(78, 53.5, r"$v_d, v_q$", size=7.6)
    sv = d.box(116, 45.5, 18, 9, "SVPWM", kind="navy_t", size=7.6)
    d.arrow(ip.e, sv.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(110, 53.5, r"$v_\alpha, v_\beta$", size=7.6)
    inv = d.box(146, 43, 21, 14, "inverter", sub="ePWM, DRV8323RS", kind="grey", size=7.6, sub_size=5.6)
    d.arrow(sv.e, inv.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.circle(156.5, 22, 6.5, kind="navy", label="M", size=9)
    d.arrow(inv.bottom(), (156.5, 28.5), color=C["coral"], lw=1.3, mutation=6)
    d.text(158.5, 35.5, "3 phases", size=6.4, color=C["muted"], ha="left")
    adc = d.box(122, 17.5, 16, 9, "ADC", kind="navy_t", size=7.6)
    d.arrow((150, 22), adc.e, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(144, 25.5, r"$i_a, i_b$", size=7.6)
    cl = d.box(92, 17.5, 18, 9, "Clarke", kind="navy_t", size=7.6)
    d.arrow(adc.w_, cl.e, color=C["ink"], lw=0.9, mutation=5.5)
    pk = d.box(58, 17.5, 18, 9, "Park", kind="navy_t", size=7.6)
    d.arrow(cl.w_, pk.e, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(84, 25, r"$i_\alpha, i_\beta$", size=7.6)
    d.arrow((63, 26.5), (63, cur.y), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(61.5, 35, r"$i_d, i_q$", size=7.6, ha="right")
    ob = d.box(84, 29.5, 22, 9, "flux observer", sub="and PLL", kind="purple_t", size=6.8, sub_size=6.0)
    d.arrow((100, 26.5), (100, ob.y), color=C["ink"], lw=0.8, mutation=5)
    d.arrow((99, ip.y), (99, ob.y + ob.h), color=C["ink"], lw=0.8, mutation=5)
    d.arrow((88, ob.y + ob.h), (88, ip.y), color=C["purple"], lw=0.9, mutation=5)
    d.path([ob.left(0.5), (72, 34), (72, 26.5)], color=C["purple"], lw=0.9, mutation=5.5)
    d.text(78, 36.4, r"$\theta$", size=8, color=C["purple"])
    d.arrow((8, 38), (8, 47.8), color=C["purple"], lw=0.9, mutation=5.5)
    d.text(8, 35, r"$\hat{\omega}$ from the observer", size=7, color=C["purple"])
    d.save("u3-foc")


def complementary():
    fig, (a1, a2) = plot(h=58, ncols=2, gridspec_kw={"width_ratios": [1, 1.25], "wspace": 0.3})
    f = np.logspace(-2, 2, 400)
    fc = 0.5
    s = 1j * f / fc
    lp = 1 / (1 + s)
    hp = s / (1 + s)
    a1.semilogx(f, 20 * np.log10(np.abs(lp)), color=C["amber"], label="accelerometer path (low-pass)")
    a1.semilogx(f, 20 * np.log10(np.abs(hp)), color=C["navy"], label="gyroscope path (high-pass)")
    a1.semilogx(f, 20 * np.log10(np.abs(lp + hp)), color=C["coral"], lw=1.2, ls="--", label="sum")
    a1.axvline(fc, color=C["muted"], lw=0.7, ls=":")
    a1.text(fc * 1.15, 2.2, "crossover 0.5 Hz", fontsize=7, color=C["muted"])
    a1.set_ylim(-40, 6)
    a1.set_xlabel("Frequency (Hz)")
    a1.set_ylabel("Gain (dB)")
    a1.legend(loc="lower left", fontsize=6.6)
    rng = np.random.default_rng(4)
    dt = 0.002
    t = np.arange(0, 20, dt)
    truth = 10 * np.sin(2 * np.pi * 0.2 * t) * (t > 2)
    rate = np.gradient(truth, dt) + 1.5 + rng.normal(0, 3, t.size)
    acc = truth + rng.normal(0, 4, t.size)
    gyro_int = np.cumsum(rate) * dt
    alpha = (1 / (2 * np.pi * fc)) / ((1 / (2 * np.pi * fc)) + dt)
    est = np.zeros_like(t)
    for k in range(1, t.size):
        est[k] = alpha * (est[k - 1] + rate[k] * dt) + (1 - alpha) * acc[k]
    a2.plot(t, acc, color=C["amber"], lw=0.4, alpha=0.6, label="accelerometer angle")
    a2.plot(t, gyro_int, color=C["navy"], lw=1.0, label="integrated gyroscope")
    a2.plot(t, est, color=C["coral"], lw=1.3, label="complementary filter")
    a2.plot(t, truth, color=C["ink"], lw=0.8, ls="--", label="truth")
    a2.set_xlabel("Time (s)")
    a2.set_ylabel("Roll (°)")
    a2.set_ylim(-25, 52)
    a2.legend(loc="upper left", fontsize=6.4, ncol=2)
    save(fig, "u3-complementary")


def cascade():
    d = Diagram(168, 50)
    def summer(x, y):
        d.circle(x, y, 2.2, kind="plain")
        d.text(x, y, "Σ", size=6.6)
    summer(8, 33)
    d.arrow((0.5, 33), (5.8, 33), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(1, 36.5, "angle*", size=6.6, color=C["muted"], ha="left")
    ang = d.box(15, 28, 22, 10, "angle loop", sub="500 Hz", kind="navy_t", size=7.4, sub_size=6.2)
    d.arrow((10.2, 33), ang.w_, color=C["ink"], lw=0.9, mutation=5.5)
    summer(47, 33)
    d.arrow(ang.e, (44.8, 33), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(41, 36.3, "rate*", size=6.4, color=C["muted"])
    rate = d.box(54, 28, 24, 10, "rate PID", sub="1.66 kHz", kind="navy", size=7.6, sub_size=6.2)
    d.arrow((49.2, 33), rate.w_, color=C["ink"], lw=0.9, mutation=5.5)
    mix = d.box(86, 28, 16, 10, "mixer", kind="navy_t", size=7.4)
    d.arrow(rate.e, mix.w_, color=C["ink"], lw=0.9, mutation=5.5)
    mot = d.box(110, 28, 26, 10, "ESCs and motors", sub="lag from Lab 3.1.1", kind="coral_t", size=7.0, sub_size=5.8)
    d.arrow(mix.e, mot.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(106, 36.3, "DShot", size=6.2, color=C["muted"])
    air = d.box(144, 28, 22, 10, "airframe", sub="inertia, drag", kind="grey", size=7.4, sub_size=6.0)
    d.arrow(mot.e, air.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(140, 36.3, "thrust", size=6.2, color=C["muted"])
    d.path([air.bottom(0.5), (155, 20), (47, 20), (47, 30.8)], color=C["purple"], lw=0.9, mutation=5.5)
    d.text(100, 21.8, "gyroscope rates", size=6.6, color=C["purple"])
    d.dot(128, 20, r=0.7, color=C["purple"])
    est = d.box(112, 3, 32, 9, "attitude estimator", kind="purple_t", size=7.2)
    d.arrow((128, 20), (128, 12), color=C["purple"], lw=0.8, mutation=5)
    d.arrow((165, 7.5), est.e, color=C["ink"], lw=0.8, mutation=5)
    d.text(160, 9.8, "accel, mag", size=6.0, color=C["muted"])
    d.path([est.w_, (8, 7.5), (8, 30.8)], color=C["purple"], lw=0.9, mutation=5.5)
    d.text(60, 9.5, "estimated angle", size=6.6, color=C["purple"])
    d.group(43, 15, 70, 30, "", color=C["navy"])
    d.text(45, 42.8, "inner loop", size=6.6, color=C["navy"], weight="bold", ha="left")
    d.save("u3-cascade")


def gfsk():
    fig, axes = plot(h=74, nrows=3, sharex=True, gridspec_kw={"hspace": 0.18})
    rb, fs = 50e3, 1e6
    sps = int(fs / rb)
    bits = np.array([1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 1])
    nrz = np.repeat(2 * bits - 1, sps).astype(float)
    t = np.arange(nrz.size) / fs * 1e6
    bt = 0.5
    b = bt * rb
    tt = np.arange(-2 * sps, 2 * sps + 1) / fs
    h = np.sqrt(2 * np.pi / np.log(2)) * b * np.exp(-2 * np.pi ** 2 * b ** 2 * tt ** 2 / np.log(2))
    h /= h.sum()
    freq = 25e3 * np.convolve(nrz, h, mode="same")
    rng = np.random.default_rng(7)
    phase = 2 * np.pi * np.cumsum(freq) / fs
    iq = np.exp(1j * phase) + (rng.normal(0, 0.12, phase.size) + 1j * rng.normal(0, 0.12, phase.size))
    disc = np.angle(iq[1:] * np.conj(iq[:-1])) * fs / (2 * np.pi)
    disc = np.r_[disc[0], disc]
    smooth = np.convolve(disc, np.ones(7) / 7, mode="same")
    axes[0].step(t, 2 * np.repeat(bits, sps) - 1, where="post", color=C["navy"], lw=1.2)
    for i, bit in enumerate(bits):
        axes[0].text((i + 0.5) * 20, 1.35, str(bit), fontsize=7.4, ha="center", color=C["ink"])
    axes[0].set_ylim(-1.6, 1.9)
    axes[0].set_yticks([-1, 1])
    axes[0].set_ylabel("bits")
    axes[1].plot(t, freq / 1e3, color=C["purple"], lw=1.3)
    axes[1].axhline(25, color=C["rule"], lw=0.8, ls="--")
    axes[1].axhline(-25, color=C["rule"], lw=0.8, ls="--")
    axes[1].set_ylabel("Δf (kHz)")
    axes[1].set_ylim(-32, 32)
    axes[1].text(t[-1] - 2, 27, "±25 kHz deviation", fontsize=6.8, color=C["muted"], ha="right", va="bottom")
    axes[2].plot(t, disc / 1e3, color=C["amber"], lw=0.5, alpha=0.7, label="discriminator output")
    axes[2].plot(t, smooth / 1e3, color=C["coral"], lw=1.2, label="after a short low-pass")
    centres = (np.arange(bits.size) + 0.5) * sps
    axes[2].plot(t[centres.astype(int)], smooth[centres.astype(int)] / 1e3, "o", color=C["navy"], ms=3.2, label="decision instants")
    axes[2].set_ylabel("Δf (kHz)")
    axes[2].set_ylim(-70, 95)
    axes[2].set_xlabel("Time (µs)")
    axes[2].legend(loc="upper right", fontsize=6.4, ncol=3)
    save(fig, "u3-gfsk")


def packet():
    d = Diagram(168, 42)
    fields = [("preamble", 4, "grey"), ("sync word", 4, "grey"), ("length", 1, "amber_t"), ("sequence", 2, "purple_t"),
              ("payload", 30, "navy_t"), ("CRC", 2, "amber_t")]
    total = sum(f[1] for f in fields)
    x0, wpb = 6.0, 156.0 / total
    t_byte = 8 / 50e3 * 1e3
    d.text(x0, 38, "One packet at 50 kbit/s: each byte occupies 0.16 ms of airtime", size=7.8, weight="bold", ha="left")
    x, cum = x0, 0
    edges = []
    for name, n, kind in fields:
        w = n * wpb
        d.box(x, 15, w, 11, name if w > 12 else "", kind=kind, size=7.2, radius=0.6, lw=0.8)
        if name == "length":
            d.line((x + w / 2, 26), (x + w / 2, 29.5), color=C["muted"], lw=0.6)
            d.text(x + w / 2 - 0.8, 31, "length", size=6.6, ha="right")
        elif name == "sequence":
            d.line((x + w / 2, 26), (x + w / 2, 29.5), color=C["muted"], lw=0.6)
            d.text(x + w / 2 + 0.8, 31, "sequence", size=6.6, ha="left")
        elif name == "CRC":
            d.line((x + w / 2, 26), (x + w / 2, 29.5), color=C["muted"], lw=0.6)
            d.text(x + w / 2, 31, "CRC", size=6.6)
        d.text(x + w / 2, 12.3, f"{n} B", size=6.2, color=C["muted"])
        edges.append((x, cum))
        x += w
        cum += n
    edges.append((x, cum))
    for i, (ex, c) in enumerate(edges):
        d.line((ex, 9.5), (ex, 15), color=C["rule"], lw=0.6)
        if i in (0, 1, 2, 4, 5, 6):
            lab = f"{c * t_byte:.2f}" + (" ms" if i == 6 else "")
            d.text(ex, 7.2, lab, size=6.0, color=C["muted"], ha="center" if i not in (2, 4) else ("right" if i == 2 else "left"))
    d.text(x0, 2.4, f"Total {total} bytes: {total * t_byte:.2f} ms. A 1 % duty cycle allows {int(36 / (total * t_byte / 1e3)):,} such packets an hour.",
           size=7.0, color=C["ink"], ha="left")
    d.save("u3-packet")


def conducted():
    d = Diagram(168, 62)
    d.group(3, 10, 40, 34, "die-cast box, seams taped", color=C["muted"], fill=C["grey"], dashed=False, size=6.8)
    tx = d.box(7, 25, 24, 12, "CC1312R", sub="transmitter", kind="navy", size=7.6, sub_size=6.4)
    d.box(7, 13, 24, 7, "power bank", kind="plain", size=6.8, weight="normal")
    d.line(tx.bottom(0.5), (19, 20), color=C["muted"], lw=0.8)
    d.rect(42, 28.5, 3, 5, fill=C["amber"], edge=C["ink"], lw=0.6, z=5)
    d.wire([tx.e, (42, 31)], color=C["ink"], lw=1.1)
    d.text(37, 22.5, "J7 to the\nbulkhead", size=6.0, color=C["muted"])
    x = 50
    for att, dashed in (("30 dB", False), ("30 dB", False), ("30 dB", False), ("20 dB", False), ("10 dB", True)):
        d.box(x, 27, 14, 8, att, kind="amber_t" if not dashed else "ghost", size=7.0, dashed=dashed)
        d.wire([(x - 4 if x > 50 else 45, 31), (x, 31)], color=C["ink"], lw=1.1)
        x += 18
    d.wire([(x - 4, 31), (x + 2, 31)], color=C["ink"], lw=1.1)
    rx = d.box(x + 2, 25, 24, 12, "CC1312R", sub="receiver", kind="navy_t", size=7.6, sub_size=6.4)
    d.text(129, 37.5, "long-range\nmode only", size=6.0, color=C["muted"])
    d.text(88, 22.5, "110 dB chain (120 dB with the 10 dB pad), each pad calibrated with the tinySA", size=6.6, color=C["ink"])
    d.text(52, 39, "0 to +14 dBm", size=6.8, color=C["navy"], weight="semibold", ha="left")
    d.text(rx.cx, 40, "−110 to −96 dBm", size=6.8, color=C["navy"], weight="semibold")
    d.curve((24, 44.5), (rx.cx, 43.5), 7.5, color=C["coral"], dashed=True,
            label="leakage path: must stay 10 dB below the conducted level", size=6.6, label_pad=2.4)
    log = d.box(rx.x, 3, 24, 9, "log on the Pi", kind="plain", size=7.0, weight="normal")
    d.arrow(rx.bottom(), log.top(), color=C["ink"], lw=0.8, mutation=5.5)
    d.text(rx.cx + 1.5, 18.5, "USB", size=6.2, color=C["muted"], ha="left")
    d.save("u3-conducted")


def pll():
    d = Diagram(168, 66)
    ref = d.box(2, 28, 20, 12, "reference", sub="100 MHz", kind="grey", size=7.4, sub_size=6.4)
    rdiv = d.box(28, 29, 14, 10, "÷R", kind="navy_t", size=8.4)
    pfd = d.box(48, 28, 18, 12, "phase", sub="detector", kind="navy_t", size=7.2, sub_size=7.2)
    cp = d.box(72, 28, 18, 12, "charge", sub="pump", kind="navy_t", size=7.2, sub_size=7.2)
    lf = d.box(96, 28, 18, 12, "loop", sub="filter", kind="navy_t", size=7.2, sub_size=7.2)
    vco = d.box(122, 27, 20, 14, "VCO", sub="3.2–6.4 GHz", kind="navy", size=8.0, sub_size=6.2)
    chd = d.box(148, 29, 16, 10, "÷CHDIV", kind="navy_t", size=7.2)
    for a, b in ((ref, rdiv), (rdiv, pfd), (pfd, cp), (cp, lf), (lf, vco), (vco, chd)):
        d.arrow(a.e, b.w_, color=C["ink"], lw=0.9, mutation=5.5)
    d.arrow(chd.bottom(0.5), (156, 20), color=C["coral"], lw=1.3, mutation=6)
    d.text(156, 17, "RF out", size=7.0, color=C["coral"], weight="semibold")
    nd = d.box(84, 6, 34, 11, "÷(N + NUM/DEN)", kind="navy_t", size=7.2)
    sd = d.box(48, 6, 26, 11, "ΣΔ modulator", kind="purple_t", size=7.0)
    d.path([vco.bottom(0.5), (132, 11.5), nd.e], color=C["ink"], lw=0.9, mutation=5.5)
    d.arrow(sd.e, nd.w_, color=C["purple"], lw=0.8, mutation=5)
    d.path([nd.top(0.3), (94.2, 22), (61, 22), (61, 28)], color=C["ink"], lw=0.9, mutation=5.5)
    d.text(78, 24, "divided VCO", size=6.2, color=C["muted"])
    d.arrow((52, 28), (52, 22.5), color=C["green"], lw=0.8, mutation=5)
    d.text(50.5, 20.5, "lock detect\nto MUXout", size=6.2, color=C["green"], ha="right")
    spi = d.box(28, 54, 136, 9, "SPI registers, written by your lmx2572.py", kind="amber_t", size=7.2)
    for x, y_end in ((35, 39), (81, 40), (156, 39)):
        d.arrow((x, 54), (x, y_end), color=C["amber"], lw=0.7, dashed=True, mutation=4.5)
    d.path([(116, 54), (116, 17)], color=C["amber"], lw=0.7, dashed=True, mutation=4.5)
    d.text(99, 46.5, "C2 15 nF, R2 330 Ω, C4 2.2 nF:\n115 kHz bandwidth, 48° margin", size=6.2, color=C["muted"])
    d.save("u3-pll")


def fmcw():
    fig, (a1, a2) = plot(h=60, ncols=2, gridspec_kw={"width_ratios": [1.05, 1], "wspace": 0.28})
    tc, b = 40.0, 4.0
    t = np.linspace(0, 60, 600)
    tx = np.where(t < tc, 60 + b * t / tc, np.nan)
    tau = 6.0
    rx = np.where((t >= tau) & (t < tc + tau), 60 + b * (t - tau) / tc, np.nan)
    a1.plot(t, tx, color=C["navy"], lw=1.6, label="transmitted chirp")
    a1.plot(t, rx, color=C["coral"], lw=1.6, ls="--", label="echo, delayed by τ")
    a1.annotate("", xy=(36, 60 + b * 36 / tc), xytext=(36, 60 + b * 30 / tc),
                arrowprops=dict(arrowstyle="<->", color=C["ink"], lw=0.8))
    a1.text(37.5, 62.35, "beat frequency\n$f_b = S\\tau$", fontsize=7.0, va="center")
    a1.annotate("", xy=(16 + tau, 60 + b * 16 / tc), xytext=(16, 60 + b * 16 / tc),
                arrowprops=dict(arrowstyle="<->", color=C["purple"], lw=0.8))
    a1.text(24.5, 61.25, "τ = 2R/c", fontsize=7.0, color=C["purple"], ha="left")
    a1.set_xlabel("Time (µs, delay exaggerated)")
    a1.set_ylabel("Frequency (GHz)")
    a1.set_xlim(0, 50)
    a1.set_ylim(59.8, 64.4)
    a1.legend(loc="upper left", fontsize=6.6)
    rng = np.random.default_rng(3)
    fs, n = 10e6, 256
    slope = 100e12
    c = 3e8
    tt = np.arange(n) / fs
    sig = np.zeros(n, complex)
    for rng_m, amp in ((2.0, 1.0), (4.0, 0.08)):
        sig += amp * np.exp(2j * np.pi * (2 * rng_m * slope / c) * tt)
    sig += (rng.normal(0, 0.02, n) + 1j * rng.normal(0, 0.02, n))
    win = np.hanning(n)
    spec = np.abs(np.fft.fft(sig * win, 1024)) / win.sum()
    freqs = np.fft.fftfreq(1024, 1 / fs)
    rngs = freqs * c / (2 * slope)
    keep = (rngs >= 0) & (rngs < 8)
    a2.plot(rngs[keep], 20 * np.log10(spec[keep] + 1e-9), color=C["navy"], lw=1.2)
    a2.set_xlabel("Range (m)")
    a2.set_ylabel("Magnitude (dB)")
    a2.set_ylim(-75, 5)
    a2.text(2.1, -4, "floor, 2 m", fontsize=7, color=C["ink"])
    a2.text(4.1, -24, "person, 4 m", fontsize=7, color=C["ink"])
    a2.set_title("Range profile: FFT of the beat signal", fontsize=8.2)
    save(fig, "u3-fmcw")


def range_doppler():
    setup()
    rng = np.random.default_rng(11)
    nr, nd = 128, 64
    r = np.linspace(0, 8, nr)
    v = np.linspace(-5, 5, nd)
    rr, vv = np.meshgrid(r, v)
    power = rng.exponential(1.0, (nd, nr)) * 0.0003
    power += 1.0 * np.exp(-((rr - 2.0) / 0.06) ** 2 - (vv / 0.12) ** 2)
    power += 0.05 * np.exp(-((rr - 2.0) / 0.06) ** 2) * np.exp(-(vv / 2.0) ** 2) * 0.02
    power += 0.06 * np.exp(-((rr - 4.0) / 0.08) ** 2 - ((vv - 1.2) / 0.18) ** 2)
    db = 10 * np.log10(power)
    cmap = LinearSegmentedColormap.from_list("omh", ["#FFFFFF", C["purple_t"], C["purple"], C["navy"]])
    fig, ax = plot(w=150, h=74)
    im = ax.pcolormesh(r, v, db, cmap=cmap, shading="auto", vmin=-45, vmax=0, rasterized=True)
    ax.grid(False)
    for (x, y, lab) in ((2.0, 0.0, "floor"), (4.0, 1.2, "walking person")):
        ax.plot(x, y, "o", mfc="none", mec=C["coral"], ms=11, mew=1.3)
        ax.text(x + 0.25, y + 0.55, lab, fontsize=7.4, color=C["coral"], weight="semibold")
    ax.set_xlabel("Range (m)")
    ax.set_ylabel("Velocity (m/s)")
    cb = fig.colorbar(im, ax=ax, pad=0.02, fraction=0.05)
    cb.set_label("Power (dB)", fontsize=7.6)
    cb.ax.tick_params(labelsize=7, length=2)
    cb.outline.set_linewidth(0.5)
    ax.text(0.15, -4.55, "circles: CFAR detections", fontsize=6.8, color=C["coral"])
    save(fig, "u3-range-doppler")


def boards():
    d = Diagram(168, 84)
    d.group(2, 2, 86, 78, "On the drone", color=C["magenta"])
    d.group(92, 2, 74, 78, "In the rack", color=C["purple"])
    bat = d.box(6, 60, 20, 10, "3S LiPo", kind="grey", size=7.6)
    bp = d.box(34, 58, 22, 14, "Board P", sub="shunt, INA228, 5 V", kind="magenta", size=8.0, sub_size=6.0)
    esc = d.box(64, 60, 20, 10, "4 ESCs", kind="grey", size=7.6)
    d.arrow(bat.e, bp.w_, color=C["coral"], lw=1.8, mutation=6.5)
    d.arrow(bp.e, esc.w_, color=C["coral"], lw=1.8, mutation=6.5)
    d.text(60, 74, "XT60, 60 A", size=6.4, color=C["coral"])
    fc = d.box(30, 30, 30, 16, "Board F", sub="on the MSP432E401Y LaunchPad", kind="magenta_t", size=8.2, sub_size=5.8)
    d.arrow(bp.bottom(0.5), fc.top(0.5), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(46.5, 52, "5 V, I²C", size=6.4, color=C["muted"], ha="left")
    d.path([fc.right(0.75), (74, 42), esc.bottom(0.5)], color=C["ink"], lw=0.9, mutation=5.5)
    d.text(76, 50, "DShot ×4", size=6.4, color=C["muted"], ha="left")
    radio = d.box(6, 8, 22, 12, "CC1312R", sub="telemetry", kind="navy_t", size=7.4, sub_size=6.0)
    radar = d.box(34, 8, 22, 12, "IWRL6432", sub="altimeter", kind="navy_t", size=7.4, sub_size=6.0)
    rcv = d.box(62, 8, 22, 12, "RP1", sub="receiver", kind="navy_t", size=7.4, sub_size=6.0)
    for n, lab in ((radio, "UART"), (radar, "UART"), (rcv, "CRSF")):
        d.arrow(n.top(0.5), (fc.x + fc.w * (0.12 if n is radio else 0.5 if n is radar else 0.88), fc.y), both=True,
                color=C["ink"], lw=0.8, mutation=5)
    d.text(17, 25.5, "UART", size=6.2, color=C["muted"])
    d.text(47.5, 25.5, "UART", size=6.2, color=C["muted"], ha="left")
    d.text(73, 25.5, "CRSF", size=6.2, color=C["muted"])
    mag = d.box(4, 33, 20, 10, "mag mast", kind="plain", size=7.0, weight="normal")
    d.arrow(mag.e, fc.left(0.5), both=True, color=C["ink"], lw=0.8, mutation=5)
    psu = d.box(96, 62, 22, 10, "12 V supply", kind="grey", size=7.4)
    ba = d.box(98, 34, 26, 16, "Board A", sub="BMC-lite, MSP432E401Y", kind="purple", size=8.0, sub_size=5.8)
    bb = d.box(136, 34, 26, 16, "Board B", sub="CM5 carrier", kind="purple_t", size=8.0, sub_size=6.0)
    nvme = d.box(138, 8, 22, 10, "NVMe, TPM", kind="plain", size=7.0, weight="normal")
    sw = d.box(98, 8, 26, 10, "managed switch", kind="grey", size=7.0)
    d.arrow(psu.bottom(0.5), ba.top(0.3), color=C["ink"], lw=0.9, mutation=5.5)
    d.path([psu.e, (149, 67), bb.top(0.5)], color=C["ink"], lw=0.9, mutation=5.5)
    d.text(122, 69, "12 V", size=6.4, color=C["muted"])
    d.arrow(ba.e, bb.w_, both=True, color=C["purple"], lw=1.2, mutation=6)
    d.text(130, 56.5, "management:\nUART, I²C, power,\nreset, presence", size=6.0, color=C["purple"])
    d.arrow(bb.bottom(0.5), nvme.top(0.5), both=True, color=C["ink"], lw=0.8, mutation=5)
    d.text(151, 25.5, "PCIe, SPI", size=6.2, color=C["muted"], ha="left")
    d.arrow(ba.bottom(0.5), sw.top(0.5), both=True, color=C["ink"], lw=0.8, mutation=5)
    d.path([bb.left(0.2), (128, 37.2), (128, 13), sw.e], color=C["ink"], lw=0.8, mutation=5)
    d.text(112.5, 25.5, "Ethernet", size=6.2, color=C["muted"], ha="left")
    d.save("u3-boards")


def stackup():
    d = Diagram(168, 56)
    cu = "#B87333"
    layers = [("L1: signal", 1.4, cu, True), ("prepreg, about 0.2 mm", 6.0, C["amber_t"], False),
              ("L2: ground plane", 1.4, cu, False), ("core, about 1.1 mm", 14.0, C["grey"], False),
              ("L3: power plane", 1.4, cu, False), ("prepreg, about 0.2 mm", 6.0, C["amber_t"], False),
              ("L4: signal", 1.4, cu, True)]
    x0, w, top = 4, 70, 48
    y = top
    centres = []
    for name, h, col, traces in layers:
        y -= h
        if traces:
            for xx, ww in ((8, 6), (22, 6), (44, 3.4), (49.6, 3.4)):
                d.rect(x0 + xx, y, ww, h, fill=col, edge=None, z=4)
        else:
            d.rect(x0, y, w, h, fill=col, edge=C["rule"], lw=0.4, z=2)
        centres.append((name, y + h / 2))
    label_ys = np.linspace(top - 0.7, y + 0.7, len(layers))
    for (name, cy), ly in zip(centres, label_ys):
        d.line((x0 + w + 1, cy), (x0 + w + 6, ly), color=C["muted"], lw=0.5)
        d.text(x0 + w + 7, ly, name, size=6.6, ha="left")
    d.text(x0 + 11, top + 3.4, "50 Ω trace", size=6.4, color=C["muted"])
    d.text(x0 + 47.5, top + 3.4, "90 Ω pair", size=6.4, color=C["muted"])
    d.text(x0 + w / 2, y - 4, "1.6 mm finished thickness (layers not to scale)", size=6.4, color=C["muted"])
    mx, my = 140, 18
    d.rect(mx - 22, my - 2, 44, 2, fill=cu, edge=None, z=3)
    d.rect(mx - 22, my, 44, 10, fill=C["amber_t"], edge=None, z=2)
    d.rect(mx - 5, my + 10, 10, 1.6, fill=cu, edge=None, z=4)
    d.arrow((mx - 5, my + 14.5), (mx + 5, my + 14.5), both=True, color=C["ink"], lw=0.7, mutation=4.5)
    d.text(mx, my + 17.3, "w", size=8, family="Source Serif 4", style="italic")
    d.arrow((mx + 9, my), (mx + 9, my + 10), both=True, color=C["ink"], lw=0.7, mutation=4.5)
    d.text(mx + 11, my + 5, "h", size=8, family="Source Serif 4", style="italic", ha="left")
    d.text(mx, my - 5.5, "reference plane", size=6.4, color=C["muted"])
    d.text(mx, 51, "Microstrip, approximately", size=7.2, weight="bold")
    d.text(mx, 45, r"$Z_0 \approx \frac{87}{(\varepsilon_r + 1.41)^{1/2}} \ln\frac{5.98\,h}{0.8\,w + t}$", size=8.6)
    d.text(mx, 3.5, "Use your fabricator's calculator for real numbers", size=6.2, color=C["muted"])
    d.save("u3-stackup")


def bringup():
    d = Diagram(168, 52)
    steps = [("inspect", "microscope"), ("continuity", "unpowered"), ("power", "current-limited"), ("rails", "voltage, ripple"),
             ("clock, reset", "scope"), ("debugger", "read the ID"), ("firmware", "one peripheral\nat a time")]
    w, h, gap = 20.5, 14, 3.4
    nodes = []
    for i, (a, b) in enumerate(steps):
        x = 2 + i * (w + gap)
        kind = "navy" if i == 6 else "navy_t"
        nodes.append(d.box(x, 26, w, h, a, sub=b, kind=kind, size=7.2, sub_size=5.6))
    for a, b in zip(nodes, nodes[1:]):
        d.arrow(a.e, b.w_, color=C["ink"], lw=0.9, mutation=5.5)
    for i, n in enumerate(nodes[1:], 1):
        d.line(n.bottom(0.5), (n.cx, 16), color=C["coral"], lw=0.8, dashed=True)
    d.path([(nodes[-1].cx, 16), (nodes[0].cx, 16), nodes[0].bottom(0.5)], color=C["coral"], lw=0.8, dashed=True, mutation=5.5)
    d.text(84, 11.5, "any failure: back to the microscope and the schematic, never to the firmware", size=7.0, color=C["coral"])
    d.text(84, 47, "Each gate passes only when its measurement is written in the notebook", size=7.4, weight="bold")
    d.save("u3-bringup")


def drone_system():
    d = Diagram(168, 96)
    fc = d.group(52, 32, 64, 40, "flight controller", color=C["magenta"], fill=C["magenta_t"], dashed=False)
    d.box(56, 54, 56, 10, "MSP432E401Y LaunchPad", kind="magenta", size=7.6)
    d.box(56, 36, 17, 14, "IMU", sub="LSM6DSOX", kind="plain", size=7.0, sub_size=5.6)
    d.box(75.5, 36, 17, 14, "baro", sub="BMP581", kind="plain", size=7.0, sub_size=5.6)
    d.box(95, 36, 17, 14, "flash", sub="logger", kind="plain", size=7.0, sub_size=5.6)
    d.text(84, 67.5, "Board F", size=6.6, color=C["magenta"], weight="bold")
    bat = d.box(4, 76, 20, 10, "3S LiPo", kind="grey", size=7.4)
    bp = d.box(4, 54, 30, 14, "Board P", sub="shunt, INA228, 5 V buck", kind="magenta", size=7.6, sub_size=5.6)
    d.arrow(bat.bottom(), (14, 68), color=C["coral"], lw=1.8, mutation=6)
    escs = d.box(4, 28, 30, 12, "4 ESCs, 4 motors", kind="grey", size=7.4)
    d.arrow(bp.bottom(0.35), (14.5, 40), color=C["coral"], lw=1.8, mutation=6)
    d.text(2.5, 46, "60 A", size=6.2, color=C["coral"], ha="left")
    d.arrow(bp.e, (52, 61), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(43, 63.5, "5 V, 3.3 V, I²C", size=6.0, color=C["muted"])
    d.arrow((52, 40), escs.e, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(43, 42.5, "DShot600 ×4", size=6.0, color=C["muted"])
    rx = d.box(60, 82, 24, 10, "RP1 receiver", kind="navy_t", size=7.2)
    tx = d.box(128, 84, 34, 9, "Pocket transmitter", kind="grey", size=7.0)
    d.arrow(tx.w_, rx.e, color=C["navy"], lw=0.9, dashed=True, mutation=5.5)
    d.text(106, 91, "2.4 GHz ExpressLRS", size=6.2, color=C["navy"])
    d.arrow(rx.bottom(), (72, 72), color=C["ink"], lw=0.9, mutation=5.5)
    d.text(74, 77, "CRSF, 420 kbaud", size=6.0, color=C["muted"], ha="left")
    tel = d.box(124, 56, 26, 12, "CC1312R", sub="telemetry radio", kind="navy_t", size=7.4, sub_size=5.8)
    d.arrow((116, 62), tel.w_, both=True, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(120, 65.5, "UART", size=6.0, color=C["muted"])
    gs = d.box(128, 30, 36, 14, "ground station", sub="CC1312R and Raspberry Pi", kind="grey", size=7.2, sub_size=5.6)
    d.arrow(tel.bottom(0.5), (137, 44), both=True, color=C["navy"], lw=0.9, dashed=True, mutation=5.5)
    d.text(139, 50, "868 MHz", size=6.2, color=C["navy"], ha="left")
    radar = d.box(64, 8, 40, 12, "IWRL6432BOOST", sub="facing down: range to ground", kind="navy_t", size=7.2, sub_size=5.6)
    d.arrow((84, 32), radar.top(), both=True, color=C["ink"], lw=0.9, mutation=5.5)
    d.text(86, 25, "UART", size=6.0, color=C["muted"], ha="left")
    mag = d.box(4, 8, 30, 12, "LIS3MDL", sub="on a mast", kind="navy_t", size=7.2, sub_size=5.6)
    d.path([mag.e, (46, 14), (46, 36), (52, 36)], color=C["ink"], lw=0.9, mutation=5.5)
    d.text(36, 16.5, "I²C", size=6.0, color=C["muted"])
    d.text(84, 4.5, "Board P powers the radar and the telemetry radio through their USB connectors", size=6.2,
           color=C["coral"])
    d.save("u3-drone-system")


def dshot():
    d = Diagram(168, 50)
    bits = [1, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0]
    x0, bw = 6, 9.6
    y0, hh = 22, 9
    pts = []
    x = x0
    for b in bits:
        hi = 0.75 if b else 0.375
        pts += [(x, y0), (x, y0 + hh), (x + hi * bw, y0 + hh), (x + hi * bw, y0), (x + bw, y0)]
        x += bw
    d.wire(pts, color=C["navy"], lw=1.2)
    for i, b in enumerate(bits):
        d.text(x0 + (i + 0.5) * bw, y0 + hh + 3, str(b), size=7.2, mono=True)
        d.line((x0 + i * bw, y0 - 2), (x0 + i * bw, y0 + hh + 1), color=C["rule"], lw=0.4)
    d.line((x0 + 16 * bw, y0 - 2), (x0 + 16 * bw, y0 + hh + 1), color=C["rule"], lw=0.4)
    groups = [("throttle 1,046 (11 bits)", 0, 11, "navy_t"), ("T", 11, 12, "amber_t"), ("checksum", 12, 16, "purple_t")]
    for lab, a, b, kind in groups:
        d.box(x0 + a * bw + 0.3, 8, (b - a) * bw - 0.6, 7, lab, kind=kind, size=6.8, radius=0.6, lw=0.7)
    d.arrow((x0, 44), (x0 + bw, 44), both=True, color=C["ink"], lw=0.7, mutation=4.5)
    d.text(x0 + bw / 2, 47, "1.67 µs", size=6.4)
    d.arrow((x0 + 6 * bw, 39.5), (x0 + 6 * bw + 0.75 * bw, 39.5), both=True, color=C["coral"], lw=0.7, mutation=4)
    d.text(x0 + 6.4 * bw, 42.2, "1: 1.25 µs", size=6.2, color=C["coral"])
    d.arrow((x0 + 1 * bw, 39.5), (x0 + 1 * bw + 0.375 * bw, 39.5), both=True, color=C["coral"], lw=0.7, mutation=4)
    d.text(x0 + 1.8 * bw, 42.2, "0: 0.625 µs", size=6.2, color=C["coral"])
    d.text(x0 + 16 * bw + 2, y0 + hh / 2, "frame\n26.7 µs", size=6.6, color=C["muted"], ha="left")
    d.text(x0, 2.5, "checksum = (v XOR v>>4 XOR v>>8) AND 0xF, where v is the first 12 bits", size=6.6, color=C["muted"], ha="left")
    d.save("u3-dshot")


def arming():
    d = Diagram(168, 72)
    boot = d.state(10, 40, "BOOT", r=7, kind="grey", size=7.0)
    cal = d.state(38, 40, "CAL", r=7.5, kind="navy_t", sub="IMU bias", size=7.2)
    dis = d.state(78, 40, "DISARMED", r=10.5, kind="navy", size=7.6)
    arm = d.state(140, 52, "ARMED", r=10.5, kind="coral", size=7.8)
    fs = d.state(140, 16, "FAILSAFE", r=8.5, kind="amber_t", size=7.0)
    flt = d.state(78, 9, "FAULT", r=7.0, kind="grey", size=7.0)
    d.arrow((17, 40), (30.5, 40), color=C["ink"], lw=0.9, mutation=6)
    d.arrow((45.5, 40), (67.5, 40), color=C["ink"], lw=0.9, mutation=6)
    d.text(56.5, 42.6, "still, level", size=6.4, color=C["muted"])
    d.curve((85.5, 47.5), (130, 57), 6, color=C["ink"], label="arm switch off→on, throttle low, level,\nsensors, battery and link healthy",
            size=6.3, label_pad=4.6)
    d.arrow((129.6, 48.8), (88.5, 40.5), color=C["ink"], lw=0.9, mutation=6)
    d.text(109, 50.5, "switch off, attitude > 60°,\nbattery critical", size=6.3, color=C["ink"])
    d.arrow((140, 41.5), (140, 24.5), color=C["ink"], lw=0.9, mutation=6)
    d.text(142, 33, "no link\nfor 100 ms", size=6.3, color=C["muted"], ha="left")
    d.curve((131.5, 15.5), (84.5, 31.8), -6, color=C["ink"])
    d.text(103, 17.5, "disarm after 0.5 s", size=6.3, color=C["muted"])
    d.arrow((78, 29.5), (78, 16), color=C["ink"], lw=0.9, mutation=6)
    d.text(76, 22.5, "sensor or\nflash error", size=6.3, color=C["muted"], ha="right")
    d.text(86.5, 9, "until reboot", size=6.2, color=C["muted"], ha="left")
    d.loop(dis, label="arm refused:\nreason logged", angle=110, size=6.3, r_loop=4.0, label_pad=5.4)
    d.save("u3-arming")


def mixer():
    d = Diagram(150, 72)
    cx, cy, a = 36, 36, 22
    motors = [(1, -1, 1, "CW"), (2, 1, 1, "CCW"), (3, 1, -1, "CW"), (4, -1, -1, "CCW")]
    d.line((cx - a, cy + a), (cx + a, cy - a), color=C["muted"], lw=2.2)
    d.line((cx - a, cy - a), (cx + a, cy + a), color=C["muted"], lw=2.2)
    d.box(cx - 6, cy - 6, 12, 12, "FC", kind="magenta_t", size=7.0)
    from matplotlib.patches import Arc
    for n, sx, sy, rot in motors:
        x, y = cx + sx * a, cy + sy * a
        d.circle(x, y, 8, kind="navy_t" if rot == "CW" else "coral_t")
        d.text(x, y + 1.6, str(n), size=9, weight="bold")
        d.text(x, y - 2.6, rot, size=6.4, color=C["muted"])
        col = C["navy"] if rot == "CW" else C["coral"]
        d.ax.add_patch(Arc((x, y), 21, 21, theta1=20, theta2=160, color=col, lw=1.0, zorder=5))
        tip = math.radians(20 if rot == "CW" else 160)
        ex, ey = x + 10.5 * math.cos(tip), y + 10.5 * math.sin(tip)
        tdir = -1 if rot == "CW" else 1
        d.arrow((ex - tdir * 0.9 * math.sin(tip), ey + tdir * 0.9 * math.cos(tip)),
                (ex + tdir * 0.6 * math.sin(tip) * -1, ey - tdir * 0.6 * math.cos(tip) * -1), color=col, lw=1.0, mutation=6)
    d.arrow((cx, cy + 8), (cx, cy + 19), color=C["ink"], lw=1.2, mutation=7)
    d.text(cx, cy + 22, "front", size=7.4, weight="bold")
    d.text(104, 64, "Mixer (T thrust, R roll, P pitch, Y yaw)", size=7.6, weight="bold")
    rows = [("M1", "T + R + P − Y"), ("M2", "T − R + P + Y"), ("M3", "T − R − P − Y"), ("M4", "T + R − P + Y")]
    for i, (m, eq) in enumerate(rows):
        y = 53 - i * 8
        d.box(80, y - 3, 12, 6, m, kind="navy_t", size=7.2, radius=0.6)
        d.text(96, y, eq, size=8, ha="left", family="Source Serif 4")
    d.text(80, 16, "R > 0 rolls right (right side down);\nP > 0 pitches the nose up;\nY > 0 yaws the nose right, by speeding\nup the counter-clockwise pair.",
           size=6.6, color=C["muted"], ha="left", va="top")
    d.save("u3-mixer")


def alt_fusion():
    rng = np.random.default_rng(5)
    dt = 0.02
    t = np.arange(0, 14, dt)
    h = np.interp(t, [0, 1, 2.5, 5, 6.5, 14], [0.0, 0.0, 1.0, 1.0, 2.0, 2.0])
    h = np.convolve(np.r_[np.zeros(12), h, np.full(12, h[-1])], np.ones(25) / 25, mode="valid")
    acc = np.gradient(np.gradient(h, dt), dt) + rng.normal(0, 0.3, t.size)
    radar = h + rng.normal(0, 0.02, t.size)
    valid = ~((t > 8) & (t < 10))
    baro = h + 0.25 + 0.02 * t + rng.normal(0, 0.1, t.size)
    x = np.array([0.0, 0.0, 0.25])
    P = np.diag([0.1, 0.1, 0.5])
    F = np.array([[1, dt, 0], [0, 1, 0], [0, 0, 1]])
    B = np.array([0.5 * dt * dt, dt, 0])
    Q = np.diag([1e-6, 4e-4, 1e-6])
    est = []
    for k in range(t.size):
        x = F @ x + B * acc[k]
        P = F @ P @ F.T + Q
        meas = [(np.array([1.0, 0, 1.0]), baro[k], 0.1 ** 2)]
        if valid[k]:
            meas.append((np.array([1.0, 0, 0]), radar[k], 0.02 ** 2))
        for Hm, z, R in meas:
            S = Hm @ P @ Hm + R
            K = P @ Hm / S
            x = x + K * (z - Hm @ x)
            P = (np.eye(3) - np.outer(K, Hm)) @ P
        est.append(x[0])
    fig, ax = plot(h=60)
    ax.axvspan(8, 10, color=C["amber_t"], zorder=0)
    ax.text(9, 0.25, "radar\ndropout", fontsize=7, ha="center", color=C["amber"])
    ax.plot(t, baro, ".", color=C["amber"], ms=1.4, label="barometer")
    ax.plot(t[valid], radar[valid], ".", color=C["navy"], ms=1.4, label="radar")
    ax.plot(t, est, color=C["coral"], lw=1.4, label="fused estimate")
    ax.plot(t, h, color=C["ink"], lw=0.8, ls="--", label="truth")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Height (m)")
    ax.set_ylim(-0.3, 3.2)
    ax.legend(loc="upper left", ncol=2, fontsize=6.8)
    save(fig, "u3-alt-fusion")


ALL = [thrust_stand, foc, complementary, cascade, gfsk, packet, conducted, pll, fmcw, range_doppler, boards, stackup,
       bringup, drone_system, dshot, arming, mixer, alt_fusion]

if __name__ == "__main__":
    import sys
    want = set(sys.argv[1:])
    for fn in ALL:
        if not want or fn.__name__ in want:
            fn()
            print("drew", fn.__name__)
