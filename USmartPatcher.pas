unit USmartPatcher;

interface

uses
  Windows, SysUtils, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, Classes, Graphics, StrUtils, Math,
  Gauges, Clipbrd;

type
  TFPatcher = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    GroupOrigFileset: TGroupBox;
    Label3: TLabel;
    Label4: TLabel;
    OpenDialog: TOpenDialog;
    EditOrigFile: TEdit;
    EditModFile: TEdit;
    ButBrowseOrig: TButton;
    ButBrowseMod: TButton;
    GroupNewFile: TGroupBox;
    Label5: TLabel;
    EditNewFile: TEdit;
    ButtBrowseNew: TButton;
    ImgLogoRiddickTop: TImage;
    ButtSmartPatch: TButton;
    LogBox: TListBox;
    Label6: TLabel;
    CheckBackup: TCheckBox;
    ButtExit: TButton;
    ImgLogoRiddickLeft: TImage;
    CheckExtSearch: TCheckBox;
    Gauge: TGauge;
    ButtClear: TButton;
    procedure ButBrowseOrigClick(Sender: TObject);
    procedure ButtExitClick(Sender: TObject);
    procedure ButBrowseModClick(Sender: TObject);
    procedure ButtBrowseNewClick(Sender: TObject);
    procedure ButtSmartPatchClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure LogBoxDblClick(Sender: TObject);
    procedure ButtClearClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;
type
  CharFile = file of char;

var
  FPatcher: TFPatcher;

implementation

{$R *.dfm}

uses VersionInfo;

const
  PreAftLen: integer = 10;
  PreAftSrc: integer = $4000;

type
  TModRec = record
              Offset: longint;
              Length: longint;
              Orig: AnsiString;
              New: AnsiString;
              Pre: AnsiString;
              Aft: AnsiString;
            end;
  TModRecA = array of TModRec;

var
  Mods: TModRecA;
  Ver: TVersionInfo;

procedure Log(x: string);
var i: integer;
begin
  while (FPatcher.LogBox.Count>1000) do begin
    FPatcher.LogBox.Items.Delete(0);
  end;
  i := FPatcher.LogBox.Items.Add(x);
  FPatcher.LogBox.TopIndex := i;
  Application.ProcessMessages;
end;

procedure LogL(x: string);
begin
  FPatcher.LogBox.Items.BeginUpdate;
  FPatcher.LogBox.Items.Strings[FPatcher.LogBox.Items.Count-1] := x;
  FPatcher.LogBox.Items.EndUpdate;
  FPatcher.LogBox.TopIndex := FPatcher.LogBox.Items.Count-1;
  Application.ProcessMessages; 
end;

procedure PosUpd(fpos, fsize: integer);
var i: integer;
begin
  i := Round(fpos*100/fsize);
  if (FPatcher.Gauge.Progress<>i) then begin
    FPatcher.Gauge.Progress := i;
    Application.ProcessMessages;
  end;
end;

function Dec2Hex(d: longint): string;
const hexset: string[16] = '0123456789abcdef';
begin
  Result := '';
  while (d>=16) do begin
    Result := hexset[(d MOD 16)+1] + Result;
    d := d DIV 16;
  end;
  Result := hexset[d+1] + Result;
  if (Length(Result) MOD 2=1) then Result := '0'+Result;
end;

function FindModsInFiles(g1,g2: string): TModRecA;
var f1,f2: file of char;
    Buf1, Buf2: array[1..1024] of char;
    i, i1, i2: integer;
    o: longint;
    lastinequal: boolean;
    resi: longint;
    Last10, Next10: AnsiString;
