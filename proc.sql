DROP PROCEDURE IF EXISTS add_department(INTEGER, TEXT), remove_department(INTEGER), declare_health(BIGINT, DATE, NUMERIC)
DROP FUNCTION IF EXISTS contact_tracing(BIGINT), non_compliance(DATE, DATE);
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

CREATE OR REPLACE PROCEDURE declare_health(id BIGINT, curr_date DATE, curr_temp NUMERIC) AS $$
	BEGIN
		IF EXISTS (SELECT 1 FROM HealthDeclarations WHERE eid = id AND declareDate = curr_date)
		BEGIN
			UPDATE HealthDeclarations SET temp = curr_temp WHERE eid = id AND declareDate = curr_date;
		END
		ELSE
		BEGIN
			INSERT INTO HealthDeclarations (eid, declareDate, temp) VALUES(id, curr_date, curr_temp);
		END
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION contact_tracing(id BIGINT) AS $$
RETURNS RECORD AS $$
	DECLARE
		curr_fever := SELECT fever FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1;
		curr_date := SELECT declareDate FROM HealthDeclarations WHERE eid = id ORDER BY declareDate DESC LIMIT 1;
	BEGIN
		IF curr_fever == 1
		BEGIN

		END;
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

//adeline add here//
CREATE OR REPLACE PROCEDURE Add_employee(ename_input TEXT,
    department_name TEXT,
    mobile_contact_input INTEGER,
    home_contact_input INTEGER,
    office_contact_input INTEGER,
    kind TEXT)
AS $$
DECLARE 
    variable_id BIGINT;
    variable_did INTEGER;
BEGIN
    SELECT did FROM Departments WHERE LOWER(dname) = LOWER(department_name) INTO variable_did;
    INSERT INTO Employees(did,
        ename,
        home_contact,
        office_contact,
        mobile_contact) VALUES(variable_did,
        ename_input,
        home_contact_input,
        office_contact,
        mobile_contact_input) RETURNING eid INTO variable_id;
    IF LOWER(kind) = 'senior' THEN 
        INSERT INTO Booker(eid) VALUES(variable_id);
        INSERT INTO Senior(eid) VALUES(variable_id);
    ELSEIF LOWER(kind) = 'manager' THEN
        INSERT INTO Booker(eid) VALUES(variable_id);
        INSERT INTO Manager(eid) VALUES(variable_id);
    ELSE INSERT INTO Junior(eid) VALUES(variable_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_employee(eid_input BIGSERIAL, resignationDate DATE)
AS $$
BEGIN
    UPDATE Employees SET resignedDate = resignationDate WHERE eid = eid_input;
    DELETE FROM Booker WHERE eid = eid_input;
    DELETE FROM Junior WHERE eid = eid_input;
    DELETE FROM Sessions WHERE bookerId = eid_input;
    DELETE FROM Joins WHERE eid = eid_input;
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
        counter INTEGER:= 1;
        meeting_slot := start_hour;
BEGIN
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
    meeting_slot := start_hour;
BEGIN
    WHILE counter <= num_sessions LOOP
        DELETE FROM Joins 
        WHERE sessionTime = meeting_slot
        AND eid = eid_input
        AND sessionDate = meeting_date
        AND room = room_num
        AND floor = floor_num;
        meeting_slot := meeting_slot + counter*100;
    END LOOP;
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

//stop//
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