#import "../lib/template.typ": *

= Gradients by machine <ch-autograd>

#chapter-meta(
  time: [7 hours],
  builds: [A reverse-mode automatic differentiation engine for single numbers; then `tiny`, a tensor library of about 650 lines whose gradients respect broadcasting, checked operation by operation against central differences and, for a whole network, against PyTorch to the last bit.],
  needs: [Chapter 1.1. Derivatives and the chain rule as in the Handbook's maths part.],
)

#why[
  Training a model means nudging its parameters in the direction that lowers a loss, and that direction is the gradient: the derivative of the loss with respect to every parameter. A language model has hundreds of millions of parameters, and its gradient must be computed millions of times. _Automatic differentiation_ computes all of it exactly, at the cost of a small multiple of computing the loss itself. Every framework is built on it. This chapter builds one, first for single numbers and then for tensors, so that nothing in later chapters happens by magic, and so that when a gradient is wrong you know where to look.
]

#skip-test(
  rule: [If all four are easy, read the sections on broadcasting and checking, and do Labs 1.2.2 and 1.2.3.],
  [For $d = tanh(a b + e^a) dot b$, draw the computation graph and compute $partial d \/ partial a$ with the chain rule.],
  [A loss depends on a million parameters. Why is computing its gradient backwards from the loss cheaper than forwards from the parameters?],
  [`y = x + b` with `x` of shape $(32, 10)$ and `b` of shape $(10,)$. What is the shape of $partial L \/ partial b$, and how is it computed from $partial L \/ partial y$?],
  [Why does a backward pass add into each gradient instead of assigning it?],
)

== Core ideas

=== Derivatives on a graph

Any computation can be drawn as a graph: inputs at the leaves, each operation a node whose value depends on its inputs, and the result at the root. Take

$ c = a b + e^a, quad d = tanh(c) dot b. $

The _chain rule_ says how a change in $a$ reaches $d$: through every path from $a$ to $d$, multiplying the local derivative of each edge along the path and adding the paths. Here $a$ reaches $d$ through $a b$ and through $e^a$, both feeding $c$, so

$ (partial d) / (partial a) = (partial d) / (partial c) dot (b + e^a), quad (partial d) / (partial c) = b (1 - tanh^2 c). $

$b$ reaches $d$ twice as well, through $c$ and directly. Write $overline(v)$ for $partial d \/ partial v$, the _adjoint_ of $v$: how much the result changes per unit change in $v$. The adjoint of the root is 1. For any other node, its adjoint is the sum, over the nodes that use it, of their adjoint times the local derivative of the use. Computing adjoints from the root towards the leaves, each node visited after every node that uses it, gives the derivative of the result with respect to every node in one sweep. This is _reverse-mode automatic differentiation_, and in machine learning, where the result is a single loss, it is called _backpropagation_.

#fig("u1-graph", caption: [The computation of $d$ as a graph. Each node shows its value from the forward pass, above, and its adjoint from the backward pass, below.]) <fig-graph>

=== A scalar engine

A small class carries out this procedure for single numbers. Each `Value` holds its number, its adjoint, the values it was computed from, and a function that pushes its adjoint to them:

#snippet("aif/tiny/scalar.py", "value", caption: [Addition and multiplication, each recording how to send gradients back to its inputs])

The function attached by `__mul__` encodes the local derivatives of $z = x y$: $partial z \/ partial x = y$ and $partial z \/ partial y = x$, each multiplied by the adjoint arriving from above. Unary operations follow the same pattern:

#snippet("aif/tiny/scalar.py", "unary", caption: [Exponential, logarithm and tanh, each with its derivative])

`backward` orders the graph so that every node comes after the nodes it was computed from, then walks that order in reverse:

#snippet("aif/tiny/scalar.py", "backward", caption: [Topological order by depth-first search, then the adjoints in reverse])

The search uses an explicit stack, since a graph with tens of thousands of nodes would exceed Python's recursion limit. The gradients are _accumulated_ with `+=`: a value used twice, as $b$ is, receives one contribution from each use, which is the sum over paths that the chain rule requires.

#snippet("u1/gradcheck.py", "scalar", caption: [The example, built from `Value`s])

#console-part("/src/console/u1-gradcheck.txt", to: 2, caption: [The engine's derivatives agree with the chain rule worked by hand])

#keyidea[
  Reverse mode costs one backward sweep per _output_, whatever the number of inputs. Each node's backward step costs about as much as its forward step, so the whole gradient of a scalar loss costs a small multiple, typically two to three times, of computing the loss. Forward mode, which carries derivatives from the inputs towards the output, would cost one sweep per _input_: a million sweeps for a million parameters.
]

=== From numbers to tensors

A graph of single numbers would hold billions of nodes for a modest network. Real engines make each node a whole tensor operation: a matrix multiplication, an element-wise function, a sum. The idea is unchanged: each operation knows how to turn the adjoint of its output, a tensor of the output's shape, into adjoints of its inputs, tensors of the inputs' shapes.

