program SmartPatcher;

uses
  Forms,
  USmartPatcher in 'USmartPatcher.pas' {FPatcher};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'SmartPatcher';
  Application.CreateForm(TFPatcher, FPatcher);
  Application.Run;
end.
