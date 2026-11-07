import numpy as np
def gaussian_filter(x, s):
    k = int(3 * s + .5); t = np.arange(-k, k + 1); g = np.exp(-t * t / (2 * s * s)); g /= g.sum()
    x = np.pad(x, k, mode='constant')
    x = np.apply_along_axis(lambda v: np.convolve(v, g, 'valid'), 0, x)
    return np.apply_along_axis(lambda v: np.convolve(v, g, 'valid'), 1, x)
def metric(im):
    a = np.asarray(im).astype(float); m = a[..., 3] > 200; L = a[..., :3].mean(-1)
    w = gaussian_filter(m.astype(float), 2); low = gaussian_filter(L * m, 2) / np.maximum(w, 1e-6)
    r = (L - low); mm = m & (gaussian_filter(m.astype(float), 1.5) > .99)   # 가장자리 제외
    r = r - r[mm].mean(); sd = r[mm].std()
    def ac(k):
        x = r[:, :-k]; y = r[:, k:]; mk = mm[:, :-k] & mm[:, k:]
        x2 = r[:-k, :]; y2 = r[k:, :]; mk2 = mm[:-k, :] & mm[k:, :]
        num = (x[mk] * y[mk]).sum() + (x2[mk2] * y2[mk2]).sum(); den = (x[mk] ** 2).sum() + (x2[mk2] ** 2).sum()
        return num / den
    return round(sd, 1), round(ac(1), 2), round(ac(2), 2), round(np.percentile(L[m], 90), 1), round(L[m].mean(), 1)
