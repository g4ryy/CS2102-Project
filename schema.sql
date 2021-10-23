CREATE TABLE Employees(
TEXT ename
TEXT email UNIQUE NOT NULL
TEXT home_contact DEFAULT NULL
TEXT mobile_contact DEFAULT NULL
TEXT office_contact DEFAULT NULL
DATE resignDate
INT eid PRIMARY KEY
INT department_id NOT NULL
FOREIGN KEY department_id REFERENCES Departments(did)
);

CREATE TABLE Departments(
INT did PRIMARY KEY
TEXT dname
);

CREATE TABLE HealthDeclaration(
DATE declareDate
TEXT temp
INT fever
PRIMARY KEY(eid, declareDate)
FOREIGN KEY (eid) REFERENCES Employees(eid) ON DELETE CASCADE ON UPDATE CASCADE
);





CREATE TABLE MEETING_ROOM(
INT room
INT floor
TEXT rname
INT did
PRIMARY KEY (floor, room)
FOREIGN KEY (did) REFERENCES DEPARTMENTS (did)
	)
