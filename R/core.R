#' @include data.R
NULL

#' Link the anchors and interactions back together 
#'
#' \code{summary} takes a \code{loops} object and breaks the 
#' loop data structure resulting in a \code{data.frame}. 
#'
#' This function returns a \code{data.frame} where the left and right anchors 
#' are visualized together along with the loop width, individual counts, and
#' any anchor meta-data that has been annotated into the anchors GRanges
#' object as well as any rowData varianble. Finally, the region column
#' contains the coordinates that readily facilitates visualization of loop in 
#' UCSC or DNAlandscapeR by padding the loop by 25kb on either side. 
#'
#' @param object A loops object to be summarized
#'
#' @return A data.frame
#'
#' @examples
#' # Summarizing the first ten loops in \code{loops.small}
#' rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
#' load(rda)
#' summarydf <- summary(loops.small[1:10,])
#' # Summarizing the loops and significance results between naive and primed
#' summarylt <- summary(quickAssoc(loops.small[,1:4])[1:10,])
#' @import plyr

#' @export
setMethod(f = "summary", signature = c("loops"), definition = function(object) {
    dlo <- object
    
    # Grab all the left anchors in order of loop occurence
    leftAnchor2 <- as.data.frame(dlo@anchors[dlo@interactions[, 1]])
    leftAnchor2 <- subset(leftAnchor2, select = -c(width, strand))
    colnames(leftAnchor2) <- paste(colnames(leftAnchor2), "1", sep = "_")
    colnames(leftAnchor2)[1] <- "chr_1"
    
    # Grab all the right anchors in order of loop occurence
    rightAnchor2 <- as.data.frame(dlo@anchors[dlo@interactions[, 2]])
    rightAnchor2 <- subset(rightAnchor2, select = -c(width, strand))
    colnames(rightAnchor2) <- paste(colnames(rightAnchor2), "2", sep = "_")
    colnames(rightAnchor2)[1] <- "chr_2"
    
    # Add the loop features; UCSC coordinates
    df1 <- cbind(leftAnchor2, rightAnchor2, dlo@counts, dlo@rowData)
    reg <- paste0(df1$chr_1,":", as.character(df1$start_1 - 25000), "-", as.character(df1$end_2 + 25000))
    if(all(grepl("chr", df1$chr_1))) { region <- reg 
    } else { region <- paste0("chr", reg) } 
    return(cbind(df1, region))
})

.emptyloopsobject <- function(colData){

}

# Function that removes all anchors not being referenced in
# interactions matrix and updates indices. For internal use
# only.
setGeneric(name = "cleanup", def = function(dlo) standardGeneric("cleanup"))
setMethod(f = "cleanup", signature = c("loops"), definition = function(dlo) {
    
    #Return empty
    if (as.integer(dim(dlo)[2]) == 0) {
        cat("Creating empty loops object")
        dlo <- loops()
        slot(dlo, "anchors", check = TRUE) <- GRanges()
        slot(dlo, "interactions", check = TRUE) <- matrix()
        slot(dlo, "counts", check = TRUE) <- matrix()
        slot(dlo, "colData", check = TRUE) <- dlo@colData
        slot(dlo, "rowData", check = TRUE) <- data.frame()
        return(dlo)
    }
    
    # Grab indicies of anchors being referenced in loops
    idf <- data.frame(dlo@interactions[, 1], dlo@interactions[,2])
    sdf <- stack(idf)
    udf <- sort(unique(sdf[, "values"]))
    
    # Keep only those anchors that are being used
    newAnchors <- dlo@anchors[udf]
    
    # Create mapping from old indices to new indices
    translate <- seq(1,length(udf),1)
    names(translate) <- udf
    
    # Create new matrix
    upints <- matrix(unname(translate[as.character(dlo@interactions)]), ncol = 2)
    colnames(upints) <- c("left", "right")
    #rownames(upints) <- NULL
    
    # Update values
    slot(dlo, "interactions", check = TRUE) <- upints
    slot(dlo, "anchors", check = TRUE) <- newAnchors
    return(dlo)
})

