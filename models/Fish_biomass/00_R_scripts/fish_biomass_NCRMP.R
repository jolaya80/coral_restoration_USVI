# 1. Load Packages ------------------------------------------------------------
library(dplyr)     # for data manipulation
library(rvc)       # for RVC fish data tools
library(stringr)   # (installed, not used, safe to leave here)
library(stringi)   # (installed, not used, safe to leave here)
library(ggplot2)   # for plotting
library(ggrepel)   # for non-overlapping plot labels

# 2. Download Data ------------------------------------------------------------
# Get all USVI data for specified years and regions
USVI <- getRvcData(years = c(2017:2025), regions = c("STTSTJ", "STX")) 

# 3. Group (Family) Table Construction ----------------------------------------
species_group_list <- "Myripristis jacobus,Holocentridae
Apogon aurolineatus,Apogonidae
Apogon binotatus,Apogonidae
Apogon lachneri,Apogonidae
Apogon maculatus,Apogonidae
Apogon phenax,Apogonidae
Apogon pseudomaculatus,Apogonidae
Apogon quadrisquamatus,Apogonidae
Apogon townsendi,Apogonidae
Haemulon flavolineatum,Haemulidae
Sparisoma aurofrenatum,Scaridae
Lutjanus apodus,Lutjanidae
Lutjanus jocu,Lutjanidae
Lutjanus mahogoni,Lutjanidae
Epinephelus guttatus,Epinephelidae
Chaetodon capistratus,Chaetodontidae
Chaetodon striatus,Chaetodontidae
Chaetodon ocellatus,Chaetodontidae
Chaetodon sedentarius,Chaetodontidae
Sparisoma viride,Scaridae
Microspathodon chrysurus,Pomacentridae
Canthigaster rostrata,Tetraodontidae
Stegastes planifrons,Pomacentridae
Stegastes partitus,Pomacentridae
Stegastes adustus,Pomacentridae
Stegastes leucostictus,Pomacentridae
Chromis cyanea,Pomacentridae
Chromis multilineata,Pomacentridae
Coryphopterus personatus,Gobiidae
Coryphopterus glaucofraenum,Gobiidae
Gobiosoma grosvenori,Gobiidae
Holocentrus rufus,Holocentridae
Thalassoma bifasciatum,Labridae
Halichoeres bivittatus,Labridae
Halichoeres burekae,Labridae
Halichoeres caudalis,Labridae
Halichoeres cyanocephalus,Labridae
Halichoeres garnoti,Labridae
Halichoeres maculipinna,Labridae
Halichoeres pictus,Labridae
Halichoeres poeyi,Labridae
Halichoeres radiatus,Labridae
Scarus iseri,Scaridae
"
group_df <- read.csv(text = species_group_list, header = FALSE, col.names = c("SPECIES", "group"), strip.white=TRUE)

# 4. Match SPECIES to Internal Code -------------------------------------------
# Get RVC taxonomic codes (SPECIES_CD) for all analysis species
sp_table <- USVI$taxonomic_data
group_df2 <- group_df %>% 
  left_join(sp_table %>% select(SPECIES_CD, SCINAME), by = c("SPECIES" = "SCINAME")) %>%
  filter(!is.na(SPECIES_CD)) # keep only matched species

# 5. Estimate Biomass at PSU Level for All Species ----------------------------
# Calculate mean biomass per PSU per species (no group parameter, for species-level)
gpsu_bio_species <- getPSUBiomass(
  USVI,
  species = group_df2$SPECIES_CD
)

# 6. Add Group & Environmental Data -------------------------------------------
# Attach group and species names, for reference and aggregation
gpsu_bio_species <- gpsu_bio_species %>%
  left_join(group_df2 %>% select(SPECIES_CD, group, SPECIES), by = "SPECIES_CD")

# Create a spatial/environmental lookup table (unique per PSU)
psu_env <- USVI$sample_data %>%
  select(PRIMARY_SAMPLE_UNIT, LAT_DEGREES, LON_DEGREES, DEPTH) %>%
  distinct(PRIMARY_SAMPLE_UNIT, .keep_all = TRUE) # ensures one row per PSU