For element-wise operations the rule is the scalar rule applied at every position: for $y = exp(x)$, $overline(x) = overline(y) dot.o exp(x)$, with $dot.o$ the element-wise product. Matrix multiplication needs a short derivation.

#derivation[
  Let $C = A B$ with $A$ of shape $n times k$ and $B$ of shape $k times m$, so $C_(i j) = sum_p A_(i p) B_(p j)$. The loss depends on $A_(i p)$ through every $C_(i j)$ in row $i$, with $partial C_(i j) \/ partial A_(i p) = B_(p j)$. Summing over those uses,
  $ overline(A)_(i p) = sum_j overline(C)_(i j) B_(p j) = (overline(C) B^T)_(i p), $
  and by the same argument $overline(B) = A^T overline(C)$. Both are matrix multiplications, so the backward pass of a matrix multiplication costs twice its forward pass, and a network's training step about three times its forward pass.
]

Reductions run the other way: if $s = sum_i x_i$, each $x_i$ affects $s$ with derivative 1, so $overline(x)$ is $overline(s)$ copied to every position. Indexing gathers some elements of a tensor; its adjoint scatters the incoming gradient back to the positions it came from, adding where an index repeats. Broadcasting is the subtle one. When `b` of shape $(10,)$ is added to every row of `x` of shape $(32, 10)$, each element of `b` is used 32 times, so its adjoint is the sum of the 32 adjoints of its uses. In general, the adjoint of a broadcast is a sum over the dimensions it stretched:

#snippet("aif/tiny/tensor.py", "unbroadcast", caption: [Undoing a broadcast: sum away the dimensions that were added or stretched])

=== tiny

`tiny` is a tensor library with exactly these rules. A `Tensor` holds a NumPy array, a gradient, its parents and a backward step. Operations create their result with `child`, which links the graph only if some input needs a gradient:

#snippet("aif/tiny/tensor.py", "tensor", caption: [The tensor: data, gradient, parents and a backward step])

`requires_grad` marks the tensors whose gradients we want, the parameters. Inputs and labels do not need gradients, and a node computed only from them does not need one either; skipping them saves both time and memory. `no_grad` switches graph building off entirely, for evaluation.

#snippet("aif/tiny/tensor.py", "binary", caption: [Addition, multiplication and matrix multiplication, each undoing broadcasting on the way back])

#snippet("aif/tiny/tensor.py", "reductions", caption: [Sum, mean and max. The gradient of a max goes to the winning elements, shared equally among ties])

#snippet("aif/tiny/tensor.py", "shape-ops", caption: [Reshape and transpose move gradients back into the original layout; indexing scatters them])

`backward` is the scalar engine's, visiting only nodes that need gradients:

#snippet("aif/tiny/tensor.py", "backward", caption: [The tensor engine's backward pass])

One operation is written as a single node for numerical reasons, the logarithm of the softmax, which Chapter 1.3 derives. Its backward step uses the result of the forward step instead of recomputing anything:

#snippet("aif/tiny/tensor.py", "log-softmax", caption: [Log-softmax as one node, and the cross-entropy loss built from it])

#hazard(title: [Pitfall])[
  A backward step reads tensors saved by the forward pass: `__mul__` reads `self.data` and `other.data` when the gradient arrives. If anything modifies those arrays in place between the forward and backward passes, the gradient is silently wrong. In `tiny`, as in PyTorch, an optimiser may update parameters in place only after `backward` has finished.
]

=== Checking gradients

A wrong gradient rarely causes an error; the model merely trains badly. Every gradient should therefore be checked once against an independent calculation. The _central difference_

$ (partial f) / (partial x_i) approx (f(x + h e_i) - f(x - h e_i)) / (2 h) $

has an error proportional to $h^2$, so in float64 with $h = 10^(-6)$ it agrees with the true derivative to about eight digits. It needs two evaluations of $f$ per input, which is why it checks gradients and never computes them for training.

#snippet("u1/gradcheck.py", "numeric", caption: [Central differences, one input element at a time])

#snippet("u1/gradcheck.py", "compare", caption: [Comparing analytic and numeric gradients by relative error])

The comparison uses the relative error, the difference divided by the sizes of the two values, since a difference of $10^(-6)$ is negligible for a gradient of 1,000 and alarming for one of $10^(-6)$. Inputs to `log`, `**` and division are kept positive, and the test cases include broadcasting in every operation that allows it:

#snippet("u1/gradcheck.py", "cases", caption: [The fifteen cases])

#console-part("/src/console/u1-gradcheck.txt", from: 2, to: -1, caption: [Every operation within $10^(-6)$ of central differences])

A final check computes the gradient of a small two-layer network with `tiny` and with PyTorch, from the same weights and data:

#snippet("u1/gradcheck.py", "pytorch", caption: [The same network and loss in both libraries])

#console-part("/src/console/u1-gradcheck.txt", from: -1, command: false, caption: [Identical to the last bit, near enough])

The gradients differ by less than $10^(-16)$, the rounding of float64: the two libraries perform the same arithmetic in nearly the same order.

