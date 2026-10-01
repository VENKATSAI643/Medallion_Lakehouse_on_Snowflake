# 06 Automation - Commands and Concepts Explanation

## What is this script doing?
This script doesn't build any new tables or logic. Instead, it acts as the "On/Off Switch" for your entire automated data pipeline. In Snowflake, tasks can be linked together into an assembly line (technically called a **DAG** or Directed Acyclic Graph). This script manages the strict rules required to turn that assembly line on safely.

---

## Deep Dive: How Tasks Work from a Technical Perspective

In the previous scripts (`03_silver`, `04_quality`, `05_gold`), you created three tasks:
1. **`silver_trips_task`**: The "Root" task (runs on a 10-minute timer).
2. **`dq_gate_task`**: A "Child" task (runs `AFTER silver_trips_task`).
3. **`gold_daily_driver_earnings_task`**: Another "Child" task (runs `AFTER dq_gate_task`).

This chain of dependencies creates a Task Tree. 

### Rule 1: The Root dictates the Tree
Snowflake has a strict architectural rule: **You cannot alter, add, or resume a child task while the root task is running (RESUMED).** 
Why? Because if the root task fires while you are modifying the downstream children, the pipeline could break or skip steps entirely. Therefore, the Root must always be `SUSPENDED` before you can do maintenance on the pipeline.

### Rule 2: Resume Bottom-Up
When you want to turn the pipeline back on, you must wake up the workers in **reverse order** (bottom-up). You resume the children first, and the root task *last*. 
Why? If you resumed the root task first, it might immediately trigger on its 10-minute schedule. Because its children are still asleep (suspended), the children would get skipped for that batch of data!

---

## Detailed Code Explanation

Below is the step-by-step breakdown of how `06_automation.sql` handles these technical rules.

### 1. Suspending the Root Task Safely
```sql
EXECUTE IMMEDIATE
$$
BEGIN
  ALTER TASK MEDALLION.silver_trips_task SUSPEND;
EXCEPTION WHEN OTHER THEN
  NULL; -- Ignore if it's already suspended
END;
$$;
```
**What is the use of it?**
To follow Rule #1, we must ensure the root task is turned off. However, if the root task is *already* suspended, running a standard `ALTER TASK ... SUSPEND` command will throw an ugly red error in Snowflake and stop your script. 

To bypass this annoyance, we wrap the command in a **Snowflake Scripting Block** (`EXECUTE IMMEDIATE $$ ... $$`).
**In Technical Terms:** We try to suspend the task in the `BEGIN` block. If it throws an error (caught by `EXCEPTION WHEN OTHER`), we tell Snowflake to do `NULL` (absolutely nothing) and silently move on. It's a highly defensive way to ensure the pipeline is safely halted without breaking your deployment scripts.

---

### 2. Resuming the Child Tasks (Bottom-Up)
```sql
ALTER TASK MEDALLION.gold_daily_driver_earnings_task RESUME;
ALTER TASK MEDALLION.dq_gate_task RESUME;
```
**What is the use of it?**
Following Rule #2, we now begin waking up our assembly line from the bottom up. 
We resume the Gold task, then we resume the Data Quality Gate task. 
At this point, these child tasks are "awake", but they are essentially standing idle, waiting for the root task to hand them work.

> **What happens if I resume from Top to Bottom instead?**
> Imagine you resume the Root task (`silver`) first. Because it runs on a 10-minute timer, it might trigger *instantly* the second you turn it on. 
> The Root task finishes its cleaning job and turns around to hand the data to the Data Quality task... but the Data Quality task is still asleep (`SUSPENDED`) because you haven't run its `RESUME` command yet!
> Because the child was asleep, **it gets skipped entirely for that run.** The data never gets checked, and the Gold layer never updates. By waking up the children first (bottom-up), you guarantee they are standing by, fully alert, ready to catch the data the exact second the Root task throws it.

---

### 3. Turning on the Engine (The Cascade Trigger)
```sql
ALTER TASK MEDALLION.silver_trips_task RESUME;
```
**What is the use of it?**
Finally, we flip the master switch. By resuming the root task (`silver_trips_task`), the 10-minute timer officially starts ticking. 

**Does this trigger the Silver and Gold automation?**
**Yes!** By turning on the root task, you are turning on the entire chain reaction. Because the child tasks are linked using the `AFTER` keyword, you don't need to put timers on them. When the root finishes, it automatically taps the next task on the shoulder, creating a perfect domino effect.

Now, the fully automated, cascading lifecycle looks like this:
1. *Every 10 minutes*: The Root task (`silver`) checks the Azure Stream.
2. *If data exists*: The Root task processes the Silver data.
3. *When Root finishes*: It automatically triggers the **DQ Gate** child task to inspect the data.
4. *When DQ finishes (and passes)*: It automatically triggers the **Gold** child task to build the final business reports. 

You now have a fully functioning, self-healing, automated Medallion architecture!