# Join spatial/environmental info
final_gpsu <- gpsu_bio_species %>%
  left_join(psu_env, by = "PRIMARY_SAMPLE_UNIT")

# 7. Keep and Order Only Needed Columns ---------------------------------------
final_gpsu <- final_gpsu %>%
  select(
    YEAR, REGION, STRAT, PROT, PRIMARY_SAMPLE_UNIT,
    SPECIES, SPECIES_CD, group, m, var, biomass,
    LAT_DEGREES, LON_DEGREES, DEPTH
  )


#Summarize for Visualization (Species-Level within Groups) ----------
plot_bio <- final_gpsu %>%
  group_by(REGION, YEAR, group, SPECIES_CD) %>%
  summarise(
    mean_biomass = mean(biomass, na.rm = TRUE),
    .groups = "drop"
  )

# 2. Loop by region and plot one at a time
for (reg in unique(plot_bio$REGION)) {
  plot_bio_reg <- plot_bio %>% filter(REGION == reg)
  
  # Prepare label data (last year for each group/species)
  label_data_reg <- plot_bio_reg %>%
    group_by(group, SPECIES_CD) %>%
    filter(YEAR == max(YEAR)) %>%
    ungroup()
  
  p <- ggplot(plot_bio_reg, aes(x = YEAR, y = mean_biomass, color = SPECIES_CD, group = SPECIES_CD)) +
    geom_line() +
    geom_point(size = 2) +
    ggrepel::geom_text_repel(
      data = label_data_reg,
      aes(label = SPECIES_CD, color = SPECIES_CD),
      nudge_x = 0.2,
      direction = "y",
      hjust = 0,
      show.legend = FALSE,
      size = 3
    ) +
    scale_x_continuous(breaks = c(2017, 2019, 2021, 2023, 2025)) +
    facet_wrap(~ group, scales = "free_y") +
    theme_classic() +
    ylab("Biomass (kg per cylinder)") +
    xlab("Year") +
    ggtitle(paste("Temporal Trends in Biomass by Group and Species -", reg)) +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "none"
    )
  
  print(p)
  # Optionally, save:
  # ggsave(paste0("Temporal_Trends_", reg, ".png"), plot = p, width = 10, height = 7)
}

## General plot by group
# 1. Summarize: mean biomass & SE for each group (across all species) per year AND REGION
plot_group <- final_gpsu %>%
  group_by(REGION, YEAR, group) %>%
  summarise(
    mean_biomass = mean(biomass, na.rm = TRUE),
    se_biomass   = sd(biomass, na.rm = TRUE) / sqrt(sum(!is.na(biomass))),
    .groups      = "drop"
  )

# 2. Loop through regions and plot for each
for (reg in unique(plot_group$REGION)) {
  plot_group_reg <- plot_group %>% filter(REGION == reg)
  
  # Label data: last year per group within this region
  label_data_reg <- plot_group_reg %>%
    group_by(group) %>%
    filter(YEAR == max(YEAR)) %>%
    ungroup()
  
  p <- ggplot(plot_group_reg, aes(x = YEAR, y = mean_biomass, color = group, group = group)) +
    geom_line() +
    geom_point(size = 2) +
    geom_errorbar(
      aes(ymin = mean_biomass - se_biomass, ymax = mean_biomass + se_biomass), 
      width = 0.25, size = 0.5
    ) +
    ggrepel::geom_text_repel(
      data = label_data_reg,
      aes(label = group, color = group),
      nudge_x = 0.2,
      direction = "y",
      hjust = 0,
      show.legend = FALSE,
      size = 4
    ) +
    scale_x_continuous(breaks = c(2017, 2019, 2021, 2023, 2025)) +
    theme_classic() +
    ylab("Biomass (kg per cylinder)") +
    xlab("Year") +
    ggtitle(paste("Temporal Trends in Biomass by Group -", reg)) +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "none"
    )
  print(p)
  # Optionally save:
  # ggsave(paste0("Trend_by_group_", reg, ".png"), plot = p, width = 9, height = 6)
}


