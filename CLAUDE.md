# CLAUDE.md — County Health Mapping Project

## Project Overview

This project integrates two complementary public health datasets — **County Health Rankings & Roadmaps (CHR&R)** and **CDC PLACES** — to produce a national choropleth map of U.S. counties visualizing key health indicators. The primary output is an interactive or static map at the county level spanning all 50 states and the District of Columbia. Data are already downloaded locally and do not need to be fetched programmatically.

---

## Data Sources

### 1. County Health Rankings & Roadmaps (CHR&R)

**Source:** University of Wisconsin Population Health Institute, funded by the Robert Wood Johnson Foundation  
**URL:** https://www.countyhealthrankings.org/health-data/methodology-and-sources/data-documentation  
**Geographic unit:** U.S. counties (~3,000+ counties)  
**Key identifier:** 5-digit FIPS code (`fipscode`), composed of `statecode` (2-digit) + `countycode` (3-digit)

**What CHR&R measures:**  
CHR&R publishes an Annual Data Release with approximately 80–90 measures organized around a model of health that includes both **health outcomes** and **health factors** (community conditions and societal rules). Measures span:

- Health outcomes: premature death (YPLL), self-rated health, mental health days, physical health days, low birthweight
- Health behaviors: adult smoking, adult obesity, physical inactivity, excessive drinking, sexually transmitted infections, teen births
- Clinical care: uninsured rates, primary care access, mental health provider ratios, preventable hospital stays, mammography, flu vaccinations
- Social and economic factors: high school graduation, some college, unemployment, income inequality, children in poverty, social associations, violent crime, injury deaths
- Physical environment: air pollution, drinking water violations, housing problems, severe housing cost burden, driving alone to work, long commutes

**Variable naming convention:**  
Variables follow the pattern `v###_rawvalue` (e.g., `v001_rawvalue` = Premature Death). Each measure also includes numerator, denominator, confidence interval bounds, a data quality flag (`0` = no flag, `1` = unreliable, `2` = suppressed), and racial/ethnic disaggregations where available (AIAN, Asian, Black, Hispanic, White, NHOPI, two or more races).

**Data files available:**
- **Analytic file** — wide-format county-level dataset with all measures, suitable for analysis
- **Ranked measures file** — includes only ranked measures
- **Additional measures file** — supplemental indicators not used in rankings
- Available as `.csv` and `.sas` format

**County coverage note:**  
Beginning with the 2024 release, CHR&R moved away from ordinal rankings and toward **Health Groups** — data-informed county clusters enabling more meaningful peer comparisons nationally. Not all counties are ranked (e.g., very small or data-sparse counties may be excluded). Connecticut introduced new **planning regions** in 2024 as county equivalents, replacing legacy county boundaries.

**Racial/ethnic disaggregation note:**  
Race/ethnicity categories follow 1997 OMB standards as collected by the U.S. Census Bureau. Intersecting categories and multiracial identities are not fully captured. Use disaggregated estimates with appropriate caution, particularly for small county-group cells flagged as unreliable or suppressed.

---

### 2. CDC PLACES: Local Data for Better Health

**Source:** CDC Division of Population Health, in partnership with the Robert Wood Johnson Foundation and CDC Foundation  
**URL:** https://www.cdc.gov/places/index.html  
**Geographic unit:** County, Place (incorporated/CDP), Census Tract, ZIP Code Tabulation Area (ZCTA)  
**Key identifier:** County FIPS code (5-digit); the county-level file covers **3,144 counties** across 50 states + DC

**What PLACES measures:**  
PLACES provides **40 measures** (2024 release) generated via small area estimation (SAE) using a multilevel regression and poststratification (MRP) methodology. The underlying data sources are BRFSS (2022 or 2021 depending on measure), the American Community Survey (ACS 2018–2022), and Census Bureau county population estimates. Estimates represent **model-based prevalences** — not direct survey estimates — and should not be used to evaluate local program or policy effects.

Measures are organized into six domains:

| Domain | Count | Examples |
|--------|-------|---------|
| Health outcomes | 12 | Arthritis, cancer, COPD, coronary heart disease, diabetes, obesity, stroke, depression, high blood pressure, high cholesterol, asthma, kidney disease |
| Preventive services | 7 | Colorectal cancer screening, mammography, cholesterol screening, dental visit, health insurance, annual checkup, cervical cancer screening |
| Health risk behaviors | 4 | Current smoking, binge drinking, physical inactivity, sleep <7 hours |
| Disabilities | 7 | Cognitive disability, hearing disability, vision disability, self-care disability, independent living disability, mobility disability, any disability |
| Health status | 3 | Self-rated health (fair/poor), mental health (14+ unhealthy days), physical health (14+ unhealthy days) |
| Health-related social needs (new in 2024) | 7 | Food insecurity, housing insecurity, utility service needs, transportation needs, social isolation/loneliness, lack of social and emotional support |

**Variable format:**  
Each measure is reported as a crude prevalence estimate and, where applicable, an age-adjusted prevalence. Confidence intervals are generated via Monte Carlo simulation (1,000 draws; 2.5th–97.5th percentile range). Column names follow a pattern such as `ARTHRITIS_CrudePrev`, `ARTHRITIS_Crude95CI`, `ARTHRITIS_AdjPrev`, etc.

**Geography note (important):**  
Starting with the 2024 release, PLACES uses **2020 Census geographies**, which includes Connecticut planning regions as county equivalents. This aligns with the CHR&R 2024 treatment of Connecticut. Ensure FIPS codes are joined consistently across both datasets using the 2020-vintage county definitions.

