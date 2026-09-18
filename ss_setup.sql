DROP DATABASE IF EXISTS dbmaster_handoff_setup;
GO
CREATE DATABASE dbmaster_handoff_setup;
GO
USE dbmaster_handoff_setup;
GO

CREATE TABLE t_types (
  id            INT IDENTITY(1,1) PRIMARY KEY,
  c_datetime2   DATETIME2(7),
  c_date        DATE,
  c_time        TIME(7),
  c_dtoffset    DATETIMEOFFSET(7),
  c_money       MONEY,
  c_smallmoney  SMALLMONEY,
  c_varchar_max VARCHAR(MAX),
  c_nvarcharmx  NVARCHAR(MAX),
  c_varchar_reg VARCHAR(100)
);
INSERT INTO t_types (c_datetime2, c_date, c_time, c_dtoffset, c_money, c_smallmoney, c_varchar_max, c_nvarcharmx, c_varchar_reg)
VALUES
  ('2026-07-15 13:45:30.1234567', '2026-07-15', '13:45:30.1234567',
   '2026-07-15 13:45:30.1234567 +08:00',
   1234.5678, 1234.56,
   REPLICATE('A', 8000),
   REPLICATE(N'文', 8000),
   'short value');
GO

CREATE PROCEDURE p_echo @x INT AS BEGIN SELECT @x AS v; END;
GO

CREATE PROCEDURE p_needparam @x INT AS BEGIN SELECT @x AS v; END;
GO

CREATE PROCEDURE p_multi AS BEGIN SELECT 1 AS a; SELECT 2 AS b; END;
GO