#' Combine nearby anchors into one peak
#'
#' \code{mergeAnchors} combines anchors that are within a user-defined radius
#'
#' This function takes a loops object and combines nearby anchors, up to
#' a distance specified by the \code{mergegap}. This likely will cause self
#' loops to form (loop where the left and right anchor are the same), which
#' can either be removed (by default) or retained with \code{selfloops}
#'
#' @param dlo A loops object whose anchors will be merged
#' @param mergegap An integer value of the bp between anchors to be merged
#' @param selfloops A logical value to either retain (T) or remove (F) 
#' resulting self-loops after merging anchors
#'
#' @return A loops object
#'
#' @examples
#' # Merge anchors within 1kb of each other, keeping self loops 
#' rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
#' load(rda)
#' m1kb <- mergeAnchors(loops.small, 1000, FALSE)
#'
#' # Merge anchors within 1kb of each other, removing self loops by default
#' m1kb_unique <- mergeAnchors(loops.small, 1000)

#' @import GenomicRanges
#' @import reshape2
#' @export
#' 
setGeneric(name = "mergeAnchors", def = function(dlo, mergegap, 
    selfloops = FALSE) standardGeneric("mergeAnchors"))

.mergeAnchors <- function(dlo, mergegap, selfloops) {
    # Join the anchors
    newAnchors <- reduce(dlo@anchors, min.gapwidth = mergegap)
    
    # Create mapping from old indices to new indices
    ov <- findOverlaps(dlo@anchors, newAnchors)
    translate <- ov@to
    names(translate) <- ov@from
    
    # Update interactions indices
    upints <- matrix(unname(translate[as.character(dlo@interactions)]), ncol = 2)
    colnames(upints) <- c("left", "right")
    #rownames(upints) <- NULL
    
    # Link counts and interactions
    df <- data.frame(upints, dlo@counts)
    dnames <- colnames(df)
    dM <- melt(df, id.vars = c("left", "right"))
    updatedLink <- suppressWarnings(dcast(dM, left + right ~ 
        variable, sum))
    intz <- matrix(c(updatedLink$left, updatedLink$right), ncol = 2)
    colnames(intz) <- c("left", "right")
    countz <- data.matrix(updatedLink[, -1:-2])
    
    # Re-initialize new loops with column width
    w <- (start(newAnchors[intz[, 2]]) + end(newAnchors[intz[, 2]]))/2 -
         (start(newAnchors[intz[, 1]]) + end(newAnchors[intz[, 1]]))/2
    w[w < 0] <- 0
    rowData <- as.data.frame(as.integer(w))
    colnames(rowData) <- c("loopWidth")
    
    mergedObject <- loops(anchors = newAnchors, interactions = intz, 
        counts = countz, colData = dlo@colData, rowData = rowData)
    
    if (selfloops) {
        return(mergedObject)
    } else {
        return(subsetLoops(mergedObject,
            mergedObject@interactions[, 1] != mergedObject@interactions[, 2]))
    }
}

#' @rdname mergeAnchors
setMethod(f = "mergeAnchors", signature = c("loops", "numeric", 
    "missing"), definition = function(dlo, mergegap, selfloops) {
    .mergeAnchors(dlo, mergegap, FALSE)
})

#' @rdname mergeAnchors
setMethod(f = "mergeAnchors", signature = c("loops", "numeric", 
    "logical"), definition = function(dlo, mergegap, selfloops) {
    .mergeAnchors(dlo, mergegap, selfloops)
})


#' Extract region from loops object
#'
#' \code{subsetRegion} takes a \code{loops} object and a \code{GRanges}
#' object and returns a \code{loops} object where both anchors map inside
#' the \code{GRanges} coordinates by default. Once can specify where only
#' one anchor is in the region instead.
#'
#' By default, \code{nachors = 2}, meaning both anchors need to be in the 
#' region for the loop to be preserved when extracting. However, by specifying
#' a numeric 1, interactions with either the left or right anchor will be extracted.
#' Loops with both anchors in the region will be excluded (exclusive \code{or}).
#' To get an inclusive \code{or}, take the union of subsetting both with 1 and 2.
#'
#' @param dlo A loops object to be subsetted
#' @param region A GRanges object containing region of interest 
#' @param nanchors Number of anchors to be contained in GRanges object. Default 2
#' 
#' @return A loops object
#'
#' @examples
#' # Grab region chr1:36000000-36100000
#' library(GenomicRanges)
#' regA <- GRanges(c('1'),IRanges(c(36000000),c(36100000)))
#' rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
#' load(rda)
#' # Both anchors in region
#' loops.small.two <- subsetRegion(loops.small, regA)
#' #Only one anchor in region
#' loops.small.one <- subsetRegion(loops.small, regA, 1)
#' #Either one or two anchors in region
#' loops.small.both <- union(loops.small.one, loops.small.two)
#' @import GenomicRanges
#' @importFrom stats na.omit
#' @export
setGeneric(name = "subsetRegion", def = function(dlo, region, 
    nanchors) standardGeneric("subsetRegion"))

