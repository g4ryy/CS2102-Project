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
    INSERT INTO Updates (update_date, new_cap, floor, room) VALUES (CURRENT_DATE, room_capacity, floor_number, room_number)
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
        ELSEIF LOWER(kind) = 'manager' THEN
            INSERT INTO Bookers(eid) VALUES(variable_id);
            INSERT INTO Managers(eid) VALUES(variable_id);
        ELSE INSERT INTO Juniors(eid) VALUES(variable_id);
        END IF;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_employee(eid_input BIGINT, resignationDate DATE) AS $$
    BEGIN   
        UPDATE Employees SET resignedDate = resignationDate WHERE eid = eid_input;
        DELETE FROM Bookers WHERE eid = eid_input;
        DELETE FROM Juniors WHERE eid = eid_input;
        DELETE FROM Sessions WHERE bookerId = eid_input AND sessionDate > resignationDate; /*delete all meetings booked by this employee*/
        DELETE FROM Joins WHERE eid = eid_input; /*Remove this employee from all future meetings*/
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

CREATE OR REPLACE PROCEDURE book_room(floor_num INT, room_num INT, booking_date DATE, start_hour INT, end_hour INT, eid INT) AS $$
    DECLARE temp INT := start_hour;
    BEGIN
        IF EXISTS (SELECT 1 FROM search_room(0, booking_date, start_hour, end_hour) AS SR
            WHERE SR.floor_number = floor_num AND SR.room_number = room_num)
        THEN
            LOOP
                EXIT WHEN temp >= end_hour;
                INSERT INTO Sessions(sessionDate, sessionTime, room, floor, bookerId)
                VALUES (booking_date, temp, room_num, floor_num, eid);
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

CREATE OR REPLACE PROCEDURE join_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE num_sessions INTEGER := ceil(end_hour/100 - start_hour/100);
        counter INTEGER := 1;
        meeting_slot INTEGER := start_hour;
        approval_indicator BIGINT;
BEGIN
    SELECT approverId FROM Sessions WHERE sessionTime = start_hour
        AND sessionDate = meeting_date
        AND room = room_num
        AND floor = floor_num INTO approval_indicator;
    IF approval_indicator IS NULL THEN
        WHILE counter <= num_sessions LOOP
            INSERT INTO Joins(eid,
            sessionDate,
            sessionTime,
            room,
            floor) VALUES(eid_input,
            meeting_date,
            meeting_slot,
            room_num,
            floor_num);
            meeting_slot := meeting_slot + counter*100;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE leave_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE num_sessions INTEGER := ceil(end_hour/100 - start_hour/100);
    counter INTEGER:= 1;
    meeting_slot INTEGER:= start_hour;
    approval_indicator BIGINT;
BEGIN
    SELECT approverId FROM Sessions WHERE sessionTime = start_hour
        AND sessionDate = meeting_date
        AND room = room_num
        AND floor = floor_num INTO approval_indicator;
    IF approval_indicator IS NULL THEN
        WHILE counter <= num_sessions LOOP
            DELETE FROM Joins 
            WHERE sessionTime = meeting_slot
            AND eid = eid_input
            AND sessionDate = meeting_date
            AND room = room_num
            AND floor = floor_num;
            meeting_slot := meeting_slot + counter*100;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE approve_meeting(floor_num INTEGER,
    room_num INTEGER,
    meeting_date DATE,
    start_hour INTEGER,
    end_hour INTEGER,
    eid_input BIGINT)
AS $$
DECLARE num_sessions INTEGER := ceil(end_hour/100 - start_hour/100);
    counter INTEGER:= 1;
    meeting_slot := start_hour;
