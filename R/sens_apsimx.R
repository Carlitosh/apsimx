#' @title Sensitivity Analysis for APSIM Next Generation simulation
#' @name sens_apsimx
#' @rdname sens_apsimx
#' @description It is a wrapper for running APSIM-X and evaluating different parameters values
#' @param file file name to be run (the extension .apsimx is optional)
#' @param src.dir directory containing the .apsimx file to be run (defaults to the current directory)
#' @param parm.paths absolute or relative paths of the coefficients to be evaluated. 
#'             It is recommended that you use \code{\link{inspect_apsimx}} for this
#' @param parm.vector.index Index to evaluate a specific element of a parameter vector.  At the moment it is
#' possible to only edit one element at a time. This is because there is a conflict when generating multiple
#' elements in the candidate vector for the same parameter.
#' @param replacement TRUE or FALSE for each parameter. Indicating whether it is part of 
#' the \sQuote{replacement} component. Its length should be equal to the length or \sQuote{parm.paths}.
#' @param grid grid of parameter values for the evaluation. It can be a data.frame.
#' @param summary function name to use to summarize the output to be a sinlge row (default is the mean).
#' @param root root argument for \code{\link{edit_apsimx_replacement}}
#' @param verbose whether to print progress in percent and elapsed time.
#' @param ... additional arguments (none used at the moment).
#' @return object of class \sQuote{sens_apsim}, but really just a list with results from the evaluations.
#' @export
#' @examples 
#' \donttest{
#' ## See the vignette for examples
#' }
#' 

sens_apsimx <- function(file, src.dir = ".", 
                        parm.paths,
                        parm.vector.index,
                        replacement,
                        grid,
                        summary = c("mean", "max", "var", "sd", "none"),
                        root,
                        verbose = TRUE,
                        ...){
  
  if(missing(file))
    stop("file is missing with no default")
  
  .check_apsim_name(file)
  .check_apsim_name(src.dir)
  
  ## This might offer suggestions in case there is a typo in 'file'
  file.names <- dir(path = src.dir, pattern = ".apsimx$", ignore.case = TRUE)
  
  if(length(file.names) == 0){
    stop("There are no .apsimx files in the specified directory to run.")
  }
  
  file <- match.arg(file, file.names)
  
  summary <- match.arg(summary)
  
  if(missing(parm.vector.index)){
    parm.vector.index <- rep(-1, length(parm.paths))
  }else{
    if(length(parm.vector.index) != length(parm.paths))
      stop("parm.vector.index should have length equal to parm.paths") 
    if(!is.numeric(parm.vector.index))
      stop("parm.vector.index should be numeric")
  }
  
  if(missing(replacement)) replacement <- rep(FALSE, length(parm.paths))
  
  ## If root is not present. Need to think more about this...
  if(missing(root)) root <- list("Models.Core.Replacements", NA)
  
  if(missing(grid))
    stop("grid argument is missing")
  
  grid <- as.data.frame(grid)
  
  if(ncol(grid) != length(parm.paths))
      stop("Number of columns in grid should be equal to the number of parameters")
  
  ## Check that the name in the grid appears somewhere in the parameter path
  for(i in seq_along(parm.paths)){
    ippgn <- grepl(names(grid)[i], parm.paths[i], ignore.case = TRUE)
    if(!ippgn){
      cat("Name in grid:", names(grid)[i], "\n")
      cat("parameter name", parm.paths[i], "\n")
      warning("names in grid object do not match parameter path name")  
    }
  }

  col.sim <- NULL
  start <- Sys.time()
  
  for(i in 1:dim(grid)[1]){
    
    ## Need to edit the parameters in the simulation file or replacement
    for(j in seq_along(parm.paths)){
      ## Edit the specific parameters with the corresponding values
      if(parm.vector.index[j] <= 0){
        par.val <- grid[i, j]  
      }else{
        stop("not sure about this yet")
      }
      
      if(replacement[j]){
        pp0 <- strsplit(parm.paths[j], ".", fixed = TRUE)[[1]]
        mpp <- paste0(pp0[-length(pp0)], collapse = ".")
        edit_apsimx_replacement(file = file, 
                                src.dir = src.dir,
                                wrt.dir = src.dir,
                                node.string = mpp,
                                overwrite = TRUE,
                                parm = pp0[length(pp0)],
                                value = par.val,
                                root = root,
                                verbose = FALSE) 
      }else{
        edit_apsimx(file = file, 
                    src.dir = src.dir,
                    wrt.dir = src.dir,
                    node = "Other",
                    parm.path = parm.paths[j],
                    overwrite = TRUE,
                    value = par.val,
                    verbose = FALSE) 
      }
    }
    
    ## Run simulation  
    sim <- try(apsimx(file = file, src.dir = src.dir,
                      silent = TRUE, cleanup = TRUE, value = "report"),
               silent = TRUE)
    
    if(inherits(sim, "try-error") && i == 1){
      stop("Simulation failed for initial parameter combination")
    }
    
    if(inherits(sim, "try-error") && i > 1){
      mat <- matrix(ncol = ncol(sim[,col.class.numeric]))
      sim.sd <- as.data.frame(mat)
      names(sim.sd) <- nms.sim
      col.sim <- rbind(col.sim, sim.sd)
      next
    } 
    
    ## Extract basic information from sim
    col.class.numeric <- which(sapply(sim, class) == "numeric") ## Which columns are numeric
    nms.sim <- names(sim[, col.class.numeric]) ## Names of the columns
    
    if(summary == "mean"){
      sim.s <- colMeans(sim[, col.class.numeric], na.rm = TRUE)
      sim.sd <- as.data.frame(t(sim.s))
    }

    if(summary == "max"){
      sim.s <- apply(sim[, col.class.numeric], 2, max, na.rm = TRUE)
      sim.sd <- as.data.frame(t(sim.s))
    }
    
    if(summary == "var"){
      sim.s <- apply(sim[, col.class.numeric], 2, var, na.rm = TRUE)
      sim.sd <- as.data.frame(t(sim.s))
    }
    
    if(summary == "sd"){
      sim.s <- apply(sim[, col.class.numeric], 2, sd, na.rm = TRUE)
      sim.sd <- as.data.frame(t(sim.s))
    }
    
    if(summary == "none"){
      sim.sd <- sim
    }
    
    col.sim <- rbind(col.sim, sim.sd)
    
    if(verbose){
      nrow.grid <- nrow(grid)
      old.prev.div <- 0
      
      if(nrow.grid <= 10){
        dftm <- difftime(Sys.time(), start)
        cat("Progress:", round((i/nrow.grid) * 100), "%. Time elapsed:", dftm, units(dftm)," \n")  
      }else{
        progress.step <- ifelse(nrow.grid <= 20, 10, 5)
        
        prev.div <- round((i/nrow.grid) * 100) %/% progress.step
        
        if(prev.div > old.prev.div){
          dftm <- difftime(Sys.time(), start)
          cat("Progress:", round((i/nrow(grid)) * 100), "%. Time elapsed:", dftm, units(dftm)," \n")  
          old.prev.div <- prev.div
        } 
      }
    }

  }
  
  cdat <- cbind(grid, col.sim)
  
  ans <- structure(list(grid.sims = cdat, grid = grid, parm.paths = parm.paths), class = "sens_apsim")
 
  return(ans) 
}


