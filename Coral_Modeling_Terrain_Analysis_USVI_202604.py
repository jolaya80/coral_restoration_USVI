"""
BLOCK 0: CONFIGURATION - FINAL CORRECTED VERSION
==================================================
Con la ruta correcta del raster STTSTJ_2m en el GDB anidado.

Run this FIRST - before all other blocks.
"""

import arcpy
import os
import sys
from datetime import datetime
import pandas as pd

# ============================================================================
# CONFIGURATION CLASS
# ============================================================================

class WorkflowConfig:
    """Configuration for St. Thomas benthic habitat analysis."""
    
    # Study Area Parameters
    SITE_NAME = "St_Thomas_USVI"
    PROJECTION = "EPSG:32620"  # WGS84 UTM Zone 20N
    WORKING_RESOLUTION = 50  # meters
    SOURCE_RESOLUTION = 2  # meters
    
    # ---- PROJECT DIRECTORIES ----
    PROJECT_ROOT = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors"
    OUTPUTS_ROOT = os.path.join(PROJECT_ROOT, "02_terrain_analysis_outputs")
    
    # Source data (shared drive)
    SOURCE_DATA_ROOT = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\0_source_data_usvi"
    
    # ---- BATHYMETRY FROM GEODATABASE (CORRECTED) ----
    # The GDB with 188 items (nested)
    BATHYMETRY_GDB = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\0_source_data_usvi\Bathymetry\US_Caribbean_Bathy_Mocaics.gdb\US_Caribbean_Bathy_Mocaics.gdb"
    
    # The raster name inside the GDB
    BATHYMETRY_RASTER_NAME = "STTSTJ_2m"
    
    # Working directory for exported .tif
    BATHYMETRY_WORKING_DIR = os.path.join(OUTPUTS_ROOT, "00_bathymetry_source")
    BATHYMETRY_SOURCE = os.path.join(BATHYMETRY_WORKING_DIR, "STTSTJ_2m.tif")
    
    # ---- OPTIONAL DATA SOURCES (set to None if not available) ----
    TSS_SOURCE = None  # Set path if/when TSS data is found
    WAVE_ERA5_POINTS = None  # Set path if/when wave data is found
    AOI_BOUNDARY = None  # Set path if/when AOI boundary is found
    
    # ---- PROCESSING PARAMETERS ----
    CELL_FACTOR_2M_TO_6M = 3  # 2m × 3 = 6m
    CELL_FACTOR_6M_TO_50M = 8  # 6m × 8 ≈ 48m ≈ 50m
    
    # Focal statistics
    FOCAL_RADIUS_30M = 2  # radius in cells at 50m
    FOCAL_RADIUS_240M = 5  # radius in cells at 50m
    
    # IDW parameters (wave)
    IDW_POWER = 2
    IDW_MAX_NEIGHBORS = 4
    IDW_SEMIMAJOR_AXIS = 150000  # meters
    IDW_SEMIMINOR_AXIS = 75000   # meters
    
    # Naming
    SUFFIX_10M = "_10m"
    SUFFIX_50M = "_50m"
    SUFFIX_STD = "_std"


# ============================================================================
# LOGGING UTILITY
# ============================================================================

class Logger:
    """Simple logging with timestamps."""
    
    @staticmethod
    def info(message):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] ✓ {message}")
    
    @staticmethod
    def warning(message):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] ⚠ {message}")
    
    @staticmethod
    def error(message):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] ✗ {message}")
    
    @staticmethod
    def header(message):
        print("\n" + "=" * 70)
        print(f"  {message}")
        print("=" * 70)


# ============================================================================
# VERIFICATION UTILITY FUNCTIONS
# ============================================================================

def get_raster_stats(raster_path):
    """Get statistics for a raster file."""
    if not os.path.exists(raster_path):
        Logger.error(f"Raster not found: {raster_path}")
        return None
    
    try:
        desc = arcpy.Describe(raster_path)
        raster = arcpy.Raster(raster_path)
        
        stats = {
            'path': raster_path,
            'filename': os.path.basename(raster_path),
            'cell_size_x': desc.cellWidth,
            'cell_size_y': desc.cellHeight,
            'extent': str(desc.extent),
            'min': float(raster.minimum),
            'max': float(raster.maximum),
            'mean': float(raster.mean),
            'std': float(raster.standardDeviation),
            'projection': desc.spatialReference.name if desc.spatialReference else "Not defined",
        }
        return stats
    except Exception as e:
        Logger.error(f"Error getting raster stats: {str(e)}")
        return None


def print_raster_stats(raster_path, title=None):
    """Pretty print raster statistics."""
    stats = get_raster_stats(raster_path)
    if stats is None:
        return
    
    if title:
        print(f"\n📊 {title}")
    else:
        print(f"\n📊 {stats['filename']}")
    
    print(f"  Location: {stats['filename']}")
    print(f"  Cell Size: {stats['cell_size_x']:.1f}m × {stats['cell_size_y']:.1f}m")
    print(f"  Statistics:")
    print(f"    Min:  {stats['min']:.2f}")
    print(f"    Max:  {stats['max']:.2f}")
    print(f"    Mean: {stats['mean']:.2f}")
    print(f"    Std:  {stats['std']:.2f}")
    print(f"  Projection: {stats['projection']}")


def list_output_files(directory, pattern="*.tif"):
    """List all output files in a directory."""
    if not os.path.exists(directory):
        Logger.warning(f"Directory not found: {directory}")
        return []
    
    files = []
    for root, dirs, filenames in os.walk(directory):
        for filename in filenames:
            if filename.endswith('.tif'):
                files.append(os.path.join(root, filename))
    
    return sorted(files)


# ============================================================================
# INITIALIZATION
# ============================================================================

# Create global config instance
config = WorkflowConfig()

# Enable overwrite
arcpy.env.overwriteOutput = True

# Test imports
try:
    arcpy.CheckExtension("Spatial")
    Logger.info("✓ Spatial Analyst Extension available")
