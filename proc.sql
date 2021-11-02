---------------------------------- Application Functionalities ------------------------------
CREATE OR REPLACE PROCEDURE add_department(id INTEGER, name TEXT) AS $$
	BEGIN
		INSERT INTO Departments (did, dname) VALUES (id, name);
	END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE remove_department(id INTEGER) AS $$
	BEGIN
		DELETE FROM Departments WHERE did = id;
	END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE add_room(floor_number INTEGER, room_number INTEGER, room_name TEXT, room_capacity INTEGER, departmentId INTEGER) AS $$
	BEGIN
    INSERT INTO MeetingRooms (room, floor, rname, did) VALUES (room_number, floor_number, room_name, departmentId);
    INSERT INTO Updates (update_date, new_cap, floor, room) VALUES (CURRENT_DATE, room_capacity, floor_number, room_number);
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE change_capacity(floor_number INTEGER, room_number INTEGER, capacity INTEGER, changed_date DATE, eid_input INTEGER) AS $$
    BEGIN
        IF ((eid_input IN (SELECT eid FROM Managers)) AND 
            (eid_input IN (SELECT eid FROM Employees NATURAL JOIN MeetingRooms WHERE floor = floor_number AND room = room_number))) THEN
            INSERT INTO Updates(update_date, new_cap, floor, room) VALUES(changed_date, capacity, floor_number, room_number);
        END IF;
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE add_employee(ename_input TEXT, department_name TEXT, mobile_contact_input INTEGER, home_contact_input INTEGER,
    office_contact_input INTEGER, kind TEXT) AS $$
    DECLARE 
        variable_id BIGINT;
        variable_did INTEGER;
    BEGIN
        SELECT did FROM Departments WHERE LOWER(dname) = LOWER(department_name) INTO variable_did;
        INSERT INTO Employees(did, ename, home_contact, office_contact, mobile_contact) 
                VALUES(variable_did, ename_input, home_contact_input, office_contact_input, mobile_contact_input) RETURNING eid INTO variable_id;
        IF LOWER(kind) = 'senior' THEN 
            INSERT INTO Bookers(eid) VALUES(variable_id);
            INSERT INTO Seniors(eid) VALUES(variable_id);
        ELSIF LOWER(kind) = 'manager' THEN
            INSERT INTO Bookers(eid) VALUES(variable_id);
            INSERT INTO Managers(eid) VALUES(variable_id);
        ELSE INSERT INTO Juniors(eid) VALUES(variable_id);
        END IF;

        UPDATE Employees 
        SET email = LOWER(REPLACE(ename_input, ' ', ''))  || variable_id::TEXT || '@company.com' 
        WHERE Employees.eid = variable_id;
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE remove_employee(eid_input BIGINT, resignationDate DATE) AS $$
    BEGIN   
        UPDATE Employees SET resignedDate = resignationDate WHERE eid = eid_input;
        DELETE FROM Sessions WHERE bookerId = eid_input AND sessionDate > resignationDate; -- delete all future meetings booked by this employee
        DELETE FROM Joins WHERE eid = eid_input AND sessionDate > resignationDate;  -- Remove this employee from all future meetings
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION search_room(capacity_input INTEGER, search_date DATE, start_hour INTEGER, end_hour INTEGER)
RETURNS TABLE(floor_number INTEGER, room_number INTEGER, Department_id INTEGER, capacity INTEGER) AS $$
BEGIN
RETURN QUERY
    SELECT u2.floor, u2.room, m2.did, u2.new_cap
    FROM MeetingRooms AS m2, Updates u2
    WHERE NOT EXISTS (
        SELECT 1
        FROM Sessions AS s, MeetingRooms AS m
        WHERE (s.sessionDate = search_date
            AND s.sessionTime >= start_hour
            AND s.sessionTime < end_hour
            AND m.room = s.room
            AND m.room = m2.room
            AND m.floor = m2.floor
            AND m.floor = s.floor))
    AND u2.new_cap >= capacity_input
    AND u2.floor = m2.floor
    AND u2.room = m2.room
    AND u2.update_date IN (SELECT MAX(update_date)
        FROM Updates U
        WHERE U.room = m2.room 
        AND U.floor = m2.floor
        AND U.update_date <= search_date)
    ORDER BY u2.new_cap;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE book_room(floor_num INT, room_num INT, booking_date DATE, start_hour INT, end_hour INT, eid_input INT) AS $$
    DECLARE temp INT := start_hour;
    BEGIN
        IF EXISTS (SELECT 1 FROM search_room(0, booking_date, start_hour, end_hour) AS SR
            WHERE SR.floor_number = floor_num AND SR.room_number = room_num)
        THEN
            LOOP
                EXIT WHEN temp >= end_hour;
                INSERT INTO Sessions(sessionDate, sessionTime, room, floor, bookerId)
                VALUES (booking_date, temp, room_num, floor_num, eid_input);
                temp := temp + 1;
            END LOOP;
        END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE unbook_room(floor_number INT, room_number INT, unbookingDate DATE, start_hour INT, end_hour INT, eid INT)
