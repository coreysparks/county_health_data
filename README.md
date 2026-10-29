# County Health Explorer

An interactive R Shiny application for mapping and spatially analyzing county-level public health indicators across the United States, built by [Corey Sparks, Ph.D.](https://www.linkedin.com/in/corey-sparks-ph-d/)

---

## Overview

This application integrates two national public health datasets — **County Health Rankings & Roadmaps (CHR&R)** and **CDC PLACES** — to produce interactive county-level choropleth maps and local spatial autocorrelation analyses for all 50 states and the District of Columbia (~3,100 counties).

---

## Features

### Page 1 — Choropleth Map
- Select any of the 53 available health indicators (13 CHR&R, 40 PLACES)
- Filter by data source (CHR&R, PLACES, or all)
- Choose color palette, classification scheme (quantile, Jenks natural breaks, equal interval), and number of classes
- Light grey county boundaries with narrow black state boundaries
- Click any county to view a full table of all its indicator values

### Page 2 — Spatial Autocorrelation (LISA)
- Three local spatial statistics using asymptotic normal approximation:
  - **Local Moran's I** — identifies HH, LL, HL, LH clusters and spatial outliers
  - **Local G (Getis-Ord)** — identifies hot spots and cold spots
  - **Local G\*** (Getis-Ord) — includes focal unit in neighbor set
- K = 4 nearest-neighbor spatial weights
- Adjustable significance level
- Global Moran's I summary (I, E[I], Var[I], z-score, p-value)
- Cluster count table

### Page 3 — Data Sources
- Full documentation, methodology notes, and links for all data sources and spatial methods

---

## Data Sources

| Dataset | Publisher | Release | Measures |
|---------|-----------|---------|----------|
| [County Health Rankings & Roadmaps](https://www.countyhealthrankings.org) | UW Population Health Institute / RWJF | 2025 | 13 (premature death, uninsured, preventable hospitalizations, air pollution, unemployment, poverty, STIs, mammography, flu vaccinations, school funding, alcohol-impaired driving) |
| [CDC PLACES](https://www.cdc.gov/places/index.html) | CDC Division of Population Health | 2025 (data year 2023) | 40 (health outcomes, preventive services, risk behaviors, disabilities, health status, social needs) |
| [TIGER/Line Shapefiles](https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html) | U.S. Census Bureau | 2022 (2020-vintage boundaries) | County and state geometries |

All datasets are joined on the 5-digit county FIPS code. The combined dataset is stored as a Parquet file for fast loading.

### Downloading Raw Data Files

The raw data files are **not included in this repository** (each exceeds 50 MB). Download them before running `prep_data.R` and place them in `data/raw/` with the filenames shown in the project structure below.

| File | Download |
|------|----------|
| `chr_trends_csv_2025.csv` | [CHR&R 2025 Downloads page](https://www.countyhealthrankings.org/health-data/methodology-and-sources/data-documentation) — select **"Trends Data"** for 2025 |
| `PLACES__Local_Data_for_Better_Health,_County_Data,_2025_release_*.csv` | [CDC PLACES County Data 2025 on data.cdc.gov](https://data.cdc.gov/500-Cities-Places/PLACES-Local-Data-for-Better-Health-County-Data-20/swc5-untb) — export as CSV |

---

## Project Structure

```
county_health_data/
├── app.R                          # Shiny application
├── prep_data.R                    # Data preparation script
├── README.md
├── data/
│   ├── raw/
│   │   ├── chr_trends_csv_2025.csv
│   │   ├── PLACES__Local_Data_for_Better_Health,_County_Data,_2025_release_*.csv
│   │   └── DataDictionary_2025.xlsx
│   └── processed/
│       └── county_health_merged.parquet   # Joined wide-format data
```

---

## Setup & Usage

### Requirements
R 4.x with the following packages:

```r
install.packages(c(
  "shiny", "bslib", "leaflet", "sf", "dplyr", "arrow",
  "classInt", "RColorBrewer", "sfdep", "spdep", "DT", "shinycssloaders"
))
```

### Prepare the data
Run once to build the merged Parquet file:

```r
source("prep_data.R")
```

### Launch the app
```r
shiny::runApp("app.R")
```

County and state boundaries are read from the bundled `data/processed/county_state_geometries.rds` (2022 cartographic boundary files, 1:20m, territories removed). To rebuild it, install `tigris` and run `tigris::counties()` / `tigris::states()` with `cb = TRUE, resolution = "20m", year = 2022`, drop the territory FIPS codes (60, 66, 69, 72, 78), transform to EPSG:4326, and `saveRDS()` a list with elements `counties` and `states`.

---

## Spatial Methods

- **Local Moran's I:** Anselin, L. (1995). Local indicators of spatial association—LISA. *Geographical Analysis*, 27(2), 93–115. https://doi.org/10.1111/j.1538-4632.1995.tb00338.x
- **Local G / G\*:** Getis, A., & Ord, J. K. (1992). The analysis of spatial association by use of distance statistics. *Geographical Analysis*, 24(3), 189–206. https://doi.org/10.1111/j.1538-4632.1992.tb00261.x
- Implemented via [`sfdep`](https://sfdep.josiahparry.com/) (Parry 2023) and [`spdep`](https://r-spatial.github.io/spdep/) (Bivand et al.)

---

## Deployment

The app is deployed on Posit Connect Cloud:
https://connect.posit.cloud/coreysparks/content/01a18972-3b02-7b0b-8610-ab1f1c14eb3d

It is published with the [Posit Publisher](https://docs.posit.co/publisher/) VS Code extension. The configuration lives in `.posit/publish/`, package dependencies are pinned in `renv.lock`, and the bundle includes `app.R` plus the two files in `data/processed/`. To update the deployment, open the Publisher panel, select the deployment, and click **Republish**.

---

## Notes

- PLACES estimates are model-based (MRP using BRFSS 2022/2021 + ACS 2018–2022) and should not be used for causal inference or program evaluation.
- CHR&R 2025 uses Health Groups rather than ordinal county rankings (introduced in 2024).
- Connecticut uses 9 planning regions as county equivalents per 2020 Census geographies; both datasets and the TIGER shapefiles are consistent on this.
- All spatial statistics use asymptotic normal approximation, not permutation-based inference.