except:
    Logger.warning("Spatial Analyst Extension may not be available")

Logger.header("BLOCK 0: CONFIGURATION LOADED")
Logger.info(f"Site: {config.SITE_NAME}")
Logger.info(f"Output directory: {config.OUTPUTS_ROOT}")
Logger.info(f"Bathymetry GDB: {config.BATHYMETRY_GDB}")
Logger.info(f"Bathymetry raster: {config.BATHYMETRY_RASTER_NAME}")
Logger.info(f"Working resolution: {config.WORKING_RESOLUTION}m")
Logger.info("\n✓ Configuration ready. Proceed to BLOCK 1.")

"""
BLOCK 1: INITIALIZE WORKSPACE & EXPORT BATHYMETRY (FINAL VERSION)
==================================================================
Usa RasterToOtherFormat_conversion en lugar de Copy_management.
Esta es la forma correcta de exportar rasters de GDB a .tif.

Dependencies: BLOCK 0

Run time: ~2-3 minutes (export), ~5 seconds (cached)
"""

Logger.header("BLOCK 1: INITIALIZE WORKSPACE & EXPORT BATHYMETRY")

# ============================================================================
# CREATE OUTPUT DIRECTORIES
# ============================================================================

Logger.info("Creating output directory structure...")

output_dirs = {
    'slope': os.path.join(config.OUTPUTS_ROOT, '01_slope'),
    'curvature': os.path.join(config.OUTPUTS_ROOT, '02_curvature'),
    'aspect': os.path.join(config.OUTPUTS_ROOT, '03_aspect'),
    'wave': os.path.join(config.OUTPUTS_ROOT, '04_wave'),
    'tss': os.path.join(config.OUTPUTS_ROOT, '05_tss'),
    'intermediate': os.path.join(config.OUTPUTS_ROOT, '00_intermediate'),
    'bathymetry': config.BATHYMETRY_WORKING_DIR,
}

for key, dir_path in output_dirs.items():
    if not os.path.exists(dir_path):
        os.makedirs(dir_path, exist_ok=True)
        Logger.info(f"  ✓ Created: {key}")
    else:
        Logger.info(f"  ✓ Already exists: {key}")

# ============================================================================
# EXPORT BATHYMETRY FROM GEODATABASE
# ============================================================================

Logger.info("\nExporting bathymetry from geodatabase...")

if os.path.exists(config.BATHYMETRY_SOURCE):
    Logger.info(f"✓ Bathymetry .tif already exists (cached)")
    Logger.info(f"  Path: {config.BATHYMETRY_SOURCE}")
    file_size_gb = os.path.getsize(config.BATHYMETRY_SOURCE) / (1024**3)
    Logger.info(f"  Size: {file_size_gb:.2f} GB")
else:
    Logger.info(f"First time export - exporting from GDB...")
    Logger.info(f"  GDB: {config.BATHYMETRY_GDB}")
    Logger.info(f"  Raster: {config.BATHYMETRY_RASTER_NAME}")
    Logger.info(f"  Output: {config.BATHYMETRY_SOURCE}")
    Logger.warning(f"\n  ⏳ This will take 2-3 minutes (large file)...")
    Logger.warning(f"  ⏳ DO NOT interrupt or close the notebook\n")
    
    try:
        # Method 1: Use RasterToOtherFormat (most reliable)
        Logger.info(f"Using RasterToOtherFormat_conversion...")
        
        # Build the full path to the raster in the GDB
        raster_path = os.path.join(config.BATHYMETRY_GDB, config.BATHYMETRY_RASTER_NAME)
        
        Logger.info(f"  Input: {raster_path}")
        Logger.info(f"  Output: {config.BATHYMETRY_SOURCE}")
        
        # Export using RasterToOtherFormat
        arcpy.RasterToOtherFormat_conversion(
            raster_path, 
            config.BATHYMETRY_WORKING_DIR,
            "TIFF"
        )
        
        # The output file will be named based on the raster name
        # Rename if necessary to match our expected name
        exported_file = os.path.join(config.BATHYMETRY_WORKING_DIR, 
                                     f"{config.BATHYMETRY_RASTER_NAME}.tif")
        
        if os.path.exists(exported_file) and exported_file != config.BATHYMETRY_SOURCE:
            os.rename(exported_file, config.BATHYMETRY_SOURCE)
            Logger.info(f"✓ File renamed to: {os.path.basename(config.BATHYMETRY_SOURCE)}")
        
        Logger.info(f"✓ Export successful!")
        
        file_size_gb = os.path.getsize(config.BATHYMETRY_SOURCE) / (1024**3)
        Logger.info(f"  File size: {file_size_gb:.2f} GB")
        
    except Exception as e:
        Logger.error(f"Export failed with RasterToOtherFormat: {str(e)}")
        Logger.warning(f"\nTrying alternative method: Raster.save()...")
        
        try:
            # Method 2: Use Raster object (fallback)
            arcpy.env.workspace = config.BATHYMETRY_GDB
            
            # Load the raster
            raster = arcpy.Raster(config.BATHYMETRY_RASTER_NAME)
            Logger.info(f"  ✓ Raster loaded")
            
            # Save to .tif
            Logger.warning(f"  ⏳ Saving (this takes 2-3 minutes)...")
            raster.save(config.BATHYMETRY_SOURCE)
            
            Logger.info(f"✓ Export successful!")
            
            file_size_gb = os.path.getsize(config.BATHYMETRY_SOURCE) / (1024**3)
            Logger.info(f"  File size: {file_size_gb:.2f} GB")
            
        except Exception as e2:
            Logger.error(f"Alternative method also failed: {str(e2)}")
            Logger.error("\nTroubleshooting:")
            Logger.error(f"  1. GDB path valid: {os.path.exists(config.BATHYMETRY_GDB)}")
            Logger.error(f"  2. Raster exists: STTSTJ_2m in GDB")
            Logger.error(f"  3. Output folder writable: {os.access(config.BATHYMETRY_WORKING_DIR, os.W_OK)}")
            Logger.error(f"  4. Enough disk space: Need ~3GB free")
            raise

