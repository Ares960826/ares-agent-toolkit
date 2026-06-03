---
name: learning-mechanics
description: >-
  Apply the "learning mechanics" framework — the emerging physics-style theory of
  deep learning training dynamics — when writing, debugging, scaling, or tuning
  neural-network code. Use for decisions about learning rate / batch size / width /
  depth scaling, μP (Maximal Update Parameterization) and hyperparameter transfer,
  edge-of-stability and progressive sharpening, lazy vs. rich (feature-learning)
  regimes and initialization scale, neural scaling laws, gradient-flow conservation
  laws / symmetries, neural collapse, the neural feature ansatz, and for designing
  scientific experiments on training. Trigger phrases: "learning mechanics",
  "why is training unstable", "how should I scale the learning rate with width/batch",
  "muP / mup / hyperparameter transfer", "edge of stability", "lazy vs rich",
  "feature learning regime", "scaling laws", "tune hyperparameters on a small model".
  Source: Simon et al., "There Will Be a Scientific Theory of Deep Learning" (2026).
---

# Learning Mechanics — Applied DL Engineering Reference

Distilled from Simon, Kunin, Atanasov et al., *There Will Be a Scientific Theory of
Deep Learning* (arXiv 2604.21691). It is a position paper, not an algorithm — so this
skill turns its named, falsifiable phenomena into **decision rules, checklists, and
pseudo-code** an agent can apply while writing DL code. The *phenomena and scalings* below
are paper-derived; the *engineering recommendations* layered on them (library choices,
instrumentation, debugging order) are standard practitioner guidance, not paper text. Where
the paper flags a thing as heuristic/unproven, so does this skill.

For the deeper paper-derived rationale (the five pillars, proxy catalog, limit theory,
situation→lens decision table), read `references/core-method.md` only when a task needs
the *why* rather than the *what*.

## Core mental model: training is mechanics
A DL system is fully specified by four explicit, measurable parts — treat them as the
"equations of motion," and instrument all of them:

- **Architecture** `f(x; θ)` — composition of linear + nonlinear maps.
- **Data** `D = {(xᵢ, yᵢ)}`, sampled from unknown `P_data`.
- **Task / loss** `L(θ)`.
- **Learning rule** `θ⁽ᵗ⁺¹⁾ = θ⁽ᵗ⁾ − η ∇L(θ⁽ᵗ⁾)`, plus init `θᵢ⁽⁰⁾ ~ N(0, α_init²)` and HPs.

Nothing is hidden: every weight, activation, gradient, loss is loggable. So **prefer
fast cheap experiments over assumptions** — measure the regime before reasoning about it.

## Workflow (do these in order — don't skip step 2)
1. **Specify the system** — pin down all four ingredients above and the scaling axis
   under test (width / depth / batch / data / compute).
2. **Instrument coarse dynamics *before* changing any code.** Always log train/val loss
   vs. tokens, steps, and compute. For instability/scaling work also log: gradient norm,
   update norm, parameter norm, update-to-weight ratio, activation RMS, a sharpness proxy,
   and a gradient-noise proxy. For representation work, snapshot activations at matched
   checkpoints.
3. **Pick the simplest predictive lens** (solvable proxy, tractable limit, empirical law,
   hyperparameter theory, or universality check — see decision rules below).
4. **State a falsifiable quantitative prediction *before* the main run** (LR-vs-width
   scaling, batch scaling, stability threshold, loss-curve shape, scaling exponent,
   representation-similarity trend). Note the regime where it should hold and where it
   should break.
5. **Make the smallest code change that tests the prediction** — metrics & config first,
   proxy/scaling variants second, optimizer/architecture changes last.
6. **Validate and update** — plot observed vs. predicted; if it fails, decide whether the
   proxy, the limit, the independent variable, or the instrumentation was wrong. Keep
   negative results — they mark a boundary of applicability.

## Decision rules you can apply directly

### 1. Scale hyperparameters across model size — don't re-tune blindly
- **Width scaling → use μP (Maximal Update Parameterization).** Under standard
  parameterization the optimal LR drifts as width grows; under μP it stays ~constant,
  so you can tune on a small proxy and transfer. Write `η = η₀ · width^c` and pick the
  μP exponents (the paper's whole point: μP is the feature-learning scaling, NTP freezes
  features — choose μP because feature learning is needed for most tasks).
  - Practical: use a μP-aware library (e.g. `mup`) rather than hand-rolling; tune LR /
    init on a narrow model, transfer to the wide one.
