-- CS4400: Introduction to Database Systems: Monday, July 1, 2024
-- Simple Cruise Management System Course Project Stored Procedures [TEMPLATE] (v0)
-- Views, Functions & Stored Procedures

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'cruise_tracking';
use cruise_tracking;
-- -----------------------------------------------------------------------------
-- stored procedures and views
-- -----------------------------------------------------------------------------
/* Standard Procedure: If one or more of the necessary conditions for a procedure to
be executed is false, then simply have the procedure halt execution without changing
the database state. Do NOT display any error messages, etc. */

-- [_] supporting functions, views and stored procedures
-- -----------------------------------------------------------------------------
/* Helpful library capabilities to simplify the implementation of the required
views and procedures. */
-- -----------------------------------------------------------------------------
drop function if exists leg_time;
delimiter //
create function leg_time (ip_distance integer, ip_speed integer)
	returns time reads sql data
begin
	declare total_time decimal(10,2);
    declare hours, minutes int default 0;
    set total_time = truncate(ip_distance / ip_speed, 2);
    set hours = floor(truncate(total_time, 0));
    set minutes = floor(truncate((total_time - hours) * 60, 0));
    return maketime(hours, minutes, 0);
end //
delimiter ;

-- [1] add_ship()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new ship.  A new ship must be sponsored
by an existing cruiseline, and must have a unique name for that cruiseline. 
A ship must also have a non-zero seat capacity and speed. A ship
might also have other factors depending on it's type, like paddles or some number
of lifeboats.  Finally, a ship must have a new and database-wide unique location
since it will be used to carry passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_ship;
delimiter //
create procedure add_ship (in ip_cruiselineID varchar(50), in ip_ship_name varchar(50),
	in ip_max_capacity integer, in ip_speed integer, in ip_locationID varchar(50),
    in ip_ship_type varchar(100), in ip_uses_paddles boolean, in ip_lifeboats integer)
sp_main: begin
	if ip_cruiselineID not in (select distinct cruiselineID from ship) then leave sp_main; end if;
    if ip_ship_name in (select distinct ship_name from ship) then leave sp_main; end if;
    if ip_max_capacity = 0  or ip_max_capacity is null then leave sp_main; end if;
    if ip_speed = 0 or ip_speed is null then leave sp_main; end if;
    if ip_locationID in (SELECT DISTINCT locationID FROM location) then leave sp_main; end if;
   
    if ip_ship_type = 'ocean-liner' then if ip_uses_paddles is not null then leave sp_main; end if; end if;
	if ip_ship_type = 'river' then if ip_lifeboats is not null then leave sp_main; end if; end if;
   
    insert into location (locationID) values (ip_locationID);
    insert into ship
	values (
		ip_cruiselineID,
        ip_ship_name,
        ip_max_capacity,
        ip_speed,
        ip_locationID,
        ip_ship_type,
        ip_uses_paddles,
        ip_lifeboats);
end //
delimiter ;

-- [2] add_port()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new port.  A new port must have a unique
identifier along with a new and database-wide unique location if it will be used
to support ship arrivals and departures.  A port may have a longer, more
descriptive name.  An airport must also have a city, state, and country designation. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_port;
delimiter //
create procedure add_port (in ip_portID char(3), in ip_port_name varchar(200),
    in ip_city varchar(100), in ip_state varchar(100), in ip_country char(3), in ip_locationID varchar(50))
sp_main: begin
	if ip_portid in (select portid from ship_port) 
		then leave sp_main; 
	end if;
    if ip_locationid in (select locationid from location) then 
		leave sp_main; 
	end if;
    insert into location (locationid) values (ip_locationid);
    insert into ship_port (portid, port_name, city, state, country, locationid) 
    values (ip_portid, ip_port_name, ip_city, ip_state, ip_country, ip_locationid);
end //
delimiter ;

-- [3] add_person()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new person.  A new person must reference a unique
identifier along with a database-wide unique location used to determine where the
person is currently located: either at a port, on a ship, or both, at any given
time.  A person must have a first name, and might also have a last name.

A person can hold a crew role or a passenger role (exclusively).  As crew,
a person must have a tax identifier to receive pay, and an experience level.  As a
passenger, a person will have some amount of rewards miles, along with a
certain amount of funds needed to purchase cruise packages. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_person;
delimiter //
create procedure add_person (in ip_personID varchar(50), in ip_first_name varchar(100),
    in ip_last_name varchar(100), in ip_locationID varchar(50), in ip_taxID varchar(50),
    in ip_experience integer, in ip_miles integer, in ip_funds integer)
