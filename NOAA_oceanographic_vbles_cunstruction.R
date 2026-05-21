# ============================================================================
# Script: process_swan_wave_predictors.R
# Purpose: Download, aggregate, align, and export SWAN wave variables
#          (hs, tp, dir) for 2025, aligned to the BRT coral cover modeling grid
# Target CRS: WGS84 / UTM Zone 20N (EPSG:32620)
# Target resolution: 50m
# Inputs: SWAN NetCDF, master depth grid (for alignment)
# Outputs: 3 aligned predictors (wave_hs_50m_UTM20N.tif, etc.) for BRT
# Author: [Your Name]
# ============================================================================
library(terra)

# ----------------------------------------------------------------------------
# 1. Define file paths (Edit as necessary)
# ----------------------------------------------------------------------------
# Path to the SWAN NetCDF file
swan_nc <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/Ben_products/SWAN_HighRes_USVI_cda1_22a8_a456_U1779327579725.nc"

# Path to the master template raster (aligned to 50m, EPSG:32620)
template_grid <- "G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/05_preparation_spatial_predictors/02_terrain_analysis_outputs/aggregated_50m/depth_mean_50m.tif"

# Output directory for model-ready predictors
output_dir <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/model_ready_grid"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ----------------------------------------------------------------------------
# 2. Load SWAN NetCDF as SpatRaster and list variable/band names
# ----------------------------------------------------------------------------
swan_stack <- rast(swan_nc)
print(names(swan_stack)) # Inspect all variable and band names (should include hs, tp, dir, each with a time dimension)

# 3. List all variable and band names
cat("Variable and band names:\n")
print(names(swan_stack))

# 4. Get dimensions (rows, columns, bands)
cat("\nDimensions (rows, cols, bands):\n")
print(dim(swan_stack))

# 5. Inspect the time dimension (if present)
swan_time <- time(swan_stack)
cat("\nTime vector/class:\n")
print(class(swan_time))
print(swan_time)

# 6. Check variable metadata
cat("\nRaster summary:\n")
print(swan_stack)

# 7. (Optional) Plot the first band/layer for each variable to visualize
if ("hs" %in% names(swan_stack)) plot(swan_stack[["hs"]], main="Wave Hs (first time/band)")
if ("tp" %in% names(swan_stack)) plot(swan_stack[["tp"]], main="Wave Tp (first time/band)")
if ("dir" %in% names(swan_stack)) plot(swan_stack[["dir"]], main="Wave Dir (first time/band)")

# 8. Print a summary of all bands (e.g., which time they correspond to)
if (!is.null(swan_time)) {
  cat("\nFirst and last few time values:\n")
  print(head(swan_time))
  print(tail(swan_time))
  cat("\nNumber of time steps available:\n")
  print(length(swan_time))
}

## Identify Bands for Each Variable
# Indices for each variable's layers in swan_stack:
dir_idx <- grep("^dir_", names(swan_stack))
tp_idx  <- grep("^tp_", names(swan_stack))
hs_idx  <- grep("^hs_", names(swan_stack))

## Calculate the Annual Mean for Each Variable
hs_2025_mean <- mean(swan_stack[[hs_idx]], na.rm=TRUE)
tp_2025_mean <- mean(swan_stack[[tp_idx]], na.rm=TRUE)
dir_2025_mean <- mean(swan_stack[[dir_idx]], na.rm=TRUE)

# Set CRS for all SWAN rasters (before projecting)
crs(hs_2025_mean)  <- "EPSG:4326"
crs(tp_2025_mean)  <- "EPSG:4326"
crs(dir_2025_mean) <- "EPSG:4326"

# 2. Assign extent for all (from SWAN metadata: 1264 columns = -65.2 to -64.0; 689 rows = 18.18 to 18.8)
new_extent <- c(-65.2, -64.0, 18.18, 18.8)

ext(hs_2025_mean)  <- new_extent
ext(tp_2025_mean)  <- new_extent
ext(dir_2025_mean) <- new_extent

## Align and Mask to BRT Modeling Grid
# Path to 50m master template
template <- rast(template_grid)

# Project/resample
hs_aligned <- project(hs_2025_mean, template)
tp_aligned <- project(tp_2025_mean, template)
dir_aligned <- project(dir_2025_mean, template)

# Mask land pixels if template only covers the ocean
hs_final <- mask(hs_aligned, template)
tp_final <- mask(tp_aligned, template)
dir_final <- mask(dir_aligned, template)

## export
writeRaster(hs_final,  file.path(path_final_preds, "wave_hs_50m_UTM20N.tif"),  overwrite=TRUE)
writeRaster(tp_final,  file.path(path_final_preds, "wave_tp_50m_UTM20N.tif"),  overwrite=TRUE)
writeRaster(dir_final, file.path(path_final_preds, "wave_dir_50m_UTM20N.tif"), overwrite=TRUE)

