# GREEN MRP (monthly periods + Access database)

#The missing component BrakeBox was added to the CompSupp table, with the same CostOfBox and supplier as ClutchBox

set PRODUCTS;
set COMPONENTS;
set SUPPLIERS;
set PERIODS ordered; 

# Bridge sets
set BOM within (PRODUCTS cross COMPONENTS);
set COMP_SUPP within (COMPONENTS cross SUPPLIERS);

#1. DATA FROM MPS
param MPS_Plan {PRODUCTS, PERIODS} >= 0 default 0;  # X[p,t] computed by the MPS

# DATA FROM ACESS DATABASE
# From table BOM
param nProdComp {BOM} >= 0 default 1;

#From table Product
param LTPP {PRODUCTS} >= 0 default 0;  #Used in the MPS: time needed by the factory to take the raw components from the warehouse, process them and obtain the finished product (e.g. 1 month for the brake).

# From table Component
param UnitWeight {COMPONENTS} >= 0 default 0;  
param BoxWeight {COMPONENTS} >= 0 default 0;   
param PcsPerBox {COMPONENTS} >= 1 default 1;   
param MagInit {COMPONENTS} >= 0 default 0;    

# From table Supplier
param Distance {SUPPLIERS} >= 0; #Km done by the suppliers [Km]

#Supplier lead time on a monthly basis
# If a supplier delivers in less than 30 days, in a monthly plan the arrival is instantaneous (LT=0).
param LT_Supp {s in SUPPLIERS} := 0;  #Travel time of the supplier's truck from its depot to our warehouse. Set to zero because the plan is monthly: with the distances in the Access tables, no supplier needs more than one month

# From table CompSupp
param CostOfBox {COMP_SUPP} >= 0 default 5; #Cost of each ordered box including the components inside!!

#3. LOGISTIC AND SUSTAINABILITY PARAMETERS
param CostPerKm >= 0 default 1.5;           #assumption from internet [euro/km]
param CO2EmissionPerKm >= 0 default 0.9;    #assumption from internet [Kg of CO2/Km]
param CO2Tax >= 0 default 0.05;             #assumption from internet [euro/Kg of CO2]
param StorageCostPerKg >= 0 default 0.02;  #assumption based on market data: DAILY storage cost of 0.02 euro per kg
                   
param DaysInMonth := 30;  # Conversion factor for the monthly logic
param BigM := 1000000;
param MaxT := max {t in PERIODS} t;  #max is 12 months


# 4. MONTHLY CALCULATIONS

#Monthly holding cost of each component in the warehouse
#Multiplied by the days of the month to charge the whole monthly storage.
param HoldingCostComp {c in COMPONENTS} := 
    (UnitWeight[c] + (BoxWeight[c] / PcsPerBox[c])) * StorageCostPerKg * DaysInMonth;  #BoxWeight/PcsPerBox spreads the weight of the box over the pieces it contains, so that the box weight is also taken into account.

# Fixed ordering cost (transport + CO2 tax, independent of time)
param SetupOrderCost {s in SUPPLIERS} := 
    (Distance[s] * CostPerKm) + (Distance[s] * CO2EmissionPerKm * CO2Tax);

# Explosion of the BOM with time phasing
param GrossReq {c in COMPONENTS, t in PERIODS} := 
    sum {(p,c) in BOM: t + LTPP[p] <= MaxT} 
    (MPS_Plan[p, t + LTPP[p]] * nProdComp[p,c]);  #GrossReq is the exact requirement of each component in each month t; MPS_Plan is the quantity of finished products made in month t, decided by the MPS.

#VARIABLES 
var ArrivalQty {COMP_SUPP, PERIODS} >= 0;  #physical components arriving in month t (the equivalent of the MPS SPO, counted in components instead of batches)
var Inv {COMPONENTS, 0..MaxT} >= 0;  #physical quantity of component c left in the warehouse at the end of month t
var RO_Comp {COMP_SUPP, PERIODS} >= 0;  #released orders: quantity of components written on the purchase order sent to the supplier in month t; it is a multiple of the pieces per box (unlike GrossReq, the exact requirement computed from the MPS)
var Y {COMP_SUPP, PERIODS} binary;  #binary switch of the release order: if an order is placed (RO_Comp > 0), the Big-M constraint forces Y to 1
var NumBoxes {COMP_SUPP, PERIODS} integer >= 0;  # Number of whole boxes ordered (variable added by us)

#OBJECTIVE FUNCTION
minimize Total_MRP_Cost:
    sum {t in PERIODS, c in COMPONENTS} 
        (HoldingCostComp[c] * Inv[c,t]) + 
    sum {t in PERIODS, (c,s) in COMP_SUPP} 
        ((CostOfBox[c,s] / PcsPerBox[c]) * ArrivalQty[c,s,t] + SetupOrderCost[s] * Y[c,s,t]); #ASSUMPTION: since LeadTime=0 then RO_comp=ArrivalQty. When the order of components is released (Y=1), then i will pay the SetupOrderCost
        
        
#CONSTRAINTS     
subject to Init_Inventory {c in COMPONENTS}:
    Inv[c, 0] = MagInit[c];                   #see Access table where MagInit is the initial quantity of component at month 1 altraedy present in the inventory

subject to Inv_Balance {c in COMPONENTS, t in PERIODS}:
    Inv[c, t-1] + sum {s in SUPPLIERS: (c,s) in COMP_SUPP} ArrivalQty[c,s,t] = GrossReq[c,t] + Inv[c,t];

#LeadTime contraint (remember in this mrp the leadtime is zero month)
subject to LeadTime_Offset {(c,s) in COMP_SUPP, t in PERIODS: t > LT_Supp[s]}:
    ArrivalQty[c,s,t] = RO_Comp[c,s, t - LT_Supp[s]]; 

subject to Pipeline_Init {(c,s) in COMP_SUPP, t in PERIODS: t <= LT_Supp[s]}:
    ArrivalQty[c,s,t] = 0;

#BATCHES AND BOXES CONSTRAINTS

# 1. Exact multiple: the components ordered are the number of boxes times the pieces in each box
subject to Box_Multiplier {(c,s) in COMP_SUPP, t in PERIODS}:
    RO_Comp[c,s,t] = PcsPerBox[c] * NumBoxes[c,s,t];

# 2. Order activation: if at least 1 box is ordered then 1 <= BigM*Y, so Y is forced to 1 and the SetupOrderCost is paid
subject to Supplier_Selection {(c,s) in COMP_SUPP, t in PERIODS}:
    NumBoxes[c,s,t] <= BigM * Y[c,s,t];

# 3. Minimum lot: if the order is active (Y=1), at least 1 whole box must be bought. An active order with zero boxes
#would mean a truck carrying nothing while paying transport and CO2 costs
subject to Min_Order_Lot {(c,s) in COMP_SUPP, t in PERIODS}:
    NumBoxes[c,s,t] >= Y[c,s,t];
