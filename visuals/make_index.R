#!/usr/bin/env Rscript

# Define paths relative to the repository root
# (Assuming the action runs from the root)

# source_file <- "visuals/visual_template.html"
# target_file <- "index.html"

# # Execute copy
# if (file.exists(source_file)) {
#   success <- file.copy(from = source_file, to = target_file, overwrite = TRUE)
  
#   if (success) {
#     message(paste("Successfully deployed:", source_file, "->", target_file))
#   } else {
#     stop("Failed to copy file. Check write permissions.")
#   }
# } else {
#   stop(paste("Source template not found at:", source_file))
# }


# Set the directory to crawl
base_dir <- "."
output_file <- "index.html"

# 1. Find all .html files recursively
# We exclude 'index.html' itself to avoid self-referencing
html_files <- list.files(path = base_dir, 
                         pattern = "\\.html$", 
                         recursive = TRUE, 
                         full.names = TRUE)
html_files <- html_files[basename(html_files) != "index.html"]

# 2. Start building the HTML string
html_content <- c(
  "<!DOCTYPE html>",
  "<html>",
  "<head>",
  "  <title>Benchmark Reports</title>",
  "  <style>",
  "    body { font-family: sans-serif; margin: 40px; line-height: 1.6; }",
  "    h1 { color: #2c3e50; }",
  "    ul { list-style-type: none; padding: 0; }",
  "    li { margin-bottom: 10px; background: #f8f9fa; padding: 10px; border-radius: 5px; }",
  "    a { text-decoration: none; color: #3498db; font-weight: bold; }",
  "    a:hover { text-decoration: underline; }",
  "    .path { color: #7f8c8d; font-size: 0.85em; }",
  "  </style>",
  "</head>",
  "<body>",
  "  <h1>Benchmark Visualization Index</h1>",
  "  <p>Available reports:</p>",
  "  <ul>"
)

# 3. Add a list item for each file
if (length(html_files) > 0) {
  for (f in sort(html_files)) {
    # Create a link relative to the root of the Pages site
    # (assuming index.html is in the same parent folder as benchmark_logs)
    display_name <- basename(f)
    file_path <- f
    
    html_content <- c(html_content, 
      paste0('    <li><a href="./', file_path, '">', display_name, '</a><br>',
             '<span class="path">Location: ', file_path, '</span></li>'))
  }
} else {
  html_content <- c(html_content, "    <li>No reports found yet.</li>")
}

# 4. Close HTML tags
html_content <- c(html_content, "  </ul>", "</body>", "</html>")

# 5. Write to file
writeLines(html_content, output_file)
cat("Generated index.html with", length(html_files), "links.\n")
