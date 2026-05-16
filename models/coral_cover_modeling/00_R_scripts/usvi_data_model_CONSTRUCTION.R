library(sf)
library(terra)
library(dplyr)

# --- 1. Define Target CRS (WGS84 UTM 20N)
target_crs <- 32620

# --- 2. Leer puntos de coral, renombrar campo, proyectar (importante revisar el nombre!)
coral_pts <- st_read("G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/01_inputs_csv/shp/hard_coral_2025.shp")
coral_pts <- coral_pts %>%
  rename(hard_coral_cover = hard_coral)
if (st_crs(coral_pts)$epsg != target_crs) coral_pts <- st_transform(coral_pts, target_crs)

# --- 3. Cargar predictores raster y asegurarse CRS es correcto
folder_pred <- "G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/05_preparation_spatial_predictors/02_terrain_analysis_outputs/aggregated_50m/final_predictors/model_ready_grid"
rasters <- list.files(folder_pred, pattern = "\\.tif$", full.names = TRUE)
stack_pred <- rast(rasters)
# Renombrar raster layers según el nombre de archivo
layer_names <- tools::file_path_sans_ext(basename(rasters))
names(stack_pred) <- layer_names

# Proyectar si es necesario
if (!crs(stack_pred, describe = TRUE)$code == target_crs) stack_pred <- project(stack_pred, paste0("EPSG:", target_crs))

# --- 4. Extraer valores de predictores para cada punto de coral
# Convertir a SpatVector para terra::extract
coral_vect <- vect(coral_pts)
pred_values <- terra::extract(stack_pred, coral_vect)
pred_values <- pred_values[, -1] # quitar columna ID

# --- 5. Construir dataframe final: cada row es un punto de coral + predictors extraídos
coral_df <- coral_pts %>%
  st_drop_geometry() %>%
  bind_cols(as.data.frame(pred_values))

# Opcional: Revisar y guardar
str(coral_df)
head(coral_df)



#####################################################################
### eliminate correlated variables
# Load necessary libraries
library(corrplot)
library(caret)
library(gridExtra)

# 1. Select only the oceanographic predictors
predictor_start <- which(names(coral_df) == layer_names[1])
ocean_pred <- coral_df[, predictor_start:ncol(coral_df)]

# 2. Remove predictors with zero variance
ocean_pred <- ocean_pred[, apply(ocean_pred, 2, sd, na.rm = TRUE) > 0]

# 3. Initial correlation matrix
cor_matrix <- cor(ocean_pred, use = "complete.obs", method = "pearson")

# 4. Identify all variable pairs with |correlation| ≥ 0.75
cor_pairs <- which(abs(cor_matrix) >= 0.75 & abs(cor_matrix) < 1, arr.ind = TRUE)
high_cor_pairs <- data.frame(
  Var1 = rownames(cor_matrix)[cor_pairs[,1]],
  Var2 = colnames(cor_matrix)[cor_pairs[,2]],
  correlation = cor_matrix[cor_pairs]
)
high_cor_pairs <- high_cor_pairs[high_cor_pairs$Var1 < high_cor_pairs$Var2, ] # Avoid duplicates
high_cor_pairs <- unique(high_cor_pairs)

# 5. Remove highly correlated variables using caret::findCorrelation
high_cor_idx <- findCorrelation(cor_matrix, cutoff = 0.75, verbose = FALSE, names = FALSE, exact = TRUE)
removed_vars <- names(ocean_pred)[high_cor_idx]
kept_vars <- names(ocean_pred)[-high_cor_idx]

reduced_pred <- ocean_pred[, kept_vars]

# 6. Reduced correlation matrix
cor_matrix_reduced <- cor(reduced_pred, use = "complete.obs", method = "pearson")

# 7. Plotting before and after correlation matrices side-by-side
png(filename = file.path(Fig_output_folder, "correlation_side_by_side.png"), width = 12, height = 6, units = "in", res = 300)
par(mfrow = c(1,2), mar = c(3,3,3,3))
corrplot(cor_matrix, method = "number", type = "upper", diag = FALSE,
         number.cex = 0.7, title = "Initial correlation", mar = c(0,0,1,0))
corrplot(cor_matrix_reduced, method = "number", type = "upper", diag = FALSE,
         number.cex = 0.7, title = "After removing correlated vars", mar = c(0,0,1,0))
dev.off()

# Optional: also print to console both plots (for RStudio)
par(mfrow = c(1,2), mar = c(3,3,3,3))
corrplot(cor_matrix, method = "number", type = "upper", diag = FALSE,
         number.cex = 0.7, title = "Initial correlation", mar = c(0,0,1,0))
corrplot(cor_matrix_reduced, method = "number", type = "upper", diag = FALSE,
         number.cex = 0.7, title = "After removing correlated vars", mar = c(0,0,1,0))
par(mfrow = c(1,1))

# 8. Write report tables to files if needed
write.csv(high_cor_pairs, file = file.path(Fig_output_folder, "highly_correlated_pairs.csv"), row.names = FALSE)
write.csv(removed_vars, file = file.path(Fig_output_folder, "removed_predictors.csv"), row.names = FALSE)
write.csv(kept_vars, file = file.path(Fig_output_folder, "kept_predictors.csv"), row.names = FALSE)

# --- English Report (copy this for your methods/report section) ---
cat("OCEANOGRAPHIC PREDICTORS MULTICOLLINEARITY REPORT\n")
cat("----------------------------------------------------\n")
cat("1. Initial predictor set:\n")
print(names(ocean_pred))
cat("\n2. Predictor pairs with |Pearson correlation| ≥ 0.75:\n")
print(high_cor_pairs)
cat("\n3. Variables excluded to avoid collinearity:\n")
print(removed_vars)
cat("\n4. Final set of predictors retained for modeling:\n")
print(kept_vars)
cat("\n5. Correlation matrices before and after removal have been plotted to ",
    file.path(Fig_output_folder, "correlation_side_by_side.png"), "\n")

#########################################################################
# final data set
# 1. Create the final modeling dataframe by excluding removed_vars from coral_df
final_vars <- setdiff(names(coral_df), removed_vars)
usvi_data_model <- coral_df[, final_vars]

# 2. Export to CSV (update the path as you specified)
write.csv(usvi_data_model,
          "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/01_inputs_csv/usvi_data_model.csv",
          row.names = FALSE)

# Optionally, confirm by printing the first few column names and rows:
cat("Variables in the exported modeling dataframe:\n")
print(names(usvi_data_model))
head(usvi_data_model)




























