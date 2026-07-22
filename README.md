# 2-Way Set Associative Cache

This project implements a basic **2-way set associative cache** using SystemVerilog.

## Files

* `cache_2way.sv` – Contains the 2-way set associative cache and simple main memory.
* `tb_cache_2way.sv` – Testbench used to test the cache.

## Cache Features

* 2-way set associative cache
* 8 cache sets
* 4 words per cache block
* 8-bit data
* 10-bit address
* Valid bits
* Tag, index (set), and offset
* Cache hit and miss detection
* LRU replacement policy
* Read hits
* Write hits
* Write misses with block allocation
* Simple main memory with fixed delay

## Address Format

The CPU address is divided into three parts:

```text
+---------+-------+--------+
|   TAG   | INDEX | OFFSET |
+---------+-------+--------+
```

* **Tag** identifies the memory block.
* **Index** selects the cache set.
* **Offset** selects the word inside the cache block.

For this design:

* Tag = 5 bits
* Index = 3 bits
* Offset = 2 bits

## Cache Operation

### Cache Hit

When the requested block is already in the cache:

1. The tag is compared with both ways.
2. If a matching valid tag is found, it is a cache hit.
3. The requested data is returned.
4. The accessed way becomes the most recently used way.

### Cache Miss

When the requested block is not found:

1. The cache detects a miss.
2. The LRU way is selected for replacement.
3. The complete block is loaded from main memory.
4. The block is stored in the selected cache way.
5. The original CPU request is completed.

## LRU Replacement

Each set has two ways:

```text
Set
+---------+
| Way 0   |
+---------+
| Way 1   |
+---------+
```

The cache uses one LRU bit per set to decide which way should be replaced when both ways are occupied.

## Write Policy

The cache uses a simple write-allocate approach.

* On a **write hit**, data is updated directly in the cache.
* On a **write miss**, the block is first loaded from memory and then the new data is written into the cache.

This design does **not** use dirty bits or write-back logic.

## Testbench

The testbench checks:

1. Write to address A – miss and block allocation.
2. Read A – hit.
3. Write to address B – miss and use the second way.
4. Read A and B – both should hit.
5. Write to address C – causes LRU replacement.
6. Read C – hit.
7. Read B – hit because B was not evicted.
8. Read A – miss because A was replaced.

The testbench also checks the returned data and whether each request was a hit or miss.

## Simulation

Add both files to your SystemVerilog project:

```text
cache_2way.sv
tb_cache_2way.sv
```

Set the simulation top module to:

```text
tb_cache_2way
```

Then run the simulation and check the console output for:

```text
RESULT: ALL TESTS PASSED
```

## Summary

This project demonstrates the basic working of a **2-way set associative cache**, including cache hits, misses, block allocation, and LRU replacement.