begin
  try
    AssignFile(f1,g1);
    AssignFile(f2,g2);
    FileMode := fmOpenRead;
    lastinequal := false;
    Reset(f1);
    Reset(f2);
    Log('Now parsing files for changes ... ');
    FPatcher.Gauge.Visible := true;
    FPatcher.Gauge.Progress := 0;
    repeat
      PosUpd(FilePos(f1), FileSize(f1));
      if (FilePos(f1)<>FilePos(f2)) then begin
        Log('ERROR while reading! File positions are different. Aborting.');
        CloseFile(f1);
        CloseFile(f2);
        Exit;
      end;
      o := FilePos(f1);
      BlockRead(f1,Buf1,SizeOf(Buf1),i1);
      BlockRead(f2,Buf2,SizeOf(Buf2),i2);
      if (i2<>i1) then begin
        Log('ERROR while reading! Different sized blocks were read. Aborting.');
        CloseFile(f1);
        CloseFile(f2);
        Exit;
      end;
      for i:=1 to i1 do begin
        if (Buf1[i]<>Buf2[i]) then begin
          if (lastinequal) then begin
            resi := Length(Result)-1;
            Inc(Result[resi].Length);
            Result[resi].Orig := Result[resi].Orig + Buf1[i];
            Result[resi].New := Result[resi].New + Buf2[i];
          end else begin
            resi := Length(Result);
            SetLength(Result, resi+1);
            Result[resi].Offset := o+i-1;
            Result[resi].Length := 1;
            Result[resi].Orig := Buf1[i];
            Result[resi].New := Buf2[i];
            Result[resi].Pre := Last10;
            // Result[resi].Aft := Next10;
          end;
          lastinequal := true;
        end else begin
          if (lastinequal) then begin
            Last10 := '';
            resi := Length(Result)-1;
            Log('Found '+IntToStr(Result[resi].Length)+' diff. Byte(s) at Offset 0x'+UpperCase(Dec2Hex(Result[resi].Offset))+' ('+FloatToStr(SimpleRoundTo(FilePos(f1)*100/FileSize(f1),-2))+'%)');
          end;
          lastinequal := false;
        end;
        if (Length(Last10)<PreAftLen) then Last10 := Last10 + Buf1[i] else Last10 := RightBStr(Last10, PreAftLen - 1) + Buf1[i];
      end;
    until (i1=0) OR (i2=0);
    FPatcher.Gauge.Visible := false;
    CloseFile(f1);
    CloseFile(f2);
    Log('>>> Found '+IntToStr(Length(Result))+' different areas.');
  except
    on e: Exception do Log('Exception: '+e.Message);
  end;
end;

function ChangeNewFile(g: string; m: TModRecA): boolean;
var f: file of char;
    i,j: integer;
    o, lo, mo: longint;
    Last: AnsiString;
    Buf: char;
    foundit, missedany: boolean;