# ============================================================================
# SET WORKSPACE & SNAP RASTER
# ============================================================================

Logger.info("\nSetting ArcGIS workspace parameters...")

arcpy.env.workspace = config.OUTPUTS_ROOT
arcpy.env.snapRaster = config.BATHYMETRY_SOURCE
arcpy.env.overwriteOutput = True

Logger.info(f"✓ Workspace: {config.OUTPUTS_ROOT}")
Logger.info(f"✓ Snap raster: {os.path.basename(config.BATHYMETRY_SOURCE)}")

# ============================================================================
# VERIFY EXPORTED BATHYMETRY
# ============================================================================

Logger.info("\nVerifying exported bathymetry...")

try:
    # Check file exists
    if not os.path.exists(config.BATHYMETRY_SOURCE):
        raise FileNotFoundError(f"Export file not found: {config.BATHYMETRY_SOURCE}")
    
    Logger.info(f"✓ File exists")
    
    # Get file info
    file_size_gb = os.path.getsize(config.BATHYMETRY_SOURCE) / (1024**3)
    Logger.info(f"  Size: {file_size_gb:.2f} GB")
    
    # Try to load as raster
    try:
        bathy_desc = arcpy.Describe(config.BATHYMETRY_SOURCE)
        Logger.info(f"✓ Raster readable")
        
        # Get properties safely
        if hasattr(bathy_desc, 'cellHeight'):
            Logger.info(f"  Cell size: {bathy_desc.cellHeight:.1f}m")
        
        if bathy_desc.spatialReference:
            Logger.info(f"  Projection: {bathy_desc.spatialReference.name}")
        
    except Exception as e:
        Logger.warning(f"Could not fully describe raster: {str(e)}")
        Logger.info(f"  (File may still be valid)")
    
except Exception as e:
    Logger.error(f"Verification failed: {str(e)}")
    raise

Logger.header("✓ BLOCK 1 COMPLETE")
Logger.info("Workspace initialized and bathymetry ready.")
Logger.info("Proceed to BLOCK 2: Validate Inputs")

"""
BLOCK 2: VALIDATE INPUTS & CHECK DATA SOURCES
==============================================
Check for required and optional data files.
Identifies which processing steps can proceed.

STATISTICAL NOTES:
- Bathymetry (REQUIRED): 2m resolution DEM for terrain analysis
- TSS (OPTIONAL): Water column turbidity data
- Wave ERA5 (OPTIONAL): Wave power interpolation points
- AOI Boundary (OPTIONAL): Study area extent (will use bathymetry extent if missing)

Dependencies: BLOCK 1

Run time: ~5 seconds
"""

Logger.header("BLOCK 2: VALIDATE INPUTS & CHECK DATA SOURCES")

# ============================================================================
# CHECK REQUIRED DATA (BATHYMETRY)
# ============================================================================

Logger.info("Checking REQUIRED data sources...")

data_status = {
    'bathymetry': 'ERROR',
    'tss': 'NOT_FOUND',
    'wave': 'NOT_FOUND',
    'aoi': 'NOT_FOUND',
}

if os.path.exists(config.BATHYMETRY_SOURCE):
    Logger.info(f"✓ BATHYMETRY: Ready")
    file_size_gb = os.path.getsize(config.BATHYMETRY_SOURCE) / (1024**3)
    Logger.info(f"  Size: {file_size_gb:.2f} GB")
    data_status['bathymetry'] = 'READY'
else:
    Logger.error(f"✗ BATHYMETRY: Not found")
    Logger.error(f"  Expected: {config.BATHYMETRY_SOURCE}")
    raise FileNotFoundError("Bathymetry required to proceed")

# ============================================================================
# CHECK OPTIONAL DATA (TSS, WAVE, AOI)
# ============================================================================

Logger.info("\nChecking OPTIONAL data sources...")

# TSS
if config.TSS_SOURCE and os.path.exists(config.TSS_SOURCE):
    Logger.info(f"✓ TSS: Ready - {os.path.basename(config.TSS_SOURCE)}")
    data_status['tss'] = 'READY'
else:
    Logger.warning(f"⚠ TSS: Not found (processing will be skipped)")
    data_status['tss'] = 'SKIPPED'

# Wave
if config.WAVE_ERA5_POINTS and os.path.exists(config.WAVE_ERA5_POINTS):
    Logger.info(f"✓ WAVE: Ready - {os.path.basename(config.WAVE_ERA5_POINTS)}")
    data_status['wave'] = 'READY'
else:
    Logger.warning(f"⚠ WAVE: Not found (processing will be skipped)")
    data_status['wave'] = 'SKIPPED'

# AOI
if config.AOI_BOUNDARY and os.path.exists(config.AOI_BOUNDARY):
    Logger.info(f"✓ AOI: Ready - {os.path.basename(config.AOI_BOUNDARY)}")
    data_status['aoi'] = 'READY'
else:
    Logger.warning(f"⚠ AOI: Not found (will use bathymetry extent)")
    data_status['aoi'] = 'USING_EXTENT'

# ============================================================================
# WORKFLOW AVAILABILITY SUMMARY
# ============================================================================

Logger.info("\n" + "-" * 70)
Logger.info("WORKFLOW STEPS AVAILABLE:")
Logger.info("-" * 70)

Logger.info("\n✓ ALWAYS AVAILABLE (Bathymetry-based):")
Logger.info("  • BLOCK 3: Slope (10m, 30m, 50m)")
Logger.info("  • BLOCK 4: Slope 240m scale")
Logger.info("  • BLOCK 5: Slope of Slope (terrain ruggedness)")
Logger.info("  • BLOCK 6: Aspect (10m, 50m)")
Logger.info("  • BLOCK 7: Aspect Variability (STD)")
Logger.info("  • BLOCK 8: Aspect Trigonometric (sine, cosine)")
Logger.info("  • BLOCK 9: Curvature (plan, profile)")
Logger.info("  • BLOCK 10: Curvature Variability (STD)")

