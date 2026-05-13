### Mapping reef indicators for MAR
### by Jade Delevaux 03/17/2020
### by Jade Delevaux 10/10/2024

##### Load required libraries ######
require(dismo)
require(parallel)
require(geosphere)
require(ape)
require(plyr)
require(reshape2)
require(foreign)
require(gstat)
require(stats)
require(ipred)
require(MASS)
require(raster)
require(rgdal)
require(gbm)
require(sp)
require(sf)
require(ggplot2)
require(cowplot)

####Function to apply data transformation  ##### 
#Options include logarithm, square root, and fourth root
Transform.Data <- function(d, transformation) {
  if (transformation == "log") {
    d_transformed <- exp(d + 1)
  } else if (transformation == "square.root") {
    d_transformed <- sqrt(d)
  } else if (transformation == "fourth.root") {
    d_transformed <- d^(1/4)    
  }
}

#### Function to fit optimal BRT model #####
# with optimal number of boosting trees for a given set of model tuning parameters
Fit.BRT.Model <- function(i) {
  library(dismo)
  gbm.step(data=data,
           gbm.x = which(names(data) %in% predictor_set),
           gbm.y = grep(response_var_transformed,names(data)),
           tree.complexity=tuning_parameters[i,3],
           learning.rate=tuning_parameters[i,1],
           bag.fraction=tuning_parameters[i,2],
           n.folds=10,
           family="gaussian",
           plot.main=FALSE)
}


#### Function to fit BRT model with fixed number of boosting trees #####
# for a given set of model tuning parameters using a bootstrap sample of the calibration data
Fit.BRT.Model.Fixed.Bootstrap <- function(i) {
  library(dismo)
  gbm.fixed(data=calib_data[bootstrap_samples[[i]],],
            gbm.x = final_vars_ix,
            gbm.y = grep(response_var_transformed,names(calib_data)),
            tree.complexity=gbm_model_simp$gbm.call$tree.complexity,
            learning.rate=gbm_model_simp$gbm.call$learning.rate,
            bag.fraction=gbm_model_simp$gbm.call$bag.fraction,
            family="gaussian",
            n.trees=gbm_model_simp$gbm.call$best.trees)
}


##### Function to back-transform data ######
Back.Transform.Data <- function(d, transformation) {
  if (transformation == "log") {
    exp(d)-1
  } else if (transformation == "square.root") {
    d^2
  } else if (transformation == "fourth.root") {
    d^4
  }
}


#####Function to generate a spatial (raster) prediction ####
Spatial.Prediction <- function(i) {
  library(gbm)
  library(raster)
  gbm_model <- gbm_model_final[[i]]
  predict(raster_stack, 
          gbm_model, 
          n.trees=gbm_model$gbm.call$best.trees, 
          progress="text")
}

#####Function to back-transform a spatial (raster) prediction #####
Back.Transform.Prediction <- function(i) {
  library(raster)
  raster_prediction
  if (transformation == "log") {
    exp(raster_prediction)-1
  } else if (transformation == "square.root") {
    raster_prediction^2
  } else if (transformation == "fourth.root") {
    raster_prediction^4
  }
}


#### 1/ Set variables ####
reef <- "benthic"
model <- "3"
response_var <- "cor"  	#response variable attribute field name
output_name <- "cor"	#generic name of response variable for use in output file names
transformation <- "square.root" #options include "log", "square.root", and "fourth.root"
num_bootstraps <- 100      #number of bootstrap samples to use to generate spatial predictions
training_holdout <- 30   #percentage of data to be withheld for model validation
nCPUs <- detectCores()-1		#detect number of processing cores for parallel processing; can instead manually choose number
set.seed(28)

## set working directory
setwd("G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_Belize/2_model_inputs_belize/coral_reef_modeling")

##### 2/ Import data #####
predictor_set <- as.vector(read.csv(file.path("01_input_csv", paste("0_predictors_benthic.csv",sep="")), header=FALSE)[,1])
predictor_set

# Import data frame with coordinates, response variables, and extracted environmental predictor values (all variables)
data <- read.csv(file.path("01_input_csv", "bz_data_model.csv"))
# data$cor<- as.numeric(data$cor)