**Methodology caution:**  
PLACES estimates are modeled, not directly observed. They have well-validated correlations with direct BRFSS state and county estimates, but precision is lower for small, rural counties. Use confidence interval columns to assess reliability.

---

## Data Integration Notes

### Joining the Two Datasets

Both datasets use the 5-digit county FIPS code as the primary geographic identifier. CHR&R stores this as `fipscode`; PLACES stores it as `CountyFIPS` or equivalent (confirm column name in downloaded file). The join is straightforward:

```python
import pandas as pd

chr_df = pd.read_csv("chr_2024_analytic.csv", dtype={"fipscode": str})
places_df = pd.read_csv("places_county_2024.csv", dtype={"CountyFIPS": str})

# Ensure zero-padded 5-digit FIPS
chr_df["fipscode"] = chr_df["fipscode"].str.zfill(5)
places_df["CountyFIPS"] = places_df["CountyFIPS"].str.zfill(5)

merged_df = chr_df.merge(places_df, left_on="fipscode", right_on="CountyFIPS", how="outer")
```

Always use `dtype=str` when reading FIPS codes — leading zeros will be dropped if read as integers, silently corrupting joins for states like Alabama (01), Alaska (02), etc.

### Connecticut Boundary Changes

In 2024, Connecticut replaced its 8 legacy counties with 9 **planning regions**. Both CHR&R and PLACES have adopted these new geographies in their 2024 releases. If using shapefiles for mapping, confirm that the county boundary shapefile is also 2020-Census-vintage (e.g., Census TIGER/Line 2022 or later). Mismatched vintages will result in unmatched records for Connecticut.

### Coverage Discrepancies

CHR&R excludes some counties from ranking due to insufficient data; PLACES excludes geographies with fewer than 50 adult residents. An outer join will expose these gaps as NaN rows. Document coverage decisions clearly — either restrict to counties present in both datasets or retain all and handle missingness explicitly.

---

## Mapping Approach

### Geometry Source

Use the U.S. Census Bureau TIGER/Line county shapefiles (2022 or later for 2020-vintage boundaries). The `geopandas` library handles these well in Python:

```python
import geopandas as gpd

counties = gpd.read_file("tl_2022_us_county.shp")
counties["GEOID"] = counties["GEOID"].str.zfill(5)
counties = counties.merge(merged_df, left_on="GEOID", right_on="fipscode", how="left")
```

### Projection

Use **EPSG:5070** (Conus Albers / NAD83) for continental U.S. display. Alaska and Hawaii typically require separate inset panels or their own projections (EPSG:3338 for Alaska, EPSG:102007 or similar for Hawaii).

### Recommended Libraries

- `geopandas` — spatial joins and choropleth rendering
- `matplotlib` / `mapclassify` — static choropleth maps with classification schemes (Jenks, quantile, equal interval)
- `plotly` / `folium` — interactive maps with hover tooltips
- `contextily` — basemap tiles if needed

### Classification

For choropleth maps, prefer **quantile** or **natural breaks (Jenks)** classification over equal intervals, given the skewed distributions typical of health outcome data. Always include a legend with the classification thresholds and the data vintage year.

---

## Key Analytical Considerations

**Unit of analysis:** All mapping is at the county level (n ≈ 3,100). This is appropriate for identifying geographic patterns but masks within-county variation.

**Modeled vs. observed data:** CHR&R combines observed, survey-based, and modeled measures. PLACES measures are uniformly model-based. Neither dataset should be used for causal inference or program evaluation.

**Temporal alignment:** CHR&R 2024 draws on data from a range of source years (varies by measure). PLACES 2024 primarily uses 2022 BRFSS data, with 5 measures carried over from 2021 estimates. Document the data vintage of each specific indicator used rather than citing the release year alone.

**Suppressed/flagged values:** CHR&R flags unreliable estimates (`flag = 1`) and suppressed estimates (`flag = 2`). These should be excluded from visual encodings or mapped to a distinct "data not available" color. PLACES confidence intervals can serve a similar diagnostic function.

**Health equity:** Both datasets provide some racial/ethnic disaggregation. CHR&R disaggregates by race for select measures; PLACES does not currently provide subnational race-stratified estimates. Any equity-focused mapping should be framed carefully given these limitations.

---

## File Organization (Suggested)

```
project/
├── CLAUDE.md
├── data/
│   ├── raw/
│   │   ├── chr_2024_analytic.csv
│   │   ├── places_county_2024.csv
│   │   └── tl_2022_us_county/          # TIGER shapefiles
│   └── processed/
│       └── county_health_merged.gpkg   # GeoPackage with joined data
├── notebooks/
│   ├── 01_data_cleaning.ipynb
│   ├── 02_merge_and_validate.ipynb
│   └── 03_mapping.ipynb
├── outputs/
│   └── maps/
└── README.md
```

---

## Reference Links

- CHR&R Data & Documentation: https://www.countyhealthrankings.org/health-data/methodology-and-sources/data-documentation
- CHR&R 2024 Data Dictionary (PDF): https://www.countyhealthrankings.org/sites/default/files/media/document/DataDictionary_2024.pdf
- CHR&R Technical Documentation (PDF): https://www.countyhealthrankings.org/sites/default/files/media/document/2024%20CHRR%20Technical%20Document_1.pdf
- CDC PLACES Homepage: https://www.cdc.gov/places/index.html
- CDC PLACES Methodology: https://www.cdc.gov/places/methodology/index.html
- CDC PLACES Measure Definitions: https://www.cdc.gov/places/measure-definitions/index.html
- CDC PLACES Current Release Notes: https://www.cdc.gov/places/current-release-notes/index.html
- TIGER/Line Shapefiles: https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html
