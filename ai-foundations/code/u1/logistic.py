import numpy as np

from aif import check, data
from aif.tiny import Tensor, cross_entropy, no_grad, optim
from u1.common import batches, mnist_split


def main() -> None:
    (x, y), (x_val, y_val), (x_test, y_test) = mnist_split()
    rng = np.random.default_rng(0)
    # snippet:begin softmax-regression
    w = Tensor(np.zeros((784, 10), dtype=np.float32), requires_grad=True)
    b = Tensor(np.zeros(10, dtype=np.float32), requires_grad=True)
    opt = optim.SGD([w, b], lr=0.1)
    for epoch in range(1, 6):
        for idx in batches(len(x), 128, rng):
            loss = cross_entropy(Tensor(x[idx]) @ w + b, y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
        with no_grad():
            val = ((Tensor(x_val) @ w + b).data.argmax(1) == y_val).mean()
        print(f"epoch {epoch}  validation accuracy {val:.2%}")
    # snippet:end softmax-regression
    with no_grad():
        logits = (Tensor(x_test) @ w + b).data
    test = float((logits.argmax(1) == y_test).mean())
    confusion = np.zeros((10, 10), dtype=int)
    np.add.at(confusion, (y_test, logits.argmax(1)), 1)
    np.fill_diagonal(confusion, 0)
    worst = np.dstack(np.unravel_index(np.argsort(-confusion.ravel())[:3], confusion.shape))[0]
    print(
        f"test accuracy {test:.2%}; most common mistakes: "
        + ", ".join(f"{t} read as {p} ({confusion[t, p]})" for t, p in worst)
    )
    np.save(data.RUNS / "u1-logistic-weights.npy", w.data.T.reshape(10, 28, 28))
    check.expect("softmax regression accuracy", test > 0.90, f"{test:.2%}")


if __name__ == "__main__":
    check.main(main)
