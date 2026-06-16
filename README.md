# 32-Bit Out-of-Order RISC-V Processor (RV32I)

A 32-bit scalar Out-of-Order (OoO) processor implementing the RV32I instruction set architecture. Written in SystemVerilog, this core features hardware-level dynamic scheduling using Tomasulo's algorithm, speculative execution, and precise exception handling through a Reorder Buffer (ROB).

---

## System Architecture Overview

This project explores deep instruction-level parallelism (ILP) by decoupling instruction fetch and dispatch from execution and retirement. The microarchitecture allows independent instructions to execute dynamically out of program order while guaranteeing strict in-order commit. 

**Core Specifications:**
* **ISA:** RV32I (Base Integer Instruction Set)
* **Scheduling:** Tomasulo's Algorithm with Register Renaming
* **Hardware Description:** SystemVerilog (IEEE 1800)
* **Simulation/Verification Environment:** ModelSim (Debian Linux target)

---

## Microarchitecture Deep Dive

### 1. Instruction Fetch & Speculative Execution
The frontend implements a highly responsive fetch stage aligned with a 0-cycle latency memory model, supported by an advanced branch prediction unit to minimize pipeline stalls.
* **Branch Target Buffer (BTB):** 256-entry direct-mapped buffer calculating speculative target addresses to prevent fetch bubbles.
* **Branch History Table (BHT):** 256-entry table utilizing standard 2-bit saturating counters (Strongly Not Taken to Strongly Taken) for conditional direction prediction.
* **Misprediction Recovery:** Branch mispredictions are buffered until the branch instruction reaches the head of the ROB. At commit, the ROB initiates a global pipeline flush and redirects the Program Counter to the correct architectural path.

### 2. Distributed Reservation Stations (RS)
To prevent stalls in unrelated instruction streams, the architecture utilizes decentralized, decoupled reservation stations mapping to specific functional units. This eliminates Write-After-Write (WAW) and Write-After-Read (WAR) hazards.
* **ALU Subsystem:** 8-entry Reservation Station feeding dedicated execution blocks:
  * Arithmetic (Add/Sub)
  * Logical (And/Or/Xor)
  * Shift (Logical/Arithmetic, Left/Right)
  * Compare (Signed/Unsigned)
* **Branch Subsystem:** 4-entry Reservation Station dedicated to resolving conditional and unconditional jumps (JAL, JALR).
* **Load/Store Queue (LSQ):** 8-entry Reservation Station managing memory operations.

### 3. Memory Subsystem & Disambiguation
The memory unit is designed to handle out-of-order address calculation and execution while maintaining strict memory consistency.
* **Store-to-Load Forwarding:** The LSQ actively snoops memory addresses. If a younger load perfectly aliases with an older, uncommitted store, the data is forwarded directly within the queue, bypassing the memory access latency.
* **In-Order Store Commit:** Stores are held speculatively in the LSQ and only dispatched to physical memory once they reach the head of the ROB and are officially retired.

### 4. Common Data Bus (CDB) & Broadcast Network
A high-throughput arbitration network handles the propagation of executed results back to dependent instructions.
* **Integrated FIFO Buffer:** The CDB features a 64-entry deep FIFO queue capable of buffering multiple simultaneous completion events.
* **Multi-Push Capability:** The bus logic supports up to 3 simultaneous result pushes per cycle (ALU, LSU, Branch) to prevent structural hazards at the execution writeback stage.

### 5. Reorder Buffer (ROB)
The core of the precise exception and in-order retirement mechanism.
* **Capacity:** 32-entry circular queue.
* **Functionality:** Tracks the speculative state of all dispatched instructions. It commits results to the architectural Register File only when an instruction becomes the oldest in the machine and has executed without faults.

---

## Simulation and Verification

### Prerequisites
* Intel Quartus Prime / ModelSim
* SystemVerilog (IEEE 1800-2012) compatible simulator

### Build Instructions
1. Clone the repository to your local environment.
   ```bash
   git clone [https://github.com/yourusername/ooo-riscv-processor.git](https://github.com/yourusername/ooo-riscv-processor.git)