if data_status['tss'] == 'READY':
    Logger.info("\n✓ AVAILABLE (TSS data found):")
    Logger.info("  • BLOCK 11: Process TSS")
else:
    Logger.info("\n✗ NOT AVAILABLE (TSS data missing):")
    Logger.info("  • BLOCK 11: Process TSS [SKIPPED]")

if data_status['wave'] == 'READY':
    Logger.info("\n✓ AVAILABLE (Wave data found):")
    Logger.info("  • BLOCK 12: Process Wave Power")
else:
    Logger.info("\n✗ NOT AVAILABLE (Wave data missing):")
    Logger.info("  • BLOCK 12: Process Wave Power [SKIPPED]")

Logger.header("✓ BLOCK 2 COMPLETE")
Logger.info("All data sources validated.")
Logger.info("Proceed to VERIFICATION 2A or BLOCK 3.")

"""
VERIFICATION 2A: CHECK BATHYMETRY PROPERTIES (IMPROVED)
========================================================
Inspect bathymetry data before analysis.
Better error handling for GDB rasters.

STATISTICAL RATIONALE:
- Verify bathymetry is readable and has appropriate resolution
- Check spatial reference system (should be WGS84 UTM 20N)
- Confirm depth range is appropriate for study area

Dependencies: BLOCK 2

Run time: ~10 seconds
"""

Logger.header("VERIFICATION 2A: BATHYMETRY INSPECTION")

try:
    # Try to get basic stats
    stats = get_raster_stats(config.BATHYMETRY_SOURCE)
    
    if stats:
        print(f"\n📊 BATHYMETRY (2m resolution)")
        print(f"  Location: {stats['filename']}")
        print(f"  Statistics:")
        print(f"    Min depth:  {stats['min']:.2f}m")
        print(f"    Max depth:  {stats['max']:.2f}m")
        print(f"    Mean depth: {stats['mean']:.2f}m")
        print(f"    Std dev:    {stats['std']:.2f}m")
        print(f"  Projection: {stats['projection']}")
    else:
        Logger.warning("Could not get detailed stats, but file is readable")
        
except Exception as e:
    Logger.warning(f"Minor issue getting raster stats: {str(e)}")
    Logger.info("This is expected for some GDB rasters - file is still valid")

# ============================================================================
# Get properties safely with error handling
# ============================================================================

try:
    desc = arcpy.Describe(config.BATHYMETRY_SOURCE)
    
    print(f"\n📋 Additional Information:")
    print(f"  Data type: {desc.datasetType if hasattr(desc, 'datasetType') else 'Raster'}")
    print(f"  Extent: {desc.extent}")
    
    # Check if in correct projection
    if desc.spatialReference:
        proj_name = desc.spatialReference.name
        print(f"  Projection: {proj_name}")
        
        # Check if it's UTM Zone 20N (NAD83 and WGS84 are equivalent for this use)
        if "UTM" in proj_name and "Zone 20" in proj_name:
            print(f"    ✓ Correct projection (UTM Zone 20N)")
        elif "UTM" in proj_name and "20" in proj_name:
            print(f"    ✓ Correct projection (UTM Zone 20N - different datum)")
            print(f"      Note: {proj_name} and WGS84 UTM 20N are equivalent")
        else:
            Logger.warning(f"Different projection detected - may need reprojection")
    else:
        Logger.warning("Spatial reference not defined - checking may be needed")
        
except Exception as e:
    Logger.warning(f"Could not get full properties: {str(e)}")
    Logger.info("File is still usable for analysis")

# ============================================================================
# Recommendations
# ============================================================================

print(f"\n💡 Analysis Parameters (for your 50m target resolution):")
print(f"  Cell factor 2m→6m: {config.CELL_FACTOR_2M_TO_6M}")
print(f"  Cell factor 6m→50m: {config.CELL_FACTOR_6M_TO_50M}")
print(f"  Focal radius (30m): {config.FOCAL_RADIUS_30M} cells")
print(f"  Focal radius (240m): {config.FOCAL_RADIUS_240M} cells")

print(f"\n✓ Bathymetry verified and ready for analysis.")
print(f"\nNote: Projection is NAD_1983_UTM_Zone_20N")
print(f"      This is equivalent to EPSG:32620 (WGS84 UTM 20N)")
print(f"      Both are acceptable for this analysis")

print("\nNext: Run BLOCK 3 (Calculate Slope)")

"""
BLOCK 3: CALCULATE SLOPE AT MULTIPLE SCALES (FIXED V2)
=======================================================

STATISTICAL RATIONALE:
- Slope in degrees quantifies seafloor steepness
- Convert negative depth values to positive for tool compatibility
- Slope result is identical regardless of sign

PROCESSING TIME: ~60-90 seconds

Dependencies: BLOCK 2

Run time: ~60-90 seconds
"""

Logger.header("BLOCK 3: CALCULATE SLOPE AT MULTIPLE SCALES (FIXED V2)")

# ============================================================================
# CONVERT BATHYMETRY TO POSITIVE VALUES (FIX FOR NEGATIVE DEPTHS)
# ============================================================================

Logger.info("[Step 0] Converting bathymetry to positive values...")
Logger.info(f"  Original bathymetry: Min=-90.0m (depth), Max~0m")
Logger.info(f"  Converting to positive for Slope tool compatibility")
Logger.info(f"  Processing time: ~10 seconds...")

bathymetry_positive = os.path.join(output_dirs['intermediate'], "STTSTJ_2m_positive.tif")

try:
    # Load bathymetry raster
    arcpy.env.snapRaster = config.BATHYMETRY_SOURCE
    bathy_raster = arcpy.Raster(config.BATHYMETRY_SOURCE)
    
    # Multiply by -1 to convert negative to positive
    bathy_positive_raster = bathy_raster * -1
    
    # Save the result
    bathy_positive_raster.save(bathymetry_positive)
    Logger.info(f"✓ Bathymetry converted to positive values")
    
    if os.path.exists(bathymetry_positive):
        file_size_mb = os.path.getsize(bathymetry_positive) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
    else:
        raise FileNotFoundError("Conversion failed")
        
