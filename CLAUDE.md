# Project Instructions for Claude

## Report Workflow

When making any report change, always do all of these in sequence without being asked:
1. Regenerate interactive report (`./visuals/make_custom_percona.sh`)
2. Generate test-report.html using REPORT.md
3. Update the Google Doc in-place via `gws drive files update --params '{"fileId":"1cVz_3RMHAao_VNkkxmAS4Q_EvHiojKRrP1QhTzRfwQc"}' --upload test-report.html --upload-content-type "text/html"`