#' @rdname subsetRegion
setMethod(f = "subsetRegion", signature = c("loops", "GRanges", 
    "numeric"), definition = function(dlo, region, nanchors) {
    if (nanchors == "1") {
        .subsetRegion1(dlo, region)
    } else if (nanchors == "2") {
        .subsetRegion2(dlo, region)
    } else {
        print("Please specify either 1 or 2 anchors in region")
    }
})

#' @rdname subsetRegion
setMethod(f = "subsetRegion", signature = c("loops", "GRanges", 
    "missing"), definition = function(dlo, region, nanchors) {
    .subsetRegion2(dlo, region)
})

.subsetRegion1 <- function(dlo, region) {
    
    # Keep only those anchors that are being used
    newAnchors <- dlo@anchors[findOverlaps(region, dlo@anchors)@to, ]
    
    # Create mapping from old indices to new indices
    ov <- findOverlaps(dlo@anchors, newAnchors)
    translate <- ov@to
    names(translate) <- ov@from
    
    # Update interactions indices
    upints <- matrix(unname(translate[as.character(dlo@interactions)]), ncol = 2)
    #rownames(upints) <- NULL
    
    keepTheseLoops <- xor(!is.na(upints[,1]), !is.na(upints[,2]))  # only one anchor in region
    keepTheseAnchors <- as.numeric(na.omit(unique(as.vector(dlo@interactions[keepTheseLoops,]))))
    
    new.interactions <- dlo@interactions[keepTheseLoops,]
    new.counts <- dlo@counts[keepTheseLoops,]
    new.rowData <- as.data.frame(dlo@rowData[keepTheseLoops,])
    colnames(new.rowData) <- colnames(dlo@rowData)
    
    # Go back through the motions
    
    # Create mapping from old indices to new indices
    ov <- findOverlaps(dlo@anchors, dlo@anchors[keepTheseAnchors, ])
    translate <- ov@to
    names(translate) <- ov@from
    
    # Update interactions indices
    upints <- matrix(unname(translate[as.character(new.interactions)]), ncol = 2)
    colnames(upints) <- c("left", "right")
    #rownames(upints) <- NULL

    # Format new indices matrix
    cc <- complete.cases(upints)
    newinteractions <- matrix(upints[cc], ncol = 2)
    colnames(newinteractions) <- c("left", "right")
    
    # Subset rowData
    newRowData <- as.data.frame(new.rowData[cc, ])
    colnames(newRowData) <- colnames(dlo@rowData)
    row.names(newRowData) <- NULL
    
    # Grab counts indicies
    newcounts <- matrix(new.counts[cc], ncol = ncol(dlo@counts))
    colnames(newcounts) <- colnames(dlo@counts)
    
    # Update values
    slot(dlo, "anchors", check = TRUE) <- dlo@anchors[keepTheseAnchors, ]
    slot(dlo, "interactions", check = TRUE) <- newinteractions
    slot(dlo, "counts", check = TRUE) <- newcounts
    slot(dlo, "rowData", check = TRUE) <- newRowData
    return(dlo)
}

