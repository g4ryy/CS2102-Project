---------------------------------- Application Functionalities ------------------------------





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