#### 3/ Build database ####
# Remove data surveys for which the response variable is NA
data <- data[which(!is.na(data[,response_var])),]
# Apply transformation to response variable and store as new variable in data frame
response_var_transformed <- paste(transformation,".",response_var,sep="")
data[[response_var_transformed]] <- Transform.Data(data[[response_var]], transformation) 
# Subset data to include only the coordinates, the response variable, 
# and the extracted values of the potential environment predictors for the 
# specified island group 
data <- data[,c("x", "y", response_var, response_var_transformed, predictor_set)]
hist(data$square.root.cor)
write.csv(data, file.path("01_input_csv", paste(model, output_name,"data.csv",sep="_")))

# # Create model calibration and model validation subsets by randomly selecting specified percentages of rows in "data"
# calib_ix <- sample(seq(1,nrow(data)), ((100-training_holdout)/100)*nrow(data))
# calib_data <- data[calib_ix,]
# valid_data <- data[-calib_ix,]
# # Write calibration and validation data to .csv files
# write.csv(calib_data, file.path("Input_CSVs", paste("_",output_name,"_cal.csv",sep="")))
# write.csv(valid_data, file.path("Input_CSVs", paste("_",output_name,"_val.csv",sep="")))


##### 4/ Model tuning #####
# Cross-validation optimization of boosted regression tree model tuning parameters
# Create lists of model tuning parameter options
lr <- c(0.01,0.001,0.005) 	#list of options for learning rate
bag <- c(0.5,0.75) 		#list of options for bag fraction
tc <- c(2,3,4,5,10) 		#list of options for tree complexity
# Create a data frame of all possible combinations of tuning parameters
tuning_parameters <- expand.grid(lr,bag,tc)	
names(tuning_parameters) <- c("learning.rate","bag.fraction","tree.complexity")
# Create a data frame to store boosted regression tree model statistics
model_tuning_outputs <- data.frame(mean.total.dev=rep(NA,nrow(tuning_parameters)),
                                   mean.resid.dev=rep(NA,nrow(tuning_parameters)),
                                   cv.mean.dev=rep(NA,nrow(tuning_parameters)),
                                   cv.se.dev=rep(NA,nrow(tuning_parameters)),
                                   perc.dev.expl=rep(NA,nrow(tuning_parameters)))

# Loop through (in parallel) all possible model tuning parameter combinations, each time fitting a 
# boosted regression tree model with the optimal number of boosting trees
# Create directory for model calibration outputs; will give warning if folder already exists
dir.create(file.path("02_calibration"), showWarning=TRUE, recursive=TRUE)
# Create vector to store boosted regression tree models for each combination of model tuning parameters
gbm_models_step <- vector("list", nrow(tuning_parameters))

# Apply the function "Fit.BRT.Model" to each model tuning parameter combination
cl <- makeCluster(nCPUs)
clusterExport(cl, list("response_var_transformed", "predictor_set", "data", "tuning_parameters"))
gbm_models_step <- parLapply(cl, seq(1,nrow(tuning_parameters)), Fit.BRT.Model)
stopCluster(cl)
# For each boosted regression tree model from model parameter tuning, extract statistics
for (i in seq(1,nrow(tuning_parameters))) {
  model_tuning_outputs[i,1] <- gbm_models_step[[i]]$self.statistics$mean.null				# mean total deviance
  model_tuning_outputs[i,2] <- gbm_models_step[[i]]$self.statistics$mean.resid			# mean residual deviance
  model_tuning_outputs[i,3] <- gbm_models_step[[i]]$cv.statistics$deviance.mean			# cross-validation mean residual deviance
  model_tuning_outputs[i,4] <- gbm_models_step[[i]]$cv.statistics$deviance.se				# cross-validation standard error residual deviance
  model_tuning_outputs[i,5] <- ((model_tuning_outputs[i,1] - model_tuning_outputs[i,3])/model_tuning_outputs[i,1])*100 # Calculate percent deviance explained	
}
# Attach model statistics to data frame of tuning parameter options
model_tuning_outputs <- cbind(tuning_parameters, model_tuning_outputs)
# Write model tuning outputs table to csv file
write.csv(model_tuning_outputs, file.path("02_calibration", paste(model, output_name,"brt_tuning_outputs.csv",sep="_")))
# Identify the optimal combination of model tuning parameters by identifying the model with the maximum percent deviance explained
best <- which.max(model_tuning_outputs$perc.dev.expl)
best


##### 5/ Model simplification #####
#Use gbm.simplify to assess potential to drop lowest contributing predictors using k-fold cross validation
## gbm.simplify identifies sequence of variables to remove
# Run gbm.simplify function on cross-validated model with optimal model tuning parameters 
gbm_model_simp <- gbm.simplify(gbm_models_step[[best]], n.folds=10, n.drops=12, alpha=1)

