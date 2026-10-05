# MASTER PRODUCTION SCHEDULE (MPS)

#SETS
set PRODUCTS;
set MACHINES;
set PERIODS ordered; # t = 1..12 (months from Access)
set PRODMACH within (PRODUCTS cross MACHINES);
set ORDPROD dimen 2; 
set CALENDAR dimen 2;

# NEW SETS FILTERED FOR THE MPS (assembly excluded)
set MPS_MACHINES := MACHINES diff {"AssemblyTable"};
set MPS_PRODMACH := {(p,m) in PRODMACH: m != "AssemblyTable"};

#PARAMETERS

# Costs parameters (Imported from file Costs.mod)
param UnitProdCost {PRODUCTS} >= 0 default 0; # Unit production cost [euro/product]. 
param HoldingCost {PRODUCTS} >= 0 default 0;  # Unit holding cost [euro/product]. The cost of keeping an unsold items in the warehouse (tied-up capital, space, risk).
param SetupCost {PRODUCTS} >= 0 default 0;    # Setup cost [euro/SPO]. The fixed penalty paid every time a machine is stopped and reconfigured to start a new batch. 

# Demand and Inventory parameters
param RealDemand {PRODUCTS, PERIODS} >= 0 default 0; #Accepted demand by the RRP model
param OrdQ {PRODUCTS} >=0;                           # Number of products per each order
param InitInv {PRODUCTS} >= 0;                       # Initial inventory [number of products] (on hand). The physical quantity of items already available in the warehouse at the start of the planning horizon (t=0)
param MaxBatchCap {PRODUCTS} >= 0;                   # Maximum capacity of a single batch [number of products]. If we overcome that capacity, then we need to produce another batch (RO+1, SPO+1)
param MinBatchProd {PRODUCTS} >=0;                   # Minimum number of products that we can produce in a single batch [number of products]. If we need to produce only one product, it doesn't make sense to switch on the machine and pay the setup cost
param SetupTime {PRODMACH} >= 0 default 0;
param ProcTime {PRODMACH} >= 0 default 0;        # processing time: time required to process a single unit of a product [min]
param BigM := 100000;                            # For the activation of the Setup cost payment 
param LTPP {PRODUCTS} >= 0 default 0;            # Production Lead Time [Periods] (time between order released and order completed). 
param BatchCost {PRODUCTS} >= 0 default 0;       # Cost of one batch produced [euro/SPO]. Forklift driver taking away the full pallet, end-of-line testing or closing the case on the software

#FINITE CAPACITY PLANNING: Calendar & Capacity Parameters
param Lavorativo {CALENDAR} default 1; # 1 if it is a working day, 0 otherwise

# Sums of all the working days per each month with a for cycle in order to get the REAL working days of this specific month
param DaysInMonth {t in PERIODS} := 
    sum {(d,p) in CALENDAR: p == t} Lavorativo[d,p];



#From RRP
param MachQuantity {MACHINES} >= 0;
param Shift_Day {MACHINES} >= 0;     
param DeltaTj {MACHINES} >= 0;  
    

# TOTAL capacity of the plant in each period [min]
param AvailCap {m in MPS_MACHINES, t in PERIODS} := 
    (MachQuantity[m] * Shift_Day[m] * 8 * 60 * DeltaTj[m]) * DaysInMonth[t];
    

# VARIABLES 
var X {PRODUCTS, PERIODS} >= 0 integer;          # Produced quantity of product p in the period t
var S {PRODUCTS, 0..card(PERIODS)} >= 0 integer; # Inventory level at the end of period t
var RO {PRODUCTS, PERIODS} >= 0 integer;  # Production Orders Released (number of batches launched)
var SPO {PRODUCTS, PERIODS} >= 0 integer;  # Scheduled Production Orders (number of batches completed)


#OBJECTIVE FUNCTION
minimize Total_MPS_Cost:
    sum {p in PRODUCTS, t in PERIODS} 
        (UnitProdCost[p] * X[p,t] + 
         HoldingCost[p] * S[p,t] + 
         SetupCost[p] * RO[p,t] + 
         BatchCost[p] * SPO[p,t]);        # If we produce a batch then Setup cost must be active. If we produce 1 or 200 pieces on the same machine the Setup cost remains the same because in any case the machine must be switched on. It all depends on whether we produce or not
                                          


#CONSTRAINTS     
# 1. Flow Balancing Constraint (inventory balance) (Main constraint)
 # previous stock + current production = current demand + new stock
subject to Inv_Balance {p in PRODUCTS, t in PERIODS}:
    S[p, t-1] + X[p,t] = (RealDemand[p,t]*OrdQ[p]) + S[p,t];
                                                                           

subject to Init_Pipeline {p in PRODUCTS, t in PERIODS: t <= LTPP[p]}:
    SPO[p,t] = 0;   #If the planning horizon begins in January (month 1) and the production of a batch requires a 1-month lead time, it is physically impossible to record completed batches (SPO) during the month of January, as there has not been the necessary physical time to process them.     
					#In other words: until the lead time of a product has passed, nothing can leave the factory (no work in progress is inherited from the previous year).

#2 Lead time constraint
subject to LeadTime_Link {p in PRODUCTS, t in PERIODS: t > LTPP[p]}:
    SPO[p,t] = RO[p, t - LTPP[p]];                                         
              #The batches completed in month t (SPO) are exactly those released (RO) in month t-LTPP.
              #If the lead time of a brake is 2 months and the order is released in January, the batches completed in March are those released in January.

# 3. On-hand (inventory) constraints
subject to Init_Inventory {p in PRODUCTS}:
    S[p, 0] = InitInv[p];                            #see Access table for the initial inventory

# 4. Setup constraint (Big-M activation)
subject to Setup_Activation {p in PRODUCTS, t in PERIODS}:
    X[p,t] <= BigM * SPO[p,t];  #X is the number of finished pieces ready to be sold or stored at time t; SPO is the number of batches completed at time t.
                                                                       #Pieces physically reach the warehouse only when the batch is completed (SPO), so completion is the logical switch.
    
# 5. Minimum batch size and maximum batch capacity
subject to Maximum_Batch {p in PRODUCTS, t in PERIODS}:
    X[p,t] <= MaxBatchCap[p] * SPO[p,t];  #A batch has a fixed capacity: MaxBatchCap is the threshold that, once exceeded, opens a new batch (SPO+1) and charges a new fixed batch cost
    
subject to Min_Production_Threshold {p in PRODUCTS, t in PERIODS}:
    X[p,t] >= MinBatchProd[p] * (if SPO[p,t] >= 1 then 1 else 0);  #Produce only if the quantity reaches the minimum batch size: it makes no sense to switch on a machine and pay the setup to produce a single brake
                                        
# 6. Production capacity constraint per period
subject to Prod_Capacity {m in MPS_MACHINES, t in PERIODS}:
    sum {p in PRODUCTS: (p,m) in MPS_PRODMACH} 
    (ProcTime[p,m] * X[p,t] + SetupTime[p,m] * RO[p,t]) <= AvailCap[m,t];  #The setup (operator changing the tools) happens at the start of production, i.e. when the order is released (RO).
                                                                           #In other words, machine capacity is consumed in the month the order is released (RO), not when it is completed (SPO)