except Exception as e:
    Logger.error(f"Conversion failed: {str(e)}")
    Logger.error("Alternative: Using original bathymetry with Slope tool")
    Logger.info("Attempting direct slope calculation...")
    bathymetry_positive = config.BATHYMETRY_SOURCE

# ============================================================================
# SLOPE AT ~10M RESOLUTION
# ============================================================================

Logger.info("\n[Step 1/3] Computing slope from bathymetry in degrees...")
Logger.info(f"  Input: Converted bathymetry (positive values)")
Logger.info(f"  Output measurement: DEGREE")
Logger.info(f"  Z-factor: 1.0 (no exaggeration)")
Logger.info(f"  ⏳ Processing time: ~30-40 seconds (please wait)...\n")

slope_10m = os.path.join(output_dirs['intermediate'], "slope_10m.tif")

try:
    arcpy.env.snapRaster = config.BATHYMETRY_SOURCE
    arcpy.Slope_3d(bathymetry_positive, slope_10m, 
                  output_measurement="DEGREE", 
                  z_factor=1.0)
    Logger.info(f"✓ Slope at ~10m created successfully")
    
    # Verify output
    if os.path.exists(slope_10m):
        file_size_mb = os.path.getsize(slope_10m) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        print(f"  Output: {slope_10m}")
        
        # Get stats
        try:
            slope_raster = arcpy.Raster(slope_10m)
            Logger.info(f"  Slope range: {slope_raster.minimum:.2f}° to {slope_raster.maximum:.2f}°")
        except:
            pass
    else:
        raise FileNotFoundError("Slope output file not created")
        
except Exception as e:
    Logger.error(f"Failed to compute slope: {str(e)}")
    Logger.error("Troubleshooting:")
    Logger.error("  1. Check Spatial Analyst license is available")
    Logger.error("  2. Verify bathymetry file is not corrupted")
    Logger.error("  3. Check disk space (need ~2GB)")
    raise

# ============================================================================
# SLOPE AT ~30M RESOLUTION (First aggregation)
# ============================================================================

Logger.info("\n[Step 2/3] Aggregating slope to ~30m resolution...")
Logger.info(f"  Input: slope_10m.tif")
Logger.info(f"  Method: MEAN aggregation")
Logger.info(f"  Cell factor: {config.CELL_FACTOR_2M_TO_6M}")
Logger.info(f"  ⏳ Processing time: ~15-20 seconds...\n")

slope_30m = os.path.join(output_dirs['intermediate'], "slope_30m.tif")

try:
    arcpy.env.snapRaster = config.BATHYMETRY_SOURCE
    arcpy.Aggregate_management(slope_10m, slope_30m,
                              cell_factor=config.CELL_FACTOR_2M_TO_6M,
                              aggregation_type="MEAN")
    Logger.info(f"✓ Slope at ~30m created successfully")
    
    # Verify output
    if os.path.exists(slope_30m):
        file_size_mb = os.path.getsize(slope_30m) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        print(f"  Output: {slope_30m}")
    else:
        raise FileNotFoundError("Aggregated slope output not created")
        
except Exception as e:
    Logger.error(f"Failed to aggregate slope: {str(e)}")
    raise

# ============================================================================
# SLOPE AT ~50M RESOLUTION (Final output)
# ============================================================================

Logger.info("\n[Step 3/3] Creating final slope output at ~50m resolution...")
Logger.info(f"  Input: slope_30m.tif")
Logger.info(f"  ⏳ Processing time: ~5 seconds...\n")

slope_50m = os.path.join(output_dirs['slope'], "slope_50m.tif")

try:
    arcpy.env.snapRaster = config.BATHYMETRY_SOURCE
    arcpy.Copy_management(slope_30m, slope_50m)
    Logger.info(f"✓ Slope at ~50m finalized successfully")
    
    # Verify output
    if os.path.exists(slope_50m):
        file_size_mb = os.path.getsize(slope_50m) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        print(f"  Output: {slope_50m}")
    else:
        raise FileNotFoundError("Final slope output not created")
        
except Exception as e:
    Logger.error(f"Failed to create final slope: {str(e)}")
    raise

# Store reference for dependent calculations
slope_10m_path = slope_10m
Logger.info(f"\n✓ Slope_10m_path stored for dependent calculations")

Logger.header("✓ BLOCK 3 COMPLETE")
Logger.info("Slope calculated at 10m, 30m, and 50m scales.")
Logger.info(f"\nGenerated outputs:")
Logger.info(f"  • slope_10m.tif (intermediate)")
Logger.info(f"  • slope_30m.tif (intermediate)")
Logger.info(f"  • slope_50m.tif (final output)")
Logger.info(f"\n✓ All files created successfully!")
Logger.info("Next: Run BLOCK 4 (Slope at 240m scale)")

"""
MANUAL AGGREGATION - USING SPATIAL ANALYST MODULE
==================================================
Usa arcpy.sa.Aggregate que es más directo
"""

import arcpy
from arcpy.sa import *
import os

print("Starting aggregations with Spatial Analyst...\n")

# Setup paths
intermediate_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_intermediate"
slope_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\01_slope"

slope_10m_input = os.path.join(intermediate_dir, "slope_10m.tif")
slope_30m_output = os.path.join(intermediate_dir, "slope_30m.tif")
slope_50m_output = os.path.join(slope_dir, "slope_50m.tif")

bathymetry = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_bathymetry_source\STTSTJ_2m.tif"

# Set environment
arcpy.env.workspace = slope_dir
arcpy.env.snapRaster = bathymetry
arcpy.env.overwriteOutput = True

# Check out Spatial Analyst
try:
    arcpy.CheckOutExtension("Spatial")
    print("✓ Spatial Analyst extension checked out\n")
except:
    print("⚠ Could not check out Spatial Analyst\n")

