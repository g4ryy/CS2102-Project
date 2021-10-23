DROP TABLE IF EXISTS Employees, Departments, HealthDeclaration, Sessions

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
    sessionTime INT,
    room INTEGER, 
    floor INTEGER,
    bookerId BIGINT,
    PRIMARY KEY (sessionDate, sessionTime, room, floor),
    FOREIGN KEY (room, floor) REFERENCES MeetingRooms(room, floor) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (bookerId) REFERENCES Booker(eid);
    CHECK ((sessionDate >= CURRENT_DATE) OR (sessionTime >= CURRENT_TIME))
)