sp_main: begin
-- Check if the person already exists
    if (select count(*) from person where personID = ip_personID) > 0 then
        leave sp_main;
    end if;

    -- Check if the location exists
    if (select count(*) from location where locationID = ip_locationID) = 0 then
        leave sp_main;
    end if;

    -- Check if the first name is not null
    if ip_first_name is null then 
        leave sp_main;
    end if;

    -- Ensure that a person cannot be both a crew member and a passenger
    if (ip_taxID is not null and ip_experience is not null) and (ip_miles is not null or ip_funds is not null) then
        leave sp_main;
    end if;

    -- Insert new person
    insert into person (personID, first_name, last_name)
    values (ip_personID, ip_first_name, ip_last_name);
    insert into person_occupies(personID, locationID) values (ip_personID, ip_locationID);

    -- Insert crew details if taxID and experience are provided
    if ip_taxID is not null and ip_experience is not null then
        insert into crew (personID, taxID, experience, assigned_to)
        values (ip_personID, ip_taxID, ip_experience, null);
    end if;

    -- Insert passenger details if miles and funds are provided
    if ip_miles is not null and ip_funds is not null then
        insert into passenger (personID, miles, funds)
        values (ip_personID, ip_miles, ip_funds);
    end if;

end //
delimiter ;


-- [4] grant_or_revoke_crew_license()
-- -----------------------------------------------------------------------------
/* This stored procedure inverts the status of a crew member's license.  If the license
doesn't exist, it must be created; and, if it already exists, then it must be removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists grant_or_revoke_crew_license;
delimiter //
create procedure grant_or_revoke_crew_license (in ip_personID varchar(50), in ip_license varchar(100))
sp_main: begin
	declare new_license varchar(100);
    if not exists (select * from crew where personID = ip_personID) then 
		leave sp_main; 
	end if;
	if ip_license = 'ocean_liner' then 
		set new_license = 'river';
	elseif ip_license = 'river' then 
		set new_license = 'ocean_liner';
	else 
		leave sp_main; 
	end if;
    if exists (select * from licenses where personid = ip_personid and license = ip_license) then
		delete from licenses where personid = ip_personid and license = ip_license;
    else
        insert into licenses (personid, license) values (ip_personid, ip_license);
    end if;
end //
delimiter ;

-- [5] offer_cruise()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new cruise.  The cruise can be defined before
a ship has been assigned for support, but it must have a valid route.  And
the ship, if designated, must not be in use by another cruise.  The cruise
can be started at any valid location along the route except for the final stop,
and it will begin docked.  You must also include when the cruise will
depart along with its cost. */
-- -----------------------------------------------------------------------------
drop procedure if exists offer_cruise;
delimiter //
create procedure offer_cruise (in ip_cruiseID varchar(50), in ip_routeID varchar(50),
    in ip_support_cruiseline varchar(50), in ip_support_ship_name varchar(50), in ip_progress integer,
    in ip_next_time time, in ip_cost integer)
sp_main: begin
	if not exists (select * from route where routeID = ip_routeID) then 
		leave sp_main; 
	end if;
    if ip_support_ship_name is not null and exists (select * from cruise where support_ship_name = ip_support_ship_name) then 
			leave sp_main; 
    end if;
    if ip_progress < 0 or ip_progress > 100 then 
		leave sp_main; 
    end if;
    insert into cruise (cruiseID,routeID,support_cruiseline,support_ship_name,progress,ship_status,next_time,cost)
    values (ip_cruiseID,ip_routeID,ip_support_cruiseline,ip_support_ship_name,ip_progress,'docked',ip_next_time,ip_cost);
end //
delimiter ;


-- [6] cruise_arriving()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a cruise arriving at the next port
along its route.  The status should be updated, and the next_time for the cruise 
should be moved 8 hours into the future to allow for the passengers to disembark 
and sight-see for the next leg of travel.  Also, the crew of the cruise should receive 
increased experience, and the passengers should have their rewards miles updated. 
Everyone on the cruise must also have their locations updated to include the port of 
arrival as one of their locations, (as per the scenario description, a person's location 
when the ship docks includes the ship they are on, and the port they are docked at). */
-- -----------------------------------------------------------------------------
drop procedure if exists cruise_arriving;
delimiter //
create procedure cruise_arriving (in ip_cruiseID varchar(50))
sp_main: begin

