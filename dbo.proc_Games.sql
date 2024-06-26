USE [Games_analysis]
GO
/****** Object:  StoredProcedure [dbo].[proc_Games]    Script Date: 4/30/2024 7:46:11 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

alter PROC [dbo].[proc_Games]
-- =============================================
-- Author:		
-- Create date: YYYYMMDD
-- Description:	RAW -> WRK
-- =============================================

AS
BEGIN

/* Extract `P_ID`, `Dev_ID`, `PName`, and `Difficulty_level` of all players at Level 0.*/

select p.P_ID, l.Dev_ID, p.PName, l.Difficulty
from player_details p
join level_details l
on p.P_ID = l.P_ID
where l.level = 0;

/*Find the total number of stages crossed at each difficulty level for Level 2 with players.*/

select sum(stages_crossed) as Total_Stages_Crossed, difficulty
from level_details
where level = 2
group by Difficulty;

/*Find `Level1_code`wise average `Kill_Count` where `lives_earned` is 2, and at least 3 stages are crossed.
using `zm_series` devices. Arrange the result in decreasing order of the total number of stages crossed*/

select p.L1_Code,avg(l.Kill_Count)as Avg_kill_count, l.Lives_Earned, l.Dev_ID
from player_details p
join level_details l
on p.P_ID = l.P_ID
where l.Lives_Earned = 2 and l.Stages_crossed>3 and l.Dev_ID like '%zm%'
group by l.Lives_Earned, p.L1_Code, l.Dev_ID
order by sum(l.Stages_crossed) desc;

/*Extract `P_ID` and the total number of unique dates for those players who have played games on multiple days.*/

select distinct count(timestamp)as Total_no_of_dates, p_id
from level_details
group by P_ID;

/*Find `P_ID` and levelwise sum of `kill_counts` where `kill_count` is greater than the average kill count for Medium difficulty*/

select p_id, level, sum(kill_count) as sum_kill_count
from level_details
where kill_count > (select avg(kill_count) 
					from level_details
					where difficulty='Medium')
group by p_id, level;

/*Find `Level` and its corresponding `Level_code`wise sum of lives earned, excluding Level 0 Arrange in ascending order of level*/

select l.level, p.l1_code, p.l2_code, sum(lives_earned) as sum_lives_earned
from player_details p
join level_details l
on p.p_id = l.P_ID
where level != 0
group by l.level, p.L1_Code, p.L2_Code
order by level asc;

/*Find the top 3 scores based on each `Dev_ID` and rank them in increasing order using `Row_Number`. Display the difficulty as well.*/

WITH RankedScores AS (
    SELECT 
        P_ID,
        Dev_ID,
        Difficulty,
        Score,
        ROW_NUMBER() OVER (PARTITION BY Dev_ID ORDER BY Score ASC) AS rank
    FROM 
        level_details
)
SELECT top 3
    P_ID,
    Dev_ID,
    Difficulty,
    Score
FROM 
    RankedScores
WHERE 
    rank <= 3
order by score asc;

/*Find the `first_login` datetime for each device ID*/

SELECT 
    Dev_ID,
    MIN(timestamp) as first_login_time
FROM 
    level_details
GROUP BY 
    Dev_ID;

/*Find the top 5 scores based on each difficulty level and rank them in increasing order using `Rank`. Display `Dev_ID` as well*/

with rank_scores as ( select
							p_id,
							dev_id,
							difficulty,
							score,
							Rank() over (partition by dev_id  order by score) as rank
						from level_details)
select top 5
		p_id,
		dev_id,
		difficulty,
		score
from rank_scores
order by score asc;

/*Find the device ID that is first logged in (based on `start_datetime`) for each player (`P_ID`).
Output should contain player ID, device ID, and first login datetime*/

SELECT 
    l.p_id,
    l.Dev_ID,
    l.TimeStamp as first_login_datetime
FROM 
    level_details l
JOIN 
    (
        SELECT 
            P_ID,
			min(TimeStamp) AS first_login
        FROM 
            level_details
        GROUP BY 
            P_ID
    ) AS first_logins
ON 
    l.P_ID = first_logins.P_ID
    AND l.TimeStamp = first_logins.first_login;

/*For each player and date, determine how many `kill_counts` were played by the player so far.*/
/*a) Using window functions*/

select
	p_id,
	timestamp,
	sum(kill_count) over (partition by p_id order by timestamp) as sum_of_kills
from level_details;

/*b) Without window functions*/

SELECT 
    t1.P_ID,
    t1.timestamp,
    SUM(t2.kill_count) AS total_kill_counts_so_far
FROM 
    level_details t1
JOIN 
     level_details t2  ON t1.P_ID = t2.P_ID AND t1.TimeStamp >= t2.TimeStamp
GROUP BY 
    t1.P_ID, t1.TimeStamp
ORDER BY 
    t1.P_ID, t1.TimeStamp;

/*Find the cumulative sum of stages crossed over `start_datetime` for each `P_ID`, excluding the most recent `start_datetime*/

WITH RankedStages AS (
    SELECT 
        P_ID,
        TimeStamp,
        ROW_NUMBER() OVER (PARTITION BY P_ID ORDER BY TimeStamp DESC) AS rn
    FROM 
        level_details
)
SELECT distinct
    t1.P_ID,
    t1.TimeStamp,
    SUM(t1.stages_crossed) OVER (PARTITION BY t1.P_ID ORDER BY t1.TimeStamp) - t1.stages_crossed AS cumulative_stages_crossed
FROM 
    level_details t1
JOIN 
    RankedStages t2 ON t1.P_ID = t2.P_ID
WHERE 
    t1.TimeStamp <> (
        SELECT MAX(TimeStamp)
        FROM RankedStages
        WHERE P_ID = t1.P_ID
    );

/*Extract the top 3 highest sums of scores for each `Dev_ID` and the corresponding `P_ID`.*/

WITH RankedScores AS (
    SELECT 
        P_ID,
        Dev_ID,
        SUM(Score) AS total_score,
        ROW_NUMBER() OVER (PARTITION BY Dev_ID ORDER BY SUM(Score) DESC) AS rank
    FROM 
        level_details
    GROUP BY 
        P_ID, Dev_ID
)
SELECT 
    P_ID,
    Dev_ID,
    total_score
FROM 
    RankedScores
WHERE 
    rank <= 3;

/*Find players who scored more than 50% of the average score, scored by the sum of scores for each `P_ID`.*/

select p_id, sum(score) as total_score
from level_details
group by p_id
having sum(score)> 0.5 *(
						select avg(total_score)
						from(
							select p_id, sum(score) as total_score
							from level_details
							group by P_ID
							)as avg_scores
						);

/*Create a stored procedure to find the top `n` `headshots_count` based on each `Dev_ID`
and rank them in increasing order using `Row_Number`. Display the difficulty as well*/

begin
    SET NOCOUNT ON;

    WITH RankedHeadshots AS (
        SELECT 
            Dev_ID,
            headshots_count,
            Difficulty,
            ROW_NUMBER() OVER (PARTITION BY Dev_ID ORDER BY headshots_count ASC) AS rank
        FROM 
            level_details
    )
    SELECT 
        Dev_ID,
        headshots_count,
        Difficulty
    FROM 
        RankedHeadshots
    WHERE 
        rank <= 3;
End








END

/*

 select * from [dbo].[TableName_YYYYMMDD]
*/