# Create a plot (pdf) to store plot of change in predictive deviance as variables are dropped
pdf(file.path("02_calibration", paste(model, output_name,"brt_simplification.pdf",sep="_")))
plot(0:length(gbm_model_simp$deviance.summary$mean), 
     c(0,gbm_model_simp$deviance.summary$mean), 
     type="l", 
     xlab="# of predictors dropped", 
     ylab="Change in predictive deviance", 
     xaxt="n", 
     ylim=c(min(gbm_model_simp$deviance.summary$mean - 1.96*gbm_model_simp$deviance.summary$se),
            max(gbm_model_simp$deviance.summary$mean + 1.96*gbm_model_simp$deviance.summary$se)
            )
     )
axis(1, at=seq(0,length(gbm_model_simp$deviance.summary$mean),2))
lines(0:length(gbm_model_simp$deviance.summary$mean), c(0,gbm_model_simp$deviance.summary$mean - 1.96*gbm_model_simp$deviance.summary$se), lty=2)
lines(0:length(gbm_model_simp$deviance.summary$mean), c(0,gbm_model_simp$deviance.summary$mean + 1.96*gbm_model_simp$deviance.summary$se), lty=2)
abline(h=0, col="green", lty=2)
abline(h=gbm_models_step[[best]]$cv.statistics$deviance.se, col="green", lty=2)
if (length(which(apply(gbm_model_simp$deviance.matrix, 1, mean) < 0)) > 0) {
  abline(v=max(which(apply(gbm_model_simp$deviance.matrix, 1, mean) < 0)), col="red", lty=2)
} else {
  abline(v=0, col="red", lty=2)
}
dev.off()

# Identify number of predictors to drop (number that can be dropped without reduction in predictive deviance)
if (length(which(apply(gbm_model_simp$deviance.matrix, 1, mean) < 0)) > 0) {
  num_predictors_dropped <- max(which(apply(gbm_model_simp$deviance.matrix, 1, mean) < 0))
} else {
  num_predictors_dropped <- 0
}

# Create list of indices of predictors remaining after model simplification
if (num_predictors_dropped > 0) {
  final_vars_ix <- gbm_model_simp$pred.list[[7]] # manually input the number of variables dropped
} else {
  final_vars_ix <- which(names(data) %in% predictor_set)
}
# Create list of the names of the predictors remaining after model simplification
final_vars <- names(data[,final_vars_ix])
final_vars

##### 6/ Fit final model #####
gbm_model_final <- gbm.step(data=data,
                            gbm.x = final_vars_ix,
                            gbm.y = grep(response_var_transformed,names(data)),
                            tree.complexity=gbm_model_simp$gbm.call$tree.complexity,
                            learning.rate=gbm_model_simp$gbm.call$learning.rate,
                            bag.fraction=gbm_model_simp$gbm.call$bag.fraction,
                            family="gaussian")
Model_summary_plot <- summary(gbm_model_final, xlim=c(0,100))
summary(gbm_model_final)
percent_deviance_explained_train <- ((gbm_model_final$self.statistics$mean.null-gbm_model_final$self.statistics$mean.resid)/gbm_model_final$self.statistics$mean.null)*100
percent_deviance_explained_train 
mean_percent_deviance_explained_cv <- ((gbm_model_final$self.statistics$mean.null-gbm_model_final$cv.statistics$deviance.mean)/gbm_model_final$self.statistics$mean.null)*100
mean_percent_deviance_explained_cv

###### 7/ Partial plots ######
# NOTE: gbm.plot original codes from Elith et al. 2008 were modified accordingly replaced the function: windows() for the Windows platform with quartz() for COR (use X11() if operating w Unix)
# Additional arguments to this function allow for making a smoothed representation of the plot, allowing different vertical scales for each variable, omitting (and formatting) the rugs, and plotting a single variable. 
# Depending on the distribution of observations within the environmental space, fitted functions can give a misleading indication about the distribution of the fitted values in relation to each predictor. 
# The function gbm.plot.fits has been provided to plot the fitted values in relation to each of the predictors used in the model. 
# This has options that allow for the plotting of all fitted values or of fitted values only for positive observations, or the plotting of fitted values in factor type graphs that are much quicker to print.
# Values above each graph indicate the weighted mean of fitted values in relation to each non-factor predictor.
# NOTE: gbm.plot original codes from Elith et al. 2008 were modified accordingly
# fix(gbm.plot)
# fix(gbm.plot.fits)

