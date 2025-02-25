#' @title Fitting Multivariate Covariance Generalized Linear Models
#' @author Wagner Hugo Bonat, \email{wbonat@@ufpr.br}
#'
#' @description The function \code{mcglm} is used to fit multivariate
#'     covariance generalized linear models.
#'     The models are specified by a set of lists giving a symbolic
#'     description of the linear and matrix linear predictors.
#'     The user can choose between a list of link, variance and covariance
#'     functions. The models are fitted using an estimating function
#'     approach, combining quasi-score functions for regression
#'     parameters and Pearson estimating function for covariance
#'     parameters. For details see Bonat and Jorgensen (2016).
#'
#' @param linear_pred a list of formula see \code{\link[stats]{formula}}
#'     for details.
#' @param matrix_pred a list of known matrices to be used on the matrix
#'     linear predictor. For details see
#'     \code{\link[mcglm]{mc_matrix_linear_predictor}}.
#' @param link a list of link functions names. Options are:
#'     \code{"logit"}, \code{"probit"}, \code{"cauchit"}, \code{"cloglog"},
#'     \code{"loglog"}, \code{"identity"}, \code{"log"}, \code{"sqrt"},
#'     \code{"1/mu^2"} and \code{"inverse"}.
#'     See \code{\link{mc_link_function}} for details.
#' @param variance a list of variance functions names.
#'     Options are: \code{"constant"}, \code{"tweedie"},
#'     \code{"poisson_tweedie"}, \code{"binomialP"} and \code{"binomialPQ"}. \cr
#'     See \code{\link{mc_variance_function}} for details.
#' @param covariance a list of covariance link functions names.
#'     Options are: \code{"identity"}, \code{"inverse"} and
#'     exponential-matrix \code{"expm"}.
#' @param offset a list of offset values if any.
#' @param Ntrial a list of number of trials on Bernoulli
#'     experiments. It is useful only for \code{binomialP} and
#'     \code{binomialPQ} variance functions.
#' @param power_fixed a list of logicals indicating if the values of the
#'     power parameter should be estimated or not.
#' @param weights A list of weights for model fitting. Each element of
#' the list should be a vector of weights of size equals the number of
#' observations. Missing observations should be annotated as NA.
#' @param control_initial a list of initial values for the fitting
#'     algorithm. If no values are supplied automatic initial values
#'     will be provided by the function \code{\link{mc_initial_values}}.
#' @param control_algorithm a list of arguments to be passed for the
#'     fitting algorithm. See \code{\link[mcglm]{fit_mcglm}} for
#'     details.
#' @param contrasts extra arguments to passed to
#'     \code{\link[stats]{model.matrix}}.
#' @param data a data frame.
#' @usage mcglm(linear_pred, matrix_pred, link, variance, covariance,
#'        offset, Ntrial, power_fixed, data, control_initial,
#'        contrasts, weights, control_algorithm)
#' @return mcglm returns an object of class 'mcglm'.
#'
#' @seealso \code{fit_mcglm}, \code{mc_link_function} and
#' \code{mc_variance_function}.
#'
#' @source Bonat, W. H. and Jorgensen, B. (2016) Multivariate
#'     covariance generalized linear models.
#'     Journal of Royal Statistical Society - Series C 65:649--675.
#'
#' @source Bonat, W. H. (2018). Multiple Response Variables Regression
#' Models in R: The mcglm Package. Journal of Statistical Software, 84(4):1--30.
#'
#' @export
#' @import Matrix

