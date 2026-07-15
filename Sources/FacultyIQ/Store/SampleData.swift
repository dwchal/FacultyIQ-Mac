import Foundation

/// The sample roster from the original FacultyIQ Shiny app (fictional faculty;
/// the external IDs are placeholders, so use manual name search to resolve).
let sampleRosterCSV = #"""
Id,Name,Email,What is your current academic rank?,What was the date/ year of your last academic promotion?,Initial hire date,Assistant Professor start date,Associate Professor start date,Full Professor start date,How many peer-reviewed publications do you have in REAIMS?,What is your Scopus ID?,What is your Google Scholar username?,ORCID ID,Semantic Scholar ID,Specialty associations,Division
1,Sarah Chen,schen@university.edu,Associate Professor,2021,2014-08-15,2015-07-01,2021-07-01,,45,7004567890123,ABCD1234efgh,0000-0002-1825-0097,,IDSA member; Editorial board - Journal of Infectious Diseases,Infectious Diseases
2,Michael Rodriguez,mrodriguez@university.edu,Full Professor,2018,2005-09-01,2005-09-01,2011-07-01,2018-07-01,127,7003456789012,XYZ789ghijkl,0000-0003-4567-8901,1234567890,ACOEM past president; JOEM editor-in-chief,Occupational Medicine
3,Emily Thompson,ethompson@university.edu,Assistant Professor,2023,2023-07-01,2023-07-01,,,12,7002345678901,,,,SHEA early career; Institutional safety committee,Infectious Diseases
4,David Kim,dkim@university.edu,Associate Professor,2020,2014-01-15,2014-07-01,2020-07-01,,67,7001234567890,MNOP5678qrst,0000-0001-2345-6789,,ACP fellow; Regional medical director,Occupational Medicine
5,Jennifer Martinez,jmartinez@university.edu,Full Professor,2015,2002-08-20,2003-07-01,2009-07-01,2015-07-01,189,7009876543210,UVWX9012yzab,0000-0004-5678-9012,2345678901,IDSA board member; NIH study section,Infectious Diseases
6,Robert Wilson,rwilson@university.edu,Assistant Professor,2022,2022-09-01,2022-09-01,,,8,,,,,Early career researcher,Pulmonary & Critical Care
7,Lisa Anderson,landerson@university.edu,Associate Professor,2019,2012,2013,2019,,52,7008765432109,CDEF3456ghij,,,ACOEM member; State occupational health advisor,Occupational Medicine
8,James Taylor,jtaylor@university.edu,Full Professor,2012,1999-07-01,2000-07-01,2006-07-01,2012-07-01,245,7007654321098,IJKL7890mnop,0000-0005-6789-0123,3456789012,ACCP fellow; Former division chief,Pulmonary & Critical Care
9,Amanda White,awhite@university.edu,Instructor,2024,2024-01-10,,,,3,,,,,New faculty member,Infectious Diseases
10,Christopher Brown,cbrown@university.edu,Assistant Professor,2021,2021-08-15,2021-08-15,,,18,7006543210987,QRST1234uvwx,,,SHEA member; Hospital infection control committee,Infectious Diseases
11,Michelle Davis,mdavis@university.edu,Associate Professor,2018,2011-09-01,2012-07-01,2018-07-01,,78,7005432109876,,0000-0006-7890-1234,,IDSA fellow; Clinical trials unit director,Infectious Diseases
12,Daniel Garcia,dgarcia@university.edu,Full Professor,2010,1997-07-15,1998-07-01,2004-07-01,2010-07-01,312,7004321098765,YZAB5678cdef,0000-0007-8901-2345,4567890123,ACOEM president-elect; WHO consultant,Occupational Medicine
13,Stephanie Lee,slee@university.edu,Assistant Professor,2023,2023-07-01,2023-07-01,,,6,7003210987654,GHIJ9012klmn,,,Early career; Quality improvement committee,Pulmonary & Critical Care
14,Kevin Johnson,kjohnson@university.edu,Associate Professor,2017,2010-08-01,2011-07-01,2017-07-01,,89,7002109876543,OPQR3456stuv,,,ATS member; Pulmonary fellowship director,Pulmonary & Critical Care
15,Rachel Moore,rmoore@university.edu,Research Faculty,,2016-09-15,,,,34,7001098765432,,0000-0008-9012-3456,,Research track; Core lab director,Infectious Diseases
"""#
