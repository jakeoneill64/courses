import numpy as np

from aif import check, results
from aif.tiny import Tensor, cross_entropy, nn, no_grad, optim
from u1.common import batches, mnist_split


# snippet:begin shift
def shift(images: np.ndarray, rng: np.random.Generator, pixels: int = 2) -> np.ndarray:
    grid = images.reshape(-1, 28, 28)
    out = np.empty_like(grid)
    for i, img in enumerate(grid):
        dy, dx = rng.integers(-pixels, pixels + 1, 2)
        out[i] = np.roll(np.roll(img, dy, axis=0), dx, axis=1)
    return out.reshape(len(images), -1)


# snippet:end shift


def accuracy(model, x, y) -> float:
    model.eval()
    with no_grad():
        right = (model(Tensor(x)).data.argmax(1) == y).mean()
    model.train()
    return float(right)


# snippet:begin variant
def train(
    x,
    y,
    x_val,
    y_val,
    epochs: int,
    weight_decay: float = 0.0,
    dropout: float = 0.0,
    augment: bool = False,
    seed: int = 1,
):
    rng = np.random.default_rng(seed)
    model = nn.mlp([784, 512, 512, 10], rng, dropout=dropout)
    opt = optim.AdamW(model.parameters(), lr=1e-3, weight_decay=weight_decay)
    history = []
    for epoch in range(epochs):
        losses = []
        for idx in batches(len(x), 100, rng):
            xb = shift(x[idx], rng) if augment else x[idx]
            loss = cross_entropy(model(Tensor(xb)), y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
            losses.append(loss.item())
        history.append((float(np.mean(losses)), accuracy(model, x_val, y_val)))
    return model, history


# snippet:end variant


def main() -> None:
    (x, y), (x_val, y_val), (x_test, y_test) = mnist_split()
    x, y = x[:1000], y[:1000]
    epochs = 150
    variants = {
        "no regularisation": {},
        "weight decay 0.5": {"weight_decay": 0.5},
        "dropout 0.5": {"dropout": 0.5},
        "shifts of up to 2 pixels": {"augment": True},
        "all three": {"weight_decay": 0.5, "dropout": 0.5, "augment": True},
    }
    print(f"1,000 training images, {epochs} epochs; validation on 5,000, test on 10,000")
    print(
        f"{'':<26}{'train loss':>11}{'final val':>11}{'best val':>10}{'at epoch':>10}{'test':>9}"
    )
    curves = {}
    for name, options in variants.items():
        model, history = train(x, y, x_val, y_val, epochs, **options)
        losses, accs = zip(*history)
        best = int(np.argmax(accs))
        test = accuracy(model, x_test, y_test)
        curves[name] = history
        print(
            f"{name:<26}{losses[-1]:11.4f}{accs[-1]:11.2%}{accs[best]:10.2%}{best + 1:10d}{test:9.2%}"
        )
    results.save("u1-overfit", curves)
    final = {name: h[-1][1] for name, h in curves.items()}
    check.expect(
        "regularisation helps", final["all three"] > final["no regularisation"] + 0.01
    )


if __name__ == "__main__":
    check.main(main)
