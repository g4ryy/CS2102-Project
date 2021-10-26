DROP PROCEDURE IF EXISTS add_department(INTEGER, TEXT), remove_department(INTEGER), declare_health(BIGINT, DATE, NUMERIC), contact_tracing(BIGINT), non_compliance(DATE, DATE);
---------------------------------- Application Functionalities ------------------------------

CREATE OR REPLACE PROCEDURE add_department(id INTEGER, name TEXT) AS $$
	INSERT INTO Departments (did, dname) VALUES(id, name);
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_department(id INTEGER) AS $$
	DELETE FROM Departments WHERE did = id;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE declare_health(id BIGINT, curr_date DATE, curr_temp NUMERIC) AS $$
	IF EXISTS (SELECT 1 FROM HealthDeclarations WHERE eid = id AND declareDate = curr_date)
	BEGIN
		UPDATE HealthDeclarations SET temp = curr_temp WHERE eid = id AND declareDate = curr_date;
	END
	ELSE
	BEGIN
		INSERT INTO HealthDeclarations (eid, declareDate, temp) VALUES(id, curr_date, curr_temp);
	END
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
RETURNS TABLE(id BIGINT, days INTEGER) AS $$
	DECLARE
		totalDays INTEGER := end_date - start_date + 1;
	BEGIN
		SELECT eid, totalDays - COUNT(*) AS number_of_days
		FROM HealthDeclarations
		WHERE declareDate >= start_date AND declareDate <= end_date
		GROUP BY eid
		HAVING COUNT(*) < totalDays;
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