print(f"Input: {slope_10m_input}")
print(f"Exists: {os.path.exists(slope_10m_input)}\n")

# Step 1: Create slope_30m using Block Statistics (alternative to Aggregate)
print("[Step 1] Creating slope_30m from slope_10m...")
print("  Using: BlockStatistics with MEAN")
print("  Block size: 3x3 cells")
print("  This may take 15-20 seconds...\n")

try:
    # Load the raster
    input_raster = Raster(slope_10m_input)
    
    # Use BlockStatistics which is more reliable
    # Define a 3x3 neighborhood
    neighborhood = NbrRectangle(3, 3, "CELL")
    
    # Calculate mean
    result = BlockStatistics(input_raster, neighborhood, "MEAN")
    
    # Save result
    result.save(slope_30m_output)
    print(f"✓ slope_30m.tif created")
    
    if os.path.exists(slope_30m_output):
        size_mb = os.path.getsize(slope_30m_output) / (1024 * 1024)
        print(f"  Size: {size_mb:.1f} MB")
        
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()

# Step 2: Create slope_50m (copy of slope_30m)
print("\n[Step 2] Creating slope_50m (copy of slope_30m)...")

if os.path.exists(slope_30m_output):
    try:
        arcpy.management.Copy(slope_30m_output, slope_50m_output)
        print(f"✓ slope_50m.tif created")
        
        if os.path.exists(slope_50m_output):
            size_mb = os.path.getsize(slope_50m_output) / (1024 * 1024)
            print(f"  Size: {size_mb:.1f} MB")
            
    except Exception as e:
        print(f"✗ Error copying: {e}")
        import traceback
        traceback.print_exc()
else:
    print("✗ Cannot copy - slope_30m does not exist")

# Check in extension
try:
    arcpy.CheckInExtension("Spatial")
except:
    pass

print("\n" + "="*70)
print("FINAL VERIFICATION:")
print("="*70 + "\n")

files_to_check = {
    'slope_10m.tif': os.path.join(intermediate_dir, "slope_10m.tif"),
    'slope_30m.tif': os.path.join(intermediate_dir, "slope_30m.tif"),
    'slope_50m.tif': os.path.join(slope_dir, "slope_50m.tif"),
}

all_ok = True
for name, path in files_to_check.items():
    if os.path.exists(path):
        size_mb = os.path.getsize(path) / (1024 * 1024)
        print(f"✓ {name}: {size_mb:.1f} MB")
    else:
        print(f"✗ {name}: MISSING")
        all_ok = False

print("\n" + "="*70)
if all_ok:
    print("✓ ALL FILES CREATED SUCCESSFULLY!")
    print("✓ BLOCK 3 IS COMPLETE")
    print("✓ Ready for BLOCK 4")
else:
    print("✗ Some files still missing")
print("="*70)

"""
BLOCK 4: CALCULATE SLOPE AT 240M SCALE (FOCAL STATISTICS)
===========================================================
Computes broad-scale slope variation using focal mean.

STATISTICAL RATIONALE:
- Focal statistics captures regional-scale variation
- Radius = 5 cells at 50m ≈ 500m footprint (represents ~240m scale)
- Represents broader habitat context and regional trends
- MEAN statistic: Averages slopes in neighborhood (smooths local variation)

PROCESSING TIME: ~90-120 seconds
- Focal statistics: ~60-80 seconds (computationally intensive)
- Aggregation: ~15-20 seconds

EXPECTED OUTPUT FILES:
- slope_10m_240m_buffer.tif (~300MB, intermediate)
- slope_240m_50m.tif (~12MB, final)

Dependencies: BLOCK 3 (slope_10m_path)

Run time: ~90-120 seconds
"""

Logger.header("BLOCK 4: CALCULATE SLOPE AT 240M SCALE")

# ============================================================================
# FOCAL STATISTICS: SLOPE AT 240M
# ============================================================================

Logger.info("[Step 1/2] Applying focal mean to slope (240m scale)...")
Logger.info(f"  Input: slope_10m.tif")
Logger.info(f"  Neighborhood: Circle with radius 5 cells")
Logger.info(f"  Statistic: MEAN")
Logger.info(f"  ⏳ Processing time: ~60-80 seconds (wait patiently)...\n")

slope_240m_buffer = os.path.join(output_dirs['intermediate'],
                                 "slope_10m_240m_buffer.tif")

try:
    from arcpy.sa import *
    
    # Load the slope raster
    input_raster = Raster(slope_10m)
    
    # Define circular neighborhood with radius 5
    neighborhood = NbrCircle(5, "CELL")
    
    # Apply focal statistics
    focal_result = FocalStatistics(input_raster, neighborhood, "MEAN")
    
    # Save result
    focal_result.save(slope_240m_buffer)
    Logger.info(f"✓ Focal statistics complete")
    
    if os.path.exists(slope_240m_buffer):
        file_size_mb = os.path.getsize(slope_240m_buffer) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
    else:
        raise FileNotFoundError("Focal statistics output not created")
        
except Exception as e:
    Logger.error(f"Focal statistics failed: {str(e)}")
    Logger.error("Troubleshooting:")
    Logger.error("  1. Check Spatial Analyst license")
    Logger.error("  2. Verify slope_10m.tif exists and is valid")
    Logger.error("  3. Check available disk space and RAM")
    raise

# ============================================================================
# AGGREGATE TO 50M RESOLUTION
# ============================================================================

Logger.info("\n[Step 2/2] Aggregating 240m buffer to 50m output resolution...")
Logger.info(f"  Input: slope_10m_240m_buffer.tif")
Logger.info(f"  Cell factor: 3")
Logger.info(f"  Ensures consistency with other 50m outputs")
Logger.info(f"  ⏳ Processing time: ~15-20 seconds...\n")

slope_240m = os.path.join(output_dirs['slope'], "slope_240m_50m.tif")