declare curr_leg varchar(50);
declare curr_p int;
declare arr_port char(3);
declare arr_loc varchar(50);
declare ship_loc varchar(50);

if ip_cruiseID is null or ip_cruiseID not in 
(select cruiseID from cruise) then
leave sp_main;
end if;

if (select ship_status from cruise where cruiseID = ip_cruiseID) like 'docked' then
leave sp_main;
end if;

update cruise set ship_status = 'docked' where cruiseID = ip_cruiseID;
update cruise set next_time = DATE_ADD(next_time, INTERVAL 8 HOUR) where cruiseID = ip_cruiseID;

update crew set experience = experience + 1 where crew.assigned_to = ip_cruiseID;

select progress into curr_p from cruise where cruiseID = ip_cruiseID;
select legID into curr_leg from route_path where sequence = curr_p and routeID =
(select routeID from cruise where cruiseID = ip_cruiseID);

update passenger set miles = miles + (select distance from leg where legID = curr_leg)
where passenger.personID in 
(select personID from passenger_books where ip_cruiseID = cruiseID);

select arrival into arr_port from leg where legID = curr_leg;
select locationID into arr_loc from ship_port where portID = arr_port;

insert into person_occupies(personID,locationID)
select personID, arr_loc
from passenger_books
where cruiseID = ip_cruiseID;

insert into person_occupies(personID, locationID)
select personID, arr_loc
from crew
where ip_cruiseID = crew.assigned_to;

end //
delimiter ;

-- [7] cruise_departing()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a cruise departing from its current
port towards the next port along its route.  The time for the next leg of
the cruise must be calculated based on the distance and the speed of the ship. The progress
of the ship must also be incremented on a successful departure, and the status must be updated.
We must also ensure that everyone, (crew and passengers), are back on board. 
If the cruise cannot depart because of missing people, then the cruise must be delayed 
for 30 minutes. You must also update the locations of all the people on that cruise,
so that their location is no longer connected to the port the cruise departed from, 
(as per the scenario description, a person's location when the ship sets sails only includes 
the ship they are on and not the port of departure). */
-- -----------------------------------------------------------------------------
drop procedure if exists cruise_departing;
delimiter //
create procedure cruise_departing (in ip_cruiseID varchar(50))
sp_main: begin
declare new_leg varchar(50);
declare route varchar(50);
declare leg_time float;
declare ship_speed float;
declare leg_distance int;
declare temp_ship_name varchar(50);
declare cruiseline_name varchar(50);
declare ship_id varchar(50);

if ip_cruiseID not in (select cruiseID from cruise) or ip_cruiseID is null then leave sp_main; end if;

if (select ship_status from cruise where ip_cruiseID = cruiseID) != 'docked' then leave sp_main; end if;

if (select count(personID) from person_occupies where locationID = ship_id) != 
(select count(personID) from passenger_books where cruiseID = ip_cruiseID)
then update cruise set next_time = DATE_ADD(next_time, INTERVAL 30 MINUTE) where cruiseID = ip_cruiseID;
leave sp_main;
end if;

update cruise set ship_status = 'sailing' where cruiseID = ip_cruiseID;
update cruise set progress = progress + 1 where cruiseID = ip_cruiseID;

select routeID into route from cruise where cruiseID = ip_cruiseID;

select legID into new_leg from route_path where routeID = route and sequence = 
(select progress from cruise where cruiseID = ip_cruiseID);

select support_ship_name into temp_ship_name from cruise where cruiseID = ip_cruiseID;

select speed into ship_speed from ship where ship_name = temp_ship_name;

select distance into leg_distance from leg where legID = new_leg;

select support_cruiseline into cruiseline_name from cruise where cruiseID = ip_cruiseID;

select locationID into ship_id from ship where cruiselineID = cruiseline_name and ship_name = temp_ship_name;

set leg_time = leg_distance/ship_speed;
update cruise set next_time = next_time + leg_time;

update person_occupies set locationID = ship_id where personID in
(select personID from passenger_books where cruiseID = ip_cruiseID) or personID in
(select personID from crew where assigned_to = ip_cruiseID);

end //

delimiter ;

-- [8] person_boards()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the location for people, (crew and passengers), 
getting on a in-progress cruise at its current port.  The person must be at the same port as the cruise,
and that person must either have booked that cruise as a passenger or been assigned
to it as a crew member. The person's location cannot already be assigned to the ship
they are boarding. After running the procedure, the person will still be assigned to the port location, 
but they will also be assigned to the ship location. */
-- -----------------------------------------------------------------------------
drop procedure if exists person_boards;
delimiter //
create procedure person_boards (in ip_personID varchar(50), in ip_cruiseID varchar(50))
sp_main: begin

