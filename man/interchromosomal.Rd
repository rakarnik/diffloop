% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/loopFunctions.R
\docType{methods}
\name{interchromosomal}
\alias{interchromosomal}
\alias{interchromosomal,loops-method}
\title{Loops between chromosomes}
\usage{
interchromosomal(dlo)

\S4method{interchromosomal}{loops}(dlo)
}
\arguments{
\item{dlo}{A loops object}
}
\value{
A loops object with all loops on different chromosomes
}
\description{
\code{interchromosomal} restricts loops to those where anchors are observed
on different chromosomes
}
\details{
This function subsets the \code{loops} object into only those loops that
have anchors on different chromosomes
}
\examples{
rda<-paste(system.file('rda',package='diffloop'),'loops.small.rda',sep='/')
load(rda)

# Compute number of interactions on same chromosome
dim(intrachromosomal(loops.small))
samechromo <- intrachromosomal(loops.small)

# Compute number of interactions on same chromosome
# dim(interchromosomal(loops.small))
# This will throw and error since the toy only has intrachromosomal loops

}