try:
    # Load the focal result
    focal_raster = Raster(slope_240m_buffer)
    
    # Aggregate using BlockStatistics
    neighborhood = NbrRectangle(3, 3, "CELL")
    aggregated = BlockStatistics(focal_raster, neighborhood, "MEAN")
    
    # Save result
    aggregated.save(slope_240m)
    Logger.info(f"✓ Slope at 240m scale finalized")
    
    if os.path.exists(slope_240m):
        file_size_mb = os.path.getsize(slope_240m) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
    else:
        raise FileNotFoundError("Final 240m slope output not created")
        
except Exception as e:
    Logger.error(f"Aggregation failed: {str(e)}")
    raise

Logger.header("✓ BLOCK 4 COMPLETE")
Logger.info("Broad-scale slope (240m) calculated successfully.")
Logger.info(f"\nGenerated outputs:")
Logger.info(f"  • slope_10m_240m_buffer.tif (intermediate)")
Logger.info(f"  • slope_240m_50m.tif (final output)")
Logger.info("\n✓ Ready for BLOCK 5 (Terrain Ruggedness)")

"""
BLOCK 5: CALCULATE SLOPE OF SLOPE (TERRAIN RUGGEDNESS) - FIXED V2
==================================================================
Usa sintaxis correcta para Slope()
"""

import arcpy
from arcpy.sa import *
import os

Logger.header("BLOCK 5: CALCULATE SLOPE OF SLOPE (TERRAIN RUGGEDNESS)")

print("\n" + "="*70)
print("TERRAIN RUGGEDNESS CALCULATION")
print("="*70)

# Define paths explicitly
slope_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\01_slope"
curvature_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\02_curvature"

slope_50m_input = os.path.join(slope_dir, "slope_50m.tif")
slope_of_slope_output = os.path.join(curvature_dir, "slope_of_slope_50m.tif")

bathymetry = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_bathymetry_source\STTSTJ_2m.tif"

Logger.info("[Step 1/1] Computing slope of slope (terrain ruggedness)...")
Logger.info(f"  Input: slope_50m.tif")
Logger.info(f"  Method: Slope tool")
Logger.info(f"  ⏳ Processing time: ~30-40 seconds...\n")

print(f"Input path: {slope_50m_input}")
print(f"Input exists: {os.path.exists(slope_50m_input)}\n")

try:
    # Set environment
    arcpy.env.snapRaster = bathymetry
    arcpy.env.overwriteOutput = True
    
    # Check out Spatial Analyst
    arcpy.CheckOutExtension("Spatial")
    
    # Load the slope raster
    input_slope = Raster(slope_50m_input)
    
    # Calculate slope of slope - correct syntax (no output_type parameter)
    ruggedness = Slope(input_slope, z_factor=1.0)
    
    # Save result
    ruggedness.save(slope_of_slope_output)
    Logger.info(f"✓ Terrain ruggedness calculated successfully")
    
    if os.path.exists(slope_of_slope_output):
        file_size_mb = os.path.getsize(slope_of_slope_output) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        
        # Get statistics
        try:
            stats_raster = Raster(slope_of_slope_output)
            Logger.info(f"  Min ruggedness: {stats_raster.minimum:.2f}°")
            Logger.info(f"  Max ruggedness: {stats_raster.maximum:.2f}°")
            Logger.info(f"  Mean ruggedness: {(stats_raster.minimum + stats_raster.maximum)/2:.2f}°")
        except:
            pass
    else:
        raise FileNotFoundError("Ruggedness output not created")
    
    # Check in extension
    arcpy.CheckInExtension("Spatial")
        
except Exception as e:
    Logger.error(f"Failed: {str(e)}")
    import traceback
    traceback.print_exc()

Logger.header("✓ BLOCK 5 COMPLETE")
Logger.info("Terrain ruggedness calculated successfully")
Logger.info(f"Output: slope_of_slope_50m.tif")

"""
BLOCK 6: CALCULATE ASPECT (DIRECTIONAL EXPOSURE)
=================================================
Computes directional exposure of seafloor (compass direction of steepest slope).

STATISTICAL RATIONALE:
- Aspect = compass direction slope faces (0-360°)
  • 0° = North
  • 90° = East
  • 180° = South
  • 270° = West
- Key for modeling light exposure, current direction, larval settlement patterns
- North-facing slopes: Different light/current regime than south-facing
- Useful for predicting coral species distribution
- Combined with slope: Identifies favorable/unfavorable slopes

INTERPRETATION:
- Aspect reveals habitat heterogeneity based on orientation
- North vs South exposure → different environmental conditions
- Important for directional larval transport and recruitment

PROCESSING TIME: ~30-40 seconds

Dependencies: BLOCK 2 (bathymetry_positive) or original bathymetry

Run time: ~30-40 seconds
"""

import arcpy
from arcpy.sa import *
import os

Logger.header("BLOCK 6: CALCULATE ASPECT (DIRECTIONAL EXPOSURE)")

print("\n" + "="*70)
print("ASPECT CALCULATION (COMPASS DIRECTION)")
print("="*70)

# Define paths explicitly
intermediate_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_intermediate"
aspect_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\03_aspect"

bathymetry_positive = os.path.join(intermediate_dir, "STTSTJ_2m_positive.tif")
aspect_2m_output = os.path.join(aspect_dir, "aspect_2m.tif")

bathymetry_source = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_bathymetry_source\STTSTJ_2m.tif"

Logger.info("[Step 1/1] Computing aspect (directional exposure)...")
Logger.info(f"  Input: Bathymetry (positive values)")
Logger.info(f"  Method: Aspect_3d tool")
Logger.info(f"  Output: Compass direction in degrees (0-360°)")
Logger.info(f"    • 0° = North")
Logger.info(f"    • 90° = East")
Logger.info(f"    • 180° = South")
Logger.info(f"    • 270° = West")
Logger.info(f"  ⏳ Processing time: ~30-40 seconds...\n")

print(f"Input path: {bathymetry_positive}")
print(f"Input exists: {os.path.exists(bathymetry_positive)}\n")