declare ship_location varchar(50);
declare person_port varchar(50);
declare person_ship varchar(50);
declare curr_port varchar (50);

select locationID into ship_location from ship join cruise on support_ship_name = ship_name where cruiseID = ip_cruiseID;
select locationID into person_ship from person_occupies where personID = ip_personID and locationID like '%ship%';
select locationID into person_port from person_occupies where personID = ip_personID and locationID like '%port%';

select arrival into curr_port from leg where legID = 
(select legID from route_path where sequence =
(select progress from cruise where cruiseID = ip_cruiseID) and routeID = 
(select routeID from cruise where cruiseID = ip_cruiseID));

if person_port != curr_port then leave sp_main; end if;
if person_ship = ship_location then leave sp_main; end if;
if ip_personID not in (select personID from passenger_books where ip_cruiseID = cruiseID) and 
ip_personID not in (select personID from crew where assigned_to = ip_cruiseID) then leave sp_main; end if;

insert into person_occupies(personID, locationID) values (ip_personID, ship_location);

end //
delimiter ;

-- [9] person_disembarks()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the location for people, (crew and passengers), 
getting off a cruise at its current port.  The person must be on the ship supporting 
the cruise, and the cruise must be docked at a port. The person should no longer be
assigned to the ship location, and they will only be assigned to the port location. */
-- -----------------------------------------------------------------------------
drop procedure if exists person_disembarks;
delimiter //
create procedure person_disembarks (in ip_personID varchar(50), in ip_cruiseID varchar(50))
sp_main: begin
-- initalize variable to store what ship the person is currently on 
declare currentship varchar(50) default null;

-- first check if the person exists
if (select count(*) from person where personID = ip_personID) = 0 then 
	leave sp_main; 
end if;

-- check if the person is currently on a ship
if (select count(*) from person_occupies where personID = ip_personID and locationID LIKE 'ship%') = 0 then 
	leave sp_main;
end if;

-- set value to the variable
SELECT locationID INTO currentship FROM person_occupies WHERE personID = ip_personID and locationID LIKE 'ship%';

-- check if person is on ship supporting cruise
if currentship not in (select locationID from cruise join ship 
	on cruise.support_cruiseline = ship.cruiselineID 
    and cruise.support_ship_name = ship.ship_name where cruiseID = ip_cruiseID) then
	leave sp_main;
end if;

-- make sure ship is docked
if (select ship_status from cruise where cruiseID = ip_cruiseID) not like 'docked' then 
	leave sp_main;
end if;

    
-- delete association with ship, leaving them only associated with a port 
DELETE FROM person_occupies 
WHERE personID = ip_personID AND locationID = currentship;
    

end //
delimiter ;

-- [10] assign_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a crew member as part of the cruise crew for a given
cruise.  The crew member being assigned must have a license for that type of ship,
and must be at the same location as the cruise's first port. Also, the cruise must not 
already be in progress. Also, a crew member can only support one cruise (i.e. one ship) at a time. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_crew;
delimiter //
create procedure assign_crew (in ip_cruiseID varchar(50), ip_personID varchar(50))
sp_main: begin
    declare v_person_location varchar(50);
    declare v_person_license varchar(100);
	declare v_routeID varchar(50);
	declare v_legID varchar(50);
    declare v_first_port char(3);
    declare v_ship_name char(50);
    
    -- check if the cruise is in progress
    if (select progress from cruise where cruiseID = ip_cruiseID) != 0 then
        leave sp_main;
    end if;

    -- check if the crew member is already assigned to another cruise
    if (select assigned_to from crew where personID = ip_personID) is not null then
        leave sp_main;
    end if;

    -- get the route ID from cruise
    select routeID into v_routeID
    from cruise 
    where cruiseID = ip_cruiseID;
    
    -- get the legID from routeID
    select legID into v_legID
    from route_path
    where v_routeID = routeID and sequence = 1;
    
    -- get the departure port using the legID
    select departure into v_first_port
    from leg
    where v_legID = legID;
    
    -- get the location of the crew member
    select locationID into v_person_location
    from person_occupies
    where personID = ip_personID;
    
    -- check if the crew member is at the first port
    if v_person_location != (select locationID from ship_port where portID = v_first_port) then
        leave sp_main;
    end if;
    
    -- get the ship name
    select support_ship_name into v_ship_name
    from cruise
    where ip_cruiseID = cruiseID;
    
    -- check the crew member's license
    select ship_type into v_person_license
    from ship
    where ship_name = v_ship_name;
    
    if (select license from licenses where personID = ip_personID) != v_person_license then
        leave sp_main;
    end if;

    -- assign the crew member to the cruise
    update crew
    set assigned_to = ip_cruiseID
    where personID = ip_personID;
    