pdf(file.path("04_partial_dependence_plots", paste(model, output_name,"response_curve.pdf",sep="_")))
par(mfrow=c(4,4))
gbm.plot(gbm_model_final, n.plots=16, write.title = T, cex.axis=1, cex.lab=1.2)
dev.off()

# replaced the function: windows() for the Windows platform with quartz() for COR (use X11() if operating w Unix)
# par(mfrow=c(1,1))

##### 8/ Check interactions ##### 
# This code assesses the extent to which pairwise interactions exist in the data.
#find.int <- gbm.interactions(gbm_model_final)
# The reCORned object: test.int, is a list. 
# The first 2 components summarise the results:
# 1. as a ranked list of the 5 most important pairwise interactions, & 
# 2. tabulating all pairwise interactions. 
# The variable index numbers in $rank.list can be used for plotting
#find.int


##### 9/ Check final model residuals for spatial autocorrelation #####
# Create data frame to store the coordinates of the calibration data surveys and the model residual values         vector to store p values for each calculation of Moran's I
model_residuals <- data.frame(data$x, data$y, gbm_model_final$residuals)
names(model_residuals) <- c("x","y","Resid")
# Calculate a distance matrix containing the distances between each pair of survey data locations	
pt_dists <- as.matrix(dist(cbind(model_residuals$x, model_residuals$y)))
# Convert distance matrix to an inverse distance matrix	
pt_dists_inv <- 1 / pt_dists
# For coincident survey data locations, convert inverse distance from Inf to Zero (otherwise, calculation of Moran's I will fail)
pt_dists_inv[is.infinite(pt_dists_inv)] <- 0
# Calculate Moran's I autocorrelation coefficent of the model residuals using the inverse distance matrix of weights; report p-value
## if p-value suggests that observed value of I is significantly different from the expected value, then the residuals are autocorrelated
Morans_I_test <- Moran.I(model_residuals$Resid, pt_dists_inv)$p.value
Morans_I_test

##### 10/ Model validation #####
# Calculate the percent deviance explained by the final model (full set of calibration data rather than from cross validation)
## (not to be used to evaluate model, just to demonstrate overfitting) ##
percent_deviance_explained_train <- ((gbm_model_final$self.statistics$mean.null-gbm_model_final$self.statistics$mean.resid)/gbm_model_final$self.statistics$mean.null)*100

# Calculate the mean and standard error percent deviance explained by the final cross validated model
mean_percent_deviance_explained_cv <- ((gbm_model_final$self.statistics$mean.null-gbm_model_final$cv.statistics$deviance.mean)/gbm_model_final$self.statistics$mean.null)*100
percent_deviance_explained_cv_upper <- ((gbm_model_final$self.statistics$mean.null-(gbm_model_final$cv.statistics$deviance.mean-gbm_model_final$cv.statistics$deviance.se))/gbm_model_final$self.statistics$mean.null)*100
percent_deviance_explained_cv_lower <- ((gbm_model_final$self.statistics$mean.null-(gbm_model_final$cv.statistics$deviance.mean+gbm_model_final$cv.statistics$deviance.se))/gbm_model_final$self.statistics$mean.null)*100
se_percent_deviance_explained_cv <- (percent_deviance_explained_cv_upper-percent_deviance_explained_cv_lower)/2

##### 11/ Summarize model outputs#####			
model_summary <- c(output_name, response_var, transformation, 
                   gbm_model_final$gbm.call$tree.complexity, gbm_model_final$gbm.call$learning.rate, 
                   gbm_model_final$gbm.call$bag.fraction, gbm_model_final$gbm.call$best.trees,
                   percent_deviance_explained_train,mean_percent_deviance_explained_cv, 
                   se_percent_deviance_explained_cv) 

# mean_percent_deviance_explained_cv, se_percent_deviance_explained_cv,
# percent_deviance_explained_test, bias, MAE, RMSE)

model_summary_names <- c("Model name", "Response variable", "Data transformation", "Tree complexity", "Learning rate", "Bag fraction", "Number of trees",
                         "Training PDE", "Cross-Validation Mean PDE", "Cross-validation SE PDE")

