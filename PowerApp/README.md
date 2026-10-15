# Employee Comment Editor (Canvas app)

`EmployeeCommentEditor_Solution.zip` – import at make.powerapps.com → Solutions → Import solution.

- Dropdown (combo box) with delegable type-ahead: `Filter(Employees, StartsWith('Full Name', cmbEmployee.SearchText))` – works on 200k items because `Full Name` is indexed.
- Textbox `comment`; button `Update comment` runs `Patch(Employees, LookUp(Employees, ID = cmbEmployee.Selected.ID), {comment: comment.Text})`.

## Setup
1. Run `Create-EmployeesList.ps1 -SiteUrl <site>` to create the `Employees` list (`Full Name` indexed + unique, `comment`) with 200,000 items, or use your own list with those columns.
2. Import the zip, open the app, remove the `Employees` data source and re-add it from your SharePoint site/list (the package contains a placeholder site URL), then save/publish.
3. To rebuild with your site URL baked in: `./build.ps1 -SiteUrl https://tenant.sharepoint.com/sites/X` (requires `pac` CLI).
