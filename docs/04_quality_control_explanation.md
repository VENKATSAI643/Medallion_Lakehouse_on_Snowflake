# 04 Quality Control - Commands and Concepts Explanation

## What is Quality Control (The Gate)?
In a Medallion Architecture, you don't want bad data to accidentally sneak into your Gold layer where business executives are making financial decisions. 
This script acts as a **"Circuit Breaker"** or a **Quality Gate**. If the data coming in is suddenly very poor quality, it sounds an alarm and stops the pipeline before the damage can spread to the final reports.

---

## Detailed Code Explanation

Below is the step-by-step breakdown of the commands in `04_quality_control.sql` in layman's terminology.

### 1. Creating the Stored Procedure (The Inspector)
```sql
CREATE OR REPLACE PROCEDURE MEDALLION.dq_gate_proc()
...
```
**What is the use of it?**
Just like in the Silver layer, we are creating a **Stored Procedure** (a reusable script) to act as our Quality Inspector. 

#### A. Setting up the Alarm
```sql
DECLARE 
  reject_rate FLOAT; 
  bad_dq EXCEPTION (-20001, 'DQ gate failed: Reject rate too high');
```
**In Layman's Terms:** 
Before the inspector starts working, we give them a notepad (`reject_rate`) to calculate a score, and a literal red alarm button (`bad_dq EXCEPTION`). 

#### B. Calculating the Score
```sql
  SELECT COUNT_IF(reject_reason IS NOT NULL) / NULLIF(COUNT(*),0) INTO :reject_rate
  FROM (
      SELECT reject_reason FROM MEDALLION.silver_rejects WHERE DATE(inserted_at) = CURRENT_DATE()
      UNION ALL
      SELECT NULL AS reject_reason FROM MEDALLION.silver_trips WHERE DATE(inserted_at) = CURRENT_DATE()
  );
```
**In Layman's Terms:** 
The inspector looks at *all* the work done today. They count up all the "bad" trips thrown into the quarantine bin (`silver_rejects`) and combine them with all the "good" trips safely stored in the clean table (`silver_trips`). By doing a simple math equation (Bad Trips / Total Trips), they calculate the **Rejection Rate** for the day.

#### C. Tripping the Circuit Breaker
```sql
  IF (reject_rate > 0.02) THEN 
    RAISE bad_dq; 
  END IF;
  
  RETURN 'PASSED';
```
**In Layman's Terms:** 
This is the actual circuit breaker. If the inspector calculates that more than **2%** (`0.02`) of the data today was bad, they smash that red alarm button (`RAISE bad_dq`). 
When an exception is raised in Snowflake, it causes the script to loudly fail. This immediately halts the data pipeline, preventing the Gold layer from building reports on suspicious data, and sends an alert to the engineering team to investigate. If it is under 2%, it gives a thumbs up (`PASSED`).

---

### 2. Automating it with a Task (The Dependency)
```sql
CREATE TASK MEDALLION.dq_gate_task 
  WAREHOUSE = etl_wh 
  AFTER MEDALLION.silver_trips_task 
AS
  CALL MEDALLION.dq_gate_proc();
```
**What is the use of it?**
We create another automated robot worker (Task). However, unlike our Silver task which wakes up every 10 minutes on a timer, this task is part of an assembly line.

**In Layman's Terms:** 
Notice the `AFTER MEDALLION.silver_trips_task` command. This tells our Quality Inspector robot to stand at the end of the assembly line. It doesn't use a clock. Instead, it waits patiently for the Silver Cleaning robot to finish its job. The very second the Silver robot finishes cleaning a batch of data, the Inspector robot immediately wakes up and runs its quality check. If the check passes, the pipeline continues!
