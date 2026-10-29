library(shiny)
library(bslib)
library(leaflet)
library(sf)
library(dplyr)
library(arrow)
library(classInt)
library(RColorBrewer)
library(sfdep)
library(spdep)
library(DT)
library(shinycssloaders)

# Resolve DT vs shiny naming conflict
dataTableOutput <- DT::dataTableOutput
renderDataTable <- DT::renderDataTable

# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------
load_health <- function() {
  hd <- arrow::read_parquet("data/processed/county_health_merged.parquet")
  hd$fips <- formatC(as.character(hd$fips), width = 5, flag = "0")
  hd
}

# Boundaries are precomputed from tigris (2022 cartographic boundary files, 1:20m,
# territories removed, EPSG:4326) so the deployed app needs no network access.
load_geo <- function() {
  readRDS("data/processed/county_state_geometries.rds")
}

# ---------------------------------------------------------------------------
# Label helper
# ---------------------------------------------------------------------------
col_label <- function(col) {
  lbl <- sub("^chr_",    "[CHR] ",    col)
  lbl <- sub("^places_", "[PLACES] ", lbl)
  lbl <- gsub("_+", " ", lbl)
  tools::toTitleCase(trimws(lbl))
}

indicator_choices <- function(health_data, source_filter) {
  all_cols    <- setdiff(names(health_data), c("fips", "county", "state"))
  chr_cols    <- all_cols[startsWith(all_cols, "chr_")]
  places_cols <- all_cols[startsWith(all_cols, "places_")]
  cols <- switch(source_filter,
    "CHR (County Health Rankings)" = chr_cols,
    "PLACES (CDC)"                 = places_cols,
    c(chr_cols, places_cols)
  )
  setNames(cols, sapply(cols, col_label))
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
ui <- page_navbar(
  title = div(
    style = "display:flex; flex-direction:column; line-height:1.2;",
    span("County Health Explorer", style = "font-weight:600;"),
    tags$a(
      "Corey Sparks, Ph.D.",
      href   = "https://www.linkedin.com/in/corey-sparks-ph-d/",
      target = "_blank",
      style  = "font-size:0.72em; font-weight:400; color:rgba(255,255,255,0.72);
                text-decoration:none;"
    )
  ),
  theme    = bs_theme(bootswatch = "flatly"),
  fillable = FALSE,

  # ---- PAGE 1: Choropleth map -------------------------------------------
  nav_panel(
    "Choropleth Map",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        selectInput("p1_source", "Data source",
          choices  = c("All", "CHR (County Health Rankings)", "PLACES (CDC)"),
          selected = "All"),
        selectInput("p1_indicator", "Indicator", choices = NULL),
        selectInput("p1_palette", "Color palette",
          choices  = c("YlOrRd", "YlGnBu", "RdPu", "BuPu", "Greens", "Blues", "Oranges", "Purples"),
          selected = "YlOrRd"),
        selectInput("p1_class", "Classification",
          choices  = c("quantile", "jenks", "equal"),
          selected = "quantile"),
        sliderInput("p1_n", "Number of classes", min = 3, max = 9, value = 5, step = 1),
        checkboxInput("p1_rev", "Reverse palette",      value = FALSE),
        checkboxInput("p1_na",  "Show missing as grey", value = TRUE),
        hr(),
        tags$small(tags$b("Click a county to see all its indicators."))
      ),
      withSpinner(leafletOutput("choro_map", height = "72vh"), type = 4),
      uiOutput("county_panel")
    )
  ),

  # ---- PAGE 2: LISA spatial autocorrelation ----------------------------
  nav_panel(
    "Spatial Autocorrelation (LISA)",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        selectInput("p2_source", "Data source",
          choices  = c("All", "CHR (County Health Rankings)", "PLACES (CDC)"),
          selected = "All"),
        selectInput("p2_indicator", "Indicator", choices = NULL),
        selectInput("p2_stat", "Statistic",
          choices = c(
            "Local Moran's I" = "moran",
            "Local G"         = "g",
            "Local G*"        = "gstar"
          ),
          selected = "moran"),
        tags$p(tags$b("Spatial weights:"), " K-nearest neighbors (k = 4)",
               class = "mb-1 mt-2", style = "font-size:0.9em"),
        numericInput("p2_alpha", "Significance level",  value = 0.05, min = 0.001, max = 0.1,  step = 0.005),
        actionButton("p2_run", "Run LISA", class = "btn-primary w-100 mt-2"),
        hr(),
        uiOutput("p2_legend_key")
      ),
      fluidRow(
        column(8,
          withSpinner(leafletOutput("lisa_map", height = "72vh"), type = 4)
        ),
        column(4,
          uiOutput("p2_global_header"),
          withSpinner(verbatimTextOutput("moran_out"), type = 4),
          hr(),
          h5("LISA cluster counts"),
          withSpinner(DTOutput("lisa_counts"), type = 4),
          hr(),
          tags$small(
            "Significance based on asymptotic normal approximation (two-sided)."
          )
        )
      )
    )
  ),

  # ---- PAGE 3: Data Sources -----------------------------------------------
  nav_panel(
    "Data Sources",
    div(class = "container mt-4", style = "max-width:860px;",

      h3("Data Sources & Documentation"),
      p(class = "text-muted",
        "This application integrates two national county-level public health datasets.",
        "Data are not collected or modified by this tool; all estimates originate from",
        "the sources listed below."),

      hr(),

      # CHR&R ----------------------------------------------------------------
      h4(tags$a("County Health Rankings & Roadmaps (CHR&R)",
                href   = "https://www.countyhealthrankings.org",
                target = "_blank")),
      p(tags$b("Publisher:"), " University of Wisconsin Population Health Institute,",
        "funded by the Robert Wood Johnson Foundation."),
      p(tags$b("Release used:"), " 2025 Annual Data Release (trends file)."),
      p(tags$b("Geographic unit:"), " U.S. counties (~3,100+); 5-digit FIPS code."),
      p(tags$b("Coverage:"), " 13 ranked and supplemental measures spanning premature",
        "death, uninsured rates, preventable hospitalizations, air pollution,",
        "unemployment, children in poverty, STIs, mammography, flu vaccinations,",
        "school funding, and alcohol-impaired driving deaths."),
      tags$ul(
        tags$li(tags$a("Data & Documentation home",
          href="https://www.countyhealthrankings.org/health-data/methodology-and-sources/data-documentation",
          target="_blank")),
        tags$li(tags$a("2025 Data Dictionary (PDF)",
          href="https://www.countyhealthrankings.org/sites/default/files/media/document/DataDictionary_2025.pdf",
          target="_blank")),
        tags$li(tags$a("Technical Documentation (PDF)",
          href="https://www.countyhealthrankings.org/sites/default/files/media/document/2025%20CHRR%20Technical%20Document.pdf",
          target="_blank"))
      ),
      p(class="text-muted", tags$small(
        "Note: beginning with the 2024 release, CHR&R replaced ordinal county rankings",
        "with Health Groups (data-informed peer clusters). Connecticut uses 9 planning",
        "regions as county equivalents per 2020 Census geographies."
      )),

      hr(),

      # CDC PLACES -----------------------------------------------------------
      h4(tags$a("CDC PLACES: Local Data for Better Health",
                href   = "https://www.cdc.gov/places/index.html",
                target = "_blank")),
      p(tags$b("Publisher:"), " CDC Division of Population Health, in partnership with",
        "the Robert Wood Johnson Foundation and CDC Foundation."),
      p(tags$b("Release used:"), " 2025 release (county-level file); primary data year 2023."),
      p(tags$b("Geographic unit:"), " 3,144 counties across 50 states + DC; 5-digit FIPS code."),
      p(tags$b("Coverage:"), " 40 model-based prevalence estimates across six domains:"),
      tags$ul(
        tags$li(tags$b("Health outcomes (12):"), " arthritis, cancer, COPD, coronary heart disease,",
          "diabetes, obesity, stroke, depression, high blood pressure, high cholesterol, asthma, kidney disease."),
        tags$li(tags$b("Preventive services (7):"), " colorectal cancer screening, mammography,",
          "cholesterol screening, dental visit, health insurance, annual checkup, cervical cancer screening."),
        tags$li(tags$b("Health risk behaviors (4):"), " current smoking, binge drinking,",
          "physical inactivity, short sleep duration."),
        tags$li(tags$b("Disabilities (7):"), " cognitive, hearing, vision, self-care,",
          "independent living, mobility, any disability."),
        tags$li(tags$b("Health status (3):"), " fair/poor general health, frequent mental distress,",
          "frequent physical distress."),
        tags$li(tags$b("Health-related social needs (7):"), " food insecurity, food stamps, housing",
          "insecurity, utility services threat, transportation barriers, loneliness,",
          "lack of social/emotional support.")
      ),
      p(class="text-muted", tags$small(
        "PLACES estimates are generated via multilevel regression and poststratification (MRP)",
        "using BRFSS 2022/2021, ACS 2018–2022, and Census Bureau population estimates.",
        "They are modeled prevalences, not direct survey estimates, and should not be used",
        "for causal inference or program evaluation."
      )),
      tags$ul(
        tags$li(tags$a("PLACES homepage",
          href="https://www.cdc.gov/places/index.html", target="_blank")),
        tags$li(tags$a("Methodology",
          href="https://www.cdc.gov/places/methodology/index.html", target="_blank")),
        tags$li(tags$a("Measure definitions",
          href="https://www.cdc.gov/places/measure-definitions/index.html", target="_blank")),
        tags$li(tags$a("2025 release notes",
          href="https://www.cdc.gov/places/current-release-notes/index.html", target="_blank"))
      ),

      hr(),

      # Geography ------------------------------------------------------------
      h4(tags$a("U.S. Census Bureau TIGER/Line Shapefiles",
                href   = "https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html",
                target = "_blank")),
      p(tags$b("Vintage:"), " 2022 (1:20,000,000 cartographic boundary files via the",
        tags$a("tigris", href="https://github.com/walkerke/tigris", target="_blank"),
        "R package)."),
      p(tags$b("Projection:"), " WGS 84 (EPSG:4326) for interactive display."),
      p(class="text-muted", tags$small(
        "The 2022 TIGER/Line files use 2020 Census county definitions, including Connecticut's",
        "9 planning regions, consistent with both CHR&R 2025 and PLACES 2025 geographies."
      )),

      hr(),

      # Spatial stats --------------------------------------------------------
      h4("Spatial Statistics Methods"),
      tags$ul(
        tags$li(
          tags$b("Local Moran's I: "),
          "Anselin, L. (1995). Local indicators of spatial association—LISA. ",
          tags$i("Geographical Analysis"), ", 27(2), 93–115. ",
          tags$a("https://doi.org/10.1111/j.1538-4632.1995.tb00338.x",
                 href="https://doi.org/10.1111/j.1538-4632.1995.tb00338.x", target="_blank")
        ),
        tags$li(
          tags$b("Local G / G*: "),
          "Getis, A., & Ord, J. K. (1992). The analysis of spatial association by use of distance statistics. ",
          tags$i("Geographical Analysis"), ", 24(3), 189–206. ",
          tags$a("https://doi.org/10.1111/j.1538-4632.1992.tb00261.x",
                 href="https://doi.org/10.1111/j.1538-4632.1992.tb00261.x", target="_blank")
        ),
        tags$li(
          tags$b("R packages: "),
          tags$a("sfdep", href="https://sfdep.josiahparry.com/", target="_blank"), " (Parry 2023); ",
          tags$a("spdep", href="https://r-spatial.github.io/spdep/", target="_blank"),
          " (Bivand et al.)"
        )
      ),

      hr(),
      p(class="text-muted", tags$small(
        "Built with R/Shiny · ",
        tags$a("Corey Sparks, Ph.D.",
               href="https://www.linkedin.com/in/corey-sparks-ph-d/",
               target="_blank"),
        " · Data vintage: CHR&R 2025, PLACES 2025 (data year 2023)"
      ))
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
server <- function(input, output, session) {

  # -- Reactive data -------------------------------------------------------
  health    <- reactive({ load_health() })
  geo       <- reactive({ load_geo()    })
  county_sf <- reactive({
    left_join(geo()$counties, health(), by = c("GEOID" = "fips"))
  })

  # -- Indicator dropdowns -------------------------------------------------
  update_choices <- function(session_id, source_id) {
    observeEvent(list(health(), input[[source_id]]), ignoreNULL = TRUE, {
      req(health())
      ch  <- indicator_choices(health(), input[[source_id]])
      cur <- input[[session_id]]
      updateSelectInput(session, session_id, choices = ch,
                        selected = if (!is.null(cur) && cur %in% ch) cur else ch[1])
    })
  }
  update_choices("p1_indicator", "p1_source")
  update_choices("p2_indicator", "p2_source")

  # ========================================================================
  # PAGE 1 — Choropleth map
  # ========================================================================
  output$choro_map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addProviderTiles("Esri.WorldGrayCanvas") |>
      setView(lng = -96, lat = 38, zoom = 4)
  })

  observeEvent(
    list(input$p1_indicator, input$p1_palette, input$p1_class,
         input$p1_n, input$p1_rev, input$p1_na, county_sf()),
    ignoreNULL = TRUE, {

    req(input$p1_indicator, county_sf())
    csf    <- county_sf()
    col    <- input$p1_indicator
    values <- csf[[col]]

    valid_vals <- values[!is.na(values) & is.finite(values)]
    if (length(unique(valid_vals)) < 2) return()

    pal_name <- if (input$p1_rev) paste0("-", input$p1_palette) else input$p1_palette
    brks <- tryCatch(
      classIntervals(valid_vals, n = input$p1_n, style = input$p1_class)$brks,
      error = function(e) quantile(valid_vals, probs = seq(0, 1, length.out = input$p1_n + 1),
                                    na.rm = TRUE)
    )
    brks    <- unique(brks)
    na_col  <- if (input$p1_na) "#AAAAAA88" else "#00000000"
    pal_fn  <- colorBin(pal_name, domain = values, bins = brks, na.color = na_col)

    labels <- sprintf(
      "<b>%s</b><br/>%s: %s",
      paste0(csf$NAME, ", ", csf$state),
      col_label(col),
      ifelse(is.na(values), "No data",
             formatC(values, format = "fg", digits = 4, big.mark = ","))
    ) |> lapply(htmltools::HTML)

    leafletProxy("choro_map") |>
      clearShapes() |> clearControls() |>
      addPolygons(
        data             = csf,
        fillColor        = ~pal_fn(get(col)),
        fillOpacity      = 0.75,
        color            = "#BBBBBB",
        weight           = 0.4,
        opacity          = 0.7,
        smoothFactor     = 0.3,
        label            = labels,
        layerId          = ~GEOID,
        highlightOptions = highlightOptions(
          weight = 1.8, color = "#444", fillOpacity = 0.9, bringToFront = TRUE
        )
      ) |>
      addPolylines(
        data         = geo()$states,
        color        = "#111111",
        weight       = 0.9,
        opacity      = 0.9,
        smoothFactor = 0.3
      ) |>
      addLegend(
        position = "bottomright",
        pal      = pal_fn,
        values   = values,
        title    = col_label(col),
        opacity  = 0.9,
        na.label = "No data"
      )
  })

  # County detail on click
  observeEvent(input$choro_map_shape_click, {
    click <- input$choro_map_shape_click
    req(click$id)
    hd  <- health()
    row <- hd[hd$fips == click$id, ]
    if (nrow(row) == 0) return()

    mcols <- setdiff(names(hd), c("fips", "county", "state"))
    df <- data.frame(
      Indicator = sapply(mcols, col_label),
      Value     = sapply(mcols, function(m) {
        v <- row[[m]]
        if (is.null(v) || is.na(v)) "—"
        else formatC(v, format = "fg", digits = 4, big.mark = ",")
      }),
      stringsAsFactors = FALSE
    )

    output$county_panel <- renderUI({
      div(class = "mt-3",
        wellPanel(
          h5(paste0(row$county[1], " (FIPS: ", click$id, ")"), style = "margin-top:0"),
          DT::datatable(df, rownames = FALSE,
                        options = list(pageLength = 10, dom = "tip", scrollY = "300px"),
                        class = "compact stripe")
        )
      )
    })
  })

  # ========================================================================
  # PAGE 2 — LISA
  # ========================================================================
  lisa_rv <- reactiveVal(NULL)

  output$lisa_map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addProviderTiles("Esri.WorldGrayCanvas") |>
      setView(lng = -96, lat = 38, zoom = 4)
  })

  observeEvent(input$p2_run, {
    req(input$p2_indicator, county_sf())

    withProgress(message = "Running LISA analysis...", value = 0, {

      csf    <- county_sf()
      col    <- input$p2_indicator
      values <- csf[[col]]

      # Subset to non-missing counties for weight computation
      valid  <- !is.na(values) & is.finite(values)
      if (sum(valid) < 20) {
        showNotification("Too few valid observations for LISA.", type = "warning")
        return()
      }
      csf_v  <- csf[valid, ]
      vals_v <- values[valid]

      setProgress(0.2, detail = "Building k=4 nearest-neighbor weights")
      nb <- tryCatch(
        st_knn(st_geometry(csf_v), k = 4L),
        error = function(e) {
          showNotification(paste("Neighbor error:", e$message), type = "error")
          NULL
        }
      )
      req(!is.null(nb))

      wts   <- st_weights(nb)
      listw <- sfdep::recreate_listw(nb, wts)
      stat  <- input$p2_stat

      setProgress(0.35, detail = "Computing global Moran's I")
      gmt <- tryCatch(global_moran_test(vals_v, nb, wts), error = function(e) NULL)

      setProgress(0.55, detail = paste("Computing local", switch(stat,
        moran = "Moran's I", g = "G", gstar = "G*")))

      if (stat == "moran") {
        # Asymptotic normal approximation via spdep::localmoran()
        lm <- tryCatch(
          spdep::localmoran(vals_v, listw, zero.policy = TRUE),
          error = function(e) {
            showNotification(paste("LISA error:", e$message), type = "error")
            NULL
          }
        )
        req(!is.null(lm))

        z_std <- scale(vals_v)[, 1]
        lag_z <- spdep::lag.listw(listw, z_std, zero.policy = TRUE)
        p_val <- lm[, "Pr(z != E(Ii))"]
        sig   <- !is.na(p_val) & p_val <= input$p2_alpha

        cluster <- rep("Not significant", length(vals_v))
        cluster[sig & z_std >  0 & lag_z >  0] <- "HH"
        cluster[sig & z_std <  0 & lag_z <  0] <- "LL"
        cluster[sig & z_std >  0 & lag_z <  0] <- "HL"
        cluster[sig & z_std <  0 & lag_z >  0] <- "LH"

        stat_vals <- lm[, "Ii"]
        stat_z    <- lm[, "Z.Ii"]
        p_sim     <- p_val

      } else {
        # Local G or G* — asymptotic normal approximation
        lg <- tryCatch(
          if (stat == "g") local_g(vals_v, nb, wts)
          else             local_gstar(vals_v, nb, wts),
          error = function(e) {
            showNotification(paste("LISA error:", e$message), type = "error")
            NULL
          }
        )
        req(!is.null(lg))

        p_val <- lg$p_value
        sig   <- !is.na(p_val) & p_val <= input$p2_alpha

        cluster <- rep("Not significant", length(vals_v))
        cluster[sig & lg$cluster == "High"] <- "Hot Spot"
        cluster[sig & lg$cluster == "Low"]  <- "Cold Spot"

        stat_col  <- if (stat == "g") "gi" else "gi_star"
        stat_vals <- lg[[stat_col]]
        stat_z    <- lg$std_dev
        p_sim     <- p_val
      }

      setProgress(0.9, detail = "Merging results")

      # Merge results into the full county sf (NA for excluded rows)
      csf$lisa_cluster <- NA_character_
      csf$lisa_stat    <- NA_real_
      csf$lisa_p_sim   <- NA_real_
      csf$lisa_z       <- NA_real_

      idx <- match(csf_v$GEOID, csf$GEOID)
      csf$lisa_cluster[idx] <- cluster
      csf$lisa_stat[idx]    <- stat_vals
      csf$lisa_p_sim[idx]   <- p_sim
      csf$lisa_z[idx]       <- stat_z

      lisa_rv(list(
        sf             = csf,
        stat           = stat,
        gmt            = gmt,
        cluster_counts = table(cluster)
      ))
    })
  })

  # Render LISA map
  observeEvent(lisa_rv(), {
    req(lisa_rv())
    res <- lisa_rv()
    csf <- res$sf

    stat <- res$stat

    cluster_pal <- if (stat == "moran") {
      c("HH" = "#d7191c", "LL" = "#2c7bb6", "HL" = "#fdae61",
        "LH" = "#4dac26", "Not significant" = "#e8e8e8")
    } else {
      c("Hot Spot" = "#d7191c", "Cold Spot" = "#2c7bb6", "Not significant" = "#e8e8e8")
    }

    # Attach color as a plain (unnamed) column so leaflet formula works correctly
    quad <- ifelse(is.na(csf$lisa_cluster), "Not significant", csf$lisa_cluster)
    csf$fill_color <- unname(cluster_pal[quad])

    stat_label <- switch(stat, moran = "Local I", g = "Gi", gstar = "Gi*")
    labels <- sprintf(
      "<b>%s</b><br/>Cluster: %s<br/>%s: %s<br/>z: %s<br/>p (asymp): %s",
      paste0(csf$NAME, ", ", csf$state),
      ifelse(is.na(csf$lisa_cluster), "No data", csf$lisa_cluster),
      stat_label,
      ifelse(is.na(csf$lisa_stat),  "—", round(csf$lisa_stat,  4)),
      ifelse(is.na(csf$lisa_z),     "—", round(csf$lisa_z,     4)),
      ifelse(is.na(csf$lisa_p_sim), "—", round(csf$lisa_p_sim, 4))
    ) |> lapply(htmltools::HTML)

    leafletProxy("lisa_map") |>
      clearShapes() |> clearControls() |>
      addPolygons(
        data             = csf,
        fillColor        = ~fill_color,
        fillOpacity      = 0.75,
        color            = "#BBBBBB",
        weight           = 0.4,
        opacity          = 0.7,
        smoothFactor     = 0.3,
        label            = labels,
        highlightOptions = highlightOptions(
          weight = 1.8, color = "#444", fillOpacity = 0.9, bringToFront = TRUE
        )
      ) |>
      addPolylines(
        data         = geo()$states,
        color        = "#111111",
        weight       = 0.9,
        opacity      = 0.9,
        smoothFactor = 0.3
      ) |>
      addLegend(
        position = "bottomright",
        colors   = unname(cluster_pal),
        labels   = names(cluster_pal),
        title    = paste0(switch(stat, moran="Moran's I", g="Local G", gstar="Local G*"),
                          " — ", col_label(input$p2_indicator)),
        opacity  = 0.9
      )
  })

  # Dynamic legend key in sidebar
  output$p2_legend_key <- renderUI({
    stat <- input$p2_stat
    tags$small(
      if (stat == "moran") tagList(
        tags$b("Local Moran's I"), " (Anselin 1995)", tags$br(), tags$br(),
        tags$span(style="color:#d7191c", tags$b("HH")), " High-High cluster", tags$br(),
        tags$span(style="color:#2c7bb6", tags$b("LL")), " Low-Low cluster",   tags$br(),
        tags$span(style="color:#fdae61", tags$b("HL")), " High outlier, low neighbors", tags$br(),
        tags$span(style="color:#4dac26", tags$b("LH")), " Low outlier, high neighbors"
      ) else tagList(
        if (stat == "g") tags$b("Local G (Getis-Ord)") else tags$b("Local G* (Getis-Ord)"),
        tags$br(), tags$br(),
        tags$span(style="color:#d7191c", tags$b("Hot Spot")), " Significant high cluster", tags$br(),
        tags$span(style="color:#2c7bb6", tags$b("Cold Spot")), " Significant low cluster"
      )
    )
  })

  # Dynamic right-panel header
  output$p2_global_header <- renderUI({
    h5("Global Moran's I")
  })

  # Global Moran's I summary
  output$moran_out <- renderPrint({
    req(lisa_rv())
    gmt <- lisa_rv()$gmt
    if (is.null(gmt)) { cat("Not computed\n"); return() }
    est <- gmt$estimate
    cat(sprintf("I       : %8.4f\n", est["Moran I statistic"]))
    cat(sprintf("E[I]    : %8.4f\n", est["Expectation"]))
    cat(sprintf("Var[I]  : %8.6f\n", est["Variance"]))
    cat(sprintf("z-score : %8.4f\n", gmt$statistic))
    cat(sprintf("p       : %8.5f\n", gmt$p.value))
  })

  # LISA cluster counts table
  output$lisa_counts <- DT::renderDT({
    req(lisa_rv())
    ct <- lisa_rv()$cluster_counts
    df <- as.data.frame(ct, stringsAsFactors = FALSE)
    names(df) <- c("Cluster", "n")
    df$Pct <- paste0(round(100 * df$n / sum(df$n), 1), "%")
    DT::datatable(df, rownames = FALSE,
                  options = list(dom = "t", pageLength = 10),
                  class = "compact stripe")
  })
}

shinyApp(ui, server)
