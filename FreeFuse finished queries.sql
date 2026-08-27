
-- All queries whose results will be used for the report can be found here.

-- TEMP TABLES:


-- Full sessions:
create temporary table `sessions`
select *, round(timestampdiff(second, `t1`, `t2`)/60, 2) `session_time`
  from (
		with `login_evt` as (
						     select row_number() over (order by `event_id`) as `row1`,
						     	    `event_id` ev1,
						    	    `timestamp` t1,
						    	    `user_id`,
						    	    `user_role`,
						    	    `organization_id`,
						    	    `state`,
						    	    `element_id` el1
							   from `events`
				 			  where `element_id` = 'form_login' or
		 	   		   			   `event_id` in (
		 	   		   			   				  select (
		 	   		   			   				  		  `event_id`+1
		 	   		   			   				  		  )
		 	   		   			   				    from `events`
												   where `element_id` = 'button_logout'
												  )
		 	   				),
			 `exit_evt` as (
			    		    select row_number() over (order by `event_id`) as `row2`,
			    		    	   `event_id` ev2, 
			    		    	   `timestamp` t2,
			    		    	   `screen_name`,
			    		    	   `element_id` el2
			    			  from `events`
			    			 where `element_id` = 'button_logout' or
		 	   		   			   `event_id` in (
		 	   		   			   				  select (
		 	   		   			   				  		  `event_id`-1
		 	   		   			   				  		  )
		 	   		   			   				    from `events`
												   where `element_id` = 'form_login'
												  )
			   				)
	   select distinct `login_evt`.*,
			   	       `exit_evt`.*
  		 from `login_evt`
  		 left join `exit_evt`
    	   on `row1` = `row2`
	  ) `sessions`;


-- New events table with session IDs:
create temporary table `events_s`
select `sessions`.`row1` as `session_id`, `events`.* 
  from `events`
  left join `sessions`
    on `events`.`event_id` >= `sessions`.`ev1` and
       `events`.`event_id` <= `sessions`.`ev2`;

-- Table containing multiplication factor qualifying high-activity claim_ids
create temporary table `mult_factor`
select '3';

-- Table of session_ids that are associated with high-activity claim_ids
create temporary table `hi_act_claim_sessions`
select distinct `session_id` -- selects session ids associated with high-activity claim_ids
  from `events_s`
 where `claim_id` in (
					  select `claim_id` -- selects only claim_id from table of claim_id + event count
					    from (
						      with `average` as ( -- CTE rounded average of event count grouped by claim_id
												 select round(avg(`count`), 2) `round_avg`
												   from ( -- event count grouped by claim_id
														 select count(*) `count`
														   from `events`
														  where `claim_id` like '%20%' 
														  group by `claim_id`
														 ) `a`
		   	  									 )
							select `claim_id`, -- claim_id with event count where event count > 2 * avg
									count(*) as `counts`
							  from `events`
							 where `claim_id` like '%20%'
							 group by `claim_id`
							having `counts` > (
											   select `round_avg`
												 from `average`
											   ) * (
											   		select *
											   		  from `mult_factor`
											   		)
 							 order by `counts` desc
							  ) `b`
					  );

-- Table with count of unique screen_names from high-activity claim_id sessions - for use in calculating true average of screen visits in same
create temporary table `hi_act_claim_ss_scrn_cnt`
select count(distinct `session_id`)
from `hi_act_claim_sessions`;


-- Lists only those events (with session_ids) associated with high-activity claim_ids
create temporary table `events_hi_act_claims`
select * from events_s
 where `session_id` in (
						select *
						  from `hi_act_claim_sessions`
						); 

select * from `events_hi_act_claims`;

-- ***** AVERAGE SESSION TIME QUERIES START HERE *****

-- Session time average - overall:
select round(avg(`session_time`), 2) as `session_time_minutes` from(
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from `sessions`) `session_time_avg`;


-- Session time average - grouped by state:
select `state`, round((avg(session_time)), 2) as `session_time_minutes` from(
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from `sessions`) `session_time_avg`
 group by `state`
 order by `state` asc;

-- Session time average - grouped by user role:
select `user_role`, round((avg(session_time)), 2) as `session_time_minutes` from(
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from  `sessions`) `session_time_avg`
 group by `user_role`
 order by `user_role`;

-- ***** EXIT EVENT QUERIES START HERE *****

-- Exit events counted and grouped by exit screen_name
select `screen_name`  `Exit screen`, count(*) `Exit count` from ( 
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from  `sessions`) `exit_count_by_screen`
 group by `Exit screen`
 order by `Exit count` desc, `Exit screen` asc;

-- Exit events counted and grouped by state and then exit screen_name, ordered by count
select `state` `State`, `screen_name` `Exit screen`, count(*) `Exit count` from ( 
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from  `sessions`) `exit_count_by_screen`
 group by `State`, `Exit screen`
 order by `State`, `Exit count` desc;

-- Exit events counted and grouped by user role and then exit screen_name, ordered by count
select `user_role` `User role`, `screen_name` `Exit screen`, count(*) `Exit count` from ( 
select *, timestampdiff(second, `t1`, `t2`) `session_time_m`
  from  `sessions`) `exit_count_by_screen`
 group by `User role`, `Exit screen`
 order by `User role`, `Exit count` desc, `Exit screen` asc;

-- ***** SESSION COUNT QUERIES START HERE *****

-- Simple session count:
select count(*) `Session count` from `sessions`;

-- ***** HIGH-ACTIVITY CLAIM_ID QUERIES START HERE *****
-- High-activity claims are defined in temp table `hi_act_claim_sessions` as X * average activity count

-- Returns total and average visits by screen from (hi-activity claim_id sessions)
 select `screen_name`, sum(`scr_name_count`) `scr_count`, round((
 						sum(`scr_name_count`)  / (
 												 select * from `hi_act_claim_ss_scrn_cnt`
 												)
 						), 2)`scr_count_avg` -- The preceding code calculates average visits to screen_name; divides distinct screen_names visits from (hi-activity claim_id sessions) by total sessions in set.
  from (
		select `session_id`, 
			   `screen_name`,
	   		   count(`screen_name`) `scr_name_count` -- visits to these screens grouped by session_id
		  from `events_hi_act_claims`
		 where `screen_name` != 'Login' -- excluding login events because there's always exactly one per session; new login = new session
		 group by `session_id`,
		 		  `screen_name`
		 order by `session_id`,
		 		  `scr_name_count` desc
 	   ) a
 group by `screen_name`
 order by `scr_count_avg` desc;

 -- Count of elements interacted with from (high-activity claim_id sessions), grouped by screen name
 --       Excluded: login events (not relevant, same as session count), and logout events (already 
 --       reported elsewhere)
 
 select `screen_name`,
 		`element_id`,
		count(`element_id`) `element_count`
   from `events_hi_act_claims`
  where `element_id` != 'button_logout' and
  		`screen_name` != 'login'
  group by `screen_name`,
 			`element_id`
  order by `screen_name` asc,
		   `element_count` desc,
 		   `element_id` asc;

-- selects error events from high-activity claim_id sessions - could be useful in showing whether these errors constituted pain points
select * from `events_hi_act_claims` where `event_type` = 'error';