BEGIN
    WHILE counter <= num_sessions LOOP
        UPDATE Sessions
        SET approverId = eid_input
        WHERE sessionTime = meeting_slot
        AND sessionDate = meeting_date
        AND room = room_num
        AND floor = floor_num;
        meeting_slot := meeting_slot + counter*100;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE declare_health(id BIGINT, curr_date DATE, curr_temp NUMERIC) AS $$
	BEGIN --assume that health declaration is to be done once at the end of the day
		INSERT INTO HealthDeclarations (eid, declareDate, temp) VALUES(id, curr_date, curr_temp);
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION contact_tracing(id BIGINT) AS $$
RETURNS RECORD AS $$ --assume that health declaration is always moving forward in time
    DECLARE
        curr_fever NUMERIC := SELECT fever FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1;
        curr_date DATE := SELECT declareDate FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1;

        curs1 CURSOR;
        r1 RECORD;
    BEGIN
        IF curr_fever = 1 THEN
            DELETE FROM Joins WHERE eid = id AND sessionTime > curr_date; --delete employee from future meetings
            DELETE FROM Sessions WHERE bookerID = id AND sessionTime > curr_date;  --delete sessions booked by the employee /auto deletes sessions in joins

            SELECT room, floor, sessionDate, sessionTime INTO contactRoom 
            FROM Sessions WHERE eid = id
            AND approverID IS NOT NULL
            AND (sessionTime = curr_date OR sessionTime = curr_date - 1 OR sessionTime = curr_date - 2 OR sessionTime = curr_date - 3);

            SELECT eid INTO employeesCloseContact
            FROM Sessions s, contactRoom c
            WHERE s.room = c.room AND s.floor = c.floor AND s.sessionDate = c.sessionDate AND s.sessionTime = c.sessionTime;

            OPEN curs1 FOR SELECT * FROM employeesCloseContact;
            LOOP
            FETCH curs1 INTO r1;
            EXIT WHEN NOT FOUND;

            DELETE FROM Joins WHERE eid = r1.id AND (sessionTime >= curr_date OR sessionTime < curr_date + 7) --delete contacted employees from future meetings

            END LOOP;
            CLOSE curs1;
            RETURN employeesCloseContact;

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
RETURN TABLE(floor_number INTEGER, room_number INTEGER, meeting_date DATE, start_hour INTEGER, is_approved BOOLEAN) AS $$
    BEGIN
        RETURN QUERY
        SELECT floor, room, sessionDate, sessionTime, approverID IS NOT NULL
        FROM Sessions
        WHERE sessionDate >= start_date AND bookerID = eid
        ORDER BY sessionDate, sessionTime;
    END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION view_future_meeting(start_date DATE, eid BIGINT) 
RETURN 


------------------------------------- TRIGGERS ---------------------------------------------
-- generates unique email for a new employee that has just been added.
CREATE OR REPLACE FUNCTION generate_email()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Employees 
    SET email = LOWER(REPLACE(NEW.ename, ' ', ''))  || NEW.eid::TEXT || '@company.com' WHERE Employees.eid = NEW.eid;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql; 

CREATE TRIGGER new_employee_added 
AFTER INSERT ON Employees
FOR EACH ROW EXECUTE FUNCTION generate_email();

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

CREATE TRIGGER check_senior
BEFORE INSERT OR UPDATE ON Seniors
FOR EACH ROW 
EXECUTE FUNCTION check_type();

CREATE TRIGGER check_manager
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
3. booker does not have another meeting in the same timeslot**/
CREATE OR REPLACE FUNCTION check_for_booking()
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    IF NEW.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.bookerId) THEN
        RAISE NOTICE 'Booker already resigned!';
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.bookerId AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW,sessionTime) THEN
        RAISE NOTICE 'Unable to book, there is conflict with another meeting!';
        RETURN NULL;
    END IF;

    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.bookerId
    AND HealthDeclarations.declareDate = NEW.sessionDate;

    IF fever_status = 't' THEN
        RAISE NOTICE 'Cannot book when having fever!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_book_check
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW
EXECUTE FUNCTION check_for_booking();

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

/** Ensure that once a booked meeting is approved, its sessionDate, sessionTime, room, floor and bookerId cannot be changed anymore.
approverId can only be changed to null in the event that the approver decides to unapprove the meeting (contact tracing)

**/
CREATE OR REPLACE FUNCTION cannot_approve_anymore()
RETURNS TRIGGER AS $$
BEGIN
    NEW.sessionDate = OLD.sessionDate; -- ensure date cannot changed anymore 
    NEW.sessionTime = NULL;
    RAISE NOTICE 'This meeting cannot be updated as it had already been approved.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER approve_only_once
BEFORE UPDATE ON Sessions
FOR EACH ROW WHEN (OLD.approverId IS NOT NULL)
EXECUTE FUNCTION cannot_approve_anymore();

/**prevent joining if :
1. employee has resigned or 
2. employee has fever or
3. employee has another meeting at that date and time OR 
4. Meeting had already been approved **//
CREATE OR REPLACE FUNCTION check_for_joining()
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    IF NEW.sessionDate > (SELECT resignedDate FROM Employees E WHERE E.eid = NEW.eid) THEN
        RAISE NOTICE 'Employee already resigned!';
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM Joins J WHERE J.eid = NEW.eid AND J.sessionDate = NEW.sessionDate AND J.sessionTime = NEW.sessionTime) THEN
        RAISE NOTICE 'There is a conflict with another meeting!';
        RETURN NULL;
    END IF;

    IF ((SELECT approverId FROM Sessions S WHERE S.sessionDate = NEW.sessionDate 
            AND S.sessionTime = NEW.sessionTime AND S.room = NEW.room AND S.floor = NEW.floor) IS NOT NULL) THEN
        RAISE NOTICE 'Meeting had already been approved, cannot join anymore!';
        RETURN NULL;
    END IF; 

    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.eid
    AND HealthDeclarations.declareDate = NEW.sessionDate;

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