- **Depth scaling (residual nets):** downscale each layer's contribution. `1/depth`
  gives a smooth ODE-like residual stream; `1/sqrt(depth)` gives an SDE-like diffusive
  one — they converge to *different* solutions in transformers, so be deliberate.
- **Caveat from the paper:** transfer theory is asymptotic; benefit depends on how fast
  optimal HPs stabilize with width. Verify transfer on at least one intermediate width.

### 2. Learning rate ↔ batch size are coupled
- **Linear scaling rule (SGD):** double batch → double LR, halve step count; trajectory
  is ~invariant. Use this to port an LR tuned at one batch size to another.
- **Adaptive optimizers (Adam etc.):** scale LR with **√(batch size)**, not linearly.
- **Choosing batch size itself** is a serial-time vs. total-compute tradeoff (Pareto
  hyperbola); the knob is the **critical batch size**. Small batch → cheaper but more
  serial steps; full batch → fewest steps but most compute.
- **`η / B` (learning rate ÷ batch size) ≈ the SGD "noise scale" / temperature** — the
  single knob for implicit-regularization strength: large LR + small batch ⇒ more gradient
  noise ⇒ stronger curvature regularization (see #4). Consistency check: the linear scaling
  rule (`η ∝ B`) is exactly what holds `η / B` fixed, so the trajectory stays invariant.

### 3. Lazy vs. rich — pick your regime by init / output scale
- **Lazy (kernel/NTK) regime:** large init/output scale → weights barely move, dynamics
  are linear in θ (kernel ridge regression w/ the NTK), **no feature learning**. Good for
  closed-form intuition; bad if the task needs learned features. LLM fine-tuning is often
  near this regime.
- **Rich (feature-learning) regime:** *down*scale the network output (final-layer weights
  ~`1/width` instead of `1/sqrt(width)`), or shrink init scale → hidden features adapt,
  neurons specialize, you get the **greedy low-rank bias** (easy/large-singular-value
  modes learned first). This is what you usually want.
- **Actionable lever:** if features aren't being learned (representations identical to
  init), *reduce* the output multiplier / init scale to push toward rich. If training is
  erratic, *increase* it to linearize. Same finite net, opposite behavior.
- Stronger greedy/low-rank bias also comes from: smaller init, more depth, stronger
  minibatch noise, explicit ℓ2 — use these as inductive-bias knobs, not just regularizers.

### 4. Optimization quietly regularizes loss curvature
- First-order optimizers implicitly **penalize Hessian curvature** along the trajectory;
  larger LR and smaller batch → stronger curvature regularization. Full-batch GD training
  is well-modeled as **gradient flow + a curvature penalty**. Treat LR/batch as setting the
  *form and strength* of that penalty, which affects generalization and compressibility.

### 5. Edge of stability — diagnose training (in)stability
- With full-batch GD at LR `η`, sharpness (top Hessian eigenvalue) **rises (progressive
  sharpening) then plateaus near `2/η`** = edge of stability. `2/η` is the max stable
  sharpness; above it, parameter oscillations grow.
- **Debugging rule:** loss oscillating/diverging? Estimate sharpness `λ_max`. If
  `λ_max ≳ 2/η`, lower `η` (or accept bounded oscillation in unstable directions — the
  trajectory decomposes into smooth gradient-flow dynamics + oscillations there).

### 6. Exploit conservation laws & symmetries (sanity checks + debugging)
- Gradient flow conserves `Wₗ Wₗᵀ − Wₗ₊₁ᵀ Wₗ₊₁` between layers (from parameter symmetry —
  a Noether-type law). Symmetry families and their conserved stats:
  - ReLU/homogeneous → rescaling symmetry; pre-norm layers → scale symmetry;
    pre-softmax logits → translation symmetry; attention key/query → rotation symmetry.
- **Use as invariants:** under gradient flow these are conserved; SGD breaks them weakly
  and predictably. A symmetry-conserved quantity drifting fast can flag a bug or
  numerical issue in your training loop.

### 7. End-of-training structure you can expect (and assert in tests)
- **Neural collapse** (classifier + cross-entropy + small weight decay): final-layer
  features cluster tightly at class means, and the `C` class means form a regular simplex.
  Reasonable post-training sanity check for classifiers.