end //
delimiter ;


-- [11] recycle_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure releases the crew assignments for a given cruise. The
cruise must have ended, and all passengers must have disembarked. */
-- -----------------------------------------------------------------------------
drop procedure if exists recycle_crew;
delimiter //
create procedure recycle_crew (in ip_cruiseID varchar(50))
sp_main: begin
	if (select ship_status from cruise where cruiseID = ip_cruiseID) = 'sailing' then
		leave sp_main;
	end if;

	if (select progress from cruise where cruiseID = ip_cruiseID) != (select max(sequence) from cruise natural join route_path where cruiseID = ip_cruiseID group by routeID) then
		leave sp_main;
	end if;
    -- Ensure all passengers have disembarked
    if (select count(*) from person_occupies natural join passenger where locationID =
    (select locationID from ship join cruise on support_cruiseline=cruiselineID and support_ship_name = ship_name
    where cruiseID = ip_cruiseID)) > 0 then
        leave sp_main;
    end if;
    
    -- update crew
    update crew 
    set assigned_to = null 
    where assigned_to = ip_cruiseID;
    
end //

delimiter ;

-- [12] retire_cruise()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a cruise that has ended from the system.  The
cruise must be docked, and either be at the start its route, or at the
end of its route.  And the cruise must be empty - no crew or passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists retire_cruise;
delimiter //
create procedure retire_cruise (in ip_cruiseID varchar(50))
sp_main: begin
	if (select ship_status from cruise where cruiseID = ip_cruiseID) = 'sailing' then
		leave sp_main;
	end if;
    
    if (select progress from cruise where cruiseId = ip_cruiseID) != (select max(sequence) from cruise natural join route_path where cruiseID = ip_cruiseID group by routeID)
	and (select progress from cruise where cruiseId = ip_cruiseID) != 0 then
		leave sp_main;
	end if;
    
    if (select count(*) from person_occupies where locationID =
    (select locationID from ship join cruise on support_cruiseline = cruiselineID and support_ship_name = ship_name
    where cruiseID = ip_cruiseID)) > 0 then
        leave sp_main;
    end if;

    delete from cruise
    where cruiseID = ip_cruiseID;
end //
delimiter ;



-- [13] cruises_at_sea()
-- -----------------------------------------------------------------------------
/* This view describes where cruises that are currently sailing are located. */
-- -----------------------------------------------------------------------------
create or replace view cruises_at_sea (departing_from, arriving_at, num_cruises,
	cruise_list, earliest_arrival, latest_arrival, ship_list) as

select leg.departure as departing_from,
    leg.arrival as arriving_at,
    COUNT(*) as num_cruises,
    GROUP_CONCAT(DISTINCT cruise.cruiseID) as cruise_list,
    MIN(cruise.next_time) as earliest_arrival,
    MAX(cruise.next_time) as latest_arrival,
    GROUP_CONCAT(DISTINCT locationID) as ship_list 
    from cruise 
	join route_path on cruise.progress = route_path.sequence and cruise.routeID = route_path.routeID 
	join leg on route_path.legID = leg.legID
    join ship on cruise.support_ship_name = ship.ship_name
	where cruise.ship_status like 'sailing'
	group by leg.departure, leg.arrival;

-- [14] cruises_docked()
-- -----------------------------------------------------------------------------
/* This view describes where cruises that are currently docked are located. */
-- -----------------------------------------------------------------------------
create or replace view cruises_docked (departing_from, num_cruises,
	cruise_list, earliest_departure, latest_departure, ship_list) as 
select 
	leg.departure,
    count(*) as count_cruise,
    group_concat(cruise.cruiseID) as list_cruise,
    min(cruise.next_time) as earliest,
    max(cruise.next_time) as latest,
    group_concat(ship.locationID) as ship_list
    from leg 
    natural join route_path rp
    join cruise on rp.routeID = cruise.routeID
    join ship on cruise.support_ship_name = ship.ship_name and cruise.support_cruiseline = ship.cruiselineID
    where cruise.ship_status like 'docked' and leg.arrival not in (select leg.departure from leg where legID in 
    (select legID from route_path where routeID in 
    (select routeID from cruise where ship_status like 'docked')))
    group by leg.departure;