### Bar plot 2025
# 1. Filter to year 2025 and aggregate by group
bar_group <- final_gpsu %>%
  filter(YEAR == 2025) %>%
  group_by(group) %>%
  summarise(
    mean_biomass = mean(biomass, na.rm = TRUE),
    se_biomass = sd(biomass, na.rm = TRUE) / sqrt(sum(!is.na(biomass))),
    .groups = "drop"
  ) %>%
  mutate(group = reorder(group, -mean_biomass))  # Reorder factor for plotting

# Plot: Monochrome, sorted, with error bars
ggplot(bar_group, aes(x = group, y = mean_biomass)) +
  geom_col(fill = "grey60", width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_biomass - se_biomass, ymax = mean_biomass + se_biomass),
    width = 0.25, size = 0.8
  ) +
  geom_text(aes(label = round(mean_biomass, 2)), 
            vjust = -0.8, size = 5) + # Add value label above the bar
  theme_classic() +
  ylab("Mean Biomass (kg per cylinder)") +
  xlab("Group") +
  ggtitle("Group Biomass in 2025") +
  theme(
    plot.title    = element_text(hjust = 0.5, size = 18),
    axis.text.x   = element_text(angle = 45, hjust = 1, size = 16), # x axis tick labels
    axis.text.y   = element_text(size = 14),                        # y axis tick labels
    axis.title.x  = element_text(size = 16, margin = margin(t = 10)),
    axis.title.y  = element_text(size = 16, margin = margin(r = 10))
  )

# Prepare data for 2025, and order group by median biomass (optional but common for boxplots)
box_data <- final_gpsu %>%
  filter(YEAR == 2025) %>%
  group_by(group, PRIMARY_SAMPLE_UNIT) %>%
  summarise(
    group_biomass = mean(biomass, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(group = reorder(group, -group_biomass, FUN = median, na.rm = TRUE))

ggplot(box_data, aes(x = group, y = group_biomass)) +
  geom_boxplot(outlier.shape = NA, fill = "grey80", width = 0.7) +
  geom_jitter(width = 0.15, size = 2, alpha = 0.6, color = "black") +
  scale_y_log10() +
  ylab("Biomass (kg per cylinder, log10) per PSU") +
  xlab("Group") +
  ggtitle("Distribution of Group Biomass\n(per PSU, 2025, log scale)") +
  theme_classic() +
  theme(
    plot.title    = element_text(hjust = 0.5, size = 18),
    axis.text.x   = element_text(angle = 45, hjust = 1, size = 16),
    axis.text.y   = element_text(size = 14),
    axis.title.x  = element_text(size = 16, margin = margin(t = 10)),
    axis.title.y  = element_text(size = 16, margin = margin(r = 10))
  )

# Prepare data for 2025, reordered by median biomass per group (for boxplot position)
# Prepare data for 2025, and order species within group (optional: by median)
box_data <- final_gpsu %>%
  filter(YEAR == 2025) %>%
  group_by(group) %>%
  mutate(SPECIES_CD = reorder(SPECIES_CD, -biomass, FUN = median, na.rm = TRUE)) %>%
  ungroup()

ggplot(box_data, aes(x = SPECIES_CD, y = biomass, fill = SPECIES_CD)) +
  geom_boxplot(outlier.shape = NA, width = 0.7, alpha = 0.7) +
  geom_jitter(width = 0.15, size = 1.2, alpha = 0.6, color = "black") +
  scale_y_log10() +
  ylab("Biomass (kg per cylinder, log10)") +
  xlab("Species") +
  ggtitle("Distribution of Biomass by Species Within Groups (2025)") +
  facet_wrap(~ group, scales = "free_x") +
  theme_classic() +
  theme(
    plot.title    = element_text(hjust = 0.5, size = 18),
    strip.text    = element_text(size = 14), # facet labels
    axis.text.x   = element_text(angle = 45, hjust = 1, size = 11),
    axis.title.x  = element_text(size = 16, margin = margin(t = 10)),
    axis.title.y  = element_text(size = 16, margin = margin(r = 10)),
    axis.text.y   = element_text(size = 14)
  ) +
  guides(fill = "none") # optionally hide the fill legend; comment out for legend
