##Shannon entropy as proposed in https://github.com/cellgeni/batchbench/blob/master/bin/R_entropy.R

suppressPackageStartupMessages({
    library(future.apply)
    library(scran)
    library(RANN)
})
args  <- commandArgs(trailingOnly=T)
infile=args[1]
#infile=snakemake@input[[1]] #GEJ_QCed_*_walktrap_clustered.rds
sce <- readRDS(file=infile)
df <- as.data.frame(colData(sce))
df <- df[, colnames(df)=='orig.ident' | grepl("^snn", colnames(df)) | grepl("_res.", colnames(df))]
colnames(df) <- gsub("^snn","walktrap_snn",colnames(df))     
df$orig.ident=sapply(strsplit(df$orig.ident,"-"),"[",1)
nbatches <- length(unique(df$orig.ident))

nworker=min(as.numeric(args[2]),length(availableWorkers()))
print(paste0("Use ",nworker, " workers"))
plan("multiprocess", workers = nworker)
options(future.globals.maxSize = 60*1024^3)

# entropy function
shannon_entropy <- function(x, batch_vector, N_batches) {
  x = x[-1]
  freq_batch = table(batch_vector[x])/length(batch_vector[x])
  freq_batch_positive = freq_batch[freq_batch > 0]
  return(-sum(freq_batch_positive * log(freq_batch_positive))/log(N_batches))
}


for(r in reducedDimNames(sce)){
    outfile <- gsub("walktrap_clustered",paste0(r, "_knnEntropy"),infile)
    if(!file.exists(outfile)){
        rd <- reducedDim(sce, type=r)
	knn <- RANN::nn2(rd,k = 31)$nn.idx
	batch_entropy <- future_apply(knn, 1, future.seed=1129, FUN = function(x) {shannon_entropy (x, df$orig.ident, nbatches)})
	#names(batch_entropy)=rownames(df)
	res <- data.frame(BasedOn='all_cell',median=median(batch_entropy),min=min(batch_entropy),max=max(batch_entropy))
	for(i in which(grepl("snn", colnames(df)) | grepl("_res.", colnames(df)))){
                clust_res <- df[,i]
                #names(clust_res) = rownames(df)
                clust_entropy_median <- NULL
		clust_entropy_min <- NULL
		clust_entropy_max <- NULL
                for(c in unique(clust_res)){
                    clust_entropy <- batch_entropy[which(clust_res==c)]
                    clust_entropy_median <- c(clust_entropy_median, median(clust_entropy))
		    clust_entropy_min <- c(clust_entropy_min, min(clust_entropy))
		    clust_entropy_max <- c(clust_entropy_max, max(clust_entropy))
                }
                res <- rbind(res, data.frame(BasedOn=colnames(df)[i],median=median(clust_entropy_median),min=median(clust_entropy_min),
			max=median(clust_entropy_max)))
	}
        saveRDS(res, file=outfile)
    }else{
        print(paste0("Already done: ", basename(outfile)))
    }
}

options(future.globals.maxSize = 500*1024^2) #500M
plan(sequential)