# Stress kit: questions built from the nlmixr2-ecosystem findings and traps in
# the nlme-benchmark project (registry/findings.csv and
# registry/translationTraps.csv). Each one is a place where a plausible answer
# is wrong in a way that still runs, still converges, or still looks like a
# fit, so a model that merely knows the API will fail it.
#
# Columns are those of nlmixr2_eval_dataset() plus:
#   source  the benchmark finding (Fnnn) or trap (Tnnn) the question tests
#   check   optional R code run after the answer's own code, in the same
#           environment; an error fails the answer even if its code ran.
#           Only used when runs = TRUE.
#
# Every target was re-checked against the installed packages when written
# (nlmixr2est 7.1.0, rxode2 5.1.8; tolerance defaults, combined error forms,
# the reserved SS/II columns and the MDV rejection were all reproduced).
# Upstream issues that have since been closed (babelmixr2#211, rxode2#1410)
# are tested as verification habits, not as bugs the answer must know about.

nlmixr2_stress_dataset <- function() {
  # The SS/II stress sample builds its own data, as a user would paste it.
  ssii_data <- paste(
    "d <- nlmixr2data::theo_sd",
    "d$EVID <- ifelse(d$EVID != 0, 1, 0)",
    "d$SS <- ifelse(d$EVID == 1, 1, 0)   # NONMEM reads these two as SSX / IIX",
    "d$II <- ifelse(d$EVID == 1, 24, 0)  # in $INPUT, i.e. as ignored covariates",
    sep = "\n"
  )
  mdv_data <- paste(
    "d <- data.frame(id = 1, time = c(0, 1, 2, 4, 8, 12),",
    "                amt = c(100, 0, 0, 0, 0, 0), evid = c(1, 0, 0, 0, 0, 0),",
    "                mdv = 0, cmt = \"depot\")",
    sep = "\n"
  )

  tibble::tribble(
    ~id, ~skill, ~source, ~runs, ~input, ~target, ~check,

    "stress-ssii-reserved", "estimation", "F010/T028", TRUE,
    paste0(
      "This dataset came from a NONMEM project. Its control stream reads the SS and II columns as SSX and IIX in $INPUT, ",
      "so NONMEM ignores them; every dose is a single dose. Write complete, runnable R code that fits it in nlmixr2 with FOCEi ",
      "using a one-compartment model with first-order absorption (linCmt() is fine), etas on ka, CL and V, and additive error. ",
      "Store the fit in an object called `fit`.\n\n```r\n", ssii_data, "\n```"
    ),
    "Recognizes that rxode2/nlmixr2 reserve SS and II as event columns, so passing the data as-is would make every dose a steady-state dose (q24h) and fit a different model: the OFV rises from about 117 to about 165 and CL is biased upward. The answer removes or renames SS and II (e.g. to SSX/IIX) before fitting, mirroring what the NONMEM $INPUT rename does, and fits with est = \"focei\". Fitting the data unchanged is incorrect even though it runs and converges.",
    "od <- fit$origData\nnm <- toupper(names(od))\nfor (col in c(\"SS\", \"II\")) if (col %in% nm) stopifnot(all(od[[which(nm == col)[1]]] == 0))",

    "stress-mdv-dose", "simulation", "T010", TRUE,
    paste0(
      "rxode2 refuses to simulate from this data frame with \"'mdv' cannot be 0 when 'evid'=1\". Write complete, runnable R code ",
      "that simulates a one-compartment oral model (ka = 1 /h, CL = 2 L/h, V = 20 L, compartments `depot` and `central`) for this subject, ",
      "storing the rxSolve() result in `sim`.\n\n```r\n", mdv_data, "\n```"
    ),
    "Treats the rejection as correct behaviour: a dose row cannot have mdv = 0. Fixes the data rather than the check, by setting mdv = 1 on dose rows (or dropping the mdv column and letting evid define the rows), then simulates. Removing the dose rows, or otherwise working around the check so that no dose is given, is incorrect.",
    "stopifnot(exists(\"sim\"), any(sim$time > 0 & sim$central > 0))",

    "stress-combined1", "interop", "T013", TRUE,
    paste0(
      "Translate this NONMEM residual error model into an nlmixr2 model function called `mod` (one-compartment oral PK with linCmt(), ",
      "log-scale thetas). The residual model must be expressed in the model itself.\n\n",
      "```\nIPRED = F\nW = THETA(4) + THETA(5)*IPRED\nY = IPRED + W*EPS(1)\n$SIGMA 1 FIX\n```"
    ),
    "Recognizes the standard-deviation-scale combined model, sd = a + b*f, which nlmixr2 calls combined1, and that nlmixr2's add() + prop() defaults to combined2 (variance scale, sqrt(a^2 + b^2*f^2)). Writes the residual line as add(add.sd) + prop(prop.sd) + combined1() (or sets addProp = \"combined1\" and says so). Writing add() + prop() alone silently fits a different error model and is a partial answer at best.",
    "ui <- rxode2::rxode2(mod)\nstopifnot(any(ui$predDf$addProp == \"combined1\"))",

    "stress-ode-tolerance", "estimation", "F011", FALSE,
    "The same two-compartment model fitted with FOCEi to identical data gives an objective function about 5 units higher when written as ODEs than when written with linCmt(). Which result should I trust, why do they differ, and what should I change?",
    "Explains that the linCmt() path gets exact gradients by automatic differentiation, while the ODE path integrates the model and its sensitivity equations at foceiControl's sigdig = 3 tolerances (rtol 1e-3, atol 1e-6, with rtolSens/atolSens set to the same values). Those are too loose for the gradient, so the ODE fit stops at a slightly worse optimum, and the gap grows with the number of observations. Remedy: tighten the solve, e.g. a larger sigdig, or tighter rtol/atol or rtolSens/atolSens passed through rxControl, then confirm the ODE objective now matches linCmt(). Concluding that the ODE model is a different or better model is incorrect.",
    NA_character_,

    "stress-rxcontrol-confound", "estimation", "F011", FALSE,
    "To test whether loose sensitivity tolerances cause my ODE fit's worse objective, I refit with foceiControl(rxControl = rxode2::rxControl(atolSens = 1e-10, rtolSens = 1e-10)). The objective improved by 5 units, so the sensitivity tolerances were the cause, right?",
    "Not established. Passing a full rxode2::rxControl() object to foceiControl() skips its sigdig-based tolerance scaling, so the STATE tolerances also changed (to rxode2's own defaults, rtol 1e-6 and atol 1e-8, much tighter than the sigdig = 3 values 1e-3 / 1e-6). The experiment tightened both at once. To attribute the effect, pass the settings as a list (rxControl = list(atolSens = 1e-10, rtolSens = 1e-10)), which keeps the sigdig scaling, or state all four tolerances explicitly in every arm. In the benchmark either knob alone closed the gap, so the cause is the overall looseness of the default tolerances.",
    NA_character_,

    "stress-sens-tolerance-solver", "simulation", "F012", FALSE,
    "In rxode2, how are atolSens and rtolSens applied during a sensitivity solve, and is there any situation in which setting them has no effect?",
    "Explains that sensitivity equations are extra states in one augmented ODE system, and atolSens/rtolSens are not a separate mechanism: they are written into the per-compartment tolerance vectors (the sensitivity states' slice of atol/rtol). So they only take effect with a solver that honours per-compartment (vector) tolerances; a solver that reads only one scalar tolerance uses the state tolerance and silently ignores them. Recommends verifying the effect (e.g. the objective changes when they are tightened) rather than assuming it.",
    NA_character_,

    "stress-method-tolerances", "estimation", "F011", FALSE,
    "I fitted the same ODE model with est = \"saem\" and with est = \"focei\" in nlmixr2, both with default controls. Are the two fits solving the ODEs to the same accuracy?",
    "No. The default solver tolerances differ by method: foceiControl() uses sigdig = 3, which scales rxode2 to rtol 1e-3 / atol 1e-6, while saemControl() leaves rxode2's own defaults (rtol 1e-6 / atol 1e-8). Differences between the fits can therefore partly come from solve accuracy; set the tolerances explicitly and identically (through rxControl, or sigdig) when comparing.",
    NA_character_,

    "stress-pinned-objective", "interop", "F007", FALSE,
    "I evaluated my model in nlmixr2 and in NONMEM ($ESTIMATION MAXEVAL=0) at the same fixed population parameters, and the objective functions differ slightly. Does that mean nlmixr2's likelihood is computed differently?",
    "Not necessarily. MAXEVAL=0 fixes the population parameters but NONMEM still estimates the etas, so the comparison includes each engine's inner (eta) optimizer and its tolerance, and their defaults differ (nlmixr2's innerOpt default and tolerances are not NONMEM's MAP settings, and the tolerance criteria are of different kinds). Also check the objective convention: totals can differ by a constant nObs*log(2*pi). Record the inner-optimizer settings and the convention before attributing a difference to the likelihood.",
    NA_character_,

    "stress-eta-se", "estimation", "F003", FALSE,
    "How do I get standard errors for each subject's eta from an nlmixr2 fit, and what uncertainty do they include?",
    "Uses fit$etaSE, which gives a per-subject standard error for each eta. These are conditional standard errors: they treat the population parameters as known, from the curvature of the individual objective at the mode (the same quantity as sqrt(ETC(i,i)) in NONMEM's .phi). They do not include uncertainty in the population parameters; that needs something like a bootstrap or simulation from the parameter covariance. Claiming they include population-parameter uncertainty is incorrect.",
    NA_character_,

    "stress-sim-truth", "simulation", "F008", FALSE,
    "I simulated 120 subjects once from known parameters (omega variance 0.09), refitted the model with nlmixr2, and the estimated omega is 20% above 0.09. Is the estimator biased?",
    "Cannot conclude that from one draw. With a single fixed sample of 120 subjects, the target for bias is the realised draw: the empirical variance of the etas actually simulated, which can differ from 0.09 by about that much. Score bias against the realised values, and judge standard-error coverage against the generating values, ideally over many simulated replicates.",
    NA_character_,

    "stress-ofv-not-params", "estimation", "F011", FALSE,
    "Two numerically different solves of the same nlmixr2 model on the same data gave estimates of the inter-compartmental clearance Q that differ by 12%, while the objective functions differ by less than 1 unit. Which solve is wrong?",
    "The parameter difference alone does not show that either is wrong. On many designs Q is weakly identified and the objective is nearly flat along it, so Q can move several percent with negligible change in fit. Compare objective functions (and parameter uncertainty or a likelihood profile), not the point estimate of a weakly identified parameter, before concluding that a solver or setting is at fault.",
    NA_character_,

    "stress-cf-vs-ode-timing", "estimation", "T031", FALSE,
    "My linCmt() model fits much faster than the identical ODE model in nlmixr2. Does that measure how much faster the closed-form solver is?",
    "No, not by itself. The two paths obtain FOCEi gradients differently: linCmt() uses automatic differentiation, while the ODE path integrates forward sensitivity equations. A wall-time ratio therefore compares gradient strategies as well as solvers. It also depends on the solve tolerances.",
    NA_character_,

    "stress-bioavailability-infusion", "simulation", "T004", FALSE,
    "In rxode2, I set f(central) <- 0.5 on an infusion. Does bioavailability shorten the infusion or slow it down?",
    "It depends on the infusion encoding. With a modelled duration (dur(central), rate = -2 in the data), F scales the rate and the duration is kept: half the amount over the same time. With a modelled rate (rate(central), rate = -1), the rate is kept and the duration shrinks: half the amount delivered in half the time. Check the solved profile when translating between encodings.",
    NA_character_,

    "stress-transit-params", "interop", "T008", FALSE,
    "How do I translate a Monolix transit-compartment absorption model, parameterised with Mtt and Ktr, into nlmixr2?",
    "Uses nlmixr2/rxode2's transit() (Savic's model), which takes the number of transit compartments n and the mean transit time directly, and maps the Monolix parameters with n = Mtt*Ktr - 1 (Ktr = (n + 1)/Mtt). Notes that a faithful translation therefore has a different parameter vector, so it should be verified by comparing solved profiles, not parameter values.",
    NA_character_,

    "stress-babelmixr2-method", "interop", "F001/T012", FALSE,
    "I ran an nlmixr2 model in NONMEM through babelmixr2 with nonmemControl(est = \"its\"). How do I confirm which estimation method NONMEM actually ran?",
    "Reads it from the run itself, not from the label nlmixr2 puts on the fit: the $ESTIMATION record babelmixr2 wrote into the control stream, and the method NONMEM reports in its listing (#METH). Older babelmixr2 versions mapped \"its\" to METHOD=IMP while labelling the fit \"nonmem its\" (babelmixr2#211, since fixed), which is why the check matters.",
    NA_character_,

    "stress-monolix-error-eta", "interop", "T005", FALSE,
    "My nlmixr2 model has between-subject variability on the residual error (add.sd * exp(eta.sd)). Can I run it in Monolix with babelmixr2?",
    "Not as written: Monolix's residual error model can depend only on the structural prediction, so a residual error term with an eta (or a covariate) has no Monolix equivalent. The right response is to refuse or reformulate, not to drop the eta, because a silently population-only error model is a different model.",
    NA_character_,

    "stress-fixed-grid-quadrature", "estimation", "F013", FALSE,
    "Does nlmixr2 have fixed-grid quadrature like NONMEM's $ESTIMATION METHOD=STIELTJES (a grid that is not re-centred for each subject)?",
    "No. nlmixr2's \"agq\" is adaptive Gauss-Hermite quadrature, re-centred and scaled at each subject's mode, and laplace is the one-node case; a fixed, non-re-centred grid is not available (it is an open feature request, nlmixr2est#1139). Suggests agq or laplace, or importance sampling (impmap), as the available alternatives. Claiming nlmixr2 has STIELTJES or that agq is a fixed grid is incorrect.",
    NA_character_
  )
}
