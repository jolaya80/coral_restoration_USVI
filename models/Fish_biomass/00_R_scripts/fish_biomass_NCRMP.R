####
library(dplyr)
library(rvc)
library(stringr)
library(stringi)

## Download data
# 
# or 2 specific years in 2 specific regions
USVI <- getRvcData(years = c(2017:2025), regions = c("STTSTJ", "STX")) # U.S. Virgin Islands


species_group_list <- "
Myripristis jacobus,Holocentridae
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

# Make data.frame
group_df <- read.csv(text = species_group_list, header = FALSE, col.names = c("SPECIES", "group"), strip.white=TRUE)

# Match taxonomic code using scientific name or as closely as possible
sp_table <- USVI$taxonomic_data

####  Obtain biomass estimations
gpsu_bio_grouped <- getPSUBiomass(
  USVI,
  species = group_df2$SPECIES_CD,
  group = group_df2
)

print(group_df2$SPECIES_CD)

##########################
## Get species-level PSU biomass
# Run getPSUBiomass() for ALL your species (no group param)
gpsu_bio_species <- getPSUBiomass(
  USVI,
  species = group_df2$SPECIES_CD
)

## Add group information by joining SPECIES_CD
# Your output gpsu_bio_species should have a column SPECIES_CD if not, 
# add it by using mutate() with the code you used as input, or check the output columns.
# Add group (family) name to species-level PSU biomass table
gpsu_bio_species <- gpsu_bio_species %>%
  left_join(
    group_df2 %>% select(SPECIES_CD, group, SPECIES),
    by = "SPECIES_CD"
  )

# Join lat/lon/depth data from sample_data
# Since LAT_DEGREES, LON_DEGREES, and DEPTH are in USVI$sample_data at the PRIMARY_SAMPLE_UNIT level, 
# build a lookup table:
psu_env <- USVI$sample_data %>%
  select(PRIMARY_SAMPLE_UNIT, LAT_DEGREES, LON_DEGREES, DEPTH) %>%
  distinct()

# Join this to your species-level data:
final_gpsu <- gpsu_bio_species %>%
  left_join(psu_env, by = "PRIMARY_SAMPLE_UNIT")

# Re-order/output as you wish (species, group, environment, biomass, etc)
final_gpsu <- final_gpsu %>%
  select(
    YEAR, REGION, STRAT, PROT, PRIMARY_SAMPLE_UNIT,
    SPECIES, SPECIES_CD, group, m, var, biomass,
    LAT_DEGREES, LON_DEGREES, DEPTH
  )

# Calculate mean (±SE) BIOMASS by YEAR, SPECIES, and GROUP
library(ggplot2)

plot_bio <- final_gpsu %>%
  group_by(YEAR, group, SPECIES) %>%
  summarise(
    mean_biomass = mean(biomass, na.rm=TRUE),
    se_biomass = sqrt(mean(var, na.rm=TRUE)), # or sd(biomass)/sqrt(n())
    .groups = "drop"
  )

plot_bio %>% 
  ggplot(aes(x = YEAR, y = mean_biomass, color = SPECIES, group = SPECIES)) +
  geom_line() +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean_biomass - se_biomass, ymax = mean_biomass + se_biomass),                  
                width = 0.25, size = 0.5) +
  theme_classic() +
  ylab("Biomass (kg per cylinder)") +
  xlab("Year") +
  ggtitle("Temporal Trends in Biomass by Group and Species") +
  facet_wrap(~ group, scales = "free_y") +
  theme(plot.title = element_text(hjust = 0.5))

library(ggrepel)

# Prepare data (summarize at species level by year/group)
plot_bio <- final_gpsu %>%
  group_by(YEAR, group, SPECIES_CD) %>%
  summarise(
    mean_biomass = mean(biomass, na.rm = TRUE),
    .groups = "drop"
  )

# Only get label for most recent year available per species/group combo
label_data <- plot_bio %>% 
  group_by(group, SPECIES_CD) %>% 
  filter(YEAR == max(YEAR)) %>%
  ungroup()

ggplot(plot_bio, aes(x = YEAR, y = mean_biomass, color = SPECIES_CD, group = SPECIES_CD)) +
  geom_line() +
  geom_point(size = 2) +
  
  ggrepel::geom_text_repel(
    data = label_data,
    aes(label = SPECIES_CD, color = SPECIES_CD),
    nudge_x = 0.2,  # nudges label slightly to the right
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
  ggtitle("Temporal Trends in Biomass by Group and Species") +
  theme(
    plot.title = element_text(hjust = 0.5),
    legend.position = "none"
  )
