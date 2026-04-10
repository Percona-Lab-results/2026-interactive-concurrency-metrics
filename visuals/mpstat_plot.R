#!/usr/bin/env Rscript

# Load libraries early
suppressPackageStartupMessages({
  library(echarts4r)
  library(htmlwidgets)
})

# ---- 1. Determine Files to Process ----
# Look in all subdirectories of benchmark_logs for .mpstat.txt files
log_dir <- "benchmark_logs"

if (!dir.exists(log_dir)) {
  stop(paste("Directory not found:", log_dir))
}

# recursive = TRUE ensures we look into all subdirectories
files_to_process <- list.files(
  path = log_dir, 
  pattern = "\\.mpstat\\.txt$", 
  full.names = TRUE, 
  recursive = TRUE
)

if (length(files_to_process) == 0) {
  cat("No .mpstat.txt files found in", log_dir, "or its subdirectories.\n")
  quit(save = "no", status = 0)
}

# ---- 2. Processing Loop ----
for (in_file in files_to_process) {
  
  out_file <- gsub("\\.mpstat\\.txt$", ".html", in_file)

  if (!file.exists(in_file)) {
    warning(paste("File not found:", in_file))
    next
  }

  cat("Processing:", in_file, "->", out_file, "\n")

  # ---- 3. Read and clean raw lines ----
  raw <- readLines(in_file, warn = FALSE)
  raw <- raw[nzchar(trimws(raw))]
  is_header <- grepl("%usr", raw, fixed = TRUE)
  dat_lines <- raw[!is_header]

  # ---- 4. Turn lines into a data.frame ----
  split_lines <- strsplit(dat_lines, "\\s+")
  # Filter out lines that don't have enough columns (avoids errors on trailing junk)
  split_lines <- split_lines[lengths(split_lines) >= 12]
  
  if (length(split_lines) == 0) {
    warning(paste("No valid data rows found in", in_file))
    next
  }

  mat <- do.call(rbind, split_lines)

  df <- data.frame(
    time_str = paste(mat[, 1], mat[, 2]), 
    CPU      = mat[, 3],
    usr      = as.numeric(mat[, 4]),
    nice     = as.numeric(mat[, 5]),
    sys      = as.numeric(mat[, 6]),
    iowait   = as.numeric(mat[, 7]),
    irq      = as.numeric(mat[, 8]),
    soft     = as.numeric(mat[, 9]),
    steal    = as.numeric(mat[, 10]),
    guest    = as.numeric(mat[, 11]),
    gnice    = as.numeric(mat[, 12]),
    idle     = as.numeric(mat[, 13]),
    stringsAsFactors = FALSE
  )

  # ---- 5. Create Time Axis ----
  df$timestamp <- as.POSIXct(
    paste("2025-01-01", df$time_str),
    format = "%Y-%m-%d %I:%M:%S %p",
    tz = "UTC"
  )

  # ---- 6. Filter and Chart ----
  df_all <- df[df$CPU == "all", ]

  if (nrow(df_all) > 0) {
    p <- df_all |>
      e_charts(timestamp) |>
      e_line(usr,   name = "%usr") |>
      e_line(sys,   name = "%sys") |>
      e_line(iowait, name = "%iowait") |>
      e_line(idle,  name = "%idle") |>
      e_title(paste("CPU usage:", in_file), "Data from mpstat/sar log") |>
      e_tooltip(trigger = "axis") |>
      e_datazoom(show = TRUE) |>
      e_legend(show = TRUE)

    # ---- 7. Save to HTML ----
    saveWidget(p, out_file, selfcontained = TRUE)
    cat("Successfully wrote:", out_file, "\n")
  } else {
    warning(paste("No 'all' CPU data found in", in_file))
  }
}
