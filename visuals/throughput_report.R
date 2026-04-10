#!/usr/bin/env Rscript
# =============================================================================
# generate_sysbench_report.R
#
# Scans benchmark_logs/ for *.sysbench.txt files, parses TPS/QPS, and
# generates the full interactive Plotly comparison HTML.
#
# Usage:
#   Rscript generate_sysbench_report.R [base_dir] [output_file]
#
# Defaults:
#   base_dir    = "benchmark_logs"
#   output_file = "sysbench_interactive_comparison.html"
# =============================================================================

args        <- commandArgs(trailingOnly = TRUE)
base_dir    <- if (length(args) >= 1) args[1] else "benchmark_logs"
test_type   <- if (length(args) >= 3) args[3] else "OLTP Read-Write"

default_input  <- file.path("visuals", "visual_template.html.in")
default_output <- file.path(base_dir, "sysbench_interactive_comparison.html")

output_file <- if (length(args) >= 2) args[2] else default_output

cat(sprintf("Scanning: %s\n", base_dir))

# ── 1. Find all sysbench result files ─────────────────────────────────────────
files <- list.files(
  path       = base_dir,
  pattern    = "\\.sysbench\\.txt$",
  recursive  = TRUE,
  full.names = TRUE
)

if (length(files) == 0) {
  stop(sprintf("No .sysbench.txt files found under '%s'", base_dir))
}

cat(sprintf("Found %d file(s)\n", length(files)))

# ── 2. Parse each file into a data row ────────────────────────────────────────
# Expected path structure: benchmark_logs/{db_type}/{version}/Tier{N}G_RW_{T}th.sysbench.txt
parse_file <- function(path) {
  parts    <- strsplit(path, "/", fixed = TRUE)[[1]]
  # parts: [base_dir, db_type, version, filename]
  if (length(parts) < 4) {
    warning(sprintf("Skipping unexpected path structure: %s", path))
    return(NULL)
  }

  db_type  <- parts[length(parts) - 2]
  version  <- parts[length(parts) - 1]
  filename <- parts[length(parts)]

  # Extract memory (e.g. 12 from Tier12G_RW_64th.sysbench.txt)
  mem_match <- regmatches(filename, regexpr("Tier(\\d+)G", filename, perl = TRUE))
  thr_match <- regmatches(filename, regexpr("_(\\d+)th\\.", filename, perl = TRUE))

  if (length(mem_match) == 0 || length(thr_match) == 0) {
    warning(sprintf("Cannot parse mem/threads from filename: %s", filename))
    return(NULL)
  }

  mem_gb  <- as.integer(sub("Tier(\\d+)G",  "\\1", mem_match))
  threads <- as.integer(sub("_(\\d+)th\\.", "\\1", thr_match))
  server  <- paste(db_type, version)

  # Read file and extract TPS / QPS
  lines   <- readLines(path, warn = FALSE)
  content <- paste(lines, collapse = "\n")

  extract_rate <- function(pattern) {
    m <- regmatches(content, regexpr(pattern, content, perl = TRUE))
    if (length(m) == 0) return(NA_real_)
    as.numeric(sub(".*\\(([0-9.]+) per sec\\.\\).*", "\\1", m))
  }

  tps <- extract_rate("transactions:.*?\\([0-9.]+ per sec\\.\\)")
  qps <- extract_rate("queries:.*?\\([0-9.]+ per sec\\.\\)")

  if (is.na(tps) || is.na(qps)) {
    cat(sprintf("  NA result (skipped): %s\n", path))
    return(NULL)
  }

  data.frame(
    server  = server,
    mem_gb  = mem_gb,
    threads = threads,
    tps     = tps,
    qps     = qps,
    stringsAsFactors = FALSE
  )
}

rows <- lapply(files, parse_file)
rows <- rows[!sapply(rows, is.null)]

if (length(rows) == 0) {
  stop("No valid data rows could be parsed from the files found.")
}

data <- do.call(rbind, rows)
cat(sprintf("Parsed %d data rows across %d servers\n",
            nrow(data), length(unique(data$server))))

# ── 3. Build JS constants ─────────────────────────────────────────────────────
to_js_array <- function(x) {
  if (is.character(x)) {
    paste0('["', paste(x, collapse = '", "'), '"]')
  } else {
    paste0("[", paste(x, collapse = ", "), "]")
  }
}

to_json_rows <- function(df) {
  parts <- apply(df, 1, function(r) {
    sprintf('{"server":"%s","mem_gb":%s,"threads":%s,"tps":%s,"qps":%s}',
            r["server"], r["mem_gb"], r["threads"], r["tps"], r["qps"])
  })
  paste0("[", paste(parts, collapse = ","), "]")
}

servers_sorted <- sort(unique(data$server))
mems_sorted    <- sort(unique(data$mem_gb))
threads_sorted <- sort(unique(data$threads))

# Order data rows consistently
data <- data[order(data$server, data$mem_gb, data$threads), ]

data_block <- paste0(
  "const DATA = ", to_json_rows(data), ";\n",
  "const SERVERS = ", to_js_array(servers_sorted), ";\n",
  "const MEMS = ", to_js_array(mems_sorted), ";\n",
  "const THREADS = ", to_js_array(threads_sorted), ";"
)

# ── 4. Build tick arrays for x-axis (threads mode) ───────────────────────────
threads_js_vals <- paste0("[", paste(threads_sorted, collapse = ","), "]")
threads_js_text <- paste0('["', paste(threads_sorted, collapse = '","'), '"]')

# ── 5. Load HTML template ─────────────────────────────────────────────────────
if (!file.exists(default_input)) {
  stop(sprintf("Template not found: %s", default_input))
}

tmpl <- paste(readLines(default_input, warn = FALSE), collapse = "\n")

if (!grepl("{{DATA_BLOCK}}", tmpl, fixed = TRUE)) {
  stop(sprintf("Template file '%s' is missing the {{DATA_BLOCK}} placeholder.", default_input))
}

cat(sprintf("Using template: %s\n", default_input))

# ── 6. Inject data and write output ───────────────────────────────────────────
# Replace data block
output_html <- sub("{{DATA_BLOCK}}", data_block, tmpl, fixed = TRUE)

# Replace base URL (used in download links)
output_html <- gsub("{{BASE_URL}}", base_dir, output_html, fixed = TRUE)

# Replace test type
output_html <- sub("{{TEST_TYPE}}", test_type, output_html, fixed = TRUE)

# Replace tick arrays (keep them in sync with whatever threads were found)
output_html <- gsub(
  "tickvals: \\(xMode === \"threads\"\\) \\? \\[.*?\\] : undefined,",
  paste0('tickvals: (xMode === "threads") ? ', threads_js_vals, ' : undefined,'),
  output_html, perl = TRUE
)
output_html <- gsub(
  "ticktext: \\(xMode === \"threads\"\\) \\? \\[.*?\\] : undefined,",
  paste0('ticktext: (xMode === "threads") ? ', threads_js_text, ' : undefined,'),
  output_html, perl = TRUE
)

writeLines(output_html, output_file, useBytes = TRUE)
cat(sprintf("Done. Report written to: %s\n", output_file))
cat(sprintf("  Servers : %d\n", length(servers_sorted)))
cat(sprintf("  Memories: %s\n", paste(mems_sorted, collapse = ", ")))
cat(sprintf("  Threads : %s\n", paste(threads_sorted, collapse = ", ")))
cat(sprintf("  Records : %d\n", nrow(data)))