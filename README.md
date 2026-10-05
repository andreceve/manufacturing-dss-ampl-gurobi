# Decision Support System for an Automotive Manufacturing Plant — AMPL + Gurobi

Course project for **PMaO**, MSc programme, University of Bologna (A.Y. 2025/2026).
Team project by Andrea Cevenini and Marco Buonfantino.

A **hierarchical production planning** system for a job-shop plant that makes six
automotive products (brake, clutch, piston, shaft, shift, wheel). Four optimization models,
written in **AMPL** and solved with **Gurobi**, go from the yearly sizing of the plant down to
the minute-by-minute schedule of the shop floor. All data live in a **Microsoft Access**
database: each model reads its inputs through ODBC and writes its decisions back, so the
output of one level becomes the input of the next.

![Job shop schedule](images/job_shop_gantt.png)

---

## Architecture

| Level | Model | Horizon | Type | Decides |
|---|---|---|---|---|
| 0 | `Costs.mod` | — | Pre-processing | Unit production, holding and setup cost of each product |
| 1 | **Resource Requirement Planning** `RRP.mod` | 12 months | MILP, max profit | Which customer orders to accept, how many machines of each type to buy, how many workers to hire |
| 2 | **Master Production Schedule** `MPS.mod` | 12 monthly buckets | MILP, min cost | Monthly production, inventory, released and completed batches, with lead times, batch sizes and finite capacity |
| 3 | **Green Material Requirements Planning** `MRP.mod` | 12 monthly buckets | MILP, min cost | BOM explosion, purchase orders in whole boxes, supplier selection with transport cost and **CO₂ tax** |
| 4 | **Job Shop Scheduling** `sched.mod` | continuous time [min] | MILP, min makespan | Start time of every batch on every machine, allocation to parallel machine copies, sequencing with disjunctive Big-M constraints |

### Main modelling features

- **Real calendar:** capacities are computed from the working days of each month (holidays
  excluded), shifts per day, 8-hour shifts and machine efficiency.
- **Order acceptance:** the RRP can reject orders when they would overload the bottleneck
  machines in a given month.
- **Lead-time pipeline in the MPS:** batches completed in month *t* are those released in
  month *t − LT*; setup time consumes capacity when the order is released.
- **Batch logic:** maximum batch capacity, minimum batch size, setup and batch costs
  activated with Big-M constraints.
- **Green logistics in the MRP:** every truck from a supplier costs distance × cost per km
  plus distance × CO₂ emission × CO₂ tax, so the solver trades transport emissions against
  holding cost.
- **Parallel machines in the scheduling:** each batch is assigned to exactly one physical copy
  of each machine of its routing; assembly benches have 3 operators working in parallel.

---

## Results

| Model | Result |
|---|---|
| RRP | Net profit **€11.31 M** over 261 working days; **16 machines** bought and **61 workers** hired; Piston orders rejected in months 4 and 9 to protect the bottleneck |
| MPS | Total cost **€273,711**; demand fully satisfied with batch production and almost no inventory after month 2 |
| Green MRP | Total supply cost **€9.75 M**, including transport and CO₂ penalties; stress test with a higher CO₂ tax shifts purchases to closer suppliers |
| Scheduling | Optimal makespan **6,312 min (105.2 h)**, which fits in about 13 working days of a monthly bucket |

![Master production schedule](images/mps_production_plan.png)

The full formulation, the validation and the stress tests (demand peaks, margin collapse,
CO₂ tax, storage cost) are described in the [report](docs/Report_Manufacturing_DSS.pdf).

---

## Repository structure

```
ampl/
  Costs.mod     RunCosts.run   % cost pre-processing
  RRP.mod       RRP.run        % resource requirement planning
  MPS.mod       MPS.run        % master production schedule
  MRP.mod       MRP.run        % green material requirements planning
  sched.mod     sched.run      % job shop scheduling
  Database.accdb               % Access database with all inputs and outputs
data/csv/                      % read-only export of every database table
docs/
  Report_Manufacturing_DSS.pdf
  Presentation_Manufacturing_DSS.pptx
images/
```

The CSV files are a snapshot of the database **after** all models were run (so they also
contain the accepted orders, the machine quantities and the MPS plan). They are included so
the data can be read directly on GitHub.

## How to run

Requirements: AMPL with the **Gurobi** solver, Windows with the Microsoft Access ODBC driver
(the `.run` files read and write `Database.accdb` with AMPL's `table ... 'odbc'` handler).

From the `ampl/` folder, run the models in this order, since each one writes the inputs of
the next:

```
ampl: include RunCosts.run;   # writes UnitProdCost, HoldingCost, SetupCost to Product
ampl: include RRP.run;        # writes Accepted to ORDPROD and MachQuantity to Machines
ampl: include MPS.run;        # writes the plan to MPS_Table
ampl: include MRP.run;        # reads MPS_Table
ampl: include sched.run;      # reads the batches from Jobs
```

Before running the scheduling, set `MachQuantity` of `AssemblyTable` to **13** in the
`Machines` table (the RRP sizes only the CNC machines and leaves the assembly benches at 0).

## Tools

AMPL · Gurobi · Microsoft Access (ODBC) · Mixed-integer linear programming

## Keywords

Production planning · Hierarchical planning · RRP · MPS · MRP · Job shop scheduling ·
Mixed-integer programming · Big-M · Green logistics · Decision support system
