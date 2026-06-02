# Core Method Notes

Read this only when a task needs the *why* behind a decision rule in `SKILL.md`.
Source: Jamie Simon, Daniel Kunin, Alexander Atanasov et al.,
*There Will Be a Scientific Theory of Deep Learning*, arXiv:2604.21691.
Project material: `learningmechanics.pub`.

## Thesis

The paper argues for **"learning mechanics"**: a mechanics-like scientific theory of
neural-network training. Such a theory should predict the coarse aggregate statistics of
training dynamics, hidden representations, final weights, and performance from the explicit
ingredients of a DL system — architecture, data, task/loss, and learning rule.

For a programming agent the operative conversion is:

- Do not only optimize a metric.
- **Instrument** the training process.
- **Identify** a simplified regime or empirical law.
- **Predict** a falsifiable quantity before running.
- **Test or exploit** that prediction with the smallest experiment.

This is a *research-program manifesto*, not a drop-in algorithm. Its methods are strongest
when the target behavior is measurable and repeatable; weakest when you need worst-case
guarantees or a-priori constants.

## Five pillars, converted to agent actions

### 1. Solvable idealized settings
Use pared-down models to isolate a mechanism before editing a large system.
- **Deep linear networks** — nonlinear *parameter* dynamics, singular-mode learning,
  depth effects, low-rank bias (despite a linear input→output map).
- **Linearized / NTK models** — architecture-induced inductive bias as kernel regression.
- **Teacher–student / multi-index models** — feature learning with controlled data structure.
- **Isolated blocks** — a single attention / normalization / residual / MLP unit.

Agent action: build a cheap proxy that keeps the suspected mechanism and removes confounders.

### 2. Tractable limits
Use asymptotics to decide which finite-size effects actually matter.
- **Infinite width** — separates lazy/kernel training from rich feature learning.
- **Small learning rate** — approximates gradient flow.
- **Large batch** — approximates the population gradient.
- **Depth / ResNet continuum** — depth ↔ ODE/SDE-like time evolution.
- **Finite HPs** — treated as discretization error or correction terms.

Agent action: name which finite variable you are treating as approximation error, then test
whether increasing it moves the system toward the predicted limiting behavior.

### 3. Simple empirical laws
Search for low-dimensional laws in macroscopic observables.
- Test loss vs. model size / data / compute / tokens (power laws).
- Sharpness (top-Hessian proxy) vs. learning rate or step (progressive sharpening → `2/η`).
- Spectral statistics of weights, activations, gradients, kernels, representations.
- Feature/representation similarity vs. scale or performance.

Agent action: fit a law only after plotting the *right* independent variable, and validate
it on a held-out scale before trusting extrapolation. Track an irreducible noise floor
separately from the power-law term.

### 4. Hyperparameters as system parameters
Treat HPs as variables with scaling rules and invariances, not knobs to grid-search blind.
- SGD: learning rate and batch size show approximate **linear** scaling.
- Adaptive optimizers: candidate **√(batch)** scaling — a hypothesis, not a law.
- LR and batch set the *strength* of implicit curvature regularization, not just speed.
- **μP** separates scale-independent coefficients from width-dependent factors, enabling
  small→large transfer **when the parameterization is correct**.

Agent action: disentangle HPs from architecture size, tune scale-independent values on a
proxy, then verify transfer by checking dynamics (RMS, update/weight ratio) *and* val loss.

### 5. Universal behavior
Look for behavior shared across seeds, architectures, datasets, objectives, modalities.
- Different architectures, matched on compute/data/recipe, reach similar performance and
  even similar input→output maps; representations converge toward a shared ("Platonic") one.
- Natural data shares structure: power-law spectra, sparsity, multiscale/wavelet/hierarchical
  structure, Zipf's law in text.

Agent action: when a phenomenon appears, test that it persists across seeds and nearby
model/data choices *before* attaching an explanation to one run.

## Situation → lens → first measurements

| Situation | Lens | First measurements |
| --- | --- | --- |
| Scale LR / batch / model size | Hyperparameter theory, limits | loss curves, update norm, grad norm, activation RMS |
| Training unstable | Edge of stability, curvature reg. | sharpness `λ_max`, update-to-weight ratio, NaNs/Infs |
| Estimate a bigger run | Empirical scaling law | loss vs. tokens/params/compute, held-out scale |
| Features learned or not? | Lazy vs. rich limit | activation drift, representation similarity, feature probes |
| Same result across architectures | Universality check | matched compute/data evals across seeds/architectures |
| Big run too costly to debug | Solvable proxy | minimal synthetic task preserving the suspected mechanism |

## Cautions / calibration

- The paper is a position paper — no single algorithm or benchmark to reproduce.
- Methods are strongest when the target statistic is measurable and repeatable.
- A proxy that predicts one statistic may fail on another — don't assume transfer of *fit*.
- Empirical laws hold only inside the validated regime; extrapolation is the claim under test.
- Representation-similarity metrics (CKA, kernel alignment, probing, stitching, NN-overlap)
  answer *different* questions and are **not** interchangeable. Match checkpoints by
  compute / data-seen / val-loss, not by arbitrary epoch.
- Explicitly heuristic in the paper: the **neural feature ansatz**.
  Explicitly unproven: the **Discretization Hypothesis** and **a-priori scaling exponents**.
  Do not present these as established.
</content>