mcglm <- function(linear_pred, matrix_pred, link, variance, covariance,
                  penalization, penalization_cov, gamma, gamma_cov, offset,
                  Ntrial, power_fixed, data, control_initial = "automatic",
                  contrasts = NULL, weights = NULL, control_algorithm = list()) {
    n_resp <- length(linear_pred)
    linear_pred <- as.list(linear_pred)
    matrix_pred <- as.list(matrix_pred)
    if (missing(penalization)) {
        penalization <- rep("none", n_resp)
    }
    if (missing(gamma)) {
        gamma <- 0
    }
    if (missing(penalization_cov)) {
        penalization_cov <- rep("none", n_resp)
    }
    if (missing(gamma_cov)) {
        gamma_cov <- 0
    }
    if (missing(link)) {
        link <- rep("identity", n_resp)
    }
    if (missing(variance)) {
        variance <- rep("constant", n_resp)
    }
    if (missing(covariance)) {
        covariance <- rep("identity", n_resp)
    }
    if (missing(offset)) {
        offset <- rep(list(NULL), n_resp)
    }
    if (missing(Ntrial)) {
        Ntrial <- rep(list(rep(1, dim(data)[1])), n_resp)
    }
    if (missing(power_fixed)) {
        power_fixed <- rep(TRUE, n_resp)
    }
    if (missing(contrasts)) {
        contrasts <- NULL
    }
    penalization <- as.list(penalization)
    penalization_cov <- as.list(penalization_cov)
    link <- as.list(link)
    variance <- as.list(variance)
    covariance <- as.list(covariance)
    offset <- as.list(offset)
    Ntrial <- as.list(Ntrial)
    power_fixed <- as.list(power_fixed)
    if (class(control_initial) != "list") {
        control_initial <-
            mc_initial_values(linear_pred = linear_pred,
                              matrix_pred = matrix_pred, link = link,
                              variance = variance,
                              covariance = covariance, offset = offset,
                              Ntrial = Ntrial, contrasts = contrasts,
                              data = data)
        cat("Automatic initial values selected.", "\n")
    }
    con <- list(correct = TRUE, max_iter = 20, tol = 1e-04,
                method = "chaser", tuning = 1, verbose = FALSE)
    con[(namc <- names(control_algorithm))] <- control_algorithm
    list_model_frame <- lapply(linear_pred, model.frame, na.action = 'na.pass', data = data)
    if (!is.null(contrasts)) {
        list_X <- list()
        for (i in 1:n_resp) {
            options(na.action='na.pass')
            list_X[[i]] <- model.matrix(linear_pred[[i]],
                                        contrasts = contrasts[[i]])
            options(na.action='na.omit')
        }
    } else {
        options(na.action='na.pass')
        list_X <- lapply(linear_pred, model.matrix, data = data)
        options(na.action='na.omit')
    }
    list_Y <- lapply(list_model_frame, model.response)
    y_vec <- as.numeric(do.call(c, list_Y))
    if(is.null(weights)) {
        C <- rep(1, length(y_vec))
        C[is.na(y_vec)] = 0
        weights = C
        y_vec[is.na(y_vec)] <- 0
    }
    if(!is.null(weights)) {
        y_vec[is.na(y_vec)] <- 0
        if(class(weights) != "list") {weights <- as.list(weights)}
        weights <- as.numeric(do.call(c, weights))
    }
    sparse <- lapply(matrix_pred, function(x) {
        if (class(x) == "dgeMatrix") {
            FALSE
        } else TRUE
    })
    model_fit <- try(fit_mcglm(list_initial = control_initial,
                               list_penalization = penalization,
                               list_penalization_cov = penalization_cov,
                               gamma = gamma,
                               gamma_cov = gamma_cov,
                               list_link = link,
                               list_variance = variance,
                               list_covariance = covariance,
                               list_X = list_X, list_Z = matrix_pred,
                               list_offset = offset,
                               list_Ntrial = Ntrial,
                               list_power_fixed = power_fixed,
                               list_sparse = sparse, y_vec = y_vec,
                               correct = con$correct,
                               max_iter = con$max_iter, tol = con$tol,
                               method = con$method,
                               tuning = con$tuning,
                               verbose = con$verbose,
                               weights = weights))
    if (class(model_fit) != "try-error") {
        model_fit$beta_names <- lapply(list_X, colnames)
        model_fit$power_fixed <- power_fixed
        model_fit$list_initial <- control_initial
        model_fit$n_obs <- dim(data)[1]
        model_fit$penalization <- penalization
        model_fit$penalization_cov <- penalization_cov
        model_fit$link <- link
        model_fit$variance <- variance
        model_fit$covariance <- covariance
        model_fit$linear_pred <- linear_pred
        model_fit$con <- con
        model_fit$observed <- Matrix(y_vec, ncol = length(list_Y),
                                     nrow = dim(data)[1])
        model_fit$list_X <- list_X
        model_fit$matrix_pred <- matrix_pred
        model_fit$Ntrial <- Ntrial
        model_fit$offset <- offset
        model_fit$power_fixed
        model_fit$sparse <- sparse
        model_fit$data <- data
        model_fit$weights <- weights
        class(model_fit) <- "mcglm"
    }
    n_it <- length(na.exclude(model_fit$IterationCovariance[,1]))
    if(con$max_it == n_it) {warning("Maximum iterations number reached. \n", call. = FALSE)}
    return(model_fit)
}