- **Neural feature ansatz (heuristic, inexact):**
  `W₁ᵀ W₁ ∝ E_x[ ∇ₓ f(x;θ) ∇ₓ f(x;θ)ᵀ ]` — first-layer weight Gram matrix aligns with the
  average gradient outer product; top eigenvectors of `W₁ᵀW₁` are often well predicted by
  it. Useful for interpreting *what* the first layer learned. (Paper: heuristic, only
  partially explained — don't treat as exact.)

### 8. Scaling laws — extrapolate, but don't predict exponents
- Within an architecture family, test loss follows **power laws** in compute, data, and
  parameter count. Use these to *plan* compute/data/size budgets and extrapolate loss.
- **Honest limit (from the paper):** no framework reliably predicts the *exponents* a
  priori from data/architecture. Fit them empirically on small runs; don't claim a
  first-principles exponent.
- For compute-optimal scaling, data size and parameters scale together — a finite-size
  model at fixed data can perfectly interpolate and won't show the cross-size law.

### 9. Lean on universality
- Across architectures (CNN vs. transformer vs. UNet), matched on compute/data/recipe,
  performance and even input→output mappings converge; larger models converge toward a
  shared ("Platonic") representation. Implication: **architecture choice is often
  secondary to data + compute + recipe** — don't over-index on architecture when a result
  should be architecture-universal. Natural data shares structure (power-law spectra,
  sparsity, multiscale/wavelet structure; Zipf's law in text) that the model relies on.

## The Discretization Hypothesis (framing heuristic)
Treat practical finite nets as noisy discretizations of infinite-size limits: width↔space,
depth↔time; smaller LR / larger size ⇒ smaller "discretization error" at higher compute
cost. Useful intuition for *why* scaling up and lowering LR tend to help. The paper flags
this as **unproven** — use it to reason, not to assert guarantees.

## Experiment tenets (apply when doing DL science, not just shipping)
1. **Experiment frequently** — cost is low, turnaround fast; measure to check every
   assumption and reveal a theory's limits.
2. **Simplicity & insight > technical complexity** — the simplest revealing experiment wins.
3. **Understanding > SOTA** — when investigating *why*, don't bolt on a benchmark number
   that dilutes the finding.
4. Prefer **average-case / coarse aggregate statistics** (train/test loss, sharpness,
   representation similarity) over worst-case bounds — these are where the lawful
   regularities live.

## Reproducibility checklist (record for every run you'll compare)
seed · exact data slice/order · full config dump · git commit or diff · hardware ·
numerical precision · package versions · which scaling axis varied (everything else fixed).
Without these, a "failed prediction" is unattributable.

## Quick routing checklist
- "Optimal LR changed when I widened the model" → μP + transfer (#1).
- "Changed batch size, training broke" → linear scaling rule (SGD) or √-scaling (Adam) (#2).
- "Model isn't learning features / reps == init" → push to rich regime: shrink output/init scale (#3).
- "Loss oscillates / diverges at high LR" → edge of stability, check `λ_max` vs `2/η` (#5).
- "Need to budget a big run" → fit power-law scaling on small runs, extrapolate (#8).
- "Want to predict the scaling exponent from theory" → you can't reliably; fit it (#8, honest).
- "Verifying a classifier converged sensibly" → check neural collapse (#7).

## Output requirements (include these when you apply the skill)
- **Lens chosen:** solvable proxy / limit / empirical law / hyperparameter theory / universality.
- **Measurements or logs to add** (from the workflow step 2 list).
- **The falsifiable prediction** being tested, with expected magnitude/direction.
- **Smallest experiment or code change** that tests it.
- **Regime of applicability:** where the recommendation should hold, and where it may break.

## Honesty notes
- This is a *position/theory* paper: no single algorithm or benchmark result to reproduce.
  The physics — deep linear net, NTK linearization, neural feature ansatz, and the
  `2/η`, `1/width`, `√(batch)`, `η/B` scalings — is quoted from it, not fabricated. The
  engineering advice (e.g. "use a μP-aware library", the logging/instrumentation lists,
  the debugging order) is added practitioner guidance, not paper text — treat it as such.
- Items flagged heuristic (neural feature ansatz) or unproven (Discretization Hypothesis,
  a-priori scaling exponents) are exactly the ones the paper itself flags. Don't overclaim.
- Further material: `learningmechanics.pub`; deeper rationale in `references/core-method.md`.