-- [15] people_at_sea()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently at sea are located. */
-- -----------------------------------------------------------------------------
create or replace view people_at_sea (departing_from, arriving_at, num_ships,
	ship_list, cruise_list, earliest_arrival, latest_arrival, num_crew,
	num_passengers, num_people, person_list) as
select 
	leg.departure as departing_from,
    leg.arrival as arriving_at,
    count(distinct ship.locationID) as num_ships,
    group_concat(distinct ship.locationID) as ship_list,
    group_concat(distinct cruise.cruiseID) as cruise_list,
    min(cruise.next_time) as earliest_arrival,
    max(cruise.next_time) as latest_arrival,
    count(distinct crew.personID) as num_crew,
    (count(distinct person_occupies.personID) - count(distinct crew.personID)) as num_passengers,
    count(distinct person_occupies.personID) as num_people,
    group_concat(distinct person_occupies.personID order by length(person_occupies.personID), person_occupies.personID asc) as person_list
from leg 
    natural join route_path
    join cruise on route_path.routeID = cruise.routeID
    join ship on cruise.support_ship_name = ship.ship_name and cruise.support_cruiseline = ship.cruiselineID
    join crew on cruise.cruiseID = crew.assigned_to
    join passenger_books on cruise.cruiseID = passenger_books.cruiseID 
    right join person_occupies on ship.locationID = person_occupies.locationID
where 
    cruise.ship_status like 'sailing' and route_path.sequence = cruise.progress
group by 
    leg.departure, leg.arrival;
    

-- [16] people_docked()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently docked are located. */
-- -----------------------------------------------------------------------------
create or replace view people_docked (departing_from, ship_port, port_name,
	city, state, country, num_crew, num_passengers, num_people, person_list) as
select 
leg.departure,
ship_port.locationID,
ship_port.port_name,
ship_port.city,
ship_port.state,
ship_port.country,
count(distinct crew.personID),
count(distinct passenger.personID),
(count(distinct crew.personID) + count(distinct passenger.personID)),
concat(group_concat(distinct crew.personID), ',' , group_concat(distinct passenger.personID))
from cruise
join route_path on cruise.routeID = route_path.routeID and cruise.progress + 1 = 
route_path.sequence
join leg on route_path.legID = leg.legID
join ship_port on leg.departure = ship_port.portID
join person_occupies on ship_port.locationID = person_occupies.locationID
join crew on crew.assigned_to = cruise.cruiseID
join passenger on passenger.personID = person_occupies.personID
where cruise.ship_status like 'docked' 
group by ship_port.portID, ship_port.locationID, ship_port.port_name, ship_port.city,
ship_port.state, ship_port.country;


-- [17] route_summary()
-- -----------------------------------------------------------------------------
/* This view describes how the routes are being utilized by different cruises. */
-- -----------------------------------------------------------------------------
create or replace view route_summary (route, num_legs, leg_sequence, route_length,
	num_cruises, cruise_list, port_sequence) as
select
	routeID AS route,
    COUNT(DISTINCT legID) AS num_legs,
    GROUP_CONCAT(DISTINCT legID ORDER BY sequence SEPARATOR ',') AS leg_sequence,
    SUM(DISTINCT distance) AS route_length,
    COUNT(DISTINCT cruiseID) AS num_cruises,
    GROUP_CONCAT(DISTINCT cruiseID ORDER BY cruiseID SEPARATOR ',') AS cruise_list,
    GROUP_CONCAT(DISTINCT CONCAT(departure, '->', arrival) ORDER BY sequence SEPARATOR ',') AS port_sequence
FROM route
NATURAL JOIN route_path 
NATURAL JOIN leg 
NATURAL JOIN cruise 
GROUP BY route.routeID;

-- [18] alternative_ports()
-- -----------------------------------------------------------------------------
/* This view displays ports that share the same country. */
-- -----------------------------------------------------------------------------
create or replace view alternative_ports (country, num_ports,
	port_code_list, port_name_list) as
SELECT
    country as country,
    COUNT(portID) AS num_ports,
    GROUP_CONCAT(portID ORDER BY portID SEPARATOR ',') AS port_code_list,
    GROUP_CONCAT(port_name ORDER BY portID SEPARATOR ',') AS port_name_list
FROM
    ship_port
GROUP BY
    country;