label NextTurn;
begin
  try
    missedany := false;
    AssignFile(f, g);
    FileMode := fmOpenReadWrite;
    Reset(f);
    Last := '';
    if (FPatcher.CheckExtSearch.Checked) then begin
      o := 0;
    end else begin
      o := Mods[0].Offset - PreAftSrc;
      if (o<0) then o := 0;
    end;
    lo := 0;
    Seek(f,o);
    Log('Now scanning new file to apply changes ... ');
    FPatcher.Gauge.Progress := 0;
    FPatcher.Gauge.Visible := true;
    for i:=0 to Length(Mods)-1 do begin
      foundit := false;
      NextTurn:
      if (FPatcher.CheckExtSearch.Checked) then mo := FileSize(f) else mo := Mods[i].Offset+2*PreAftSrc;
      while (FilePos(f)<mo) AND (NOT EOF(f)) do begin
        // if (FilePos(f) MOD 1024 = 0) then LogL('Now scanning pos. '+IntToStr(FilePos(f))+'/'+IntToStr(FileSize(f))+' ('+FloatToStr(SimpleRoundTo(FilePos(f)*100/FileSize(f),-2))+'%) ... ');
        PosUpd(FilePos(f), FileSize(f));
        BlockRead(f,Buf,1);
        if (RightBStr(Last, Length(Mods[i].Pre)) = Mods[i].Pre) then begin
          if (Buf = Mods[i].Orig[1]) then begin
            Seek(f,FilePos(f)-1);
            Log('Found pos at Offset 0x'+Dec2Hex(FilePos(f))+' ('+FloatToStr(SimpleRoundTo(FilePos(f)*100/FileSize(f),-2))+'%) - changing from '+Dec2Hex(Ord(Buf))+' to '+Dec2Hex(Ord(Mods[i].New[1])));
            for j:=1 to Length(Mods[i].New) do begin
              Read(f,Buf);
              if (Buf=Mods[i].Orig[j]) then begin
                foundit := true;
                Seek(f,FilePos(f)-1);
                Write(f,Mods[i].New[j]);
                lo := FilePos(f);
              end else Log('Bytes different at Offset 0x'+UpperCase(Dec2Hex(FilePos(f))));
            end;
            Break;
          end else begin
            foundit := false;
            Log('Found pos at 0x'+UpperCase(Dec2Hex(FilePos(f)))+', but different original first byte. Searching further...');
          end;
        end;
        if (Length(Last)<PreAftLen) then Last := Last + Buf else Last := RightBStr(Last, PreAftLen-1) + Buf;
      end;
      if (NOT foundit) AND (Length(Mods[i].Pre)>2) then begin
        Mods[i].Pre := RightBStr(Mods[i].Pre,Length(Mods[i].Pre)-1);
        Log('Pre not found. Dropping one byte... (now '+IntToStr(Length(Mods[i].Pre))+' bytes)');
        if (lo>0) then o := lo else begin
          if FPatcher.CheckExtSearch.Checked then begin
            o := 0;
          end else begin
            o := Mods[i].Offset - PreAftSrc;
            if (o<0) then o:=0;
          end;
        end;
        Seek(f,o);
        goto NextTurn;
      end else if (NOT foundit) then begin
        Log('Couldn''t find this mod. Trying next one...');
        missedany := true;
      end;
    end;
    FPatcher.Gauge.Visible := false;
    CloseFile(f);
    if (NOT missedany) then Result := true else Result := false;
  except
    on e: Exception do begin
      Log('Exception: '+e.Message);
      Result := falsE;
    end;
  end;
end;

function CheckFileSizes(g1,g2: string): boolean;
var f1,f2: file of char;
    s1,s2: longint;
begin
  try
    AssignFile(f1,g1);
    AssignFile(f2,g2);
    FileMode := fmOpenRead;
    Reset(f1);
    Reset(f2);
    s1 := FileSize(f1);
    s2 := FileSize(f2);
    CloseFile(f1);
    CloseFile(f2);
    if (s1=s2) then Result := true else Result := false;
  except
    on e: Exception do begin
      Log('Exception: '+e.Message);
      Result := false;
    end;
  end;
end;

procedure TFPatcher.ButBrowseOrigClick(Sender: TObject);
begin
  if (Length(ExtractFilePath(EditOrigFile.Text))>0) then OpenDialog.InitialDir := ExtractFilePath(EditOrigFile.Text);
  OpenDialog.Title := 'Select original file from old version';
  if (OpenDialog.Execute) then begin
    EditOrigFile.Text := OpenDialog.FileName;
    Log('Original file: '+ExtractFilename(OpenDialog.FileName));
  end else Log('Aborted OpenDialog. (Original file)');
end;

procedure TFPatcher.ButtExitClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TFPatcher.ButBrowseModClick(Sender: TObject);
begin
  if (Length(ExtractFilePath(EditModFile.Text))>0) then OpenDialog.InitialDir := ExtractFilePath(EditModFile.Text);
  OpenDialog.Title := 'Select modified file from old version';
  if (OpenDialog.Execute) then begin
    EditModFile.Text := OpenDialog.FileName;
    Log('Original modified file: '+ExtractFilename(OpenDialog.FileName));
  end else Log('Aborted OpenDialog. (Original mod file)');
