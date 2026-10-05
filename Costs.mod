# ECONOMIC CALCULATOR: unit production, holding and setup costs of each product

set PRODUCTS;
set MACHINES;
set PRODMACH within (PRODUCTS cross MACHINES);

#INPUT PARAMETERS (from Access)
param ProductionCost {MACHINES} >= 0 default 0; 
param ProcTime {PRODMACH} >= 0 default 0;       
param SetupTime {PRODMACH} >= 0 default 0;
param StorageCostPerKg >= 0 default 0.02;   # DAILY storage cost per kg in the warehouse (assumption based on market data)
param UnitProdWeight {PRODUCTS}>=0;
param DaysInMonth := 30;                    # Conversion factor for the monthly logic: a product can stay up to 30 days in the warehouse

#FORMULAS

#pc: Unit production cost 
param Calc_UnitProdCost {p in PRODUCTS} := 
    sum {(p,m) in PRODMACH} (ProcTime[p,m] * ProductionCost[m]);

#hc: Holding cost 
param Calc_HoldingCost {p in PRODUCTS} := 
    UnitProdWeight[p] * StorageCostPerKg * DaysInMonth;

# setc: Setup cost
param Calc_SetupCost {p in PRODUCTS} := 
    sum {(p,m) in PRODMACH} (SetupTime[p,m] * ProductionCost[m]);

param UnitProdCost {PRODUCTS} >= 0 default 0;
param HoldingCost {PRODUCTS} >= 0 default 0;
param SetupCost {PRODUCTS} >= 0 default 0;
