# 8-bit Timer + SAR ADC Peripheral on a RISC-8 5-Stage CPU

A memory-mapped **8-bit timer and 8-bit SAR ADC controller** (4 channels, 8-entry result FIFO, window check,
6 interrupt flags) attached to an instructor-provided **RISC-8 5-stage pipelined CPU**.
The CPU runs real firmware that starts conversions by software and by timer events, polls the status
registers, reads the results and stores them in RAM. Everything is verified in simulation
(Vivado xsim 2026.1, cross-checked with Icarus Verilog).

> **Scope:** simulation project. The design has not been synthesized for a board in this repository
> (no clock constraints, pin mapping or hardware test).

## Highlights

- Timer: prescaler, 8-bit counter, compare event, overflow event, PWM output, free-running and one-shot modes
- SAR ADC: sample-and-hold window, 8 trial steps (MSB first), programmable clock divider,
  conversion time `(SMP + 1 + 8) x (DIV + 1)` clocks
- 8-entry result FIFO (`{channel, code}`), window comparator, trigger select (software / timer overflow /
  timer compare / continuous), 6 sticky write-1-to-clear interrupt flags
- 16-register map in the CPU data space at `0xF0` to `0xFF`; one clock per access, no wait states
- Integration without editing the instructor's files
- Verification: self-checking block tests, a UVM 1.2 environment for timer and ADC, a system test that runs
  firmware on the CPU, and bug-injection checks

## Architecture

![SoC block diagram](docs/images/soc_block_diagram.png)

The top module `risc8_soc` holds the CPU (`u_cpu`) and the peripheral (`u_tadc`), joined by five signals:
`io_cs`, `io_we`, `io_addr[3:0]`, `io_wdata[7:0]` and `io_rdata[7:0]`.

![Peripheral architecture](docs/images/peripheral_architecture.png)

### Two design decisions that come from the CPU

| CPU property | Consequence |
|---|---|
| No "load in progress" strobe (the address bus changes every clock, even for non-loads) | Reads must have **no side effects**. Reading `ADC_DATA` only *peeks* at the oldest FIFO entry; **writing any value to `ADC_DATA` pops it** |
| No interrupt input, no RETI opcode | The firmware **polls** `ADC_STAT` / `IRQ_STAT`. The `irq` pin is still driven (observation and future use) |

## Repository layout

```
rtl/                 timer8.v  sar_adc_ctrl.v  sync_fifo.v  apb_regs8.v  timer_adc8_top.v  timer_adc8_cpu_if.v
sv/                  sar_afe_model_mv.sv          analog front-end model (simulation only)
soc/                 risc8_soc.v                  design top: CPU + peripheral
                     make_core_io.py              creates risc8_5stage_core_io.v from the instructor's core
                     alt_dmem/dmem.v              alternative integration (see below)
tb/                  tb_timer8.v  tb_sync_fifo.sv  tb_top_apb.v  tb_soc_top.v  tb_soc_alt.v
tb/uvm/              UVM environment for timer and ADC (copy your files here, see tb/uvm/README.md)
sw/                  program_soc.s  program_soc.hex  asm8.py (mini assembler)
scripts/run_all.sh   runs every simulation with Icarus Verilog
docs/                project report (Word) and figures
```

## Register map (base `0xF0`)

| Off. | Name | Type | Description (reset) |
|---|---|---|---|
| 0x0 | `TMR_CTRL` | RW | `[0]` EN, `[1]` ONESHOT (hardware clears EN after the first overflow) (00) |
| 0x1 | `TMR_PRESC` | RW | one step every PRESC+1 clocks (00) |
| 0x2 | `TMR_LOAD` | RW | counter runs 0..LOAD (FF) |
| 0x3 | `TMR_CMP` | RW | compare value / PWM threshold (80) |
| 0x4 | `TMR_CNT` | RO | current counter |
| 0x5 | `ADC_CTRL` | RW | `[0]` EN, `[1]` START (reads 0), `[3:2]` TRIG_SEL, `[5:4]` CH (00) |
| 0x6 | `ADC_SMP` | RW | sample time = SMP+1 steps (04) |
| 0x7 | `ADC_DIV` | RW | step = DIV+1 clocks (00) |
| 0x8 | `ADC_THR_LO` | RW | window lower limit (00) |
| 0x9 | `ADC_THR_HI` | RW | window upper limit (FF) |
| 0xA | `ADC_DATA` | RO / pop | **read: oldest code (no pop) - write any value: pop one entry** |
| 0xB | `ADC_RCH` | RO | `[7]` VALID, `[1:0]` channel of the oldest entry |
| 0xC | `ADC_STAT` | RO | `[3:0]` LEVEL, `[4]` EMPTY, `[5]` FULL, `[6]` BUSY (10) |
| 0xD | `IRQ_EN` | RW | enable bit per flag (00) |
| 0xE | `IRQ_STAT` | W1C | `0` TMR_OVF, `1` TMR_CMP, `2` ADC_EOC, `3` ADC_WD, `4` FIFO_OVR, `5` TRIG_MISS (00) |
| 0xF | `ID` | RO | `0xA8` |

`TRIG_SEL`: `0` software (START bit), `1` timer overflow, `2` timer compare, `3` continuous.

Formulas: timer period `(PRESC+1) x (LOAD+1)` clocks, PWM duty `CMP / (LOAD+1)`,
ideal ADC code `floor(Vin x 256 / 3300 mV)` limited to 255 (1 LSB = 12.9 mV).

## Getting started

### Prerequisites

