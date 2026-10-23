# Evaluation dataset for the nlmixr2llm agent and skills.
#
# Each row is one sample:
#   id      stable identifier, used to compare runs over time
#   skill   which skill the question exercises (list_tasks())
#   input   the prompt given to the model under test
#   target  grading guidance for the model grader: what a correct answer
#           must contain, and the specific mistakes that make it wrong
#   runs    TRUE when the answer must contain R code that executes; the
#           scorer then runs the code (see run_answer_code() in eval.R)
#
# Targets state facts the skills document and that were checked against the
# packages (see the references in inst/skills/*/references/). Keep them that
# way: a target the skills do not support measures the grader's knowledge,
# not the skills' effect.

nlmixr2_eval_dataset <- function() {
  tibble::tribble(
    ~id, ~skill, ~runs, ~input, ~target,

    "nn-method-etas", "estimation", FALSE,
    "I have an nlmixr2 model where an nlmixr2nn nn() term takes a latent eta (eta.nn ~ 0.2) as an input. Which estimation method should I use to fit it, and are there methods I should avoid?",
    "Recommends a method with gradients on the inner (eta) step: focei first; laplace/agq, impmap, or the variational methods (vae, emvi, fbvi) are also acceptable. Says to avoid saem (and fsaem), qrpem, and the nonparametric methods (npag/npb), and plain imp (no MAP step). Recommending SAEM as the primary method is incorrect. Mentioning that FOCEi's default outerOpt = \"bobyqa\" is fine earns no penalty.",

    "nn-method-no-eta", "estimation", FALSE,
    "My nlmixr2 model has an nn() term (nlmixr2nn) for an unknown elimination rate, no random effects at all, and an additive residual error. Which est= should I use?",
    "Recommends a population (no-eta) estimator that uses gradients, such as lbfgsb3c, nlminb, n1qn1 or nlm, and advises against derivative-free ones (bobyqa, newuoa, uobyqa). Recommending a mixed-effects method such as saem as the main choice is incorrect. Full credit may also note that for lnorm()/pois()/binom() endpoints these population estimators are not supported and focei should be used instead.",

    "nn-joint-check", "estimation", FALSE,
    "I fitted an nlmixr2nn model with focei and the default nnControl(). The objective function improved a lot, but fit$theta and fit$omega look identical to my ini() values. Is that expected, and what should I do?",
    "Explains that this is a known problem with the default joint training mode (nlmixr2nn issue #9): the network weights trained but THETA/OMEGA were not re-estimated. Recommends refitting with nn = nnControl(mode = \"iter\") and checking fit$theta/fit$omega against the ini() values. Saying the result is fine or that the parameters simply converged to their initial values is incorrect.",

    "struct-explore", "estimation", FALSE,
    "Using nlmixr2 and the theo_sd data (single oral dose), how should I choose the base structural PK model? Outline the procedure, including how to make the candidate comparison fair.",
    "Proposes several candidate structures (at least 1-cmt first-order absorption, absorption delay via lag time or transit compartments, and 2-cmt), ideally from nlmixr2lib (readModelDb, addLag, addTransit). Fits every candidate under an identical stochastic model: same etas, same residual error model, same estimation method, same data. Ranks with OFV / AIC / BIC after gating on convergence, covariance step, parameters on bounds and RSE, and checks with a VPC or residual diagnostics. Settles the structure before adding covariates or refining OMEGA. Extra credit for noting that CMT should be named (depot/central) because adding transit compartments renumbers them.",

    "nlmixr2auto-scope", "estimation", FALSE,
    "Can nlmixr2auto's sf.operator() with search.space = \"oralbase\" find a model with an absorption lag time or transit compartments?",
    "No. The oralbase search space has first-order absorption only; nlmixr2auto searches the number of compartments (1-3), linear vs Michaelis-Menten elimination, IIV, eta correlation and residual error. Lag or transit absorption must be proposed and fitted outside it (for example, continuing a manual structural loop from nlmixr2auto's winner). Answering yes is incorrect.",

    "saem-ofv", "estimation", FALSE,
    "After an nlmixr2 SAEM fit, fit$objDf shows NA for the objective function. How do I get an OFV, and how do I compare it fairly with a FOCEi fit of a different model?",
    "Explains that SAEM does not compute an OFV during the fit: accessing fit$objf computes one (Gaussian quadrature), and addCwres(fit) adds the FOCEi objective; setOfv() selects which one fit$objf reports. Stresses comparing OFVs only when they are computed the same way (both FOCEi, or both the same likelihood approximation).",

    "et-unnamed", "simulation", FALSE,
    "In rxode2, `et(amt = 100, cmt = \"depot\") |> et(0:24)` errors with 'improper arguments to et'. Why, and what is the fix?",
    "The sampling-time argument must be named when piped: et(amt = 100, cmt = \"depot\") |> et(time = 0:24). An unnamed vector piped into et() is not interpreted as sampling times.",

    "sim-population", "simulation", TRUE,
    "Write complete, runnable R code using rxode2 that simulates a one-compartment oral PK model (ka = 1.2 /h, CL = 3 L/h, V = 30 L, 30% CV between-subject variability on CL) for 20 subjects given 100 mg every 12 hours for 5 days, and prints the mean concentration at each sampling time.",
    "Code defines an rxode2 model with d/dt(depot) and d/dt(central) (or linCmt()), puts BSV on CL through an eta with a variance near log(1 + 0.3^2) or about 0.09, and builds the regimen with et(amt = 100, ii = 12, addl = 9, cmt = \"depot\") (or an equivalent dosing table) plus named sampling times. It simulates 20 subjects (nSub = 20 or an omega matrix), sets the random seeds for reproducibility (set.seed and rxode2::rxSetSeed), and summarizes mean concentration by time.",

    "fit-theo", "estimation", TRUE,
    "Write complete, runnable R code that fits a one-compartment model with first-order absorption to nlmixr2's theo_sd data using FOCEi, with between-subject variability on ka, CL and V and an additive residual error, and prints the parameter estimates with their precision.",
    "Code passes a model function with ini() and model() blocks to nlmixr2(model, theo_sd, est = \"focei\", ...), with fixed effects on the log scale (e.g. tka <- log(1.57), ka <- exp(tka + eta.ka)), etas on ka, CL and V, and a residual line such as cp ~ add(add.sd). It prints fit$parFixed (or print(fit)). Fixed effects not on the log scale, or est = \"saem\", is a partial answer at best.",

    "nonmem2rx-qualify", "interop", FALSE,
    "I imported a finished NONMEM run into R with nonmem2rx. What must I check before using it to simulate new dosing regimens?",
    "Must qualify the translation first: check that rxode2 reproduces NONMEM's own PRED/IPRED (mod$predCompare / mod$ipredCompare, plot(mod)), with differences near zero; if they are not, fix the translation before using it. Notes that the import is an rxode2 model, not an nlmixr2 fit (babelmixr2::as.nlmixr2() promotes a qualified import to a fit), and that it carries its covariance, so rxSolve(mod, ev, nStud = ...) can simulate uncertainty.",

    "poped-rse", "design", FALSE,
    "How do I get the expected RSE% of each parameter for a planned PK study design, starting from an nlmixr2 model function, in R?",
    "Uses babelmixr2 to build a PopED database: nlmixr2(model, design, \"poped\", popedControl(...)) with the design given as an event table (groups, doses, sampling times, groupsize), then PopED functions such as evaluate_design() or get_rse() to report expected RSE%. Answers that only describe running a simulation-estimation study without the FIM-based PopED route are partial.",

    "vpc", "reporting", FALSE,
    "How do I make a visual predictive check for an nlmixr2 fit, including when some observations are below the limit of quantification?",
    "Uses nlmixr2plot::vpcPlot(fit, n = ...) (e.g. n = 500); for censored/BLQ data, vpcCens() (or the censored VPC options). Mentions that the observation percentiles are compared with simulated prediction intervals."
  )
}