AS $$
    DECLARE temp INT := start_hour;
    BEGIN
        IF EXISTS (SELECT 1 FROM Sessions WHERE bookerId = eid
        AND floor_number = floor
        AND room_number = room
        AND unbookingDate = sessionDate)
        THEN
            LOOP
                EXIT WHEN temp >= end_hour;
                DELETE FROM Sessions WHERE bookerId = eid AND floor_number = floor
                AND room_number = room
                AND unbookingDate = sessionDate
                AND temp = sessionTime;
                temp := temp + 1;
            END LOOP;
        END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION find_room_capacity(meeting_date DATE, floor_num INTEGER,room_num INTEGER)
RETURNS INTEGER AS $$
    SELECT new_cap
    FROM Updates
    WHERE room = room_num
    AND floor = floor_num
    AND meeting_date >= update_date
    ORDER BY update_date DESC
    LIMIT 1;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION check_approval(meeting_date DATE, meeting_time INTEGER, floor_num INTEGER,room_num INTEGER)
RETURNS BIGINT AS $$
    SELECT approverId FROM Sessions WHERE sessionTime = meeting_time
        AND sessionDate = meeting_date
        AND room = room_num
        AND floor = floor_num;
$$ LANGUAGE sql;


CREATE OR REPLACE PROCEDURE join_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE meeting_slot INTEGER := start_hour;
        approval_indicator BIGINT;
        current_num_ppl INTEGER;
        room_cap INTEGER;
BEGIN
    SELECT * FROM find_room_capacity(meeting_date, floor_num, room_num) INTO room_cap;
    WHILE meeting_slot < end_hour LOOP
        SELECT COUNT(*) FROM Joins WHERE sessionDate = meeting_date
            AND sessionTime = start_hour
            AND room = room_num
            AND floor = floor_num INTO current_num_ppl;
        SELECT * FROM check_approval(meeting_date, meeting_slot, floor_num, room_num) INTO approval_indicator;
        IF approval_indicator IS NULL 
            AND current_num_ppl < room_cap
            AND NOT EXISTS (SELECT 1
                            FROM Joins
                            WHERE sessionDate = meeting_date
                            AND sessionTime = meeting_slot
                            AND eid = eid_input)
        THEN
            INSERT INTO Joins(eid,
            sessionDate,
            sessionTime,
            room,
            floor) VALUES(eid_input,
            meeting_date,
            meeting_slot,
            room_num,
            floor_num);
        END IF;
        meeting_slot := meeting_slot + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE leave_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE 
    meeting_slot INTEGER:= start_hour;
    approval_indicator BIGINT;
BEGIN
    DELETE FROM Sessions S
    WHERE S.sessionDate = meeting_date AND
    S.sessionTime >= start_hour AND
    S.sessionTime < end_hour AND
    S.bookerId = eid_input AND
    S.floor = floor_num AND
    S.room = room_num AND
    check_approval(meeting_date, S.sessionTime, floor_num, room_num) IS NULL; 

    DELETE FROM Joins J
    WHERE J.sessionDate = meeting_date AND
    J.sessionTime >= start_hour AND
    J.sessionTime < end_hour AND
    J.eid = eid_input AND
    J.floor = floor_num AND
    J.room = room_num AND
    check_approval(meeting_date, J.sessionTime, floor_num, room_num) IS NULL; 
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE approve_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE meeting_slot INTEGER := start_hour;
        approval_indicator BIGINT;
