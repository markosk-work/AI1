# Flow profile: Surveys

The Surveys app reads and writes SQL directly through the SQL connector; flows mostly build and send reports. Its
flows were written in a different style from Telework and Gaslog - match the Surveys flows themselves.

## Style
- No Try/Catch scopes; action names often carry a " - " descriptor.
- The report flow (`SurveysCreateAndSendReportsV2`) generates PDFs from SharePoint images (OneDrive `CopyFile` of
  thumbnails), reuses the existing report `Document` rows (Update row) and e-mails them. In PROD the report mails come
  from the customer's no-reply mailbox (`environments.prod.notes`).

## Test routing
- Routing is app-side: in the InTTrust tenant (`IsInTTrust`, "inttrust" in the UPN) the app sends To = the current
  user's mailbox and an empty CC, with a "!!!TEST!!!" subject. Test only as the accounts in the local allowlist; the dev
  data holds real station addresses.

## Failure patterns seen
- A 401 from a SharePoint thumbnail URL was really a revoked OneDrive connection (AADSTS50173 after a password change):
  check the connection's status before blaming the URL.
- Importing Surveys re-activates its flows; a connection with an expired sign-in leaves them Draft. Check Connections
  first and flow states after every import.
- `0x80048306 ... ReadAccess ... Process` on the report button = the user lacks Process read on a flow owned by
  someone else. Users get roles only through Entra group teams; only App Opener (through one of them) grants it.
  Fixes need a Production admin: add App Opener to the team, add Process read to the custom roles, or add the users to
  the group. A replaced flow (V2) does not inherit the old flow's sharing.
- Outlook rejects the whole report mail, and the run fails, when one recipient is malformed - for example a
  `Station.Email` holding two addresses separated by a space instead of `;`.

## Re-running the report flow without the app
- Start `SurveysCreateAndSendReportsV2` through the app's gateway URL (SKILL.md). Its flow id differs per environment:
  read it from the environment (or the project's memory), never from a skill.
- Don't press Email to recover a lost report: the button also re-sends every department "Comments for Station" mail
  from the presser's mailbox. Start V2 directly with the button's inputs instead.
- Inputs: `text` = survey ID (lower case); `text_1` = `[{Language, LanguageID, NewDocumentID}]` (Fuel Unloading: no
  `LanguageID`) for the survey's language + English (English once when the survey is English; the app really uses the
  presser's UI language, so Cyprus Mystery surveys, sent from a Greek app, get Greek + English); `text_2` =
  `{Body, CCList, Subject, ToList}` built with the button's formulas. No `text_2` (the app's call for a Mystery survey
  in External review) = PDFs only, no mail.
- The guard in `RequestSurveyReportMail` cancels a second mail request for a survey within 3 minutes: a Cancelled run
  is a refused duplicate. A sent report has a report `Document` row whose Description starts `EMAIL_SENT|` - check it
  before any resend.
- One run makes about 6 OneDrive calls (create, convert, delete per language) on the flow's one OneDrive connection.
- The project already has a resend harness for this flow (dry run by default, inputs proven against real app runs):
  reuse it rather than writing another - where it lives is in the project's memory.
