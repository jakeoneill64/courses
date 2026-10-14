from aifig import C, Diagram

UNITS = [
    ("1", "Learning Machines", "amber_t", C["amber"],
     ["Tensors and cost", "Gradients by machine", "Models as probability", "Optimisers", "Neural networks",
      "Generalisation", "Training deep networks", "Representations"]),
    ("2", "Language Models", "coral_t", C["coral"],
     ["Tokenisation", "Next-token prediction", "Attention", "The transformer", "Pretraining", "Scaling laws",
      "Decoding", "Inside the model"]),
    ("3", "Base Model to Assistant", "magenta_t", C["magenta"],
     ["Open weights", "Fine-tuning", "LoRA", "Preferences", "RL with rewards", "Evaluation", "Retrieval",
      "Tools and agents"]),
    ("4", "Making It Fast", "purple_t", C["purple"],
     ["The machine", "Profiling and memory", "Numerics", "Kernels", "Parallel training", "Engine in C++",
      "Quantisation", "Serving"]),
]

LINKS = [((1, 2), (1, 5)), ((2, 1), (3, 1)), ((2, 4), (3, 1)), ((3, 3), (4, 7)), ((3, 6), (4, 7))]


def course_map():
    d = Diagram(168, 116)
    col_w, gap, box_h, top = 34.0, 9.0, 9.0, 90.0
    boxes = {}
    for u, (number, title, kind, colour, chapters) in enumerate(UNITS):
        x = 4 + u * (col_w + gap)
        d.text(x + col_w / 2, top + 21, f"UNIT {number}", size=7.4, weight="bold", color=colour)
        d.text(x + col_w / 2, top + 15.5, title, size=7.2, color=C["ink"])
        for i, name in enumerate(chapters):
            y = top - i * (box_h + 2.4)
            boxes[(u + 1, i + 1)] = d.box(x, y, col_w, box_h, f"{number}.{i + 1}  {name}", kind=kind, size=6.6,
                                          weight="normal", radius=1.2)
    for a, b in LINKS:
        p, q = boxes[a], boxes[b]
        if a[0] == b[0]:
            d.curve(p.e, q.e, bulge=5, color=C["muted"])
        else:
            d.arrow(p.e, q.w_, color=C["muted"], lw=0.7)
    d.save("h-map")


if __name__ == "__main__":
    course_map()
