# App profile: Telework (`itt_remoteworkdays_96b83`)

Source: `canvasapps/itt_remoteworkdays_96b83/..._DocumentUri/Src/` in the solution repo (`App.pa.yaml`, `Home`,
`Calendar`, `Overview`, `Employees`, `Components/MenuComponent_{Horizontal,Vertical}`). Ship changes with pp-release
(`references/dataverse-git.md`). The project document `Architecture.md` (config `project.docs`) has the typed
Formulas -> flow -> SQL contracts, the permission table, the flow inventory and feature recipes (field, filter,
mutation, calendar/overview view, export): fill in its feature contract before a change that touches data, flows or
permissions.

## Formulas and errors
- Section banner comments inside Formulas are the owner's (`// THEME / COLORS`, `// DATA TYPES`, `// FLOW FUNCTIONS`);
  no other explanatory comments.
- `App.OnError`: `Trace` only when `IsProductionEnvironment`, plus `Notify`.
- Screens call UDFs bare (the central rule); no screen-level `IfError` / `Notify`.
- Role predicates: `HasRole(Roles, RoleID)`, `IsSameEmail`, `IsDepartmentManager(Profile)`, `IsTeamLeader(Profile)`,
  `CanEditEmployee(...)`; the flags are `Set` at the end of `App.OnStart` (`Set(IsViewer, HasRole(MyRoles, RoleViewerID))`).
- UDFs return exact contract types (`EmployeesDataType`); presentation sorts that need globals (department name via
  `Departments`) happen on the screen, not in the UDF.

## State and names
- `Set` only in `App.OnStart`; screens use `UpdateContext` / `With`.
- The owner's names: `selectedDate`, `selectedItem`, `selectedDepartment`, `varBusy`, `WorkDaysCached`, `DaysData`,
  `DatesRange`. The `loc*` / `col*` prefixes exist only on the Employees screen (built later) - keep them there.
- `DeptEmployees` (Calendar roster, from `GetEmployeesWithCriteria("", own department, true)`) is a variable table;
  Employees results are the collection `colEmployees` (Clear + Collect on search, `UpdateIf` on save). Don't conflate them.
- Calendar cache entries `{Key, Days}`, key = employee GUID text + `yyyymm`, loaded for the whole visible grid;
  `InsertCacheDay` / `RemoveCacheDay` are pure and return new tables.
- There is no role switcher: client-side impersonation was removed because the procs authorise the real caller. Test
  roles by running procs with another `@User`, or with a real account of that role.

## Search and interaction
- Employees: only the Search button searches; the department dropdown, the Active-only toggle, Clear and the team
  dropdown only change inputs; the button is disabled while `locSearching` or `locBusy`; `OnVisible` is a no-op so the
  page keeps its state.
- Overview (`btnRefresh`) and Calendar (hidden `CalendarActionsBtn`): filters do `UpdateContext(...); Select(<button>)`.
- Team filters narrow rows the server already returned; they are never search inputs.
- Role chips write immediately through Insert/RemoveEmployeeRole and adopt the returned row; no `GetRoles` re-read.
  Settings (days per week, on-customer) are drafted with Save / Cancel; Save sends the selected row's `UpdatedAt` and
  adopts the returned employee (and refreshes `MyEmployeeProfile` on a self-save).

## Layout and licensing
- Mobile parity is a rule: the vertical menu becomes `MenuComponent_Horizontal` on Small/Medium; Home cards sit in a
  wrapping AutoLayout container; keep desktop unchanged when fixing phone and vice versa.
- Employees layout decisions (keep them): on Small/Medium only, the search/filter top bar hides while an employee is
  open and list rows are 84 px (desktop: single-line top bar, 64 px rows). The fields row is `EmployeesFieldsFlexRow`
  (horizontal AutoLayout; days group FillPortions 3 / min 170, customer group FillPortions 2 / min 120; Height and
  LayoutMinHeight 84 on the row and both groups). Detail header identity block 96 px phone / 48 px desktop with
  AutoHeight labels inside. Role chips live in `EmployeesRolesGrid` (WrapCount from the width / 140, height = rows x
  56). The department picker is a ModernCombobox, width 170 (200 broke the phone top bar).
- End users are on standard licences: no premium connector in the app (no direct SQL, custom connector or Dataverse);
  data goes through flows.
- Feature switches reach the app through `TeleworkAppEnvironment` (e.g. `leavesenabled`); the app hides the feature
  when off. A helper that returns Blank (an `If` without else) becomes JSON `null` in the flow payload - give it an
  explicit empty value.
