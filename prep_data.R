#!/usr/bin/env Rscript
# prep_data.R
# Combines CHR 2025 and PLACES 2023 county-level data into a single parquet file.

library(data.table)
library(arrow)
library(dplyr)
library(tidyr)

cat("Loading CHR trends data...\n")
chr_raw <- fread(
  "data/raw/chr_trends_csv_2025.csv",
  colClasses = list(character = c("statecode", "countycode"))
)

# Keep 2025 release, county-level only (statecode != "00", countycode != "000")
chr <- chr_raw[
  chrreleaseyear == 2025 &
    statecode != "00" &
    countycode != "000"
]

# Build 5-digit FIPS
chr[, fips := paste0(
  formatC(statecode, width = 2, flag = "0"),
  formatC(countycode, width = 3, flag = "0")
)]

# Clean up rawvalue (remove commas, convert to numeric)
chr[, rawvalue := as.numeric(gsub(",", "", rawvalue))]

# Pivot to wide: one row per county, one column per measure
# Use measurename with spaces replaced by underscores, prefixed with "chr_"
chr[, col_name := paste0("chr_", gsub("[^a-zA-Z0-9]", "_", tolower(measurename)))]

# Keep key columns only
chr_wide <- dcast(
  chr[, .(fips, county, state, col_name, rawvalue)],
  fips + county + state ~ col_name,
  value.var = "rawvalue",
  fun.aggregate = mean,
  na.rm = TRUE
)

cat("CHR wide: ", nrow(chr_wide), "counties,", ncol(chr_wide) - 3, "measures\n")

cat("Loading PLACES data...\n")
places_raw <- fread(
  "data/raw/PLACES__Local_Data_for_Better_Health,_County_Data,_2025_release_20260305.csv"
)

# Use crude prevalence (CrdPrv), most recent year per measure
places <- places_raw[DataValueTypeID == "CrdPrv"]

# Zero-pad LocationID to 5 digits
places[, fips := formatC(LocationID, width = 5, flag = "0")]

# Use most recent year per measure+county
places <- places[order(-Year)]
places <- places[, .SD[1], by = .(fips, MeasureId)]

# Build column names: "places_" + short question text cleaned
places[, col_name := paste0("places_", gsub("[^a-zA-Z0-9]", "_", tolower(Short_Question_Text)))]
places[, col_name := gsub("_+", "_", col_name)]
places[, col_name := gsub("_$", "", col_name)]

# Keep only numeric data value
places[, data_value := as.numeric(Data_Value)]

# Pivot wide
places_wide <- dcast(
  places[, .(fips, StateAbbr, LocationName, col_name, data_value)],
  fips + StateAbbr + LocationName ~ col_name,
  value.var = "data_value",
  fun.aggregate = mean,
  na.rm = TRUE
)

cat("PLACES wide:", nrow(places_wide), "counties,", ncol(places_wide) - 3, "measures\n")

# Join
cat("Merging datasets...\n")
merged <- merge(
  chr_wide,
  places_wide[, !c("StateAbbr", "LocationName"), with = FALSE],
  by = "fips",
  all = TRUE
)

# Prefer CHR county/state names; fill in from PLACES where missing
merged[is.na(county) & !is.na(places_wide$LocationName[match(merged$fips, places_wide$fips)]),
       county := places_wide$LocationName[match(fips, places_wide$fips)]]
merged[is.na(state) & !is.na(places_wide$StateAbbr[match(merged$fips, places_wide$fips)]),
       state := places_wide$StateAbbr[match(fips, places_wide$fips)]]

cat("Merged:", nrow(merged), "counties,", ncol(merged), "total columns\n")

# Save as parquet
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
arrow::write_parquet(as.data.frame(merged), "data/processed/county_health_merged.parquet")
cat("Saved to data/processed/county_health_merged.parquet\n")

# Print column summary
measure_cols <- names(merged)[!names(merged) %in% c("fips", "county", "state")]
chr_cols <- measure_cols[startsWith(measure_cols, "chr_")]
places_cols <- measure_cols[startsWith(measure_cols, "places_")]
cat("\nCHR measures (", length(chr_cols), "):\n")
cat(paste(" ", chr_cols, collapse = "\n"), "\n")
cat("\nPLACES measures (", length(places_cols), "):\n")
cat(paste(" ", places_cols, collapse = "\n"), "\n")
