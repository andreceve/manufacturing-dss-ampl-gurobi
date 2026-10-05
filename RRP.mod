# RESOURCE REQUIREMENT PLANNING (RRP)

#SETS 
set PRODUCTS;
set MACHINES;
set PRODMACH within (PRODUCTS cross MACHINES);
set ORDPROD dimen 2; 
set CALENDAR dimen 2;

# NEW SETS FILTERED FOR THE RRP (Excluding the AssemblyTable machine)
set RRP_MACHINES := MACHINES diff {"AssemblyTable"};
set RRP_PRODMACH := {(p,m) in PRODMACH: m != "AssemblyTable"};


#PARAMETERS 
param Revenue {PRODUCTS} >= 0 default 0; #We consider it as: Selling price - Cost of raw materials [euro] (in the slide in the objective function is:  pr[i,o]- pr[i])
param Demand {PRODUCTS} >= 0 default 0; #annual demand for each product (we used it to calculate the parameter OrdQ which is in the table product in Access). By doing Demand which is in the table PRODUCT divided by the sum of the DemandProfile which is in the table ORDPROD for the different months for the same product, we obtained the number of products in a single order which is OrdQ
param Handling {PRODUCTS} >=0; #handling time (time for moving one piece from a machine to another) [min]. If we see it in this way it has an impact only on the worker time because while the worker is moving one piece from a M01 to M02 for example, in the meanwhile M01 can be charged and continue to produce another piece (same reasoning has been made in the scheduling part)
param ManualAssembly {PRODUCTS} >= 0 default 0;  #Manual assembly time of the operator for each single product [min]. It has an impact only on the worker time
param OrdQ {PRODUCTS} >=0; # quantity of products present in a single order. For example In january we have 15 orders of brakes (DemandProfile for brake in january is 15). If we do OrdQ*15 we obtain the number of products brakes ordered in january.

param CapitalCost {MACHINES} >= 0 default 0; #investement cost to purchase the machine. It must be multiplied by 1000 from Access to express it in thousands.
param Lifespan {MACHINES} >= 0 default 1;    #useful life of the machine [days]. In Access it is in years and it must be converted in days, and we did it in the objective function
param ProductionCost {MACHINES} >= 0 default 0; #operating cost of the machine [euro/min] (electricity, light, sensor functioning etc...)
param DeltaTj {MACHINES} >= 0 default 1; #efficiency coefficient of the machine
param Shift_Day {MACHINES} >= 0 default 1; #working shift of the machine [number of shift per day]

param ProcTime {PRODMACH} >= 0 default 0; #processing time: time required to process a single unit of a product on a specific machine [min]. It has an impact only on the machine time
param SetupTime {PRODMACH} >= 0 default 0; #time needed to set up the machine before starting to produce an order (or batch) of a specific product[min]. It has an impact on both worker and machine time because the operator must prepare the machine (worker time) and the machine must be switched off in order to be prepared to start the production of an order (machine time).

param DemandProfile {ORDPROD} >=0; #number of orders of a product p in a certain period t


param wt >= 0;  # Number of basic (permanent) workers already on staff
param wc >= 0;  # worker cost: Cost to hire a single seasonal worker

#CALENDAR
#We read if it is a working days (1) or not (0)
param Lavorativo {CALENDAR} default 1;

# Set of periods extracted automatically from the calendar
set PERIODS := setof {(d,t) in CALENDAR} t;

# Working days in EACH period t
param Period_Days {t in PERIODS} := sum {(d,t) in CALENDAR} Lavorativo[d,t];

# Horizon_Days is kept for the annual calculations
param Horizon_Days := sum {t in PERIODS} Period_Days[t];


#VARIABLES 
var Accepted {ORDPROD} binary; #Acceptance of the demand. Accepted=1 if order is accepted, otherwise Accepted=0            
var MachQuantity {MACHINES} integer >= 0; #number of machine of a specific type that we decide to buy in our company 
var sw >= 0 integer; #number of seasonal workers we hire


#OBJECTIVE FUNCTION   
maximize Production_Profit:
    # 1.Total sales revenue
    sum {(p,t) in ORDPROD} (Revenue[p] * DemandProfile[p,t] * OrdQ[p] * Accepted[p,t])
    
    # 2. Production Operating Costs calculated only on real routings
    - sum {(p,t) in ORDPROD, m in RRP_MACHINES: (p,m) in PRODMACH} 
      ((ProcTime[p,m] * DemandProfile[p,t] * OrdQ[p] * Accepted[p,t]) * ProductionCost[m])
      
    # 3. Fixed Capital Expenditures for Machinery Depreciation
    - sum {m in RRP_MACHINES} (((CapitalCost[m]*1000 * Horizon_Days) / (Lifespan[m]*365)) * MachQuantity[m])  #1000 represents the conversion into thousands
    
    # 4. Penalty costs
    - wc * sw;
    
    
#CONSTRAINTS 
    
#Machine constraint evaluated month per month
subject to Machine_Capacity {m in RRP_MACHINES, t in PERIODS}:
    sum {p in PRODUCTS: (p,t) in ORDPROD and (p,m) in RRP_PRODMACH} 
        ( (ProcTime[p,m] * OrdQ[p] + SetupTime[p,m]) * DemandProfile[p,t] * Accepted[p,t] ) 
    <= MachQuantity[m] * (Shift_Day[m] * 60 * 8 * DeltaTj[m] * Period_Days[t]);      #We assumed that each working shift is of 8 hours. 60 represents the conversion into minutes
                                                                                     #We assumed that the Setup of the machine is made for each order created
    
    
 
#Workers constraint evaluated month per month
subject to Labor_Capacity {t in PERIODS}: 
    # 1. Calculation of work at the assembly bench + 1 Final handling to bring the pieces from the last machine to the assembly bench
    sum {p in PRODUCTS: (p,t) in ORDPROD} 
        ( (ManualAssembly[p] + Handling[p]) * DemandProfile[p,t] * OrdQ[p] * Accepted[p,t] ) #each product in each order must be assembled and brought to the AssemblyTable (remember: we assumed that the Assembly tables were pre-existing in our company)
    +
    # 2. Work calculation for CNC machines (Handling between machines + Setup for EACH order)
    sum {p in PRODUCTS, m in RRP_MACHINES: (p,t) in ORDPROD and (p,m) in RRP_PRODMACH} 
        ( (Handling[p] * OrdQ[p] + SetupTime[p,m]) * DemandProfile[p,t] * Accepted[p,t] )
    <= (wt + sw) * 8 * 60 * Period_Days[t];                                                # Handling, ManualAssembly and Setup are operations that require an operator