### Plot variables
library(terra)
library(ggplot2)
library(viridis)   # for color palettes
library(sf)

# -----------------------------------------------------------------------------
# Define file paths to your final predictors
output_dir <- "G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/05_preparation_spatial_predictors/02_terrain_analysis_outputs/aggregated_50m/final_predictors/model_ready_grid"
hs_file <- file.path(output_dir, "wave_hs_50m_UTM20N.tif")
tp_file <- file.path(output_dir, "wave_tp_50m_UTM20N.tif")
dir_file <- file.path(output_dir, "wave_dir_50m_UTM20N.tif")

# -----------------------------------------------------------------------------
# Load rasters
hs_ras  <- rast(hs_file)
tp_ras  <- rast(tp_file)
dir_ras <- rast(dir_file)

# -----------------------------------------------------------------------------
# Convert to data.frames (for ggplot2 plotting)
hs_df  <- as.data.frame(hs_ras, xy=TRUE, na.rm=TRUE)
tp_df  <- as.data.frame(tp_ras, xy=TRUE, na.rm=TRUE)
dir_df <- as.data.frame(dir_ras, xy=TRUE, na.rm=TRUE)

# -----------------------------------------------------------------------------
# Make and save high-quality plots for each predictor
plot_dir <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/plots"

library(dplyr)
hs_df <- hs_df %>% rename(wave_hs_50m_UTM20N = mean)

# 1. Wave Height (hs)
p_hs <- ggplot(hs_df, aes(x = x, y = y, fill = wave_hs_50m_UTM20N)) +
  geom_raster() +
  scale_fill_viridis_c(option="C", direction=1, na.value="gray80", name="Hs (m)") +
  labs(title="SWAN Mean Significant Wave Height (2025)",
       x="Easting (m)", y="Northing (m)") +
  coord_equal() +
  theme_bw() +
  theme(panel.border = element_rect(colour = "black", fill=NA),
        plot.title = element_text(hjust=0.5),
        legend.position = "right")
print(p_hs)

ggsave(filename=file.path(plot_dir, "SWAN_Hs_2025_map.png"),
       plot=p_hs, width=7, height=6, dpi=300)

# 2. Wave Period (tp)
p_tp <- ggplot(tp_df, aes(x=x, y=y, fill=mean)) +
  geom_raster() +
  scale_fill_viridis_c(option="B", direction=1, na.value="gray80", name="Tp (s)") +
  labs(title="SWAN Mean Peak Wave Period (2025)",
       x="Easting (m)", y="Northing (m)") +
  coord_equal() +
  theme_bw() +
  theme(panel.border = element_rect(colour = "black", fill=NA),
        plot.title = element_text(hjust=0.5),
        legend.position = "right")
print(p_tp)

ggsave(filename=file.path(plot_dir, "SWAN_Tp_2025_map.png"),
       plot=p_tp, width=7, height=6, dpi=300)

# 3. Wave Direction (dir)
p_dir <- ggplot(dir_df, aes(x=x, y=y, fill=mean)) +
  geom_raster() +
  scale_fill_viridis_c(option="plasma", direction=1, na.value="gray80", name="Direction (deg)") +
  labs(title="SWAN Mean Wave Direction (2025)",
       x="Easting (m)", y="Northing (m)") +
  coord_equal() +
  theme_bw() +
  theme(panel.border = element_rect(colour = "black", fill=NA),
        plot.title = element_text(hjust=0.5),
        legend.position = "right")
print(p_dir)

ggsave(filename=file.path(plot_dir, "SWAN_DIR_2025_map.png"),
       plot=p_dir, width=7, height=6, dpi=300)

# -----------------------------------------------------------------------------
cat("All maps saved in:", plot_dir, "\n")


#############################################################################
### =========================================================================

library(terra)

# Path to downloaded SPM NetCDF file
spm_file <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/Ben_products/noaacwNPPN20S3AspmSCIDINEOF2kmDaily_4a44_0a6a_2540.nc"

# 1. Load NetCDF as SpatRaster
spm_stack <- rast(spm_file)

# 2. Check available variable and band names
print(names(spm_stack))
# Example: "spm_1", "spm_2",..., or just "spm" with multiple bands.

# 3. (Optional) Time inspection if needed
spm_time <- time(spm_stack)
print(spm_time)

# 4. Aggregate mean for 2025 (across all bands)
# Assuming all bands are for 2025 and correspond to approximately monthly means (if you used stride),
# otherwise, subset by time if needed (like you did for SWAN)
spm_2025_mean <- mean(spm_stack, na.rm=TRUE)