#inpytorch[
  PyTorch's autograd is this design at industrial scale. A tensor with `requires_grad=True` records each operation in a `grad_fn` node; `loss.backward()` walks the graph in reverse, accumulating into each leaf's `.grad`; `torch.no_grad()` disables recording. Gradients accumulate across calls, which is why training loops call `optimizer.zero_grad()` before each `backward`. `torch.autograd.gradcheck` performs this chapter's check on any function, and custom operations subclass `torch.autograd.Function`, supplying `forward` and `backward` as `tiny`'s operations do.
]

#reading(
  [Atılım Güneş Baydin, Barak Pearlmutter, Alexey Radul and Jeffrey Siskind, "Automatic Differentiation in Machine Learning: a Survey", _Journal of Machine Learning Research_ 18, 2018.],
  [The PyTorch documentation, "Autograd mechanics".],
  [Andreas Griewank and Andrea Walther, _Evaluating Derivatives_, second edition, SIAM, 2008, chapters 3 and 4, for the theory of forward and reverse modes.],
)

== Labs

#lab([XOR with a scalar engine], goal: [Train a network built from `Value`s, and see why one layer is not enough.], time: [1.5 hours], code: "code/aif/tiny/scalar.py")[
  + Add `sigmoid` to `Value`, with its derivative, and check it against central differences.
  + Build a network with two inputs, two hidden units using `tanh`, and one sigmoid output, from `Value`s. Train it on the four XOR examples with gradient descent on the squared error.
  + Try again with no hidden layer and explain the result.
  #done-when(
    [The two-layer network classifies all four XOR examples correctly from at least four of five random initialisations.],
    [You can explain, with a drawing, why no single-layer network can.],
  )
  #evidence([The training code, the loss curve, and the drawing.])
]

#lab([A new operation], goal: [Extend `tiny` with operations of your own and prove them right.], time: [1.5 hours], code: "code/aif/tiny/tensor.py")[
  + Add `concat(tensors, axis)` and `where(condition, a, b)`, each with a backward step.
  + Add both to the cases in `u1/gradcheck.py`, including inputs that broadcast in `where`.
  + Add `softplus`, $log(1 + e^x)$, written so that it neither overflows for large $x$ nor loses precision for very negative $x$, and check it at $x = plus.minus 50$.
  #done-when(
    [All three operations pass the gradient check.],
    [`softplus` returns finite, accurate values and gradients at $plus.minus 50$.],
  )
  #evidence([The code and the extended checker's output.])
]

#lab([Break it on purpose], goal: [Learn what wrong gradients look like before you meet one by accident.], time: [1 hour], code: "code/u1/gradcheck.py")[
  + Make `accumulate` assign instead of add. Run the checker and find which cases fail, and why exactly those.
  + Restore it, then remove the call to `unbroadcast` in `__add__`. Note the error that results.
  + Finally, make an optimiser step run before `backward` in a two-step training loop, and describe the symptom.
  #done-when(
    [For each break, you can name the failing cases and explain the mechanism.],
  )
  #evidence([The checker's output for each break, and the explanations.])
]

#lab([What a gradient costs], goal: [Measure the time and memory of backward passes.], time: [1.5 hours], code: "code/aif/tiny/nn.py")[
  + Time the forward pass alone and the forward and backward passes together for an MLP of widths 784, 1024, 1024, 10 in `tiny`, at batch sizes 32, 128 and 512.
  + Count the tensors that the graph holds at the moment `backward` begins, and their total size in bytes.
  + Explain how the memory held would grow with depth and with batch size.
  #done-when(
    [You have the ratio of backward to forward time at each batch size, and can relate it to the matrix-multiplication rule.],
    [Your byte count for the graph matches a prediction made from the layer sizes.],
  )
  #evidence([The table of times, the count, and the prediction.])
]

#problems(
  [Derive the backward step for $y = x \/ norm(x)$, where $x$ is a vector, and simplify it.],
  [A node's output is used by three later nodes. Show that adding the three contributions to its adjoint is exactly the multivariable chain rule.],
  [Forward-mode differentiation propagates a derivative alongside each value. For a function from $RR^n$ to $RR^m$, how many passes do forward and reverse mode need for the full Jacobian? When is forward mode the better choice?],
  [The central difference with $h = 10^(-6)$ is accurate to about $10^(-10)$ in float64. Why would $h = 10^(-12)$ be worse, and what would happen in float32?],
  [`max` shares its gradient equally among tied elements. PyTorch sends it to one of them. Which choice is a valid subgradient, and does it matter for training?],
)

#checklist(
  [I can draw a computation graph and compute every adjoint by hand.],
  [I can explain why reverse mode suits a scalar loss, and what the backward pass costs.],
  [I can derive the backward steps of matrix multiplication, reductions, broadcasting and indexing.],
  [I can check any gradient against central differences and judge the result.],
  [Lab 1.2.1–1.2.4 done-when criteria all hold, with evidence filed.],
)