end;

procedure TFPatcher.ButtBrowseNewClick(Sender: TObject);
begin
  if (Length(ExtractFilePath(EditNewFile.Text))>0) then OpenDialog.InitialDir := ExtractFilePath(EditNewFile.Text);
  OpenDialog.Title := 'Select file with new version';
  if (OpenDialog.Execute) then begin
    EditNewFile.Text := OpenDialog.FileName;
    Log('New version file: '+ExtractFilename(OpenDialog.FileName));
  end else Log('Aborted OpenDialog. (New ver file)');
end;

function Backup(f: string): boolean;
var t: string;
begin
  t := ChangeFileExt(f,'.bak');
  Log('Backup to: '+t);
  if (FileExists(t)) then begin
    Log('File exists! Let''s hope that this is an old backup of this file. Skipping backup.');
    Result := true;
  end else Result := CopyFile(PChar(f),PChar(t),true);
end;

procedure TFPatcher.ButtSmartPatchClick(Sender: TObject);
begin
  if (ExtractFileName(EditOrigFile.Text)='') then begin
    Log('ERROR! Please select the original file of the OLD version!');
    Exit;
  end;
  if (ExtractFileName(EditModFile.Text)='') then begin
    Log('ERROR! Please select the modified file of the OLD version!');
    Exit;
  end;
  if (ExtractFileName(EditNewFile.Text)='') then begin
    Log('ERROR! Please select the original file of the NEW version!');
    Exit;
  end;
  if (EditOrigFile.Text = EditModFile.Text) then begin
    Log('ERROR! Please select different original files!');
    Exit;
  end;
  if (EditOrigFile.Text = EditNewFile.Text) OR (EditModFile.Text = EditNewFile.Text) then begin
    Log('ERROR! New version file can''t be the same as old version file!');
    Exit;
  end;
  if (NOT CheckFileSizes(EditOrigFile.Text, EditModFile.Text)) then begin
    Log('ERROR! File sizes of original files differ!');
    Exit;
  end;
  Log('No errors until here. Start modification parsing...');
  Mods := FindModsInFiles(EditOrigFile.Text, EditModFile.Text);
  Log('Done finding differences in original fileset.');
  if (CheckBackup.Checked) then begin
    if (Backup(EditNewFile.Text)) then begin
      Log('Backup done.');
    end else begin
      Log('ERROR! Could not backup file. Aborting...');
      Exit;
    end;
  end else Log('Skipping backup of new file.');
  if (ChangeNewFile(EditNewFile.Text, Mods)) then begin
    Log('Done making changes to new file. File should work now!');
  end else begin
    Log('ERROR! Could not apply all changes to new file.');
  end;
end;

procedure InitLogBox;
begin
  FPatcher.LogBox.Clear;
  Log('Welcome to SmartPatcher by riddick');
  Log('');
  Log('NOTE: You can damage your files - use this app wisely!');
  Log(DupeString('-',140));
end;

procedure TFPatcher.FormCreate(Sender: TObject);
begin
  Ver := TVersionInfo.Create(Application.ExeName);
  Application.Title := 'SmartPatcher '+Ver.FileVersion;
  FPatcher.Caption := 'SmartPatcher '+Ver.FileVersion;
  InitLogBox;
end;

procedure TFPatcher.LogBoxDblClick(Sender: TObject);
var tmp: String;
begin
  FPatcher.LogBox.Items.Delimiter := Chr(255);
  tmp := FPatcher.LogBox.Items.DelimitedText;
  tmp := StringReplace(tmp, Chr(255), Chr(13)+Chr(10), [rfReplaceAll]);
  Clipboard.AsText := tmp;
end;

procedure TFPatcher.ButtClearClick(Sender: TObject);
begin
  InitLogBox;
end;

end.
