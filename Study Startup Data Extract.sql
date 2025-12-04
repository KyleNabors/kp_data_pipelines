USE [Appian_KCP_DEV]
GO

/****** Object:  View [dbo].[StudyAnalytics]    Script Date: 10/29/2025 11:16:17 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

DECLARE @columns nvarchar(max);
DECLARE @sql      nvarchar(max);

SELECT @columns =
    STRING_AGG(CONVERT(nvarchar(max), QUOTENAME([Task Name])), ',')
        WITHIN GROUP (ORDER BY [Task Name])
FROM (SELECT DISTINCT [Task Name] FROM StudyAnalytics) AS d;

SET @sql = N'
SELECT [RCP Project Title], ' + @columns + '
FROM (
    SELECT
        [RCP Project Title],
        [Task Name],
        TRY_CONVERT(int, [Task Days Open]) AS TaskDaysOpen
    FROM StudyAnalytics
) AS src
PIVOT (
    SUM(TaskDaysOpen)
    FOR [Task Name] IN (' + @columns + ')
) AS p
ORDER BY [RCP Project Title];';

EXEC sys.sp_executesql @sql;


SELECT INITCAP([Task Owner]) 