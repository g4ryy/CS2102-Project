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

CREATE OR REPLACE PROCEDURE Add_employee(ename_input TEXT, department_name TEXT, mobile_contact_input INTEGER, home_contact_input INTEGER,
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

CREATE OR REPLACE FUNCTION search_room
	(capacity INT, date DATE, start_hour INT, end_hour INT);
RETURNS TABLE (floor, room) AS $$
BEGIN
	SELECT m2.room, m2.floor
	FROM MeetingRoom AS m2
	WHERE NOT EXISTS (
		SELECT m.room, m.floor, u.floor, u.room, u.update_date, u.new_cap
		FROM Sessions AS s, MeetingRoom AS m, Updates AS u
		WHERE (s.sessionDate = date
			AND s.sessionTime >= start_hour
			AND sessionTime <= end_hour
			AND m.room = u.room
			AND m.floor = u.floor
			AND date >= u.update_date
			AND capacity <= new_cap))
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION book_room(floor_number INT, room_number INT, date DATE, start_hour INT, end_hour INT, eid INT)
RETURNS VOID AS $$
	DECLARE temp INT := start_hour;
	IF EXISTS (SELECT 1 FROM book_room(1, date, start_hour, end_hour) AS br WHERE br.floor = floor_number AND br.room = room_number)
	IF eid (SELECT 1 FROM HealthDeclarations AS h WHERE h.eid = eid AND h.fever = false)
	BEGIN
		LOOP
			EXIT WHEN temp > end_hour
			INSERT INTO Sessions (sessionDate, sessionTime, room, floor, bookerId, approverId) VALUES (date, temp, room_number, floor_number, eid, NULL);
			temp := temp + 1
		END LOOP;
END;
$$ LANGUAGE plpgsql

CREATE OR REPLACE FUNCTION unbook_room(floor_number INT, room_nuber INT, date DATE, start_hour INT, end_hour INT, eid INT)
RETURNS VOID AS $$
	DECLARE temp INT := start_hour;
	IF EXISTS (SELECT 1 FROM Sessions WHERE eid = id AND floor_number = floor AND room_number = room AND date = sessionDate AND start_hour = sessionTime)
	BEGIN
		LOOP
			EXIT WHEN temp > end_hour
			DELETE FROM Sessions WHERE eid = id AND floor_number = floor AND room_number = room AND date = sessionDate AND temp = sessionTime;
			temp := temp + 1
		END LOOP;
END;
$$ LANGUAGE plpgsql

CREATE OR REPLACE PROCEDURE add_room(floor_number INTEGER, room_number INTEGER, room_name TEXT, room_capacity INTEGER, departmentId INTEGER) AS $$
	INSERT INTO MeetingRooms (room, floor, rname, did) VALUES(floor_number, room_number, room_name, departmentId);
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE change_capacity(floor_number INTEGER, room_number INTEGER, capacity INTEGER, date DATE, eid INTEGER) AS $$
	INSERT INTO Updates (eid, update_date, new_cap, floor, room) VALUES(eid, date, capacity, floor_number, room_number);
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION view_booking_report(start_date DATE, eid BIGINT)
RETURN TABLE(floor_number INTEGER, room_number INTEGER, meeting_date DATE, start_hour INTEGER, is_approved BOOLEAN) AS $$
    BEGIN
        RETURN QUERY
        SELECT floor, room, sessionDate, sessionTime, approverID IS NULL
        FROM Sessions
        WHERE sessionDate >= start_date AND bookerID = eid
        ORDER BY sessionDate, sessionTime;
    END;
$$ LANGUAGE plpgsql;

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

-- ensure junior cannot be senior or manager
CREATE OR REPLACE FUNCTION not_senior_manager
RETURNS TRIGGER AS 
$$
DECLARE
    count_senior NUMERIC;
    count_manager NUMERIC;
BEGIN
    SELECT COUNT (*) INTO count_senior
    FROM Seniors
    WHERE Seniors.eid = NEW.eid;

    SELECT COUNT(*) INTO count_manager
    FROM Managers
    WHERE Managers.eid = NEW.eid;

    IF (count_senior > 0) OR (count_manager > 0) THEN
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_junior
BEFORE INSERT OR UPDATE ON Juniors
FOR EACH ROW 
EXECUTE FUNCTION not_senior_manager();

-- ensure senior cannot be junior or manager
CREATE OR REPLACE FUNCTION not_junior_manager
RETURNS TRIGGER AS 
$$
DECLARE
    count_junior NUMERIC;
    count_manager NUMERIC;
BEGIN
    SELECT COUNT (*) INTO count_junior
    FROM Juniors
    WHERE Juniors.eid = NEW.eid;

    SELECT COUNT(*) INTO count_manager
    FROM Managers
    WHERE Managers.eid = NEW.eid;

    IF (count_junior > 0) OR (count_manager > 0) THEN
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_senior
BEFORE INSERT OR UPDATE ON Seniors
FOR EACH ROW 
EXECUTE FUNCTION not_junior_manager();

-- ensure manager cannot be junior or senior
CREATE OR REPLACE FUNCTION not_junior_senior
RETURNS TRIGGER AS $$
DECLARE
    count_junior NUMERIC;
    count_senior NUMERIC;
BEGIN
    SELECT COUNT (*) INTO count_junior
    FROM Juniors
    WHERE Juniors.eid = NEW.eid;

    SELECT COUNT(*) INTO count_senior
    FROM Seniors
    WHERE Seniors.eid = NEW.eid;

    IF (count_junior > 0) OR (count_senior > 0) THEN
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_manager
BEFORE INSERT OR UPDATE ON Managers
FOR EACH ROW 
EXECUTE FUNCTION not_junior_senior();

-- prevent booking if booker has fever
CREATE OR REPLACE FUNCTION check_fever_for_booking
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.bookerId;

    IF fever_status = 't' THEN
        RAISE EXCEPTION 'Cannot book when having fever!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_book_if_fever
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW
EXECUTE FUNCTION check_fever_for_booking;

-- prevent joining booked meeting if employee has fever
CREATE OR REPLACE FUNCTION check_fever_for_joining
RETURNS TRIGGER AS $$
DECLARE
    fever_status BOOLEAN;
BEGIN
    SELECT fever INTO fever_status
    FROM HealthDeclarations
    WHERE HealthDeclarations.eid = NEW.eid;

    IF fever_status = 't' THEN
        RAISE EXCEPTION 'Cannot join when having fever!';
        RETURN NULL;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_join_if_fever
BEFORE INSERT OR UPDATE ON Joins
FOR EACH ROW
EXECUTE FUNCTION check_fever_for_joining;