.subsetRegion2 <- function(dlo, region) {
    
    # Keep only those anchors that are being used
    newAnchors <- dlo@anchors[findOverlaps(region, dlo@anchors)@to, ]
    
    # Create mapping from old indices to new indices
    ov <- findOverlaps(dlo@anchors, newAnchors)
    translate <- ov@to
    names(translate) <- ov@from
    
    # Update interactions indices
    upints <- matrix(unname(translate[as.character(dlo@interactions)]), ncol = 2)
    cc <- complete.cases(upints)
    upints <- matrix(upints[cc,], ncol = 2)
    colnames(upints) <- c("left", "right")

    # Grab counts indicies
    newcounts <- matrix(dlo@counts[cc], ncol = ncol(dlo@counts))
    colnames(newcounts) <- colnames(dlo@counts)
    
    # Subset rowData
    newRowData <- as.data.frame(dlo@rowData[cc, ])
    colnames(newRowData) <- colnames(dlo@rowData)
    row.names(newRowData) <- NULL
    
    # Update values
    slot(dlo, "anchors", check = TRUE) <- newAnchors
    slot(dlo, "interactions", check = TRUE) <- upints
    slot(dlo, "counts", check = TRUE) <- newcounts
    slot(dlo, "rowData", check = TRUE) <- newRowData
    return(dlo)
}


#' Remove region from loops object
#'
#' \code{removeRegion} takes a \code{loops} object and a \code{GRanges}
#' object and returns a \code{loops} object where neither anchors map inside
#' the \code{GRanges} coordinates.
#'
#' @param dlo A loops object to be subsetted
#' @param region A GRanges object containing region of interest 
#' 
#' @return A loops object with no anchors touching the region given
#'
#' @examples
#' # Remove region chr1:36000000-36100000
#' library(GenomicRanges)
#' regA <- GRanges(c('1'),IRanges(c(36000000),c(36100000)))
#' rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
#' load(rda)
#' # Get rid of loop if either anchor touches that region
#' restricted <- removeRegion(loops.small, regA)
#' @import GenomicRanges
#' @importFrom stats na.omit
#' @export
setGeneric(name = "removeRegion", def = function(dlo, region) standardGeneric("removeRegion"))

#' @rdname removeRegion
setMethod(f = "removeRegion", signature = c("loops", "GRanges"), definition = function(dlo, region) {
    # Keep only those anchors that are being used
    newAnchors <- dlo@anchors[setdiff(1:length(dlo@anchors),findOverlaps(region, dlo@anchors)@to) ]
    
    # Create mapping from old indices to new indices
    ov <- findOverlaps(dlo@anchors, newAnchors)
    translate <- ov@to
    names(translate) <- ov@from
    
    # Update interactions indices
    upints <- matrix(unname(translate[as.character(dlo@interactions)]), ncol = 2)
    cc <- complete.cases(upints)
    upints <- matrix(upints[cc,], ncol = 2)
    colnames(upints) <- c("left", "right")

    # Grab counts indicies
    newcounts <- matrix(dlo@counts[cc], ncol = ncol(dlo@counts))
    colnames(newcounts) <- colnames(dlo@counts)
    
    # Subset rowData
    newRowData <- as.data.frame(dlo@rowData[cc, ])
    colnames(newRowData) <- colnames(dlo@rowData)
    row.names(newRowData) <- NULL
    
    # Update values
    slot(dlo, "anchors", check = TRUE) <- newAnchors
    slot(dlo, "interactions", check = TRUE) <- upints
    slot(dlo, "counts", check = TRUE) <- newcounts
    slot(dlo, "rowData", check = TRUE) <- newRowData
    return(dlo)
})

#' Get number of anchors in each sample
#'
#' \code{numAnchors} takes a \code{loops} object and a summarizes the
#' number of anchors that support all the interactions (count >= 1) in the object
#'
#' This function returns a data.frame where the column names specify the
#' sample in the original \code{loops} object and the only row shows
#' the number of anchors used to support that sample
#'
#' @param x A loops object to be summarized
#' 
#' @return A data.frame of each sample and the number of anchors
#'
#' @examples
#' # Show number of anchors each sample is supported by
#' rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
#' load(rda)
#' numAnchors(loops.small)
#' @export
setGeneric(name = "numAnchors", def = function(x) standardGeneric("numAnchors"))

#' @rdname numAnchors
setMethod(f = "numAnchors", signature = c("loops"), definition = function(x) {
    nAnchors <- sapply(1:as.numeric(dim(x)[3]), function(t) {
        length(unique(stack(as.data.frame(x@interactions[x@counts[, 
            t] == "0", ])))$values)
    })
    nAnchors <- as.data.frame(t(nAnchors))
    colnames(nAnchors) <- colnames(x@counts)
    return(nAnchors)
})