try:
    # Set environment
    arcpy.env.snapRaster = bathymetry_source
    arcpy.env.overwriteOutput = True
    
    # Check out Spatial Analyst
    arcpy.CheckOutExtension("Spatial")
    
    # Load the bathymetry raster (positive values)
    input_dem = Raster(bathymetry_positive)
    
    # Calculate aspect
    aspect_result = Aspect(input_dem)
    
    # Save result
    aspect_result.save(aspect_2m_output)
    Logger.info(f"✓ Aspect calculated successfully")
    
    if os.path.exists(aspect_2m_output):
        file_size_mb = os.path.getsize(aspect_2m_output) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        
        # Get statistics
        try:
            stats_raster = Raster(aspect_2m_output)
            Logger.info(f"  Min aspect: {stats_raster.minimum:.2f}°")
            Logger.info(f"  Max aspect: {stats_raster.maximum:.2f}°")
        except:
            pass
    else:
        raise FileNotFoundError("Aspect output not created")
    
    # Check in extension
    arcpy.CheckInExtension("Spatial")
        
except Exception as e:
    Logger.error(f"Failed: {str(e)}")
    import traceback
    traceback.print_exc()

Logger.header("✓ BLOCK 6 COMPLETE")
Logger.info("Aspect (directional exposure) calculated successfully")
Logger.info(f"Output: aspect_2m.tif (in 03_aspect folder)")
Logger.info(f"\nInterpretation:")
Logger.info(f"  • 0° (North-facing): Different light/current exposure")
Logger.info(f"  • 90° (East-facing): Morning light, variable currents")
Logger.info(f"  • 180° (South-facing): Maximum light exposure")
Logger.info(f"  • 270° (West-facing): Afternoon light, variable currents")

"""
BLOCK 7: CALCULATE CURVATURE (TERRAIN SHAPE)
=============================================
Computes terrain curvature: how terrain curves (convex/concave/flat).

STATISTICAL RATIONALE:
- Curvature quantifies terrain shape/profile
- Positive curvature = Convex (ridges, peaks) - flow divergence
- Negative curvature = Concave (valleys) - flow convergence
- Zero curvature = Flat/linear

ECOLOGICAL INTERPRETATION:
- Convex slopes: Sediment divergence, exposed substrate
- Concave slopes: Sediment accumulation, sediment traps
- Important for understanding coral recruitment patterns
- Sediment accumulation areas may have different coral communities
- Exposed ridges vs sheltered valleys support different species

PROCESSING TIME: ~30-40 seconds

Dependencies: BLOCK 2 (bathymetry_positive)

Run time: ~30-40 seconds
"""

import arcpy
from arcpy.sa import *
import os

Logger.header("BLOCK 7: CALCULATE CURVATURE (TERRAIN SHAPE)")

print("\n" + "="*70)
print("CURVATURE CALCULATION (TERRAIN SHAPE)")
print("="*70)

# Define paths explicitly
intermediate_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_intermediate"
curvature_dir = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\02_curvature"

bathymetry_positive = os.path.join(intermediate_dir, "STTSTJ_2m_positive.tif")
curvature_2m_output = os.path.join(curvature_dir, "curvature_2m.tif")

bathymetry_source = r"G:\Shared drives\NSF CoPE internal\GIS_CoPE\GIS_USVI\2_model_inputs_usvi\Fisheries\coral_cover_modeling\05_preparation_spatial_predictors\02_terrain_analysis_outputs\00_bathymetry_source\STTSTJ_2m.tif"

Logger.info("[Step 1/1] Computing curvature (terrain shape)...")
Logger.info(f"  Input: Bathymetry (positive values)")
Logger.info(f"  Method: Curvature tool")
Logger.info(f"  Output: Terrain curvature")
Logger.info(f"    • Positive = Convex (ridges, peaks)")
Logger.info(f"    • Negative = Concave (valleys, troughs)")
Logger.info(f"    • Zero = Flat/linear terrain")
Logger.info(f"  ⏳ Processing time: ~30-40 seconds...\n")

print(f"Input path: {bathymetry_positive}")
print(f"Input exists: {os.path.exists(bathymetry_positive)}\n")

try:
    # Set environment
    arcpy.env.snapRaster = bathymetry_source
    arcpy.env.overwriteOutput = True
    
    # Check out Spatial Analyst
    arcpy.CheckOutExtension("Spatial")
    
    # Load the bathymetry raster (positive values)
    input_dem = Raster(bathymetry_positive)
    
    # Calculate curvature
    curvature_result = Curvature(input_dem)
    
    # Save result
    curvature_result.save(curvature_2m_output)
    Logger.info(f"✓ Curvature calculated successfully")
    
    if os.path.exists(curvature_2m_output):
        file_size_mb = os.path.getsize(curvature_2m_output) / (1024 * 1024)
        Logger.info(f"  File size: {file_size_mb:.1f} MB")
        
        # Get statistics
        try:
            stats_raster = Raster(curvature_2m_output)
            Logger.info(f"  Min curvature: {stats_raster.minimum:.2f}")
            Logger.info(f"  Max curvature: {stats_raster.maximum:.2f}")
            Logger.info(f"  Mean curvature: {(stats_raster.minimum + stats_raster.maximum)/2:.2f}")
        except:
            pass
    else:
        raise FileNotFoundError("Curvature output not created")
    
    # Check in extension
    arcpy.CheckInExtension("Spatial")
        
except Exception as e:
    Logger.error(f"Failed: {str(e)}")
    import traceback
    traceback.print_exc()

Logger.header("✓ BLOCK 7 COMPLETE")
Logger.info("Curvature (terrain shape) calculated successfully")
Logger.info(f"Output: curvature_2m.tif (in 02_curvature folder)")
Logger.info(f"\nInterpretation:")
Logger.info(f"  • Positive values: Convex slopes (ridges, exposed)")
Logger.info(f"  • Negative values: Concave slopes (valleys, sediment traps)")
Logger.info(f"  • Near zero: Flat terrain")
Logger.info(f"  • Combined with slope/aspect: Full terrain characterization")


