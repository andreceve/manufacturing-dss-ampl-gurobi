# JOB SHOP SCHEDULING

set PRODUCTS ordered;
set MACHINES;
set PRODMACH within (PRODUCTS cross MACHINES);

# Set read as (ProductID, LotNumber) from the Jobs table
set JOBS dimen 2; 

#SET DI SUPPORTO PER LE MACCHINE 
set COPIES := 1..13;  # the maximum parallelism is given by the 13 assembly benches working at the same time

# PARAMETERS

# Number of pieces in batch (p,i)
param Quantity {JOBS} > 0 default 60;   #number of products in one single batch, it must respect the MinBatchProd that we have in the MPS 

# Parallel machines of each type, read from the Machines table
param MachQuantity {MACHINES} integer >= 0 default 1;

#ASSUMPTION: the RRP gives 61 workers. 22 of them form the logistics/CNC team that performs the machine setups and moves the products between machines;
#this is realistic because the RRP buys 16 machines, i.e. about 1.3 operators per machine.
#The remaining 61-22=39 operators work on 13 assembly benches (3 operators per bench) and assemble the finished products
#NOTE: after running the RRP, set MachQuantity of the AssemblyTable to 13 in Access (the RRP sets it to zero)
param WorkersPerBench {m in MACHINES} := if m == "AssemblyTable" then 3 else 1;  #the processing time is divided by WorkersPerBench only on the AssemblyTable, where 3 workers assemble in parallel and reduce the makespan

param Precedente {PRODMACH} symbolic default "";  #previous machine in the routing (Precedente column in Access)
param ProcTime {PRODMACH} >= 0 default 0; 			#processing time: time required to process a single unit of a product on a specific machine[min]
param SetupTime {PRODMACH} >= 0 default 0;

#ManualAssembly is not needed here: it is the ProcTime of the AssemblyTable

param Handling {PRODUCTS} >= 0 default 0;

param BigM := 100000;

# VARIABLES
var Makespan >= 0;  #total completion time of the whole production plan [min]

# Start time of job (p,i) on machine m
var StartTime {(p,i) in JOBS, m in MACHINES: (p,m) in PRODMACH } >= 0 integer; # it represents the producing starting time of a single batch on a machine (i represents the lot number). It's in MINUTE!!! Is an integer because we do not start to produce a batch at 34 minutes and 50 seconds for example but at 35 minutes then.


var Z { (p1,i1) in JOBS, (p2,i2) in JOBS, m in MACHINES: 
       (ord(p1, PRODUCTS) < ord(p2, PRODUCTS) or (p1 == p2 and i1 < i2))                            
       and (p1,m) in PRODMACH and (p2,m) in PRODMACH } binary;  #Sequencing variable when two batches compete for the same machine: 0 = batch 1 goes first, 1 = batch 2 goes first.
       															# (ord p1 < ord p2) avoids duplicates: a variable is created to compare e.g. Brake and Clutch, but not the identical one comparing Clutch and Brake.
       															#For batches of the same product (p1 == p2), the lot numbers are compared (i1 < i2).
       															#This halves the number of variables and makes Gurobi much faster.
       
var Alloc {(p,i) in JOBS, m in MACHINES, k in COPIES: (p,m) in PRODMACH and k <= MachQuantity[m]} binary;  #Physical copy of the machine on which the batch is processed: 1 if batch (p,i) goes on copy k of machine m, 0 otherwise
																										  #k <= MachQuantity[m] ties the model to the physical plant: e.g. a batch cannot go on copy 5 of M01 if the RRP bought only 2 copies of M01
# OBJECTIVE FUNCTION
minimize C_max: 
    Makespan;

# CONSTRAINTS   

subject to Assign_To_One_Copy {(p,i) in JOBS, m in MACHINES: (p,m) in PRODMACH}:
    sum {k in COPIES: k <= MachQuantity[m]} Alloc[p,i,m,k] = 1;  #Each batch must choose one and only one physical copy of the machine for each step of its routing.
    																				#The sum over all available copies of a machine (e.g. copies 1 to 13 of the AssemblyTable) must be exactly 1,
    																				#so the solver sets one copy to 1 and all the others to 0.
    																				#Without this constraint the solver could cheat to lower the makespan, processing the same batch on two benches at the same time or not assigning it at all.
    
# 1. Makespan definition
subject to Calc_Makespan {(p,i) in JOBS, (p,m) in PRODMACH}:
    Makespan >= StartTime[p,i,m] + SetupTime[p,m] + ((ProcTime[p,m] * Quantity[p,i]) / WorkersPerBench[m]); #time between the start of the first batch and the completion of the last batch of our total operation
# 2. Precedence constraint
subject to Intra_Job_Routing {(p,i) in JOBS, (p,m) in PRODMACH: 
    Precedente[p,m] != "" and Precedente[p,m] != "Nessuno"}:  #The first machine has no predecessor (empty or "Nessuno" in Access), so the constraint is not generated for it
    StartTime[p,i,m] >= StartTime[p,i,Precedente[p,m]] + SetupTime[p,Precedente[p,m]] + 
    ((ProcTime[p,Precedente[p,m]] * Quantity[p,i]) / WorkersPerBench[Precedente[p,m]]) + Handling[p];  #Internal routing of the batch: it cannot start on the current machine before it has finished on the previous one
                                                                                                                                                                                          #and has been physically transported.
                        					                                                  
# 3. Disjunctive constraints. While Assign_To_One_Copy prevents the same batch from being split over several machines,
#these two constraints prevent two different batches from overlapping on the SAME physical copy of a machine
subject to No_Overlap_A { (p1,i1) in JOBS, (p2,i2) in JOBS, m in MACHINES, k in COPIES: 
    (ord(p1, PRODUCTS) < ord(p2, PRODUCTS) or (p1 == p2 and i1 < i2))  #avoids comparing each pair twice; for batches of the same product it compares the lot numbers
    and (p1,m) in PRODMACH and (p2,m) in PRODMACH and k <= MachQuantity[m]}:
    StartTime[p2,i2,m] >= StartTime[p1,i1,m] + SetupTime[p1,m] + ((ProcTime[p1,m] * Quantity[p1,i1]) / WorkersPerBench[m]) 
                        - BigM * (1 - Z[p1,i1,p2,i2,m]) 
                        - BigM * (2 - Alloc[p1,i1,m,k] - Alloc[p2,i2,m,k]);

subject to No_Overlap_B { (p1,i1) in JOBS, (p2,i2) in JOBS, m in MACHINES, k in COPIES: 
    (ord(p1, PRODUCTS) < ord(p2, PRODUCTS) or (p1 == p2 and i1 < i2)) 
    and (p1,m) in PRODMACH and (p2,m) in PRODMACH and k <= MachQuantity[m]}:
    StartTime[p1,i1,m] >= StartTime[p2,i2,m] + SetupTime[p2,m] + ((ProcTime[p2,m] * Quantity[p2,i2]) / WorkersPerBench[m]) 
                        - BigM * Z[p1,i1,p2,i2,m] 
                        - BigM * (2 - Alloc[p1,i1,m,k] - Alloc[p2,i2,m,k]);