BEGIN
    WHILE meeting_slot < end_hour LOOP
        SELECT * FROM check_approval(meeting_date, meeting_slot, floor_num, room_num) INTO approval_indicator;
        IF approval_indicator IS NULL THEN
            UPDATE Sessions
            SET approverId = eid_input
            WHERE sessionTime = meeting_slot
            AND sessionDate = meeting_date
            AND room = room_num
            AND floor = floor_num;
        END IF;
        meeting_slot := meeting_slot + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE declare_health(id BIGINT, curr_date DATE, curr_temp NUMERIC) AS $$
	BEGIN --assume that health declaration is to be done once by the end of the day
		INSERT INTO HealthDeclarations (eid, declareDate, temp) VALUES(id, curr_date, curr_temp);
	END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION contact_tracing(id BIGINT)
RETURNS TABLE(close_contacts_id BIGINT) AS $$ --assume that health declaration is always moving forward in time
    DECLARE
        curr_fever BOOLEAN;
        curr_date DATE;
        curs1 refcursor;
        r1 RECORD;
    BEGIN
        SELECT fever FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1 INTO curr_fever;
        SELECT declareDate FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1 INTO curr_date;
        IF fever THEN
            DELETE FROM Joins WHERE eid = id AND sessionDate > curr_date; --delete employee from future meetings
            DELETE FROM Sessions WHERE bookerID = id AND sessionDate > curr_date;  --delete sessions booked by the employee /auto deletes sessions in joins

            CREATE TEMP TABLE IF NOT EXISTS temp AS
            SELECT DISTINCT(j1.eid)
            FROM Joins j1, (SELECT j2.room, j2.floor, j2.sessionDate, j2.sessionTime
                            FROM Joins j2, Sessions s1
                            WHERE j2.eid = id
                            AND s1.approverID IS NOT NULL
                            AND j2.room = s1.room
                            AND j2.floor = s1.floor
                            AND j2.sessionDate = s1.sessionDate
                            AND j2.sessionTime = s1.sessionTime
                            AND (j2.sessionDate = curr_date OR 
                                j2.sessionDate = (curr_date - 1) OR 
                                j2.sessionDate = (curr_date - 2) OR 
                                j2.sessionDate = (curr_date - 3)))c1
            WHERE j1.room = c1.room 
            AND j1.floor = c1.floor 
            AND j1.sessionDate = c1.sessionDate
            AND j1.sessionTime = c1.sessionTime
            AND j1.eid <> id;

            OPEN curs1 FOR SELECT * FROM temp;
            LOOP
            FETCH curs1 INTO r1;
            EXIT WHEN NOT FOUND;

            DELETE FROM Joins j
            WHERE j.eid = r1.eid 
            AND (j.sessionDate >= curr_date AND 
                j.sessionDate < curr_date + 7); --delete contacted employees from future meetings

            END LOOP;
            CLOSE curs1;

            RETURN QUERY
            SELECT * FROM temp;
        ELSE
            RETURN;
        END IF;
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION non_compliance(start_date DATE, end_date DATE)
RETURNS TABLE(id BIGINT, days BIGINT) AS $$
	DECLARE
		totalDays INTEGER := end_date - start_date + 1;
	BEGIN
		RETURN QUERY
		SELECT eid, totalDays - COUNT(*)
		FROM HealthDeclarations
		WHERE declareDate >= start_date AND declareDate <= end_date
		GROUP BY eid
		HAVING COUNT(*) < totalDays;
	END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_booking_report(start_date DATE, eid BIGINT)