model_summary_df <- data.frame(model.summary.names=model_summary_names, model_summary=model_summary)
write.table(model_summary_df, file.path("03_model_summaries", paste(model, output_name,"brt_summary.csv",sep="_")), row.names=FALSE, col.names=FALSE, sep=",")

# save workspace
save(list=ls(all.names=TRUE), file=file.path("00_R_workspaces", paste(model, output_name,"brt_workspace.RData", sep="_")))


##### 12/ Create spatial prediction - s0_clim0 #####
# set the variables
folder <- "06_spatial_predictions"
#subfolder <- "06_spatial_predictions"
scenario <- "s3"

#Create raster stack of final set of environmental predictors
# Create a list of all the predictor geotiff files for the island
raster_list <- list.files(file.path("05_Preparation_spatial_predictors/10m"), pattern="tif$")
raster_list
# rename the TSS value to the file name
final_vars
# final_vars[3] <- "tss"
# final_vars
# Subset raster list to include only the predictors in the simplified predictor set
raster_list <- raster_list[match(paste(final_vars,".tif",sep=""), raster_list)]
raster_list
# Create raster stack of RasterLayer objects from geotiffs of the simplified predictor set
raster_stack <- stack(file.path("05_Preparation_spatial_predictors/10m", raster_list))
# rename
names(raster_stack)[which(names(raster_stack) == "Band_1.1")] <- "asp_cos"
names(raster_stack)[which(names(raster_stack) == "Band_1.2")] <- "slope_240"

# rename TSS to the model name
# names(raster_stack)[3] <- 'tss'
# names(raster_stack)
# set the final var list back to original
# final_vars[3] <- "tss"
# final_vars
# Predict to raster
raster_prediction <- predict(raster_stack, gbm_model_final, n.trees=gbm_model_final$gbm.call$best.trees, progress="text")
# back transform raster
raster_prediction_backtransformed <-  Back.Transform.Prediction(raster_prediction)
# Export to geotiff
writeRaster(raster_prediction_backtransformed, 
            filename=file.path("coral_cover/06_spatial_predictions", 
                               paste(scenario, response_var,sep="_")), 
            format="GTiff", overwrite=TRUE)

writeRaster(raster_prediction_backtransformed, 
            filename=file.path("coral_cover/07_validation", 
                               paste(scenario, response_var, sep="_")), 
            format="GTiff", overwrite=TRUE)

writeRaster(raster_prediction_backtransformed, 
            filename=file.path("predictors", 
                               paste(scenario, response_var, sep="_")), 
            format="GTiff", overwrite=TRUE)


###### correct coral cover to smooth the relationship ####
bz_coral_aoi_30m <- raster("05_Preparation_spatial_predictors/bz_coral_aoi_30m.tif") # julian line
s3_cor <- raster("coral_cover/07_validation/s3_cor.tif") # julian line
bz_coral_aoi_30m_resampled <- resample(bz_coral_aoi_30m, s3_cor, method = "bilinear") 


s3_cor_dlt <- s3_cor - bz_coral_aoi_30m_resampled # julian line

# conditional statement
s3_cor_e <- s3_cor

s3_cor_e[] = ifelse(s3_cor_dlt[]<0, bz_coral_aoi_30m_resampled[], s3_cor[])

# check
s3_cor_dlt <- s3_cor_e-bz_coral_aoi_30m_resampled

plot(s3_cor_dlt)
#writeRaster(s4a_clim0_cor_e, filename=file.path("coral_cover", folder, subfolder, paste(scenario, response_var,sep="_")), format="GTiff", overwrite=TRUE) # jade line
writeRaster(s3_cor_e, filename=file.path("coral_cover", folder, paste(scenario, response_var,sep="_e_")), format="GTiff", overwrite=TRUE)

#writeRaster(s4a_clim0_cor_dlt, filename=file.path("09_indicators_delta/2022", paste("cor_s4a_clim0_bgh_mes_max_cor_delta.tif")), format="GTiff", overwrite=TRUE)
writeRaster(s3_cor_dlt, filename=file.path("09_indicators_delta/2025", paste("s3_cor_dlt.tif")), format="GTiff", overwrite=TRUE)


