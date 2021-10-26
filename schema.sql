DROP TABLE IF EXISTS Employees, Junior, Booker, Senior, Manager, Departments, HealthDeclaration, Sessions, MeetingRoom, Updates, Joins;

CREATE TABLE Employees (
    eid BIGSERIAL PRIMARY KEY,
	did INTEGER NOT NULL,
	resignedDate DATE,
	ename TEXT NOT NULL,
	email TEXT UNIQUE,
	home_contact TEXT,
	mobile_contact TEXT NOT NULL,
	office_contact TEXT NOT NULL,
	FOREIGN KEY (did) REFERENCES Departments(did) ON UPDATE CASCADE
);

CREATE TABLE Junior (
	eid BIGINT PRIMARY KEY,
	FOREIGN KEY (eid) REFERENCES Employees(eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Booker (
	eid BIGINT PRIMARY KEY,
	FOREIGN KEY (eid) REFERENCES Employees(eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Senior (
	eid BIGINT PRIMARY KEY,
	FOREIGN KEY (eid) REFERENCES Booker(eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Manager (
	eid BIGINT PRIMARY KEY,
	FOREIGN KEY (eid) REFERENCES Booker(eid) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Departments (
    did INTEGER PRIMARY KEY,
    dname TEXT NOT NULL
);

CREATE TABLE HealthDeclaration (
    declareDate DATE,
    temp NUMERIC NOT NULL, 
    fever BOOLEAN GENERATED ALWAYS AS (temp > 37.5) STORED, 
    PRIMARY KEY(eid, declareDate),
    FOREIGN KEY (eid) REFERENCES Employees(eid) ON DELETE CASCADE ON UPDATE CASCADE,
    CHECK (temp >= 34.0 AND temp <= 43.0)
);

CREATE TABLE Sessions (
    sessionDate DATE,
    sessionTime INTEGER,
    room INTEGER, 
    floor INTEGER,
    bookerId BIGINT NOT NULL,
    approverId BIGINT,
    PRIMARY KEY (sessionDate, sessionTime, room, floor),
    FOREIGN KEY (room, floor) REFERENCES MeetingRooms(room, floor) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (bookerId) REFERENCES Booker(eid),
    FOREIGN KEY (approverId) REFERENCES Manager(eid),
    CHECK ((sessionDate > CURRENT_DATE) OR ((sessionDate = CURRENT_DATE) AND sessionTime > EXTRACT(HOUR FROM NOW())))
);

CREATE TABLE Joins (
    eid BIGINT,
    sessionDate DATE,
    sessionTime INTEGER,
    room INTEGER, 
    floor INTEGER,
    PRIMARY KEY (eid, sessionDate, sessionTime, room, floor),
    FOREIGN KEY eid REFERENCES Employees(eid),
    FOREIGN KEY (sessionDate, sessionTime, room, floor) REFERENCES Sessions(sessionDate, sessionTime, room, floor) ON DELETE CASCADE ON UPDATE CASCADE,
);

CREATE TABLE MeetingRoom (
    room INTEGER,
    floor INTEGER,
    rname TEXT,
    did INTEGER,
    PRIMARY KEY (floor, room),
    FOREIGN KEY (did) REFERENCES Departments(did) ON UPDATE CASCADE
);

CREATE TABLE Updates (
    eid BIGINT,
    update_date DATE,
    new_cap INTEGER NOT NULL,
    floor INTEGER, 
    room INTEGER,
    PRIMARY KEY (update_date, floor, room),
    FOREIGN KEY eid REFERENCES Manager(eid) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (floor, room) REFERENCES MeetingRoom(floor, room) ON DELETE CASCADE ON UPDATE CASCADE
)