RETURNS TABLE(floor_number INTEGER, room_number INTEGER, meeting_date DATE, start_hour INTEGER, is_approved BOOLEAN) AS $$
    BEGIN
        RETURN QUERY
        SELECT floor, room, sessionDate, sessionTime, approverID IS NOT NULL
        FROM Sessions
        WHERE sessionDate >= start_date AND bookerID = eid
        ORDER BY sessionDate, sessionTime;
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_future_meeting(start_date DATE, start_slot INTEGER, eid_input BIGINT)  
RETURNS TABLE(floor_number INTEGER, room_number INTEGER, meeting_date DATE, start_hour INTEGER) AS $$
    BEGIN
        IF (start_date < CURRENT_DATE OR (start_date = CURRENT_DATE AND start_hour <= EXTRACT(HOUR FROM NOW()))) THEN
            RAISE NOTICE 'start_date and start_hour must be in the future!';
            RETURN;
        END IF;

        RETURN QUERY
        SELECT J.floor, J.room, J.sessionDate, J.sessionTime 
        FROM Joins J NATURAL JOIN Sessions S
        WHERE J.eid = eid_input 
                AND ((J.sessionDate > start_date) OR (J.sessionDate = start_date AND J.sessionTime >= start_slot))
                AND S.approverId IS NOT NULL
        ORDER BY J.sessionDate, J.sessionTime;
    END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_manager_report(start_date DATE, eid_input BIGINT)
RETURNS TABLE(floor_number INTEGER, room_number INTEGER, meeting_date DATE, start_hour INTEGER, eid BIGINT) AS $$
    DECLARE
        manager_did INTEGER;
    BEGIN
        IF (NOT EXISTS(SELECT 1 FROM Managers M WHERE M.eid = eid_input)) THEN
            RETURN;
        END IF;

        SELECT did INTO manager_did FROM Employees E WHERE E.eid = eid_input;

        RETURN QUERY
        SELECT S.floor, S.room, S.sessionDate, S.sessionTime, S.bookerId
        FROM Sessions S NATURAL JOIN MeetingRooms M 
        WHERE M.did = manager_did 
                AND S.approverId IS NULL
                AND S.sessionDate >= start_date
        ORDER BY S.sessionDate, S.sessionTime;
    END;
$$ LANGUAGE plpgsql;
        
------------------------------------- TRIGGERS ---------------------------------------------
-- ensure each employee is only of 1 type
CREATE OR REPLACE FUNCTION check_type()
RETURNS TRIGGER AS $$
BEGIN
    IF (EXISTS(SELECT 1 FROM Juniors J WHERE J.eid = NEW.eid)) THEN
        RAISE NOTICE 'This employee is already a junior!';
        RETURN NULL;
    ELSIF (EXISTS(SELECT 1 FROM Seniors S WHERE S.eid = NEW.eid)) THEN
        RAISE NOTICE 'This employee is already a senior!';
        RETURN NULL;
    ELSIF (EXISTS(SELECT 1 FROM Managers M WHERE M.eid = NEW.eid)) THEN
        RAISE NOTICE 'This employee is already a manager!';
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER is_junior_only
BEFORE INSERT OR UPDATE ON Juniors
FOR EACH ROW 
EXECUTE FUNCTION check_type();

CREATE TRIGGER is_senior_only
BEFORE INSERT OR UPDATE ON Seniors
FOR EACH ROW 
EXECUTE FUNCTION check_type();

CREATE TRIGGER is_manager_only
BEFORE INSERT OR UPDATE ON Managers
FOR EACH ROW 
EXECUTE FUNCTION check_type();

-- Ensure junior cannot be booker, and vice versa
CREATE OR REPLACE FUNCTION prevent_junior_booker() 
RETURNS TRIGGER AS $$ 
BEGIN 
    IF (EXISTS(SELECT 1 FROM Juniors J WHERE J.eid = NEW.eid)) THEN
        RAISE NOTICE 'A booker cannot be a junior!';
        RETURN NULL;
    ELSIF (EXISTS(SELECT 1 FROM Bookers B WHERE B.eid = NEW.eid)) THEN
        RAISE NOTICE 'A junior cannot be a booker!';
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER booker_cannot_be_junior
BEFORE INSERT OR UPDATE ON Bookers
FOR EACH ROW
EXECUTE FUNCTION prevent_junior_booker();

CREATE TRIGGER junior_cannot_be_booker
BEFORE INSERT OR UPDATE ON Juniors
FOR EACH ROW
EXECUTE FUNCTION prevent_junior_booker();

