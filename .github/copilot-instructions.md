# Copilot instructions

## Power Apps canvas solution packaging (see `PowerApp/`)
- Build with `PowerApp/build.ps1 -SiteUrl <site>`; it packs `PowerApp/src` with `pac canvas pack` and assembles `EmployeeCommentEditor_Solution.zip`.
- Solution zip layout (verified against a real export): `[Content_Types].xml`, `solution.xml`, `customizations.xml`, `CanvasApps/<name>_DocumentUri.msapp`.
- The canvas app metadata (`<CanvasApp>`: Name, DocumentUri, ConnectionReferences, ...) goes INSIDE `customizations.xml` under `<CanvasApps>`. There is no `.meta.xml` in exports. `solution.xml` needs `<RootComponent type="300" schemaName="<app Name>" behavior="0" />`. Otherwise import fails with "Cannot add a Root Component ... of type 300 because it is not in the target system".
- Unpacked msapp sources need `DataSources\<ds>.json` plus `pkgs\TableDefinitions\<ds>.json` containing `EntityName`, `TableName`, `DataEntityMetadataJson`; `Connections\Connections.json`; `ControlTemplates.json` and `pkgs\<control>_<ver>.xml` for each control used (copy from a sample unpacked app).
- SharePoint internal names encode spaces: `Full Name` -> `Full_x0020_Name`.
- When unsure about a format, compare against a real exported solution zip (ask the user to export one) instead of guessing.