##### 16/ Validate spatial prediction - s0_clim0 #####
### Import function to validate predictions  #####
ggplotRegression <- function (fit) {
  ggplot(fit$model, aes_string(x = names(fit$model)[2], y = names(fit$model)[1])) + 
    geom_point() +
    stat_smooth(method = "lm", col = "red") +
    labs(x = "Observed", y = "Predicted",
         title = paste(response_var_name, "R2 = ",signif(summary(fit)$r.squared, 2),
                       " P =", signif(summary(fit)$coef[2,4], 2))) +
    theme(axis.title.x = element_text(size=10), axis.title.y = element_text(size=10), 
          axis.text.x = element_text(size=10), axis.text.y = element_text(size=10),
          plot.title = element_text(size=10))
}

# import the empirical dataset
point_data <- st_read(file.path("01_input_csv", "shp", "HRI_response_variables_Input.shp"))
names(point_data)
str(point_data)
#point_data <- subset(point_data, select = -c(6:16))

# Extract multi-values to points
pred_data <- raster::extract(raster_prediction_backtransformed, point_data, method='bilinear', df=TRUE)
names(pred_data)[2] <- "cor_p"

# add the UID
point_data$uid <- as.integer(rownames(point_data))
pred_data$uid <- point_data$uid

# merge w empirical values
data_valid <- merge(point_data, pred_data, by='uid')

# transform the observed values
data_valid$tCORALavg_ <- as.numeric(data_valid$tCORALavg_)
data_valid$cor_t =sqrt(data_valid$tCORALavg_)
data_valid$cor_pt =sqrt(data_valid$cor_p)

# check distribution
hist(data_valid$tCORALavg_)
hist(data_valid$cor_t)
hist(data_valid$cor_p)
hist(data_valid$cor_pt)

# fit the regression
response_var_name <- "Coral"
fit_cor <- lm(cor_p ~ tCORALavg_, data = data_valid)
plot <- ggplotRegression (fit_cor)
plot

# Print Figure 
pdf(file.path('07_validation/cor_valid.pdf'),
    width = 7, height = 7)
plot_grid(plot, 
          labels=c("A"), label_size = 10, 
          ncol = 1, nrow = 1)
dev.off()

# ######## OLD SCRIPT ########
# 
# ## AUC 
# # Observed values from the validation set
# data_valid
# head(data_valid)
# # Predicted values from the validation set
# predValues_test
# head(predValues_test)
# 
# ### Observations tercile break
# obs_cat <- data.frame(observations=data_valid)
# hist(observations)
# summary(observations)
# quantile(data_valid$cor,c(0.3333,.66666,1))
# data_valid$cat <- rep(NA,length(data_valid$cor))
# data_valid$cat[data_valid$cor <= quantile(data_valid$cor,c(0.66666))] <- "med"
# data_valid$cat[data_valid$cor <= quantile(data_valid$cor,c(0.33333))] <- "low"
# data_valid$cat[data_valid$cor >= quantile(data_valid$cor,c(0.66666))] <- "high"
# unique(data_valid$cat)
# data_valid$low <- ifelse(data_valid$cor=="low",1,0)
# data_valid$med <- ifelse(data_valid$cor=="med",1,0)
# data_valid$high <- ifelse(data_valid$cor=="high",1,0)
# 
# ## Predictions tercile break
# hist(predValues_test)
# summary(predValues_test) 
# pred_cat <- data.frame(predictions=predValues_test)
# pred_cat$cat <- rep(NA,length(pred_cat$predictions))
# pred_cat$cat[pred_cat$predictions <= quantile(data_valid$observations,c(0.66666))] <- "med"
# pred_cat$cat[pred_cat$predictions <= quantile(data_valid$observations,c(0.33333))] <- "low"
# pred_cat$cat[pred_cat$predictions >= quantile(data_valid$observations,c(0.66666))] <- "high"
# unique(pred_cat$cat)
# pred_cat$low <- ifelse(pred_cat$cat=="low",1,0)
# pred_cat$med <- ifelse(pred_cat$cat=="med",1,0)
# pred_cat$high <- ifelse(pred_cat$cat=="high",1,0)
# 
# #### Assessment metrics values ####
# # AUC values
# low <- auc(obs_cat$low, pred_cat$low)
# med <- auc(obs_cat$med, pred_cat$med)
# hig <- auc(obs_cat$high, pred_cat$high)
# # R2
# R2_low <- cor.test(obs_cat$low, pred_cat$low)
# R2_med <- cor.test(obs_cat$med, pred_cat$med)
# R2_hig <- cor.test(obs_cat$high, pred_cat$high)
# 
# # clear working environment
# rm(list = ls(all.names=TRUE))
# 
