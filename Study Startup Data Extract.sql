USE [Appian_KCP]
GO

/****** Object:  View [dbo].[StudyAnalytics]    Script Date: 10/29/2025 11:16:17 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create view  [dbo].[StudyAnalytics] as


WITH TaskDates AS ( 
    SELECT
        s.StudyID,
        t.TaskID,
        t.TaskNameId,
        t.Owner AS TaskOwner,
        t.CreatedDate AS TaskStartDate,
        t.CompletedDate AS TaskCompletedDate,
        s.Protocol,
        s.ClinicalSpecialty,
        s.PrincipalInvestigator,
        s.CreatedBy AS StudyCreatedBy,
        s.StatusID,
        s.ClosedDate AS StudyClosedDate,
        s.ModifiedDate AS ModifiedDate,
        rcp.ProjectTitle,
        rcp.CreatedDate AS RCPCreatedDate,
        rcp.SubmittedDate AS RCPSubmittedDate,
        rcp.CreatedBy_User_ID,
        sw.WithdrawalDate
    FROM dbo.KCP_Study s
    LEFT JOIN dbo.KCP_Task t ON s.StudyID = t.StudyID
    LEFT JOIN ResearchCollaborationPortal.dbo.CTP_StudyRequest_Submissions rcp
        ON s.RequestID = rcp.StudyRequest_ID
    LEFT JOIN dbo.KCP_StudyWithdrawal sw ON s.StudyID = sw.StudyID
),
StudyStart AS (
    SELECT
        StudyID,
        MIN(TaskStartDate) AS StudyStartDate
    FROM TaskDates
    GROUP BY StudyID
),
TaskDatesWithStart AS (
    SELECT
        td.*,
        ssd.StudyStartDate
    FROM TaskDates td
    LEFT JOIN StudyStart ssd ON td.StudyID = ssd.StudyID
),
RegulatoryTrigger AS (
    SELECT DISTINCT StudyID
    FROM TaskDatesWithStart td
    INNER JOIN dbo.KCP_RefTaskName tn ON td.TaskNameId = tn.TaskNameId
    WHERE tn.Value = 'Regulatory Task'
)
SELECT
    tdws.ProjectTitle AS [RCP Project Title],
    tdws.RCPCreatedDate AS [RCP Created Date],
    COALESCE(
        (SELECT TOP 1 Name 
         FROM ResearchCollaborationPortal.dbo.Users u
         WHERE u.User_ID = tdws.CreatedBy_User_ID),
        tdws.CreatedBy_User_ID
    ) AS [RCP Created By],
    tdws.RCPSubmittedDate AS [RCP Submitted Date],


    CASE 
        WHEN tdws.RCPSubmittedDate IS NOT NULL AND tdws.RCPCreatedDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.RCPCreatedDate, tdws.RCPSubmittedDate) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.RCPCreatedDate, tdws.RCPSubmittedDate) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.RCPCreatedDate, tdws.RCPSubmittedDate)
                    - (DATEDIFF(WEEK, tdws.RCPCreatedDate, tdws.RCPSubmittedDate) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.RCPCreatedDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, tdws.RCPSubmittedDate) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Days to Complete RCP],


    CASE 
        WHEN tdws.RCPSubmittedDate IS NOT NULL AND tdws.RCPCreatedDate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.RCPCreatedDate, tdws.RCPSubmittedDate) AS VARCHAR(10))
    END AS [Days to Complete RCP - Calendar Days],

    tdws.StudyStartDate AS [Study Start Up Initial Review Create Date],


    CASE 
        WHEN tdws.RCPSubmittedDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.RCPSubmittedDate, ISNULL(tdws.StudyStartDate, GETUTCDATE())) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.RCPSubmittedDate, ISNULL(tdws.StudyStartDate, GETUTCDATE())) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.RCPSubmittedDate, ISNULL(tdws.StudyStartDate, GETUTCDATE()))
                    - (DATEDIFF(WEEK, tdws.RCPSubmittedDate, ISNULL(tdws.StudyStartDate, GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.RCPSubmittedDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL(tdws.StudyStartDate, GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Days from RCP to Study Start],


    CASE 
        WHEN tdws.RCPSubmittedDate IS NOT NULL AND tdws.StudyStartDate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.RCPSubmittedDate, tdws.StudyStartDate) AS VARCHAR(10))
    END AS [Days from RCP to Study Start - Calendar Days],

    tdws.StudyID AS [Study ID],
    tdws.Protocol AS [Study Protocol],
    ref.Value AS [Study Clinical Specialty],
    (SELECT TOP 1 DisplayName 
     FROM dbo.KCP_ExternalUsers eu
     WHERE eu.UserID = tdws.PrincipalInvestigator) AS [Study Principal Investigator],
    (SELECT TOP 1 DisplayName 
     FROM dbo.KCP_ExternalUsers eu
     WHERE eu.NUID = tdws.StudyCreatedBy) AS [Study Created By],
    ss.Value AS [Study Status],

    CASE 
        WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate
        ELSE tdws.StudyClosedDate
    END AS [Study Closed Date],


    CASE 
        WHEN (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END) IS NOT NULL 
             AND tdws.StudyStartDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.StudyStartDate, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END)) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.StudyStartDate, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END)) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.StudyStartDate, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END))
                    - (DATEDIFF(WEEK, tdws.StudyStartDate, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END)) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.StudyStartDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END)) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Study E2E Duration],


    CASE 
        WHEN tdws.StudyStartDate IS NOT NULL AND (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END) IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.StudyStartDate, (CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END)) AS VARCHAR(10))
    END AS [Study E2E Duration - Calendar Days],


    CASE 
        WHEN tdws.StudyStartDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.StudyStartDate, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE())) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.StudyStartDate, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE())) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.StudyStartDate, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE()))
                    - (DATEDIFF(WEEK, tdws.StudyStartDate, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.StudyStartDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Study Days Open],


    CASE 
        WHEN tdws.StudyStartDate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.StudyStartDate, ISNULL((CASE WHEN tdws.StatusID = 3 THEN tdws.WithdrawalDate ELSE tdws.StudyClosedDate END), GETUTCDATE())) AS VARCHAR(10))
    END AS [Study Days Open - Calendar Days],


    SUM(CASE WHEN tdws.TaskCompletedDate IS NOT NULL THEN 1 ELSE 0 END) 
        OVER (PARTITION BY tdws.StudyID) AS [Study Tasks Completed],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CASE 
                WHEN rd.DateSubmted2KPNCIRB IS NOT NULL AND CAST(rd.DateSubmted2KPNCIRB AS DATE) = CAST(rd.RSADate AS DATE)
                THEN CAST(ROUND(DATEDIFF(MINUTE, rd.RSADate, rd.DateSubmted2KPNCIRB) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, rd.RSADate, ISNULL(rd.DateSubmted2KPNCIRB, GETUTCDATE()))
                    - (DATEDIFF(WEEK, rd.RSADate, ISNULL(rd.DateSubmted2KPNCIRB, GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, rd.RSADate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL(rd.DateSubmted2KPNCIRB, GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [RSS assignment to IRBnet submission],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, rd.RSADate, ISNULL(rd.DateSubmted2KPNCIRB, GETUTCDATE())) AS VARCHAR(10))
    END AS [RSS assignment to IRBnet submission - Calendar Days],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CASE 
                WHEN rd.DateSubmted2KPNCIRB IS NULL THEN 'In Progress'
                ELSE 'Completed'
            END
        ELSE NULL
    END AS [RSS assignment to IRBnet submission Status],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.DateSubmted2KPNCIRB IS NOT NULL THEN
            CASE 
                WHEN rd.DateOfFinalApproval IS NOT NULL AND CAST(rd.DateOfFinalApproval AS DATE) = CAST(rd.DateSubmted2KPNCIRB AS DATE)
                THEN CAST(ROUND(DATEDIFF(MINUTE, rd.DateSubmted2KPNCIRB, rd.DateOfFinalApproval) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, rd.DateSubmted2KPNCIRB, ISNULL(rd.DateOfFinalApproval, GETUTCDATE()))
                    - (DATEDIFF(WEEK, rd.DateSubmted2KPNCIRB, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, rd.DateSubmted2KPNCIRB) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [IRBnet submission to IRB approval],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.DateSubmted2KPNCIRB IS NOT NULL THEN
            CAST(DATEDIFF(DAY, rd.DateSubmted2KPNCIRB, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) AS VARCHAR(10))
    END AS [IRBnet submission to IRB approval - Calendar Days],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.DateSubmted2KPNCIRB IS NOT NULL THEN
            CASE 
                WHEN rd.DateOfFinalApproval IS NULL THEN 'In Progress'
                ELSE 'Completed'
            END
        ELSE NULL
    END AS [IRBnet submission to IRB approval Status],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CASE 
                WHEN rd.DateOfFinalApproval IS NOT NULL AND CAST(rd.DateOfFinalApproval AS DATE) = CAST(rd.RSADate AS DATE)
                THEN CAST(ROUND(DATEDIFF(MINUTE, rd.RSADate, rd.DateOfFinalApproval) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, rd.RSADate, ISNULL(rd.DateOfFinalApproval, GETUTCDATE()))
                    - (DATEDIFF(WEEK, rd.RSADate, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, rd.RSADate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [RSS assignment to IRB approval],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, rd.RSADate, ISNULL(rd.DateOfFinalApproval, GETUTCDATE())) AS VARCHAR(10))
    END AS [RSS assignment to IRB approval - Calendar Days],


    CASE 
        WHEN tn.Value = 'Regulatory Task' AND rd.RSADate IS NOT NULL THEN
            CASE 
                WHEN rd.DateOfFinalApproval IS NULL THEN 'In Progress'
                ELSE 'Completed'
            END
        ELSE NULL
    END AS [RSS assignment to IRB approval Status],


    tn.Value AS [Task Name],

    COALESCE(
        (SELECT TOP 1 DisplayName 
         FROM dbo.KCP_ExternalUsers eu
         WHERE eu.NUID = tdws.TaskOwner),
        tdws.TaskOwner
    ) AS [Task Owner],

    tdws.TaskStartDate AS [Task Start Date],
    tdws.TaskCompletedDate AS [Task Completed Date],


    CASE 
        WHEN tdws.TaskCompletedDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.TaskStartDate, tdws.TaskCompletedDate) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.TaskStartDate, tdws.TaskCompletedDate) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.TaskStartDate, tdws.TaskCompletedDate)
                    - (DATEDIFF(WEEK, tdws.TaskStartDate, tdws.TaskCompletedDate) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.TaskStartDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, tdws.TaskCompletedDate) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Days to Complete Task],


    CASE 
        WHEN tdws.TaskCompletedDate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.TaskStartDate, tdws.TaskCompletedDate) AS VARCHAR(10))
    END AS [Days to Complete Task - Calendar Days],


    CASE 
        WHEN tdws.TaskStartDate IS NOT NULL THEN
            CASE 
                WHEN DATEDIFF(DAY, tdws.TaskStartDate, ISNULL(tdws.TaskCompletedDate, GETUTCDATE())) = 0
                THEN CAST(ROUND(DATEDIFF(MINUTE, tdws.TaskStartDate, ISNULL(tdws.TaskCompletedDate, GETUTCDATE())) / 1440.0,4) AS VARCHAR(10))
                ELSE CAST(
                    DATEDIFF(DAY, tdws.TaskStartDate, ISNULL(tdws.TaskCompletedDate, GETUTCDATE()))
                    - (DATEDIFF(WEEK, tdws.TaskStartDate, ISNULL(tdws.TaskCompletedDate, GETUTCDATE())) * 2)
                    - CASE WHEN DATENAME(WEEKDAY, tdws.TaskStartDate) = 'Sunday' THEN 1 ELSE 0 END
                    - CASE WHEN DATENAME(WEEKDAY, ISNULL(tdws.TaskCompletedDate, GETUTCDATE())) = 'Saturday' THEN 1 ELSE 0 END
                AS VARCHAR(10))
            END
    END AS [Task Days Open],


    CASE 
        WHEN tdws.TaskStartDate IS NOT NULL THEN
            CAST(DATEDIFF(DAY, tdws.TaskStartDate, ISNULL(tdws.TaskCompletedDate, GETUTCDATE())) AS VARCHAR(10))
    END AS [Task Days Open - Calendar Days]

FROM TaskDatesWithStart tdws
LEFT JOIN dbo.KCP_RefTaskName tn ON tdws.TaskNameId = tn.TaskNameId
LEFT JOIN Appian_KCP.dbo.KCP_RefData ref ON tdws.ClinicalSpecialty = ref.RefId
LEFT JOIN dbo.KCP_RefStudyStatus ss ON tdws.StatusID = ss.StatusId
LEFT JOIN dbo.KCP_RegulatoryDetails rd ON tdws.StudyID = rd.StudyID
LEFT JOIN RegulatoryTrigger rt ON tdws.StudyID = rt.StudyID;
GO