/**prevent booking if :
1. booker has resigned or
2. booker has fever 
3. booker already has another meeting in the same timeslot**/
CREATE OR REPLACE FUNCTION check_for_booking()
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    IF NEW.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.bookerId) THEN
        RAISE NOTICE 'Booker already resigned!';
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.bookerId AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW.sessionTime) THEN
        RAISE NOTICE 'Unable to book, there is conflict with another meeting!';
        RETURN NULL;
    END IF;

    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.bookerId
    AND HealthDeclarations.declareDate = CURRENT_DATE;

    IF fever_status = 't' THEN
        RAISE NOTICE 'Cannot book when having fever!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_book_check
BEFORE INSERT ON Sessions
FOR EACH ROW 
EXECUTE FUNCTION check_for_booking();

-- booker immediately join as participant
CREATE OR REPLACE FUNCTION join_after_book() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO Joins VALUES(NEW.bookerId, NEW.sessionDate, NEW.sessionTime, NEW.room, NEW.floor);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER immediate_join
AFTER INSERT ON Sessions
FOR EACH ROW
EXECUTE FUNCTION join_after_book();


/* Sessions that are not approved yet can be modified, but must not exceed capacity of room and must meet the same 
conditions for inserting a new booking. */
CREATE OR REPLACE FUNCTION check_for_modification()
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    IF NEW.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.bookerId) THEN
        RAISE NOTICE 'Booker already resigned!';
        RETURN NULL;
    END IF;

    IF (NEW.sessionDate <> OLD.sessionDate OR NEW.sessionTime <> OLD.sessionTime)
        AND EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.bookerId AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW.sessionTime) THEN
        RAISE NOTICE 'Unable to change booking, booker has conflict with another meeting!';
        RETURN NULL;
    END IF;

    IF (
        (SELECT COUNT(*) FROM Joins J WHERE J.sessionDate = OLD.sessionDate AND 
                J.sessionTime = OLD.sessionTime AND J.room = OLD.room AND J.floor = OLD.floor) 
        > (SELECT new_cap FROM Updates U WHERE U.floor = NEW.floor AND U.room = NEW.room ORDER BY update_date DESC LIMIT 1) 
        ) THEN 
        RAISE NOTICE 'Exceed room capacity of new room, cannot change!';
        RETURN NULL;
    END IF;

    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.bookerId
    AND HealthDeclarations.declareDate = CURRENT_DATE;

    IF fever_status = 't' THEN
        RAISE NOTICE 'Cannot book when having fever!';
        RETURN NULL;
    ELSE
        IF NEW.bookerId <> OLD.bookerId THEN
            UPDATE Joins J SET eid = NEW.bookerId 
            WHERE J.eid = OLD.bookerId AND J.sessionDate = OLD.sessionDate AND J.sessionTime = OLD.sessionTime AND J.room = OLD.room AND J.floor = OLD.floor;
        END IF;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER modify_not_approved_yet 
BEFORE UPDATE ON Sessions 
FOR EACH ROW WHEN (NEW.approverId IS NULL)
EXECUTE FUNCTION check_for_modification();


/* Ensure a manager can only approve a booked meeting from the same department provided that they have not resigned,
Also ensures that an approval can only be made on future meetings. */
CREATE OR REPLACE FUNCTION check_approve()
RETURNS TRIGGER AS $$
DECLARE
    room_dept INTEGER;
    manager_dept INTEGER;
BEGIN 
    OLD.approverId = NEW.approverId; -- Ensure that only approverId is updated, and not other attributes
    IF OLD.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.approverId) THEN
        RAISE NOTICE 'Manager already resigned, not allowed to approve anymore!';
        RETURN NULL;
    END IF;

    IF ((OLD.sessionDate < CURRENT_DATE) OR 
            ((OLD.sessionDate = CURRENT_DATE) AND OLD.sessionTime <= EXTRACT(HOUR FROM NOW()))) THEN
        RAISE NOTICE 'Can only approve future meetings!';
        RETURN NULL;
    END IF;

    SELECT did INTO room_dept FROM MeetingRooms M where M.room = OLD.room AND M.floor = OLD.floor;
    SELECT did INTO manager_dept FROM Employees E where E.eid = NEW.approverId;

    IF (room_dept = manager_dept) THEN
        RETURN OLD;
    ELSE 
        RAISE NOTICE 'Cannot approve meeting room that is not from the same department!';
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_approve_check
BEFORE UPDATE ON Sessions
FOR EACH ROW WHEN ((OLD.approverId IS NULL) AND (NEW.approverId IS NOT NULL))
EXECUTE FUNCTION check_approve();

