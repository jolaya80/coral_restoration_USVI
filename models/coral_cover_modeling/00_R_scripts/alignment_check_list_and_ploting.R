# ============================================================
# STUDY AREA QA FOR FINAL RASTERS: ST. THOMAS, USVI
# CRS: WGS84 UTM 20N; EPSG:32620
# RESOLUTION: 50 x 50 m
# ============================================================

library(terra)
library(ggplot2)
library(viridis)
library(dplyr)

# -- CONFIGURATION --
# Update this path to your working directory:
folder <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/model_ready_grid"
plot_dir <- "C:/Users/jolaya/Documents/GitHub_projects/coral_restoration_USVI/models/coral_cover_modeling/05_preparation_spatial_predictors/plots"
if(!dir.exists(plot_dir)) dir.create(plot_dir, recursive=TRUE)

# -- 1. List all .tif files --
tif_files <- list.files(folder, pattern="\\.tif$", full.names=TRUE)
cat("Total .tif files found:", length(tif_files), "\n")

# -- 2. Define a summary function for raster metadata --
raster_info <- function(f, template=NULL) {
  r <- rast(f)
  nNA <- sum(is.na(values(r)))
  # Try getting min/max; protect against all-NA file
  min_val <- tryCatch(minmax(r)[1], error=function(e) NA)
  max_val <- tryCatch(minmax(r)[2], error=function(e) NA)
  crs_name <- tryCatch(crs(r, describe=TRUE)$code, error=function(e) NA)
  info <- data.frame(
    file_name = basename(f),
    crs       = crs_name,
    nrow      = nrow(r),
    ncol      = ncol(r),
    res_x     = res(r)[1],
    res_y     = res(r)[2],
    xmin      = ext(r)[1], xmax=ext(r)[2],
    ymin      = ext(r)[3], ymax=ext(r)[4],
    min_val   = min_val,
    max_val   = max_val,
    na_cells  = nNA
  )
  # If template is provided: add alignment check
  if(!is.null(template)) {
    info$template_match <- compareGeom(r, template, stopOnError=FALSE)
  }
  return(info)
}

# -- 3. Load master/template for comparison (e.g., depth_mean_50m) --
template_file <- file.path(folder, "depth_mean_50m.tif")
if(!file.exists(template_file)) stop("Template raster (depth_mean_50m.tif) not found in folder.")
template <- rast(template_file)


# -- 4. Summarize all rasters
summary_list <- lapply(tif_files, raster_info, template=template)
summary_df <- bind_rows(summary_list)
print(summary_df)

misaligned_files <- summary_df %>%
  filter(!template_match | is.na(template_match)) %>%
  pull(file_name)

# -- 5. List misaligned files (difference in extent, resolution, dimensions, or CRS) --
if("template_match" %in% names(summary_df)) {
  misaligned <- summary_df %>% filter(!template_match | is.na(template_match))
  if(nrow(misaligned) > 0) {
    cat("\nMismatched/unaligned files:\n")
    print(misaligned[,c("file_name","crs","nrow","ncol","res_x","res_y","template_match")])
  } else {
    cat("\n✅ All rasters are matched in grid, extent, and CRS.\n")
  }
}

for (fname in misaligned_files) {
  fpath <- file.path(folder, fname)
  r <- rast(fpath)
  # 1. Ensure CRS matches (convert if not)
  crs(r) <- crs(template)
  # 2. Project & resample to template grid
  r_aligned <- project(r, template)
  # 3. Mask to remove cells outside the template’s valid area
  r_final <- mask(r_aligned, template)
  # 4. Overwrite file (or save to new folder for safety)
  writeRaster(r_final, fpath, overwrite=TRUE)
  cat("Fixed alignment for:", fname, "\n")
}

# -- 6. (Optional) Save summary as CSV for records
write.csv(summary_df, file=file.path(plot_dir, "predictor_tif_summary.csv"), row.names=FALSE)

# -- 1. List all .tif predictors --
tif_files <- list.files(folder, pattern="\\.tif$", full.names=TRUE)
cat("Total .tif files found:", length(tif_files), "\n")

# -- 2. Loop and plot each raster --
for(i in seq_along(tif_files)) {
  r <- rast(tif_files[i])
  # Get file base name for plotting/legend (removes .tif)
  layer_name <- tools::file_path_sans_ext(basename(tif_files[i]))
  ras_df <- as.data.frame(r, xy=TRUE, na.rm=TRUE)
  # Skip empty rasters
  if(ncol(ras_df) < 3 || nrow(ras_df) == 0) {
    cat("Skipping empty raster:", layer_name, "\n")
    next
  }
  names(ras_df)[3] <- "value"
  # Build plot
  p <- ggplot(ras_df, aes(x = x, y = y, fill = value)) +
    geom_raster() +
    scale_fill_viridis_c(option="D", name=layer_name) +
    labs(title=layer_name,
         x="Easting (m)", y="Northing (m)") +
    coord_equal() +  theme_bw() +
    theme(panel.border = element_rect(colour = "black", fill=NA),
          plot.title = element_text(hjust=0.5),
          legend.position = "right")
  # Export to .png
  plot_file <- file.path(plot_dir, paste0(layer_name, "_map.png"))
  ggsave(filename = plot_file, plot = p, width = 7, height = 6, dpi = 300)
  cat("Plotted", layer_name, "as", plot_file, "\n")
}
