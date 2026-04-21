# InnoDB Thread Concurrency Performance Analysis Report

## 1. Interactive Graphs

An interactive web-based visualization of all benchmark results is available online:

**[View Interactive Performance Graphs](https://percona-lab-results.github.io/2026-interactive-concurrency-metrics/sysbench_oltp_rw_comparison_concur.html)**

This interactive tool allows you to:
- Compare performance across different innodb_thread_concurrency settings (8, 16, 32, 64)
- Filter by memory tier (2GB, 12GB, 32GB)
- Select specific thread counts for detailed analysis
- View raw benchmark data and configuration files
- Explore TPS metrics dynamically

## 2. Benchmark Overview

### 2.1. Purpose and Scope

### Purpose

The primary purpose of this benchmark study is to evaluate how the `innodb_thread_concurrency` parameter affects database performance under OLTP (Online Transaction Processing) read-write workloads on Percona Server 8.4.8. This investigation aims to provide empirical data on the performance characteristics of different concurrency limit configurations across various workload conditions.

### Target Questions

This analysis seeks to answer the following key questions:

1. **Impact of Concurrency Limits on Throughput**
   - How does setting `innodb_thread_concurrency` to specific values (8, 16, 32, 64) affect transaction throughput?
   - Does limiting internal InnoDB thread concurrency improve or degrade performance compared to higher limits?
   - At what client thread counts do concurrency limits begin to matter?

2. **Optimal Concurrency Settings by Client Load**
   - Which `innodb_thread_concurrency` value provides the best performance at low client concurrency (128 threads)?
   - How do optimal settings change as client concurrency increases (256, 512 threads)?
   - Is there a universal "best" setting or does it vary by workload intensity?

3. **Effect of InnoDB Buffer Pool Size**
   - How does the interaction between `innodb_thread_concurrency` and buffer pool size (2GB, 12GB, 32GB) affect throughput?
   - Does buffer pool size change which concurrency setting is optimal?

4. **Scalability Characteristics**
   - How does performance scale as client thread count increases from 128 to 512 threads?
   - Do lower concurrency limits prevent performance degradation at high client counts?

### Scope

- **Database System**: Percona Server 8.4.8-8
- **Test Parameter**: `innodb_thread_concurrency` values of 8, 16, 32, 64
- **Workload Type**: Sysbench OLTP Read-Write
- **Client Concurrency Levels**: 128, 256, 512 threads
- **Memory Tiers**: 2GB, 12GB, 32GB `innodb_buffer_pool_size`
- **Dataset Size**: 24GB (20 tables × 5M rows)
- **Test Duration**: 900 seconds (15 minutes) per configuration

### 2.2. Configuration Under Test

The `innodb_thread_concurrency` parameter limits how many threads can execute inside InnoDB simultaneously. Setting it to 0 (default) removes the limit.

| Configuration (innodb_thread_concurrency) | Purpose |
|--------------------------------------------|---------|
| **Concur8** (8) | Very conservative limit (20% of physical cores) |
| **Concur16** (16) | Conservative limit (40% of physical cores) |
| **Concur32** (32) | Moderate limit (80% of physical cores) |
| **Concur64** (64) | Liberal limit (160% of physical cores) |

**Hardware Context**: The test system has 40 physical cores (80 threads with hyperthreading), making these settings range from highly restrictive to moderately permissive.

## 3. Key Findings

### 3.1. Concurrency Limit Effectiveness by Workload Type

The performance impact of `innodb_thread_concurrency` settings varies dramatically based on workload I/O characteristics:

| Workload Type | Buffer Pool & I/O Characteristic | Best Concurrency Setting | Highest Performance Gain vs Concur8 |
|---------------|----------------------------------|--------------------------|----------------------------|
| **I/O Bound** | 2GB - Heavy disk access (1:12 data:buffer ratio) | **Concur32 or Concur64** | +158% |
| **Mixed** | 12GB - Partial buffering (1:2 data:buffer ratio) | **Concur64** | +288% |
| **Memory Bound** | 32GB - Fully buffered | **Concur32 or Concur64** | +302% |

**Critical Insight:** Higher concurrency limits (32-64) consistently outperform lower limits (8-16) across all workload types.

### 3.2. Performance Impact at Different Client Loads

#### 2GB Buffer Pool (I/O-Bound)

| Client Threads | Concur8 | Concur16 | Concur32 | Concur64 |
|----------------|---------|----------|----------|----------|
| **128** | 947 TPS | 1,920 TPS (+103%) | **2,440 TPS (+158%)** | 1,935 TPS (+104%) |
| **256** | 950 TPS | 1,892 TPS (+99%) | **2,316 TPS (+144%)** | 2,075 TPS (+118%) |
| **512** | 1,021 TPS | 1,578 TPS (+55%) | 2,198 TPS (+115%) | **2,203 TPS (+116%)** |

**Key Observation:** In I/O-bound scenarios (2G buffer pool), Concur32 and Concur64 provide 2-2.5x better throughput than Concur8.

#### 12GB Buffer Pool (Mixed Workload)

| Client Threads | Concur8 | Concur16 | Concur32 | Concur64 |
|----------------|---------|----------|----------|----------|
| **128** | 2,095 TPS | 3,731 TPS (+78%) | 5,605 TPS (+168%) | **6,427 TPS (+207%)** |
| **256** | 2,102 TPS | 3,680 TPS (+75%) | 5,541 TPS (+164%) | **6,449 TPS (+207%)** |
| **512** | 1,660 TPS | 2,906 TPS (+75%) | 5,290 TPS (+219%) | **6,439 TPS (+288%)** |

**Key Observation:** Mixed workloads (12G buffer pool) show the largest performance differences between concurrency settings.

#### 32GB Buffer Pool (Memory-Resident)

| Client Threads | Concur8 | Concur16 | Concur32 | Concur64 |
|----------------|---------|----------|----------|----------|
| **128** | 5,152 TPS | 9,658 TPS (+87%) | 13,166 TPS (+156%) | **13,142 TPS (+155%)** |
| **256** | 4,866 TPS | 9,566 TPS (+97%) | **13,708 TPS (+182%)** | 13,549 TPS (+178%) |
| **512** | 3,333 TPS | 9,515 TPS (+185%) | 12,750 TPS (+283%) | **13,406 TPS (+302%)** |

**Key Observation:** Memory-resident workloads (32G buffer pool) show the most extreme difference between highest and lowest performance levels.

### 3.3. Concurrency Setting Characteristics

**Concur8:** Consistently worst performer. Creates severe serialization bottlenecks (35-75% below optimal). **Avoid.**

**Concur16:** Below optimal in all scenarios. Better than Concur8 (+55-185%) but still bottlenecks memory-resident workloads. **Too conservative for most systems.**

**Concur32:** Optimal or near-optimal in most scenarios. Matches physical core count. Minimal difference from Concur64. **Safe default for most workloads.**

**Concur64:** Best performance at high client loads (256-512 threads). Maintains consistency as load increases. Slight edge over Concur32 at extreme oversubscription. **Best for high-concurrency workloads.**

### 3.4. Practical Deployment Recommendations

**When to Use Concur64 (High Limit) - ✅ Strongly Recommended:**
- High client concurrency (256+ concurrent connections)
- Memory-resident or mostly-cached workloads (buffer pool covers >50% of dataset)
- Systems with many CPU cores (40+)

**When to Use Concur32 (Moderate Limit) - ✅ Recommended:**
- Moderate client concurrency (128-256 connections)
- Mixed I/O workloads
- Systems with 20-40 CPU cores

**When to Use Concur16 (Conservative Limit) - ⚠️ Use with Caution:**
- I/O-bound workloads with low client concurrency (<128 connections)
- Systems with limited CPU cores (<20)
- Workloads with high lock contention
- Legacy applications being migrated
- Testing scenarios where you want to limit resource usage

**When to Use Concur8 (Very Conservative Limit) - ❌ Not Recommended:**
- Concur8 consistently underperforms across all tested scenarios
- Creates artificial serialization that wastes available resources
- Only consider for extreme edge cases with severe lock contention issues
- For troubleshooting purposes to identify concurrency-related problems

### 3.5. Performance Scalability Analysis

**Scalability from 128 to 512 Threads:**

**Concur8:**
- 2GB: 947 → 1,021 TPS (+8%) - Minimal scaling
- 12GB: 2,095 → 1,660 TPS (-21%) - Performance degradation
- 32GB: 5,152 → 3,333 TPS (-35%) - Severe degradation

**Concur64:**
- 2GB: 1,935 → 2,203 TPS (+14%) - Positive scaling
- 12GB: 6,427 → 6,439 TPS (0%) - Maintains performance
- 32GB: 13,142 → 13,406 TPS (+2%) - Maintains high performance

**Critical Insight:** Low limits (8-16) degrade under load, especially in memory-resident workloads. High limits (32-64) maintain or improve performance as client load increases.

## 4. Test Environment & Infrastructure

### 4.1. Hardware Specification

#### System Information

- **Platform**: Linux
- **Release**: Ubuntu 24.04 LTS (noble)
- **Kernel**: 6.8.0-60-generic
- **Architecture**: CPU = 64-bit, OS = 64-bit
- **Virtualized**: No virtualization detected

#### CPU

- **Architecture**: x86_64
- **CPU op-mode(s)**: 32-bit, 64-bit
- **Byte Order**: Little Endian
- **Processors**: physical = 2, cores = 40, virtual = 80, hyperthreading = yes
- **Sockets**: 2
- **Cores per socket**: 20
- **Threads per core**: 2
- **Model**: 80x Intel(R) Xeon(R) Gold 6230 CPU @ 2.10GHz
- **Base Frequency**: 2.10GHz
- **Max Frequency**: 3.90GHz
- **Cache**: 80x 28160 KB

#### NUMA

- **NUMA Nodes**: 2
- **Node 0**: 95288 MB (CPUs: 0-19, 40-59)
- **Node 1**: 96748 MB (CPUs: 20-39, 60-79)

#### Memory

- **Total Memory**: 187.5G
- **Swap Size**: 8.0G

#### Storage Configuration

**Primary Storage (SDA - System Disk)**
- **Device**: /dev/sda
- **Total Size**: 894.3 GB

**Secondary Storage (NVMe - Data Disk)**
- **Device**: /dev/nvme0n1
- **Total Size**: 2.9 TB
- **Filesystem**: ext4

### 4.2. Software Configuration

#### Operating System

- **Distribution**: Ubuntu 24.04 LTS (noble)
- **Kernel**: 6.8.0-60-generic
- **Architecture**: 64-bit

#### Database Server

- **Engine**: Percona Server for MySQL
- **Version**: 8.4.8-8
- **Deployment**: Docker container with host networking (`--network host`)

#### Benchmark Tool

- **Sysbench**: Version 1.0.20
- **LuaJIT**: 2.1.0-beta3 (system)
- **Test Script**: OLTP Read-Write (built-in)

#### Telemetry Tools

System performance metrics were collected continuously during each benchmark run:

- **iostat**: I/O statistics monitoring
- **vmstat**: Virtual memory and system statistics
- **mpstat**: Multi-processor statistics
- **dstat**: Combined system resource statistics
- **Sampling Interval**: 1 second for all tools
- **Collection Period**: Full duration of each 15-minute test run

### 4.3. Buffer Pool Tiers

With the database size of 24GB, three InnoDB buffer pool sizes were tested, each representing a distinct workload characteristic:

| Tier (innodb_buffer_pool_size) | Workload Character |
|---------------------------------|--------------------|
| **2GB** | **I/O bound** — dataset substantially exceeds buffer pool (1:12 ratio); heavy read amplification |
| **12GB** | **Mixed** — partial dataset fits in memory (1:2 ratio); realistic production scenario |
| **32GB** | **In-memory** — full working set fits; CPU and locking are primary bottlenecks |

These tiers were selected to evaluate Percona Server performance across different scenarios, from heavily disk-constrained (2GB) to fully memory-resident (32GB) workloads.

## 5. Database Configuration

Percona Server 8.4.8-8 was configured with settings optimized for OLTP workloads. The primary variable of interest was `innodb_thread_concurrency`, tested at values of 8, 16, 32, and 64.

### 5.1. General Settings

```
performance_schema              = OFF
skip-name-resolve               = ON
max_connections                 = 2000
max_connect_errors              = 1000000
max_prepared_stmt_count         = 1000000
```

### 5.2. Thread Concurrency Configuration

The `innodb_thread_concurrency` parameter was varied across test runs:

```
innodb_thread_concurrency       = 8 | 16 | 32 | 64
```

**Note:** This parameter controls the maximum number of threads that can be inside InnoDB code simultaneously. When this limit is reached, additional threads must wait before entering InnoDB.

### 5.3. InnoDB Buffer Pool

Buffer pool size varied by tier (see Section 4.3):
```
innodb_buffer_pool_size         = 2G | 12G | 32G
```

### 5.4. InnoDB I/O Configuration

Optimized for NVMe storage with high concurrency:
```
innodb_io_capacity              = 10000
innodb_io_capacity_max          = 20000
innodb_read_io_threads          = 16
innodb_write_io_threads         = 16
innodb_use_native_aio           = ON
```

### 5.5. InnoDB Durability & Logging

Full ACID compliance with transaction log optimization:
```
innodb_log_file_size            = 4G
innodb_log_buffer_size          = 256M
innodb_flush_log_at_trx_commit  = 1                 # full ACID
innodb_doublewrite              = ON
sync_binlog                     = 1
```

### 5.6. Binary Logging

Enabled for production-realistic overhead measurement:
```
log_bin                         = /var/lib/mysql/mysql-bin
binlog_format                   = ROW
binlog_row_image                = MINIMAL
binlog_cache_size               = 4M
max_binlog_size                 = 512M
```

**Note:** The complete configuration file is available in the benchmark logs directory as `TierXG.cnf.txt` for each tested configuration.

## 6. Benchmark Workload

### 6.1. Warmup Protocol

Before each production benchmark run, the database underwent a two-phase warmup sequence to ensure consistent starting conditions:

| Phase | Duration | Purpose |
|-------|----------|---------|
| **Warmup A — Read-Only** | 180s (3 min) | Populate buffer pool with hot pages |
| **Warmup B — Read-Write** | 600s (10 min) | Steady-state redo log & dirty page ratio |

**Note:** The warmup values were determined experimentally and are sufficient for the hardware configuration used. On slower systems, these durations may need adjustment.

### 6.2. Measurement Run

Following the warmup phase, each benchmark execution ran for **900 seconds (15 minutes)** with performance metrics captured at 1-second granularity. During execution, system-level telemetry tools (iostat, vmstat, mpstat, dstat) collected resource utilization data in parallel.

#### Data Collection Strategy

Single measurement per configuration. Consistency of the results is validated via selective repeat runs on configurations that show unexpected behavior.

#### Steady-State Verification

**Read Operations:** Steady state for read workloads was verified by monitoring InnoDB buffer pool metrics and OS-level I/O read counters. The system was considered stable when physical reads dropped to near-zero after the warmup period (for configurations where the dataset fit in the buffer pool).

**Write Operations:** For write-intensive phases, stability was determined by observing transaction throughput and latency metrics until they reached consistent values without significant drift.

**Known Limitation:** While short-term metric stability (15 minutes) provides confidence in measurement consistency, it does not entirely eliminate the possibility of longer-term background activity such as adaptive flushing, change buffer merges, or checkpoint behavior that might emerge during extended multi-day operations.

## 7. Metrics & Reporting

### 7.1. Primary Metrics

| Metric | Definition |
|--------|------------|
| **TPS** | Transactions per second (complete BEGIN/COMMIT cycles) |

### 7.2. Configuration Variables

| Variable | Values Tested |
|----------|---------------|
| **innodb_thread_concurrency** | 8, 16, 32, 64 |
| **Client Threads** | 128, 256, 512 |
| **Buffer Pool Size** | 2GB, 12GB, 32GB |

### 7.3. Output Files

**Per-run telemetry files:**
- `.sysbench.txt` — Sysbench benchmark results
- `.iostat.txt` — I/O statistics
- `.vmstat.txt` — Virtual memory and system statistics
- `.mpstat.txt` — Multi-processor utilization
- `.dstat.txt` — Combined system resource monitoring

**Per-tier configuration files:**
- `.cnf.txt` — Percona Server configuration file
- `.vars.txt` — Server variables (`SHOW VARIABLES`)
- `.status.txt` — Server status (`SHOW STATUS`)

## 8. Measurement Results

### 8.1. 2GB Buffer Pool Results (I/O-Bound)

#### 8.1.1. Performance Summary

At the 2GB buffer pool configuration, the database is heavily I/O-bound with the 24GB dataset substantially exceeding available memory (1:12 ratio). This creates significant disk access pressure.

*Note: Percentages show performance improvement compared to Concur8 baseline.*

| Client Threads | Concur8 (TPS) | Concur16 (TPS) | Concur32 (TPS) | Concur64 (TPS) | Best Setting |
|----------------|---------------|----------------|----------------|----------------|--------------|
| **128** | 947 | 1,920 (+103%) | 2,440 (+158%) | 1,935 (+104%) | **Concur32** |
| **256** | 950 | 1,892 (+99%) | 2,316 (+144%) | 2,075 (+118%) | **Concur32** |
| **512** | 1,021 | 1,578 (+55%) | 2,198 (+115%) | 2,203 (+116%) | **Concur64** |

#### 8.1.2. Analysis

**Key Observations:**

1. **Concur8 Creates Severe Bottleneck**: With only 8 threads allowed inside InnoDB, throughput is artificially constrained to around 950-1,020 TPS regardless of client load. This is just 40-46% of optimal performance.

2. **Concur16 Middle Ground**: Concur16 provides decent performance improvement over Concur8 (55-103%), but remains significantly below optimal, achieving only 72-82% of the best configuration's throughput.

3. **Concur32 Optimal at Lower Client Counts**: At 128 and 256 client threads, Concur32 provides the best performance (2,316-2,440 TPS), suggesting that matching the concurrency limit to physical core count works well for I/O-bound workloads at moderate client loads.

4. **Concur64 Better at High Client Load**: At 512 client threads, Concur64 edges ahead of Concur32 (2,203 vs 2,198 TPS), showing that higher limits help maintain performance as client concurrency increases.

**I/O Characteristics**: Low concurrency limits prevent maintaining sufficient I/O queue depth to saturate NVMe storage. Concur32 and Concur64 allow enough concurrent operations to fully utilize disk throughput.

### 8.2. 12GB Buffer Pool Results (Mixed Workload)

#### 8.2.1. Performance Summary

At 12GB buffer pool, approximately half of the 24GB dataset fits in memory (1:2 ratio), creating a realistic mixed workload with both cached and disk-bound operations.

| Client Threads | Concur8 (TPS) | Concur16 (TPS) | Concur32 (TPS) | Concur64 (TPS) | Best Setting |
|----------------|---------------|----------------|----------------|----------------|--------------|
| **128** | 2,095 | 3,731 (+78%) | 5,605 (+168%) | 6,427 (+207%) | **Concur64** |
| **256** | 2,102 | 3,680 (+75%) | 5,541 (+164%) | 6,449 (+207%) | **Concur64** |
| **512** | 1,660 | 2,906 (+75%) | 5,290 (+219%) | 6,439 (+288%) | **Concur64** |

#### 8.2.2. Analysis

**Key Observations:**

1. **Dramatic Performance Spread**: Concur64 provides 3-3.9x better throughput than Concur8, demonstrating how critical concurrency settings are for mixed workloads.

2. **Concur64 Consistently Optimal**: Best performance across all client loads (6,427-6,449 TPS). Maintains stability even as Concur8 degrades 21% at 512 threads.

3. **Near-Linear Scaling**: Each doubling of the concurrency limit approximately doubles performance (Concur8 < Concur16 < Concur32 < Concur64).

**Workload Characteristics**: With 50% cache hit ratio, higher concurrency limits allow memory-resident operations to proceed while I/O-bound operations wait, improving overall throughput.

### 8.3. 32GB Buffer Pool Results (Memory-Resident)

#### 8.3.1. Performance Summary

At 32GB buffer pool, the entire 24GB working set fits in memory, eliminating I/O bottlenecks. Performance is primarily constrained by CPU cycles and lock contention.

| Client Threads | Concur8 (TPS) | Concur16 (TPS) | Concur32 (TPS) | Concur64 (TPS) | Best Setting |
|----------------|---------------|----------------|----------------|----------------|--------------|
| **128** | 5,152 | 9,658 (+87%) | 13,166 (+156%) | 13,142 (+155%) | **Concur32** |
| **256** | 4,866 | 9,566 (+97%) | 13,708 (+182%) | 13,549 (+178%) | **Concur32** |
| **512** | 3,333 | 9,515 (+185%) | 12,750 (+283%) | 13,406 (+302%) | **Concur64** |

#### 8.3.2. Analysis

**Key Observations:**

1. **Highest Absolute Throughput**: Memory-resident workloads achieve the highest TPS values (13,000-13,700), as expected when I/O is eliminated from the critical path.

2. **Concur32 and Concur64 Neck-and-Neck**: At 128 and 256 client threads, Concur32 and Concur64 perform nearly identically (13,142-13,708 TPS), with Concur32 having a slight edge. Both are approximately equal to the system's physical core count (40 cores) or slightly above.

3. **Concur64 Wins at Extreme Oversubscription**: At 512 client threads, Concur64 pulls ahead (13,406 vs 12,750 TPS), showing a 5% advantage when client load is extremely high relative to core count.

4. **Massive Gap from Concur8**: Even in memory-resident workloads, Concur8 severely bottlenecks performance, achieving only 38-39% of optimal throughput at 128-256 threads, and just 25% at 512 threads.

5. **Concur16 Still Inadequate**: Despite doubling Concur8, Concur16 still achieves only 70-75% of optimal performance, demonstrating that even 16 concurrent threads inside InnoDB is insufficient for a 40-core system.

6. **Severe Degradation at 512 Threads**: Concur8 drops from 5,152 TPS at 128 threads to just 3,333 TPS at 512 threads (-35%), showing that low concurrency limits cause severe performance collapse under high client load even when I/O is not a factor.

**System Metrics Analysis:**

Examining vmstat data reveals why Concur32 degrades while Concur64 maintains performance at 512 threads (32G buffer pool):

**Concur16** (~9,500 TPS): Too restrictive with 1,024k-1,046k context switches/sec. 16-thread limit causes excessive context switching.

**Concur32** (degrades -7% at 512 threads): Queue depth explodes from 93→167 runnable processes. 820k context switches/sec. 32-thread limit becomes bottleneck under extreme load.

**Concur64** (stable 13,400-13,500 TPS): Lowest context switches at 628k/sec. Queue depth stays manageable at 110 processes. 64-thread limit handles high load efficiently.

At 512 threads, Concur32's limit causes queue depth to spike (167 vs 110 processes) and more context switches (820k vs 628k), creating serialization overhead that Concur64 avoids.

**Lock Contention Factor**: Memory-resident workloads shift bottlenecks from I/O to CPU and InnoDB locks. Higher concurrency limits improve parallelism across 40 cores, but Concur32 and Concur64 perform similarly because both saturate available CPU resources.

**Why Concur32 and Concur64 Are Nearly Identical at 32GB, But Not at Other Buffer Sizes:**

The optimal concurrency setting depends on which resource becomes the bottleneck:

- **2GB Buffer (I/O-Bound)**: Disk is the bottleneck. Concur32 saturates NVMe drives (~2,200-2,400 TPS). Concur64 adds no benefit—extra concurrency just increases context switching.

- **12GB Buffer (Mixed)**: Largest performance gap (5,300-5,600 vs 6,400+ TPS). Concur64 allows memory operations to proceed while I/O waits. Concur32's limit prevents full exploitation of cached data during I/O waits.

- **32GB Buffer (Memory-Resident)**: CPU/lock bottleneck. Both Concur32 and Concur64 saturate all 40 cores. Beyond ~32 threads contend for same resources.

### 8.4. Cross-Tier Performance Comparison

#### 8.4.1. Buffer Pool Scaling Analysis

**At 128 Client Threads with Concur64:**
- 2GB: 1,935 TPS (baseline)
- 12GB: 6,427 TPS (+232%)
- 32GB: 13,142 TPS (+579%)

**At 512 Client Threads with Concur64:**
- 2GB: 2,203 TPS (baseline)
- 12GB: 6,439 TPS (+192%)
- 32GB: 13,406 TPS (+509%)

**Insight:** Buffer pool increases provide 5-6x gains by eliminating I/O. Biggest jump: 2GB→12GB.

#### 8.4.2. Client Thread Scaling Analysis

Performance change as client threads increase from 128 to 512:

**Concur8 (Worst Scalability):**
- 2GB: 947 → 1,021 TPS (+8%)
- 12GB: 2,095 → 1,660 TPS (-21%)
- 32GB: 5,152 → 3,333 TPS (-35%)

**Concur64 (Best Scalability):**
- 2GB: 1,935 → 2,203 TPS (+14%)
- 12GB: 6,427 → 6,439 TPS (0%)
- 32GB: 13,142 → 13,406 TPS (+2%)

**Insight:** Low Concurrency limits degrade under load (especially memory-resident workloads). High Concurrency limits maintain stability, but not improving peak performance.

## 9. Limitations and Considerations

This benchmark provides performance insights but operates under specific constraints that should be considered when interpreting results:

**Single-Host Architecture:**
- All measurements reflect single-node performance only
- Replication topologies, cluster configurations, and proxy layers introduce additional overhead not captured in these tests
- Network latency and multi-node coordination costs are not represented in these results

**Synthetic Workload Characteristics:**
- The sysbench oltp_read_write workload provides a standardized OLTP approximation but does not capture the complexity of real application query patterns
- Actual production workloads exhibit varying query distributions, transaction sizes, and access patterns
- Results should be interpreted as directional indicators rather than absolute predictions of production performance

**Data Distribution Patterns:**
- Benchmark uses uniformly distributed random data access across the entire dataset
- Real-world applications typically exhibit non-uniform access patterns (hot rows, temporal locality, geographic clustering)
- Cache hit rates and I/O patterns may differ significantly in production environments with skewed data access

**Dataset Size Constraints:**
- 24GB working set is representative of small to medium database sizes
- Enterprise databases usually operate at much larger scales (hundreds of GB to TB range)
- Larger datasets may exhibit different performance characteristics, particularly regarding buffer pool efficiency and I/O patterns

**Concurrency Parameter Isolation:**
- This benchmark focuses exclusively on `innodb_thread_concurrency`
- Other concurrency-related parameters (innodb_read_io_threads, innodb_write_io_threads, etc.) were held constant
- Real-world tuning often requires adjusting multiple parameters at the same time

**Controlled Environment:**
- Tests run on dedicated hardware with minimal background processes
- Production environments experience variable load patterns, competing workloads, and system maintenance activities
- Real-world performance may be affected by factors not present in this controlled benchmark environment

These limitations do not diminish the value of the findings but provide important context for applying these results to production scenarios. The relative performance differences observed between configurations remain instructive even as absolute numbers may vary in different deployment contexts.

## 10. Reproducibility

This benchmark is designed to be reproducible on compatible systems. The testing framework and automation scripts are available in the project repository.

**System Requirements:**

**Operating System:**
- Ubuntu 24.04 LTS (current supported platform)
- Other Linux distributions may work but are not officially tested

**Software Prerequisites:**

Install required packages:
```bash
sudo apt install docker.io sysstat sysbench mysql-client dstat -y
```

**Docker Group Permissions:**

Add your user to the docker group to run containers without sudo:
```bash
sudo usermod -aG docker $USER
```

After running this command, log out and back in, or run `newgrp docker` to activate the new group membership.

**Root Access Requirement:**

The benchmark scripts require sudo privileges for:
- CPU frequency governor configuration (`cpupower`)
- System telemetry collection (iostat, vmstat, mpstat, dstat)
- Configuration file management

**Running the Benchmarks:**

The repository includes automated scripts for running the complete benchmark suite:

```bash
./run_all.sh
```

This script automatically:
- Checks the required components
- Installs additional dependencies
- Runs system profiling tools
- Executes benchmarks for each innodb_thread_concurrency value (8, 16, 32, 64)
- Tests all buffer pool configurations (2GB, 12GB, 32GB)
- Tests all client thread counts (128, 256, 512)
- Generates result directories with complete telemetry data

**Hardware Considerations:**

While the benchmark can run on various hardware configurations, results will vary significantly based on:
- CPU core count (affects optimal innodb_thread_concurrency value)
- Available RAM (determines realistic buffer pool tiers)
- Storage performance (critical for I/O-bound workloads)

**Adapting to Your System:**

The `innodb_thread_concurrency` values tested (8, 16, 32, 64) were chosen for a 40-core system. For different hardware:
- Systems with 16 cores: Consider testing 4, 8, 16, 32
- Systems with 20 cores: Consider testing 8, 16, 32, 48
- Systems with 64+ cores: Consider testing 16, 32, 64, 128

A common starting point is to set `innodb_thread_concurrency` to match your physical core count (not hyperthreaded count) and adjust based on workload characteristics.

**Result Files:**

Each test run produces:
- Sysbench output with TPS/QPS metrics
- System telemetry (iostat, vmstat, mpstat, dstat)
- Configuration files (my.cnf, SHOW VARIABLES, SHOW STATUS)

All files follow the naming pattern: `Tier{2G,12G,32G}_Concur{8,16,32,64}_{128,256,512}th.{sysbench,iostat,vmstat,mpstat,dstat}.txt`
