import argparse
import re
import subprocess

from aif import check, data, results

ENGINE = "./build/bin/aif_engine"
MODELS = ["tinystories-28m", "SmolLM2-135M", "SmolLM2-360M"]


def engine(path: str, *options: str) -> str:
    done = subprocess.run([ENGINE, path, *options], capture_output=True, text=True)
    check.expect(f"{path} {' '.join(options)} ran", done.returncode == 0, done.stderr[-300:])
    return done.stdout


# snippet:begin bench
def tokens_per_second(path: str, threads: int, tokens: int) -> float:
    out = engine(path, "--bench", "--tokens", str(tokens), "--threads", str(threads))
    return float(re.search(r"([\d.]+) tokens/s", out).group(1))


# snippet:end bench


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", nargs="+", default=MODELS)
    parser.add_argument("--weights", nargs="+", default=["f32"], choices=["f32", "i8", "q4"])
    parser.add_argument("--threads", type=int, nargs="+", default=[1, 2, 4, 8, 12])
    parser.add_argument("--tokens", type=int, default=200)
    parser.add_argument(
        "--check", action="store_true", help="also compare logits with PyTorch"
    )
    args = parser.parse_args()
    print(f"tokens per second generating {args.tokens} tokens, by threads, on the CPU:")
    header = f"{'model':<17}{'weights':<9}{'MiB':>6}"
    header += "".join(f"{t:>7}" for t in args.threads)
    print(header + ("   logit difference" if args.check else ""))
    record = {}
    for model in args.models:
        for weights in args.weights:
            path = f"runs/engine/{model}-{weights}.bin"
            size = (data.RUNS / "engine" / f"{model}-{weights}.bin").stat().st_size / 2**20
            rates = [tokens_per_second(path, t, args.tokens) for t in args.threads]
            line = f"{model:<17}{weights:<9}{size:6.0f}" + "".join(f"{r:7.0f}" for r in rates)
            if args.check:
                out = engine(path, "--check")
                difference = float(re.search(r"PyTorch ([\d.e+-]+)", out).group(1))
                line += f"   {difference:.1e}"
            print(line, flush=True)
            record[f"{model}-{weights}"] = {"mib": size, "rates": rates}
    results.save("u4-engine-bench-" + "-".join(args.weights), record)


if __name__ == "__main__":
    check.main(main)
