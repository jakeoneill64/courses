#import "../lib/template.typ": *

= The maths you need <h-maths>

The course uses three areas of mathematics: linear algebra, for the shapes of data and models; calculus, for training; and probability, for losses, sampling and evaluation. This part summarises what each chapter assumes, so that you can check yourself before you start, and says where each idea is first used. It is a reminder, not a course: if a section is new to you, the reading list at the end of the part gives a gentle source for each.

== Vectors and matrices

A _vector_ is a list of $n$ numbers, $x = (x_1, dots, x_n)$, and a _matrix_ an $m times n$ table of them. The course writes vectors as columns, so a matrix $W$ of shape $m times n$ maps a vector $x$ of length $n$ to $W x$ of length $m$, with $(W x)_i = sum_j W_(i j) x_j$. In code, a batch of vectors is a matrix with one vector per _row_, and a linear layer computes `x @ W`, so the shapes there read the other way round; Chapter 1.5 is careful about which convention each listing uses.

- *The dot product* $x dot y = sum_i x_i y_i$ measures how far two vectors point the same way; the _norm_ $norm(x) = sqrt(x dot x)$ is a vector's length, and $x dot y = norm(x) norm(y) cos theta$. Attention (Chapter 2.3) and retrieval (3.7) are built on dot products.
- *Matrix multiplication* $C = A B$ needs the inner sizes to agree: an $m times k$ matrix times a $k times n$ matrix is $m times n$, with $C_(i j) = sum_p A_(i p) B_(p j)$. It is associative but not commutative, and $(A B)^T = B^T A^T$. It costs $2 m k n$ floating-point operations (Chapter 1.1).
- *The transpose* $A^T$ swaps rows and columns; a matrix with $A = A^T$ is _symmetric_.
- *Eigenvectors* of a square matrix $H$ satisfy $H v = lambda v$: $H$ only stretches them, by the _eigenvalue_ $lambda$. A symmetric matrix has a full set of perpendicular eigenvectors. Chapter 1.4 uses them to explain why some loss surfaces are hard to descend.
- *Rank and the pseudo-inverse.* The rank of a matrix is the number of independent directions it can produce. A system $A x = b$ with more unknowns than equations has many solutions, and the _pseudo-inverse_ $A^+$ picks the shortest one; Chapter 1.6 uses it to explain double descent, and Chapter 3.3 uses low rank to make fine-tuning cheap.

== Derivatives and the chain rule

The _derivative_ $f'(x)$ is the slope of $f$ at $x$: for a small change $delta$, $f(x + delta) approx f(x) + f'(x) delta$. The derivatives the course uses most are

$ (x^n)' = n x^(n-1), quad (e^x)' = e^x, quad (ln x)' = 1/x, quad (tanh x)' = 1 - tanh^2 x, quad sigma'(x) = sigma(x)(1 - sigma(x)), $

where $sigma(x) = 1 \/ (1 + e^(-x))$. A function of many variables has a _partial derivative_ for each, $partial f \/ partial x_i$, the slope when only $x_i$ changes, and the vector of them all is the _gradient_ $nabla f$, which points in the direction of steepest increase. Training moves parameters a little against the gradient of the loss (Chapter 1.4).

The _chain rule_ differentiates compositions: if $y = g(u)$ and $u = h(x)$, then $(d y) / (d x) = (d y) / (d u) dot (d u) / (d x)$. When $x$ affects $y$ through several paths, the contributions add. Automatic differentiation (Chapter 1.2) is nothing but the chain rule, applied systematically to a program. For functions from vectors to vectors, the matrix of all partial derivatives is the _Jacobian_, and the chain rule multiplies Jacobians; Chapter 1.7 uses this to explain why gradients vanish in deep networks.

A function's _second_ derivatives describe its curvature. For a function of many variables they form the symmetric _Hessian_ matrix, whose eigenvalues say how sharply the function curves in each direction (Chapter 1.4).

== Probability

A _random variable_ takes values according to a _distribution_. The course uses four.

- *Bernoulli*: a yes or no with probability $p$ of yes. Binary classification (Chapter 1.3).
- *Categorical*: one of $K$ outcomes with probabilities $p_1, dots, p_K$ summing to one. Classification, and the next token of a language model (Unit 2).
- *Gaussian* (normal): a continuous value with mean $mu$ and standard deviation $sigma$, density $1 \/ sqrt(2 pi sigma^2) exp(-(x - mu)^2 \/ (2 sigma^2))$. Noise in regression (Chapter 1.3) and initial weights (1.5).
- *Uniform*: every value in a range equally likely. Random initialisation and sampling.

The _expectation_ $E[X] = sum_x x P(x)$ is the mean value, and is linear: $E[a X + b Y] = a E[X] + b E[Y]$. The _variance_ $"Var"(X) = E[(X - E[X])^2]$ measures spread; its square root is the standard deviation. For _independent_ variables, variances add: $"Var"(X + Y) = "Var"(X) + "Var"(Y)$. Chapter 1.5 derives initialisation from that rule, and Chapter 1.6 the precision of a test score.

Conditional probability $P(A | B) = P(A, B) \/ P(B)$ is the probability of $A$ once $B$ is known, and _Bayes' rule_ turns it round: $P(A | B) = P(B | A) P(A) \/ P(B)$. A language model is a conditional distribution, $P("next token" | "the tokens so far")$, and the probability of a whole text is the product of these conditionals, the chain rule of probability (Chapter 2.2).

The _sample mean_ of $n$ independent observations estimates the expectation, with a standard error of $sigma \/ sqrt(n)$: halving the uncertainty needs four times the data. Chapter 3.6 builds evaluation on this fact and on the bootstrap, which estimates uncertainty by resampling.

== Logarithms and exponentials

The course takes logarithms constantly, because probabilities multiply and logarithms turn products into sums: $log(a b) = log a + log b$. Natural logarithms, base $e$, are the default; a quantity in natural-log units is in _nats_, and dividing by $ln 2$ converts it to _bits_. The exponential $e^x$ grows fast enough to overflow single-precision floating point above $x approx 88.7$, which is why Chapter 1.3 computes softmax and log-probabilities with care.

#tbl(columns: (auto, 1fr), header: ([Idea], [First used]),
  [Matrix multiplication, its cost and shapes], [Chapter 1.1],
  [Chain rule, gradients, Jacobians], [Chapters 1.2 and 1.7],
  [Maximum likelihood, Gaussian and categorical distributions], [Chapter 1.3],
  [Hessian, eigenvalues, condition number], [Chapter 1.4],
  [Variance of sums of independent variables], [Chapter 1.5],
  [Pseudo-inverse, rank], [Chapters 1.6 and 3.3],
  [Conditional probability and the chain rule of probability], [Chapter 2.2],
  [Bradley–Terry model, log-odds], [Chapter 3.4],
  [Standard error, confidence intervals, the bootstrap], [Chapters 1.6 and 3.6],
)
