import math

import torch
import torch.nn as nn
import torch.nn.functional as F

from aif import data

MEAN = torch.tensor([0.4914, 0.4822, 0.4465]).view(1, 3, 1, 1)
STD = torch.tensor([0.2470, 0.2435, 0.2616]).view(1, 3, 1, 1)


def cifar_tensors(device) -> dict[str, torch.Tensor]:
    d = data.cifar10()
    out = {}
    for split in ("train", "test"):
        x = torch.from_numpy(d[f"x_{split}"]).permute(0, 3, 1, 2).float() / 255
        out[f"x_{split}"] = ((x - MEAN) / STD).to(device)
        out[f"y_{split}"] = torch.from_numpy(d[f"y_{split}"]).to(device)
    return out


# snippet:begin conv-block
def conv_bn(c_in: int, c_out: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv2d(c_in, c_out, 3, padding=1, bias=False), nn.BatchNorm2d(c_out), nn.ReLU()
    )


class Residual(nn.Module):
    def __init__(self, channels: int):
        super().__init__()
        self.body = nn.Sequential(conv_bn(channels, channels), conv_bn(channels, channels))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x + self.body(x)


# snippet:end conv-block


# snippet:begin network
class ResNet9(nn.Module):
    def __init__(self, widths=(64, 128, 256, 512), classes: int = 10):
        super().__init__()
        w1, w2, w3, w4 = widths
        self.features = nn.Sequential(
            conv_bn(3, w1),
            conv_bn(w1, w2),
            nn.MaxPool2d(2),
            Residual(w2),
            conv_bn(w2, w3),
            nn.MaxPool2d(2),
            conv_bn(w3, w4),
            nn.MaxPool2d(2),
            Residual(w4),
            nn.AdaptiveMaxPool2d(1),
            nn.Flatten(),
        )
        self.head = nn.Linear(w4, classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.head(self.features(x)) * 0.125


# snippet:end network


# snippet:begin augment
def crop_and_flip(x: torch.Tensor, pad: int = 4) -> torch.Tensor:
    B, C, H, W = x.shape
    padded = F.pad(x, (pad, pad, pad, pad), mode="reflect")
    dy = torch.randint(0, 2 * pad + 1, (B, 1), device=x.device)
    dx = torch.randint(0, 2 * pad + 1, (B, 1), device=x.device)
    rows = (dy + torch.arange(H, device=x.device))[:, None, :, None]
    cols = (dx + torch.arange(W, device=x.device))[:, None, None, :]
    batch = torch.arange(B, device=x.device)[:, None, None, None]
    channel = torch.arange(C, device=x.device)[None, :, None, None]
    out = padded[batch, channel, rows, cols]
    flip = torch.rand(B, 1, 1, 1, device=x.device) < 0.5
    return torch.where(flip, out.flip(3), out)


# snippet:end augment


# snippet:begin strong-augment
def random_view(x: torch.Tensor, min_scale: float = 0.2) -> torch.Tensor:
    B = x.shape[0]
    dev = x.device
    area = torch.empty(B, device=dev).uniform_(min_scale, 1.0)
    ratio = torch.exp(torch.empty(B, device=dev).uniform_(math.log(3 / 4), math.log(4 / 3)))
    sx = torch.sqrt(area * ratio).clamp(max=1.0)
    sy = torch.sqrt(area / ratio).clamp(max=1.0)
    tx = (torch.rand(B, device=dev) * 2 - 1) * (1 - sx)
    ty = (torch.rand(B, device=dev) * 2 - 1) * (1 - sy)
    flip = torch.where(torch.rand(B, device=dev) < 0.5, -1.0, 1.0)
    theta = torch.zeros(B, 2, 3, device=dev)
    theta[:, 0, 0], theta[:, 0, 2] = sx * flip, tx
    theta[:, 1, 1], theta[:, 1, 2] = sy, ty
    grid = F.affine_grid(theta, list(x.shape), align_corners=False)
    out = F.grid_sample(
        x * STD.to(dev) + MEAN.to(dev), grid, align_corners=False, padding_mode="reflection"
    )
    gray = (out * torch.tensor([0.299, 0.587, 0.114], device=dev).view(1, 3, 1, 1)).sum(
        1, keepdim=True
    )
    jitter = torch.rand(B, 1, 1, 1, device=dev) < 0.8
    brightness = torch.empty(B, 1, 1, 1, device=dev).uniform_(0.6, 1.4)
    contrast = torch.empty(B, 1, 1, 1, device=dev).uniform_(0.6, 1.4)
    saturation = torch.empty(B, 1, 1, 1, device=dev).uniform_(0.6, 1.4)
    mean = out.mean(dim=(1, 2, 3), keepdim=True)
    changed = (out * brightness - mean) * contrast + mean
    changed = gray + (changed - gray) * saturation
    out = torch.where(jitter, changed, out)
    to_gray = torch.rand(B, 1, 1, 1, device=dev) < 0.2
    out = torch.where(to_gray, gray.expand_as(out), out).clamp(0, 1)
    return (out - MEAN.to(dev)) / STD.to(dev)


# snippet:end strong-augment


@torch.no_grad()
def embed(encoder: nn.Module, x: torch.Tensor, batch: int = 1000) -> torch.Tensor:
    encoder.eval()
    out = torch.cat([encoder(x[i : i + batch]) for i in range(0, len(x), batch)])
    encoder.train()
    return out


# snippet:begin probe
def linear_probe(train_feats, y_train, test_feats, y_test, epochs: int = 100) -> float:
    mean, std = train_feats.mean(0), train_feats.std(0) + 1e-6
    a, b = (train_feats - mean) / std, (test_feats - mean) / std
    probe = nn.Linear(a.shape[1], 10).to(a.device)
    opt = torch.optim.AdamW(probe.parameters(), lr=1e-3, weight_decay=1e-4)
    for _ in range(epochs):
        for idx in torch.randperm(len(a), device=a.device).split(1000):
            loss = F.cross_entropy(probe(a[idx]), y_train[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
    with torch.no_grad():
        return (probe(b).argmax(1) == y_test).float().mean().item()


# snippet:end probe