-- Ensure that a booked meeting is only approved once and all other attributes cannot be updated once approved.
CREATE OR REPLACE FUNCTION cannot_approve_anymore()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'This meeting cannot be updated as it had already been approved.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approve_only_once
BEFORE UPDATE ON Sessions
FOR EACH ROW WHEN (OLD.approverId IS NOT NULL AND NEW.approverId IS NOT NULL)
EXECUTE FUNCTION cannot_approve_anymore();

/*prevent joining if :
1. employee has resigned or 
2. employee has fever or
3. employee has another meeting at that date and time OR 
4. Meeting had already been approved */
CREATE OR REPLACE FUNCTION check_for_joining()
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    IF NEW.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.eid) THEN
        RAISE NOTICE 'Employee already resigned!';
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' AND EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.eid AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW.sessionTime) THEN
        RAISE NOTICE 'There is a conflict with another meeting!';
        RETURN NULL;
    END IF;

    IF TG_OP = 'UPDATE' AND 
            EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.eid AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW.sessionTime 
                    AND (J.room <> OLD.room OR J.floor <> OLD.floor))THEN
        RAISE NOTICE 'There is a conflict with another meeting!';
        RETURN NULL;
    END IF;

    IF ((SELECT approverId FROM Sessions S WHERE S.sessionDate = NEW.sessionDate 
            AND S.sessionTime = NEW.sessionTime AND S.room = NEW.room AND S.floor = NEW.floor) IS NOT NULL) THEN
        RAISE NOTICE 'Meeting had already been approved, cannot join anymore!';
        RETURN NULL;
    END IF; 

    IF (
        (SELECT COUNT(*) FROM Joins J WHERE J.sessionDate = NEW.sessionDate AND 
                J.sessionTime = NEW.sessionTime AND J.room = NEW.room AND J.floor = NEW.floor) 
        >= (SELECT new_cap FROM Updates U WHERE U.floor = NEW.floor AND U.room = NEW.room ORDER BY update_date DESC LIMIT 1) 
        ) THEN 
        RAISE NOTICE 'No more vacancies, unable to join!';
        RETURN NULL;
    END IF;

    IF (
        TG_OP = 'UPDATE' AND 
                (SELECT approverId FROM Sessions S WHERE S.sessionDate = OLD.sessionDate 
                AND S.sessionTime = OLD.sessionTime AND S.room = OLD.room AND S.floor = OLD.floor) IS NOT NULL
        ) THEN
            RAISE NOTICE 'Meeting had already been approved, cannot change anymore!';
            RETURN NULL;
    END IF; 

    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.eid
    AND HealthDeclarations.declareDate = CURRENT_DATE;

    IF fever_status = 't' THEN
        RAISE NOTICE 'Cannot join when having fever!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_join_if_resigned_or_fever
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW
EXECUTE FUNCTION check_for_joining();


/* When a meeting room has its capacity changed, any room booking after the change date with more 
participants (including the employee who made the booking) will automatically be removed. 
This is regardless of whether they are approved or not. */
CREATE OR REPLACE FUNCTION check_exceed_cap() 
RETURNS TRIGGER AS $$
BEGIN 
    DELETE FROM Sessions S
    WHERE S.sessionDate > NEW.update_date
    AND S.room = NEW.room 
    AND S.floor = NEW.floor
    AND  (SELECT COUNT(*) FROM Joins J WHERE S.sessionDate = J.sessionDate 
            AND S.sessionTime = J.sessionTime AND S.room = J.room AND S.floor = J.floor) > NEW.new_cap;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
    
CREATE TRIGGER remove_exceed_cap
AFTER INSERT OR UPDATE ON Updates
FOR EACH ROW 
EXECUTE FUNCTION check_exceed_cap();