- Icarus Verilog 12 or newer (for `scripts/run_all.sh`), Python 3
- Vivado 2026.1 (optional, for xsim and UVM)
- **The instructor's RISC-8 core files** (`alu.v`, `control_unit.v`, `hazard_unit.v`, `imem.v`, `regfile.v`,
  `dmem.v`, `risc8_5stage_core.v`). They are **not included** in this repository.

### Run all tests

```sh
TEACHER=/path/to/risc8_5stage ./scripts/run_all.sh
```

Expected output:

```
== timer8
tb_timer8: PASS
== sync_fifo
tb_sync_fifo: PASS
== peripheral over APB
tb_top_apb: PASS
== SoC: risc8_soc (core copy with io_* bus)
*** risc8_soc: ALL TESTS PASSED ***
== SoC: alternative (replacement dmem, instructor's core untouched)
*** SOC: ALL TESTS PASSED ***
```

### Two ways to attach the peripheral

1. **`risc8_soc` (main).** `soc/make_core_io.py` reads the instructor's `risc8_5stage_core.v` and writes
   `risc8_5stage_core_io.v`: the module gets a new name and five `io_*` ports, and the `0xF0-0xFF` page leaves
   through them. The instructor's file is never modified.
2. **Replacement `dmem` (alternative).** `soc/alt_dmem/dmem.v` has the same module name and ports as the instructor's
   `dmem.v` but contains the peripheral, so `risc8_5stage_core.v` is used as is. Use it with `tb/tb_soc_alt.v`.
   Never put both `dmem.v` files in one project.

### Vivado 2026.1 (risc8_soc)

1. Design sources: the instructor's `alu`, `control_unit`, `hazard_unit`, `imem`, `regfile`, `dmem`; the generated
   `risc8_5stage_core_io.v`; `rtl/*.v`; `soc/risc8_soc.v`. Set **`risc8_soc`** as the design top.
2. Simulation sources: `sv/sar_afe_model_mv.sv`, `tb/tb_soc_top.v`, `sw/program_soc.hex`. Set **`tb_soc_top`** as the
   simulation top and run `run all` (or set `xsim.simulate.runtime` to `-all`).
3. Expected last line: `*** risc8_soc: ALL TESTS PASSED ***`.
4. If the hex file is not found, put an absolute path (forward slashes) into `HEX_FILE` at the top of `tb_soc_top.v`.
5. Peripheral only (no CPU): design top `timer_adc8_top`, simulation sources `sv/sar_afe_model_mv.sv` + `tb/tb_top_apb.v`.
6. UVM: see `tb/uvm/README.md` (needs `-L uvm`).

## Example firmware

`sw/program_soc.s` (assembled to `sw/program_soc.hex` with `python3 sw/asm8.py sw/program_soc.s sw/program_soc.hex`):

```asm
        LDI  r1, 0xF5          ; ADC_CTRL
        LDI  r2, 0x23          ; EN | START | CH=2 | software trigger
        ST   r2, [r1]
        LDI  r3, 0xFC          ; ADC_STAT
        LDI  r4, 0x10          ; EMPTY mask
pollA:  LD   r5, [r3]
        AND  r5, r5, r4        ; non-zero while the FIFO is empty
        BNZ  pollA
        LDI  r6, 0xFA          ; ADC_DATA
        LD   r7, [r6]          ; peek the result (0x56 for 1111 mV)
        ST   r7, [r6]          ; any write = pop
```

The full program also runs timer-triggered conversions, reads `ADC_RCH`, clears flags by write-1 and reads the ID.

## Verification results

| Test | What it covers | Result |
|---|---|---|
| `tb_timer8` | period, compare position, PWM duty, EN=0 clears | PASS |
| `tb_sync_fifo` | order, flags, overflow drop, 2000 random cycles vs. a queue model | PASS |
| `tb_top_apb` | all 16 registers, 4 channels, pop by write, W1C and `irq`, window, continuous mode, FIFO full/overflow, abort, one-shot, timer triggers, `TRIG_MISS` | PASS |
| UVM ADC | 28 transactions (8 corner + 20 random): code and latency vs. reference model | PASS, 0 errors |
| UVM timer | 26 runs (6 corner + 20 random): pulse positions, PWM count, EN=0 | PASS, 0 errors |
| `tb_soc_top` | CPU runs the firmware to HLT; 7 RAM results, PWM and `irq` pins | PASS |

Bug injection: 6 bugs planted one at a time in the peripheral (pop on read, one-shot not clearing EN, wrong window
boundary, no W1C, no `TRIG_MISS`, FIFO accepting when full) and 3 at system level (no writes reach the peripheral,
wrong I/O page, no read data): all detected.

![One ADC conversion](docs/images/waveform_sar_conversion.png)

`adc_dac` steps through `80, 40, 60, 50, 58, 54, 56, 57` and the comparator pattern gives `0x56` (86) for 1111 mV.

![Firmware run](docs/images/waveform_soc_run.png)

## Limitations and future work

- The core has no interrupt input; adding one (and a RETI instruction) would allow an interrupt routine instead of polling.
- The analog front end is an ideal behavioural model.
- Not yet synthesized or implemented for a board; no timing, utilization or hardware results.
- UVM is limited to the timer and ADC blocks (no register model or functional coverage yet).

## Report

The full project report is in [`docs/Project_Report_Timer_ADC_RISC8.docx`](docs/Project_Report_Timer_ADC_RISC8.docx).

## Credits

The RISC-8 5-stage core is provided by the course instructor and is not redistributed here.
The peripheral architecture follows the course lectures (Day 1 to Day 3: timer, SAR ADC, APB registers, UVM).
