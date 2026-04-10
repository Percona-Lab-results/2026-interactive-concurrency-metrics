#!/bin/bash

Rscript visuals/throughput_report.R benchmark_logs sysbench_oltp_rw_comparison_9_7.html "OLTP Read-Write With MySQL 9.7.0"
Rscript visuals/throughput_report.R benchmark_logs_read_only sysbench_oltp_ro_comparison_9_7.html "OLTP Read-Only With MySQL 9.7.0"
Rscript visuals/throughput_report.R benchmark_remote_logs sysbench_remote_oltp_rw_comparison_9_7.html "OLTP Network Read-Write With MySQL 9.7.0"
Rscript visuals/throughput_report.R benchmark_remote_logs_read_only sysbench_remote_oltp_ro_comparison_9_7.html "OLTP Network Read-Only With MySQL 9.7.0"