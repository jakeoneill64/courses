from aif import bpe, data, gpt


def tinystories_model(device, name: str = "tinystories-28m"):
    model = gpt.load(data.RUNS / name / "model.pt", device).eval()
    tok = bpe.BPE.load(data.DATA / "tinystories" / "bpe8192.json")
    return model, tok
