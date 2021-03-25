{
  Copyright 2021-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Parsing of CastleEngineManifest.xml files (shared by CGE build tool and CGE editor).
  The central class in @link(TCastleManifest). }
unit ToolManifest;

{$I castleconf.inc}

interface

uses DOM, Classes, Generics.Collections,
  CastleStringUtils, CastleImages, CastleUtils,
  ToolServices, ToolAssocDocTypes;

type
  TDependency = (depFreetype, depZlib, depPng, depSound, depOggVorbis, depHttps);
  TDependencies = set of TDependency;

  TScreenOrientation = (soAny, soLandscape, soPortrait);

  TAndroidProjectType = (apBase, apIntegrated);

  TLocalizedAppName = record
    Language: String;
    AppName: String;
    constructor Create(const ALanguage, AAppName: String);
  end;
  TListLocalizedAppName = specialize TList<TLocalizedAppName>;

  TProjectVersion = class(TComponent)
  public
    DisplayValue: String;
    Code: Cardinal;
  end;

  TImageFileNames = class(TCastleStringList)
  private
    FBaseUrl: string;
  public
    property BaseUrl: string read FBaseUrl write FBaseUrl;
    { Find image with given extension, or '' if not found. }
    function FindExtension(const Extensions: array of string): string;
    { Find and read an image format that we can process with our CastleImages.
      Try to read it to a class that supports nice-quality resizing (TResizeInterpolationFpImage).
      @nil if not found. }
    function FindReadable: TCastleImage;
  end;

  { Parsing of CastleEngineManifest.xml files. }
  TCastleManifest = class
  strict private
    const
      { Google Play requires version code to be >= 1 }
      DefautVersionCode = 1;
      { iOS requires version display to be <> '' }
      DefautVersionDisplayValue = '0.1';
      DefaultAndroidCompileSdkVersion = 29;
      DefaultAndroidTargetSdkVersion = DefaultAndroidCompileSdkVersion;
      { See https://github.com/castle-engine/castle-engine/wiki/Android-FAQ#what-android-devices-are-supported
        for reasons behind this minimal version. }
      ReallyMinSdkVersion = 16;
      DefaultAndroidMinSdkVersion = ReallyMinSdkVersion;
      DefaultUsesNonExemptEncryption = true;
      DefaultDataExists = true;
      DefaultFullscreenImmersive = true;

      { character sets }
      ControlChars = [#0 .. Chr(Ord(' ') - 1)];
      AlphaNum = ['a'..'z', 'A'..'Z', '0'..'9'];

      { qualified_name is also a Java package name for Android, so it
        cannot contain dash character.

        As for underscore:
        On Android, using _ is allowed,
        but on iOS it is not (it fails at signing),
        possibly because _ inside URLs is (in general) not allowed:
        http://stackoverflow.com/questions/2180465/can-domain-name-subdomains-have-an-underscore-in-it }
      QualifiedNameAllowedChars = AlphaNum + ['.'];

    var
      OwnerComponent: TComponent;
      FDependencies: TDependencies;
      FName, FExecutableName, FQualifiedName, FAuthor, FCaption: string;
      FIOSOverrideQualifiedName: string;
      FIOSOverrideVersion: TProjectVersion; //< nil if not overridden, should use FVersion then
      FUsesNonExemptEncryption: boolean;
      FDataExists: Boolean;
      FPath, FPathUrl, FDataPath: string;
      FIncludePaths, FExcludePaths: TCastleStringList;
      FExtraCompilerOptions, FExtraCompilerOptionsAbsolute: TCastleStringList;
      FIcons, FLaunchImages: TImageFileNames;
      FSearchPaths, FLibraryPaths: TStringList;
      FIncludePathsRecursive: TBooleanList;
      FStandaloneSource, FAndroidSource, FIOSSource, FPluginSource: string;
      FLazarusProject: String;
      FBuildUsingLazbuild: Boolean;
      FGameUnits, FEditorUnits: string;
      FVersion: TProjectVersion;
      FFullscreenImmersive: boolean;
      FScreenOrientation: TScreenOrientation;
      FAndroidCompileSdkVersion, FAndroidMinSdkVersion, FAndroidTargetSdkVersion: Cardinal;
      FAndroidProjectType: TAndroidProjectType;
      FAndroidServices, FIOSServices: TServiceList;
      FAssociateDocumentTypes: TAssociatedDocTypeList;
      FListLocalizedAppName: TListLocalizedAppName;
      FIOSTeam: string;

    function DefaultQualifiedName(const AName: String): String;
    procedure CheckMatches(const Name, Value: string; const AllowedChars: TSetOfChars);
    procedure CheckValidQualifiedName(const OptionName: string; const QualifiedName: string);
    { Change compiler option @xxx to use absolute paths.
      Important for "castle-engine editor" where ExtraCompilerOptionsAbsolute is inserted
      into lpk, but lpk is in a different directory.
      Testcase: unholy_society. }
    function MakeAbsoluteCompilerOption(const Option: String): String;
    { Create and read version from given DOM element.
      Returns @nil if Element is @nil. }
    function ReadVersion(const Element: TDOMElement): TProjectVersion;
    procedure CreateFinish;
  public
    const
      DataName = 'data';

    { Load defaults.
      @param APath Project path, must be absolute. }
    constructor Create(const APath: String);
    { Load manifest file.
      @param APath Project path, must be absolute.
      @param ManifestUrl Full URL to CastleEngineManifest.xml, must be absolute. }
    constructor CreateFromUrl(const APath, ManifestUrl: String);
    { Load manifest file.
      @param ManifestUrl Full URL to CastleEngineManifest.xml, must be absolute. }
    constructor CreateFromUrl(const ManifestUrl: String);
    { Guess values for the manifest, using AName as the project name.
      @param APath Project path, must be absolute.
      @param AName Guessed project name. }
    constructor CreateGuess(const APath, AName: String);

    destructor Destroy; override;

    { Detailed information about the project, read-only and useful for
      various project operations. }
    { }

    property Version: TProjectVersion read FVersion;
    property LazarusProject: String read FLazarusProject;
    property BuildUsingLazbuild: Boolean read FBuildUsingLazbuild;
    property GameUnits: String read FGameUnits;
    property EditorUnits: String read FEditorUnits;
    property QualifiedName: string read FQualifiedName;
    property Dependencies: TDependencies read FDependencies;
    property Name: string read FName;
    { Project path. Absolute.
      Always ends with path delimiter, like a slash or backslash. }
    property Path: String read FPath;
    { Same thing as @link(Path), but expressed as an URL. }
    property PathUrl: String read FPathUrl;
    property DataExists: Boolean read FDataExists;
    { Project data path. Absolute.
      Always ends with path delimiter, like a slash or backslash.
      Should be ignored if not @link(DataExists). }
    property DataPath: string read FDataPath;
    property Caption: string read FCaption;
    property Author: string read FAuthor;
    property ExecutableName: string read FExecutableName;
    property FullscreenImmersive: boolean read FFullscreenImmersive;
    property ScreenOrientation: TScreenOrientation read FScreenOrientation;
    property Icons: TImageFileNames read FIcons;
    property LaunchImages: TImageFileNames read FLaunchImages;
    property SearchPaths: TStringList read FSearchPaths;
    property LibraryPaths: TStringList read FLibraryPaths;
    property AssociateDocumentTypes: TAssociatedDocTypeList read FAssociateDocumentTypes;
    property ListLocalizedAppName: TListLocalizedAppName read FListLocalizedAppName;
    property IncludePaths: TCastleStringList read FIncludePaths;
    property IncludePathsRecursive: TBooleanList read FIncludePathsRecursive;
    property ExcludePaths: TCastleStringList read FExcludePaths;
    property ExtraCompilerOptions: TCastleStringList read FExtraCompilerOptions;
    property ExtraCompilerOptionsAbsolute: TCastleStringList read FExtraCompilerOptionsAbsolute;

    { iOS-specific things }
    property IOSOverrideQualifiedName: string read FIOSOverrideQualifiedName;
    property IOSOverrideVersion: TProjectVersion read FIOSOverrideVersion; //< nil if not overridden, should use FVersion then
    property UsesNonExemptEncryption: boolean read FUsesNonExemptEncryption;
    property IOSServices: TServiceList read FIOSServices;
    property IOSTeam: String read FIOSTeam;

    { Android-specific things }
    property AndroidCompileSdkVersion: Cardinal read FAndroidCompileSdkVersion;
    property AndroidMinSdkVersion: Cardinal read FAndroidMinSdkVersion;
    property AndroidTargetSdkVersion: Cardinal read FAndroidTargetSdkVersion;
    property AndroidProjectType: TAndroidProjectType read FAndroidProjectType;
    property AndroidServices: TServiceList read FAndroidServices;

    { Standalone source specified in CastleEngineManifest.xml.
      Most build tool code should use TCastleProject.StandaloneSourceFile instead,
      that can optionally auto-create the source file. }
    property StandaloneSource: string read FStandaloneSource;

    { Android source specified in CastleEngineManifest.xml.
      Most build tool code should use TCastleProject.AndroidSourceFile instead,
      that can optionally auto-create Android source file. }
    property AndroidSource: string read FAndroidSource;

    { iOS source specified in CastleEngineManifest.xml.
      Most build tool code should use TCastleProject.IOSSourceFile instead,
      that can optionally auto-create iOS source file. }
    property IOSSource: string read FIOSSource;

    { Plugin source specified in CastleEngineManifest.xml.
      Most build tool code should use TCastleProject.PluginSourceFile instead,
      that can optionally auto-create the source file. }
    property PluginSource: string read FPluginSource;

    { Find a file with given BaseName (contains filename, with extension, but without any path)
      among SearchPaths of this project.
      Returns absolute filename, or '' if not found. }
    // unused: function SearchFile(const BaseName: String): String;

    { Find a unit with given name among SearchPaths of this project.
      Returns absolute filename, or '' if not found. }
    function SearchPascalUnit(const AUnitName: String): String;
  end;

function DependencyToString(const D: TDependency): string;
function StringToDependency(const S: string): TDependency;

function ScreenOrientationToString(const O: TScreenOrientation): string;
function StringToScreenOrientation(const S: string): TScreenOrientation;

implementation

uses SysUtils,
  CastleXMLUtils, CastleFilesUtils, CastleFindFiles, CastleLog,
  CastleURIUtils,
  ToolCommonUtils;

{ TImageFileNames ------------------------------------------------------------- }

function TImageFileNames.FindExtension(const Extensions: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do
    if AnsiSameText(ExtractFileExt(Strings[I]), '.ico') then
      Exit(Strings[I]);
end;

function TImageFileNames.FindReadable: TCastleImage;
var
  I: Integer;
  MimeType, URL: string;
begin
  for I := 0 to Count - 1 do
  begin
    URL := CombineURI(BaseUrl, Strings[I]);
    MimeType := URIMimeType(URL);
    if (MimeType <> '') and IsImageMimeType(MimeType, true, false) then
      Exit(LoadImage(URL, [TRGBImage, TRGBAlphaImage]));
  end;
  Result := nil;
end;

{ TLocalizedAppName ---------------------------------------------------------- }

constructor TLocalizedAppName.Create(const ALanguage, AAppName: String);
begin
  Language := ALanguage;
  AppName := AAppName;
end;

{ TCastleManifest ------------------------------------------------------------ }

constructor TCastleManifest.Create(const APath: String);
begin
  inherited Create;
  OwnerComponent := TComponent.Create(nil);
  FIncludePaths := TCastleStringList.Create;
  FIncludePathsRecursive := TBooleanList.Create;
  FExcludePaths := TCastleStringList.Create;
  FExtraCompilerOptions := TCastleStringList.Create;
  FExtraCompilerOptionsAbsolute := TCastleStringList.Create;
  FIcons := TImageFileNames.Create;
  FLaunchImages := TImageFileNames.Create;
  FSearchPaths := TStringList.Create;
  FLibraryPaths := TStringList.Create;
  FAndroidProjectType := apIntegrated;
  FAndroidServices := TServiceList.Create(true);
  FIOSServices := TServiceList.Create(true);
  FAssociateDocumentTypes := TAssociatedDocTypeList.Create;

  { set defaults (only on fields that are not already in good default state after construction) }
  FDataExists := DefaultDataExists;
  FAndroidCompileSdkVersion := DefaultAndroidCompileSdkVersion;
  FAndroidMinSdkVersion := DefaultAndroidMinSdkVersion;
  FAndroidTargetSdkVersion := DefaultAndroidTargetSdkVersion;
  FUsesNonExemptEncryption := DefaultUsesNonExemptEncryption;
  FFullscreenImmersive := DefaultFullscreenImmersive;

  FPath := InclPathDelim(APath);
  FPathUrl := FilenameToURISafe(FPath);
  FDataPath := InclPathDelim(FPath + DataName);
end;

constructor TCastleManifest.CreateGuess(const APath, AName: String);
begin
  Create(APath);

  FDataPath := InclPathDelim(Path + DataName);
  FName := AName;
  FCaption := FName;
  FQualifiedName := DefaultQualifiedName(FName);
  FExecutableName := FName;
  FStandaloneSource := FName + '.lpr';
  FLazarusProject := FName + '.lpi';
  FVersion := TProjectVersion.Create(OwnerComponent);
  FVersion.Code := DefautVersionCode;
  FVersion.DisplayValue := DefautVersionDisplayValue;
  Icons.BaseUrl := FilenameToURISafe(InclPathDelim(GetCurrentDir));
  LaunchImages.BaseUrl := FilenameToURISafe(InclPathDelim(GetCurrentDir));

  CreateFinish;
end;

constructor TCastleManifest.CreateFromUrl(const APath, ManifestUrl: String);
var
  Doc: TXMLDocument;
  AndroidProjectTypeStr: string;
  ChildElements: TXMLElementIterator;
  Element, ChildElement: TDOMElement;
  NewCompilerOption, DefaultLazarusProject: String;
begin
  Create(APath);

  Icons.BaseUrl := ManifestUrl;
  LaunchImages.BaseUrl := ManifestUrl;

  Doc := URLReadXML(ManifestURL);
  try
    Check(Doc.DocumentElement.TagName = 'project',
      'Root node of CastleEngineManifest.xml must be <project>');
    FName := Doc.DocumentElement.AttributeString('name');
    FCaption := Doc.DocumentElement.AttributeStringDef('caption', FName);
    FQualifiedName := Doc.DocumentElement.AttributeStringDef('qualified_name', DefaultQualifiedName(FName));
    FExecutableName := Doc.DocumentElement.AttributeStringDef('executable_name', FName);
    FStandaloneSource := Doc.DocumentElement.AttributeStringDef('standalone_source', '');
    if FStandaloneSource <> '' then
      DefaultLazarusProject := ChangeFileExt(FStandaloneSource, '.lpi')
    else
      DefaultLazarusProject := '';
    FLazarusProject := Doc.DocumentElement.AttributeStringDef('lazarus_project', DefaultLazarusProject);
    FAndroidSource := Doc.DocumentElement.AttributeStringDef('android_source', '');
    FIOSSource := Doc.DocumentElement.AttributeStringDef('ios_source', '');
    FPluginSource := Doc.DocumentElement.AttributeStringDef('plugin_source', '');
    FAuthor := Doc.DocumentElement.AttributeStringDef('author', '');
    FGameUnits := Doc.DocumentElement.AttributeStringDef('game_units', '');
    FEditorUnits := Doc.DocumentElement.AttributeStringDef('editor_units', '');
    FScreenOrientation := StringToScreenOrientation(
      Doc.DocumentElement.AttributeStringDef('screen_orientation', 'any'));
    FFullscreenImmersive := Doc.DocumentElement.AttributeBooleanDef('fullscreen_immersive', true);
    FBuildUsingLazbuild := Doc.DocumentElement.AttributeBooleanDef('build_using_lazbuild', false);

    FVersion := ReadVersion(Doc.DocumentElement.ChildElement('version', false));
    // create default FVersion value, if necessary
    if FVersion = nil then
    begin
      FVersion := TProjectVersion.Create(OwnerComponent);
      FVersion.Code := DefautVersionCode;
      FVersion.DisplayValue := DefautVersionDisplayValue;
    end;

    Element := Doc.DocumentElement.ChildElement('dependencies', false);
    if Element <> nil then
    begin
      ChildElements := Element.ChildrenIterator('dependency');
      try
        while ChildElements.GetNext do
        begin
          ChildElement := ChildElements.Current;
          Include(FDependencies,
            StringToDependency(ChildElement.AttributeString('name')));
        end;
      finally FreeAndNil(ChildElements) end;
    end;

    Element := Doc.DocumentElement.ChildElement('package', false);
    if Element <> nil then
    begin
      ChildElements := Element.ChildrenIterator('include');
      try
        while ChildElements.GetNext do
        begin
          ChildElement := ChildElements.Current;
          FIncludePaths.Add(ChildElement.AttributeString('path'));
          FIncludePathsRecursive.Add(ChildElement.AttributeBooleanDef('recursive', false));
        end;
      finally FreeAndNil(ChildElements) end;

      ChildElements := Element.ChildrenIterator('exclude');
      try
        while ChildElements.GetNext do
        begin
          ChildElement := ChildElements.Current;
          FExcludePaths.Add(ChildElement.AttributeString('path'));
        end;
      finally FreeAndNil(ChildElements) end;
    end;

    Element := Doc.DocumentElement.ChildElement('icons', false);
    if Element <> nil then
    begin
      ChildElements := Element.ChildrenIterator('icon');
      try
        while ChildElements.GetNext do
        begin
          ChildElement := ChildElements.Current;
          Icons.Add(ChildElement.AttributeString('path'));
        end;
      finally FreeAndNil(ChildElements) end;
    end;

    Element := Doc.DocumentElement.ChildElement('launch_images', false);
    if Element <> nil then
    begin
      ChildElements := Element.ChildrenIterator('image');
      try
        while ChildElements.GetNext do
        begin
          ChildElement := ChildElements.Current;
          LaunchImages.Add(ChildElement.AttributeString('path'));
        end;
      finally FreeAndNil(ChildElements) end;
    end;

    Element := Doc.DocumentElement.ChildElement('localization', false);
    if Element <> nil then
    begin
      FListLocalizedAppName := TListLocalizedAppName.Create;
      ChildElements := Element.ChildrenIterator;
      try
        while ChildElements.GetNext do
        begin
          Check(ChildElements.Current.TagName = 'caption', 'Each child of the localization node must be an <caption> element.');
          FListLocalizedAppName.Add(TLocalizedAppName.Create(ChildElements.Current.AttributeString('lang'), ChildElements.Current.AttributeString('value')));
        end;
      finally
        FreeAndNil(ChildElements);
      end;
    end;

    FAndroidCompileSdkVersion := DefaultAndroidCompileSdkVersion;
    FAndroidMinSdkVersion := DefaultAndroidMinSdkVersion;
    FAndroidTargetSdkVersion := DefaultAndroidTargetSdkVersion;
    Element := Doc.DocumentElement.ChildElement('android', false);
    if Element <> nil then
    begin
      FAndroidCompileSdkVersion := Element.AttributeCardinalDef('compile_sdk_version', DefaultAndroidCompileSdkVersion);
      FAndroidMinSdkVersion := Element.AttributeCardinalDef('min_sdk_version', DefaultAndroidMinSdkVersion);
      FAndroidTargetSdkVersion := Element.AttributeCardinalDef('target_sdk_version', DefaultAndroidTargetSdkVersion);

      if Element.AttributeString('project_type', AndroidProjectTypeStr) then
      begin
        if AndroidProjectTypeStr = 'base' then
          FAndroidProjectType := apBase else
        if AndroidProjectTypeStr = 'integrated' then
          FAndroidProjectType := apIntegrated else
          raise Exception.CreateFmt('Invalid android project_type "%s"', [AndroidProjectTypeStr]);
      end;

      ChildElement := Element.ChildElement('components', false);
      if ChildElement <> nil then
      begin
        FAndroidServices.ReadCastleEngineManifest(ChildElement);
        WritelnWarning('Android', 'The name <components> is deprecated, use <services> now to refer to Android services');
      end;
      ChildElement := Element.ChildElement('services', false);
      if ChildElement <> nil then
        FAndroidServices.ReadCastleEngineManifest(ChildElement);
    end;

    Element := Doc.DocumentElement.ChildElement('ios', false);
    FUsesNonExemptEncryption := DefaultUsesNonExemptEncryption;
    if Element <> nil then
    begin
      FIOSTeam := Element.AttributeStringDef('team', '');

      FIOSOverrideQualifiedName := Element.AttributeStringDef('override_qualified_name', '');
      if FIOSOverrideQualifiedName <> '' then
        CheckValidQualifiedName('override_qualified_name', FIOSOverrideQualifiedName);

      FIOSOverrideVersion := ReadVersion(Element.Child('override_version', false));

      FUsesNonExemptEncryption := Element.AttributeBooleanDef('uses_non_exempt_encryption',
        DefaultUsesNonExemptEncryption);

      ChildElement := Element.ChildElement('services', false);
      if ChildElement <> nil then
        FIOSServices.ReadCastleEngineManifest(ChildElement);
    end;

    Element := Doc.DocumentElement.ChildElement('associate_document_types', false);
    if Element <> nil then
    begin
      FAssociateDocumentTypes.ReadCastleEngineManifest(Element);
      if FAssociateDocumentTypes.Count > 0 then
        FAndroidServices.AddService('open_associated_urls');
    end;

    Element := Doc.DocumentElement.ChildElement('compiler_options', false);
    if Element <> nil then
    begin
      ChildElement := Element.ChildElement('custom_options', false);
      if ChildElement <> nil then
      begin
        ChildElements := ChildElement.ChildrenIterator('option');
        try
          while ChildElements.GetNext do
          begin
            NewCompilerOption := ChildElements.Current.TextData;
            FExtraCompilerOptions.Add(NewCompilerOption);
            FExtraCompilerOptionsAbsolute.Add(MakeAbsoluteCompilerOption(NewCompilerOption));
          end;
        finally FreeAndNil(ChildElements) end;
      end;

      ChildElement := Element.ChildElement('search_paths', false);
      if ChildElement <> nil then
      begin
        ChildElements := ChildElement.ChildrenIterator('path');
        try
          while ChildElements.GetNext do
            FSearchPaths.Add(ChildElements.Current.AttributeString('value'));
        finally FreeAndNil(ChildElements) end;
      end;

      ChildElement := Element.ChildElement('library_paths', false);
      if ChildElement <> nil then
      begin
        ChildElements := ChildElement.ChildrenIterator('path');
        try
          while ChildElements.GetNext do
            FLibraryPaths.Add(ChildElements.Current.AttributeString('value'));
        finally FreeAndNil(ChildElements) end;
      end;
    end;

    Element := Doc.DocumentElement.ChildElement('data', false);
    if Element <> nil then
      FDataExists := Element.AttributeBooleanDef('exists', DefaultDataExists)
    else
      FDataExists := DefaultDataExists;

    if FAndroidServices.HasService('open_associated_urls') then
      FAndroidServices.AddService('download_urls'); // downloading is needed when opening files from web
  finally FreeAndNil(Doc) end;

  CreateFinish;
end;

constructor TCastleManifest.CreateFromUrl(const ManifestUrl: String);
begin
  CreateFromUrl(ExtractFilePath(URIToFilenameSafe(ManifestUrl)), ManifestUrl);
end;

destructor TCastleManifest.Destroy;
begin
  FreeAndNil(OwnerComponent);
  FreeAndNil(FIncludePaths);
  FreeAndNil(FIncludePathsRecursive);
  FreeAndNil(FExcludePaths);
  FreeAndNil(FExtraCompilerOptions);
  FreeAndNil(FExtraCompilerOptionsAbsolute);
  FreeAndNil(FIcons);
  FreeAndNil(FLaunchImages);
  FreeAndNil(FSearchPaths);
  FreeAndNil(FLibraryPaths);
  FreeAndNil(FAndroidServices);
  FreeAndNil(FIOSServices);
  FreeAndNil(FAssociateDocumentTypes);
  inherited;
end;

function TCastleManifest.DefaultQualifiedName(const AName: String): String;
begin
  Result := SDeleteChars(FName, AllChars - QualifiedNameAllowedChars);
  { On Android, package name cannot be just a word, it must have some dot. }
  if Pos('.', Result) = 0 then
    Result := 'com.mycompany.' + Result;
end;

procedure TCastleManifest.CheckMatches(const Name, Value: string; const AllowedChars: TSetOfChars);
var
  I: Integer;
begin
  for I := 1 to Length(Value) do
    if not (Value[I] in AllowedChars) then
      raise Exception.CreateFmt('Project %s contains invalid characters: "%s", this character is not allowed: "%s"',
        [Name, Value, SReadableForm(Value[I])]);
end;

procedure TCastleManifest.CheckValidQualifiedName(const OptionName: string; const QualifiedName: string);
var
  Components: TStringList;
  I: Integer;
begin
  CheckMatches(OptionName, QualifiedName, QualifiedNameAllowedChars);

  if (QualifiedName <> '') and
     ((QualifiedName[1] = '.') or
      (QualifiedName[Length(QualifiedName)] = '.')) then
    raise Exception.CreateFmt('%s (in %s) cannot start or end with a dot: "%s"', [
      OptionName,
      ManifestName,
      QualifiedName
    ]);

  Components := CastleStringUtils.SplitString(QualifiedName, '.');
  try
    for I := 0 to Components.Count - 1 do
    begin
      if Components[I] = '' then
        raise Exception.CreateFmt('%s (in %s) must contain a number of non-empty components separated with dots: "%s"', [
          OptionName,
          ManifestName,
          QualifiedName
        ]);
      if Components[I][1] in ['0'..'9'] then
        raise Exception.CreateFmt('%s (in %s) components must not start with a digit: "%s"', [
          OptionName,
          ManifestName,
          QualifiedName
        ]);
    end;
  finally FreeAndNil(Components) end;
end;

function TCastleManifest.ReadVersion(const Element: TDOMElement): TProjectVersion;
begin
  if Element = nil then
    Exit(nil);
  Result := TProjectVersion.Create(OwnerComponent);
  Result.DisplayValue := Element.AttributeString('value');
  CheckMatches('version value', Result.DisplayValue, AlphaNum + ['_','-','.']);
  Result.Code := Element.AttributeCardinalDef('code', DefautVersionCode);
end;

function TCastleManifest.MakeAbsoluteCompilerOption(const Option: String): String;
begin
  Result := Trim(Option);
  if (Length(Result) >= 2) and (Result[1] = '@') then
    Result := '@' + CombinePaths(Path, SEnding(Result, 2));
end;

procedure TCastleManifest.CreateFinish;

  { If DataExists, check whether DataPath really exists.
    If it doesn't exist, make a warning and set FDataExists to false. }
  procedure CheckDataExists;
  begin
    if FDataExists then
    begin
      if DirectoryExists(DataPath) then
        WritelnLog('Found data in "' + DataPath + '"')
      else
      begin
        WritelnWarning('Data directory not found (tried "' + DataPath + '"). If this project has no data, add <data exists="false"/> to CastleEngineManifest.xml.');
        FDataExists := false;
      end;
    end else
    begin
      if DirectoryExists(DataPath) then
        WritelnWarning('Possible data directory found in "' + DataPath + '", but your project has <data exists="false"/> in CastleEngineManifest.xml, so it will be ignored.' + NL +
        '  To remove this warning:' + NL +
        '  1. Rename this directory to something else than "data" (if it should not be packaged),' + NL +
        '  2. Remove <data exists="false"/> from CastleEngineManifest.xml (if "data" should be packaged).');
    end;
  end;

  procedure GuessDependencies;

    procedure AddDependency(const Dependency: TDependency; const FileInfo: TFileInfo);
    begin
      if not (Dependency in Dependencies) then
      begin
        WritelnLog('Automatically adding "' + DependencyToString(Dependency) +
          '" to dependencies because data contains file: ' + FileInfo.URL);
        Include(FDependencies, Dependency);
      end;
    end;

  var
    FileInfo: TFileInfo;
  begin
    if DataExists then
    begin
      if FindFirstFile(DataPath, '*.ttf', false, [ffRecursive], FileInfo) or
         FindFirstFile(DataPath, '*.otf', false, [ffRecursive], FileInfo) then
        AddDependency(depFreetype, FileInfo);
      if FindFirstFile(DataPath, '*.gz' , false, [ffRecursive], FileInfo) then
        AddDependency(depZlib, FileInfo);
      if FindFirstFile(DataPath, '*.png', false, [ffRecursive], FileInfo) then
        AddDependency(depPng, FileInfo);
      if FindFirstFile(DataPath, '*.wav', false, [ffRecursive], FileInfo) then
        AddDependency(depSound, FileInfo);
      if FindFirstFile(DataPath, '*.ogg', false, [ffRecursive], FileInfo) then
        AddDependency(depOggVorbis, FileInfo);
    end;
  end;

  procedure CloseDependencies;

    procedure DependenciesClosure(const Dep, DepRequirement: TDependency);
    begin
      if (Dep in Dependencies) and not (DepRequirement in Dependencies) then
      begin
        WritelnLog('Automatically adding "' + DependencyToString(DepRequirement) +
          '" to dependencies because it is a prerequisite of existing dependency "'
          + DependencyToString(Dep) + '"');
        Include(FDependencies, DepRequirement);
      end;
    end;

  begin
    DependenciesClosure(depPng, depZlib);
    DependenciesClosure(depFreetype, depZlib);
    DependenciesClosure(depOggVorbis, depSound);
  end;

  { Check correctness. }
  procedure CheckManifestCorrect;
  begin
    CheckMatches('name', Name                     , AlphaNum + ['_','-']);
    CheckMatches('executable_name', ExecutableName, AlphaNum + ['_','-']);

    { non-filename stuff: allow also dots }
    CheckValidQualifiedName('qualified_name', QualifiedName);

    { more user-visible stuff, where we allow spaces, local characters and so on }
    CheckMatches('caption', Caption, AllChars - ControlChars);
    CheckMatches('author', Author  , AllChars - ControlChars);

    if AndroidMinSdkVersion > AndroidTargetSdkVersion then
      raise Exception.CreateFmt('Android min_sdk_version %d is larger than target_sdk_version %d, this is incorrect',
        [AndroidMinSdkVersion, AndroidTargetSdkVersion]);

    if AndroidMinSdkVersion < ReallyMinSdkVersion then
      raise Exception.CreateFmt('Android min_sdk_version %d is too small. It must be >= %d for Castle Game Engine applications',
        [AndroidMinSdkVersion, ReallyMinSdkVersion]);
  end;

begin
  CheckDataExists;
  GuessDependencies; // depends on FDataExists finalized, so must be after CheckDataExists
  CloseDependencies; // must be after GuessDependencies, to close also guesses dependencies
  CheckManifestCorrect; // must be at end, to validate all
end;

{
function TCastleManifest.SearchFile(const BaseName: String): String;
var
  SearchPath, FileNameAbsolute: String;
begin
  for SearchPath in SearchPaths do
  begin
    FileNameAbsolute := CombinePaths(CombinePaths(Path, SearchPath), BaseName);
    if RegularFileExists(FileNameAbsolute) then
      Exit(FileNameAbsolute);
  end;
  Result := '';
end;
}

function TCastleManifest.SearchPascalUnit(const AUnitName: String): String;
var
  SearchPath, FileNameAbsolute, SearchPathAbsolute: String;
begin
  for SearchPath in SearchPaths do
  begin
    SearchPathAbsolute := CombinePaths(Path, SearchPath);

    FileNameAbsolute := CombinePaths(SearchPathAbsolute, AUnitName + '.pas');
    if RegularFileExists(FileNameAbsolute) then
      Exit(FileNameAbsolute);

    FileNameAbsolute := CombinePaths(SearchPathAbsolute, AUnitName + '.pp');
    if RegularFileExists(FileNameAbsolute) then
      Exit(FileNameAbsolute);

    { for case-sensitive filesystems, search also for lowercase version,
      just like FPC does. }

    FileNameAbsolute := CombinePaths(SearchPathAbsolute, LowerCase(AUnitName) + '.pas');
    if RegularFileExists(FileNameAbsolute) then
      Exit(FileNameAbsolute);

    FileNameAbsolute := CombinePaths(SearchPathAbsolute, LowerCase(AUnitName) + '.pp');
    if RegularFileExists(FileNameAbsolute) then
      Exit(FileNameAbsolute);
  end;
  Result := '';
end;

{ globals -------------------------------------------------------------------- }

const
  DependencyNames: array [TDependency] of string =
  ('Freetype', 'Zlib', 'Png', 'Sound', 'OggVorbis', 'Https');

function DependencyToString(const D: TDependency): string;
begin
  Result := DependencyNames[D];
end;

function StringToDependency(const S: string): TDependency;
begin
  for Result in TDependency do
    if AnsiSameText(DependencyNames[Result], S) then
      Exit;
  raise Exception.CreateFmt('Invalid dependency name "%s"', [S]);
end;

const
  ScreenOrientationNames: array [TScreenOrientation] of string =
  ('any', 'landscape', 'portrait');

function ScreenOrientationToString(const O: TScreenOrientation): string;
begin
  Result := ScreenOrientationNames[O];
end;

function StringToScreenOrientation(const S: string): TScreenOrientation;
begin
  for Result in TScreenOrientation do
    if AnsiSameText(ScreenOrientationNames[Result], S) then
      Exit;
  raise Exception.CreateFmt('Invalid orientation name "%s"', [S]);
end;

end.