## Georeference, Project, and Mask
# Assuming NetCDF is in WGS84 (EPSG:4326) and covers correct lat/lon:
# Assign correct CRS if not already set
crs(spm_2025_mean) <- "EPSG:4326"
# Set extent - check/adjust if needed based on your USVI subset in download
# For example (update lat/lon as used in the download):
ext(spm_2025_mean) <- c(-65.3, -63.9, 18.1, 18.85)

# Project to your BRT grid template
template_grid <- "G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/05_preparation_spatial_predictors/02_terrain_analysis_outputs/aggregated_50m/depth_mean_50m.tif"
template <- rast(template_grid)
spm_aligned <- project(spm_2025_mean, template)

# Mask (if you want values only where your analysis grid/ocean is) 
spm_final <- mask(spm_aligned, template)

# Export as GeoTIFF
writeRaster(spm_final, file.path(path_final_preds, "spm_mean_2025_50m_UTM20N.tif"), overwrite=TRUE)

## Plotting
library(ggplot2)
library(viridis)
spm_ras <- rast(file.path(output_dir, "spm_mean_2025_50m_UTM20N.tif"))
spm_df <- as.data.frame(spm_ras, xy=TRUE, na.rm=TRUE)
names(spm_df)[3] <- "SPM_mean_2025"

p_spm <- ggplot(spm_df, aes(x=x, y=y, fill=SPM_mean_2025)) +
  geom_raster() +
  scale_fill_viridis_c(option="D", name="SPM") +
  labs(title="Mean Suspended Particulate Matter (2025)",
       x="Easting (m)", y="Northing (m)") +
  coord_equal() +
  theme_bw() +
  theme(panel.border = element_rect(colour = "black", fill=NA),
        plot.title = element_text(hjust=0.5),
        legend.position = "right")
print(p_spm)


ggsave(filename=file.path(plot_dir, "SPM_mean_2025_map.png"),
       plot=p_spm, width=7, height=6, dpi=300)

#####################################################################################
### SST
# Path to downloaded SPM NetCDF file
sst_file <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/Ben_products/jplMURSST41mday_c99b_cf9d_a540.nc"

# 1. Load NetCDF as SpatRaster
sst_stack <- rast(sst_file)

# 2. Check available variable and band names
print(names(sst_stack))
# Example: "spm_1", "spm_2",..., or just "spm" with multiple bands.

# 3. (Optional) Time inspection if needed
sst_time <- time(sst_stack)
print(sst_time)

# 4. Aggregate mean for 2025 (across all bands)
# Assuming all bands are for 2025 and correspond to approximately monthly means (if you used stride),
# otherwise, subset by time if needed (like you did for SWAN)
sst_2025_mean <- mean(sst_stack, na.rm=TRUE)


## Georeference, Project, and Mask
# Assuming NetCDF is in WGS84 (EPSG:4326) and covers correct lat/lon:
# Assign correct CRS if not already set
crs(sst_2025_mean) <- "EPSG:4326"
# Set extent - check/adjust if needed based on your USVI subset in download
# For example (update lat/lon as used in the download):
ext(sst_2025_mean) <- c(-65.3, -63.9, 18.1, 18.85)

# Project to your BRT grid template
template_grid <- "G:/Shared drives/NSF CoPE internal/GIS_CoPE/GIS_USVI/2_model_inputs_usvi/Fisheries/coral_cover_modeling/05_preparation_spatial_predictors/02_terrain_analysis_outputs/aggregated_50m/depth_mean_50m.tif"
template <- rast(template_grid)
sst_aligned <- project(sst_2025_mean, template)

# Mask (if you want values only where your analysis grid/ocean is) 
sst_final <- mask(sst_aligned, template)

# Export as GeoTIFF
writeRaster(sst_final, file.path(path_final_preds, "sst_MUR_mean_2025_50m_UTM20N.tif"), overwrite=TRUE)

## Plotting
library(ggplot2)
library(viridis)
sst_ras <- rast(file.path(output_dir, "sst_MUR_mean_2025_50m_UTM20N.tif"))
sst_df <- as.data.frame(sst_ras, xy=TRUE, na.rm=TRUE)
names(sst_df)[3] <- "SST_mean_2025"

p_sst <- ggplot(sst_df, aes(x=x, y=y, fill=SST_mean_2025)) +
  geom_raster() +
  scale_fill_viridis_c(option="D", name="SST") +
  labs(title="Sea Surface Temperature (2025)",
       x="Easting (m)", y="Northing (m)") +
  coord_equal() +
  theme_bw() +
  theme(panel.border = element_rect(colour = "black", fill=NA),
        plot.title = element_text(hjust=0.5),
        legend.position = "right")
print(p_sst)


ggsave(filename=file.path(plot_dir, "SST_MUR_mean_2025_map.png"),
       plot=p_sst , width=7, height=6, dpi=300)