#' @rdname sens_apsimx
#' @description Summary computes variance-based sensitivity indexes from an object of class \sQuote{sens_apsim}
#' @param x object of class \sQuote{sens_apsim}
#' @param ... additional arguments (none used at the moment)
#' @param select option for selecting specific variables in the APSIM output
#' @return prints to console
#' @export
#' 
summary.sens_apsim <- function(object, ..., select = "all"){
  
  ## Here I compute sensitivity indexes based on the grid.sims object
  ## There are potentially many variables for which sensitivity analysis is relevant
  nms.resp.var <- setdiff(names(object$grid.sims), names(object$grid))
  
  if(select == "all"){
    select <- nms.resp.var
  }else{
    if(!select %in% nms.resp.var){
      cat("Variables:", nms.resp.var, "\n")
      stop("selected variable(s) not present in simulation object", call. = FALSE)    
    }
      
  } 

  object$grid.sims <- subset(object$grid.sims, select = select)
    
  num.resp.var <- ncol(object$grid.sims) - ncol(object$grid)
  nms.resp.var <- setdiff(names(object$grid.sims), names(object$grid))
  
  for(i in seq_along(nms.resp.var)){
    X <- object$grid
    y <- object$grid.sims[,nms.resp.var[i]]
    if(var(y) == 0) next
    dat <- data.frame(y, as.data.frame(sapply(X, function(x) as.factor(as.character(x)))))
    frml <- paste("y ~", paste(names(X), collapse = "+"))
    fit <- lm(formula = frml, data = dat)
    if(inherits(fit, "try-error")) next
    sfit <- as.matrix(stats::anova(fit))
    cat("Variable:", nms.resp.var[i], "\n")
    pmat <- matrix(ncol = 2, nrow = ncol(X) + 1)
    row.names(pmat) <- row.names(sfit)
    pmat[,1] <- sfit[,2] 
    pmat[,2] <- sfit[,2] / sum(sfit[,2]) * 100
    colnames(pmat) <- c("SS", "SI (%)")
    pmatd <- as.data.frame(pmat)
    pmatd <- pmatd[order(pmatd$SS, decreasing = TRUE),]
    print(knitr::kable(pmatd, digits = 0))
    cat("\n")
  }
  
}
