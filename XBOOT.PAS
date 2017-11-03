program XBoot;

{$A-,I-,S-,V-}

uses CRT, DOS;

{$L XBOOT.OBX}
procedure MBR_CODE; external;

const
  MaxPartitions = 3;
     MaxEntryes = 4;
    PartTextLen = 15;
         isBoot = $80;
   ExtendedPart = 5;
        XBootId = $11EBCEEB;
       HiddenId: integer = $FF;  { 0=unused, $FF=BBT, -1=no make hidden }

type
  TPartEntry = record
    bootIndicator : byte;
    beginHead     : byte;
    beginSector   : byte;
    beginCyl      : byte;
    SystemId      : byte;
    endHead       : byte;
    endSector     : byte;
    endCyl        : byte;
    relSectorLow  : word;
    relSectorHigh : word;
    numSectorsLow : word;
    numSectorsHigh: word;
  end;

  TPartData = record
    TrueSys: byte;
    Partition: byte;
    Text: array[0..PartTextLen-1] of char;
    Term: char;
  end;

  TBootData = record
     PartDesc: array[0..MaxPartitions-1] of TPartData;
    PartEntry: array[0..MaxEntryes   -1] of TPartEntry;
         aa55: word;
  end;

const
  SectSize   = 512;
  LoaderSize = SectSize-sizeof(TBootData);

type
  SectBuffer = record
    Loader: array[0..LoaderSize-1-sizeof(LongInt)] of byte;
    Signature: LongInt;
    Data: TBootData;
  end;

type
  TByteArray = array[0..65519] of byte;
  PByteArray = ^TByteArray;

const
  ReadSect = 2;
  SaveSect = 3;
   LF = #13#10;

function BootIO (Drive: byte; Op: byte; var Buffer): boolean;  assembler;
asm
   mov   AH,Op     { Get iotype   }
   mov   AL,1      { Read/Write 1 track }
   les   BX,Buffer { Get buffer address }
   mov   DX,80h    { Head 0, Drive C }
   add   DL,Drive  { Now DL contains HDD # }
   mov   CX,1      { Cyl 0, sector 1 }
   int   13h       { perform I/O  }
   mov   al,True   { Assume True  }
   jnc   @1
   dec   al        { Assume False }
@1:
end;

procedure Syntax (const S: string);
begin
  writeln;
  if S <> '' then writeln ('Bad command line: ', S, '.'+LF+#7);
  writeln ('Syntax: XBOOT [<bootsave.bin>] [switches]');
  writeln ('Switches:');
  writeln ('   /R   Only refresh internal XBOOT data from MBR');
  writeln ('   /I   Install with ignoring old internal XBOOT data');
  writeln ('   /Dn  Install on HDDn (n = 0..3, default = 0)');
  writeln ('   /Hn  Use n as id of unused system partition');
  writeln ('        Default = $FF (BBT ;). If n = -1, this feature is skipped.');
  writeln ('   /B   Make backup of previous MBR');
  writeln ('   //   Simple; used for install without others params.');
  writeln ('   /?   Display this help');
{ writeln ('if <bootfile> is omitted, then "XBOOT.BIN" used.'); }
  writeln ('if <bootsave> is omitted, then "OLDMBR.BIN" used.');
  writeln ('if /B or <bootsave> is omitted, then MBR is not backed up before install.');
  writeln ('if all params is omitted, this help is displayed.');
  writeln ('Note: if value is with ''$'' prefixed, it''s hex (ex: $1F = 31).');
  writeln ('*** See also XBOOT.DOC for details. ***');
  Halt (1);
end;

procedure HaltStr (Code: word; const S: string);
begin
  write (S);
  writeln ('.'#7);
  Halt (Code);
end;

procedure IOHaltStr (Code: word; const S, FileName: string);
var
  i: integer;
begin
  I := IOResult;
  if I = 0 then Exit;
  writeln (S, FileName, ', I/O error #', I, '.'#7);
  Halt (Code);
end;

function HexB (B: byte): string;
const
  Data: array[0..$F] of char = '0123456789ABCDEF';
begin
  HexB[0] := #2;
  HexB[1] := Data[B shr 4];
  HexB[2] := Data[B and $F];
end;

function SearchBytes (var Src; Count: word; var Pattern; Len: word): pointer;
var
  I, J: word;
  P: TByteArray absolute Src;
  Q: TByteArray absolute Pattern;
label
  NotEqual;
begin
  SearchBytes := nil;
  if Count < Len then exit;
  for I := 0 to Count - Len do
  begin
    for J:=0 to Len-1 do if P[I+J] <> Q[J] then goto NotEqual;
    SearchBytes := @P[I];
    exit;
NotEqual:;
  end;
end;

const
  BadHddNum = 'HDD number must be 0, 1, 2 or 3';
  BadNames  = 'too more filenames';
  BadIdStr  = '**UNKNOWN**';

  PartName: array[0..36] of record
    N: word;
    S: string[15];
  end = (
      (N:0; S:'Empty'),
      (N:1; S:'FAT-12'),
      (N:2; S:'Xenix user'),
      (N:3; S:'Xenix root'),
      (N:4; S:'FAT-16'),
      (N:5; S:'EXTEND'),
      (N:6; S:'BigDOS'),
      (N:7; S:'HPFS'),
      (N:8; S:'AIX'),
      (N:9; S:'AIX boot'),
    (N:$0A; S:'OS/2 boot man'),
    (N:$40; S:'Venix-286'),
    (N:$50; S:'DM'),
    (N:$51; S:'Novell'),
    (N:$52; S:'Microport'),
    (N:$56; S:'GB'),
    (N:$61; S:'Speed'),
    (N:$63; S:'386ix'),
    (N:$64; S:'Net286'),
    (N:$65; S:'Net386'),
    (N:$75; S:'PCIX'),
    (N:$80; S:'Minix'),
    (N:$81; S:'Linux/Minix'),
    (N:$82; S:'Linux swap'),
    (N:$83; S:'Linux native'),
    (N:$93; S:'Amoeba'),
    (N:$94; S:'Amoeba BBT'),
    (N:$A5; S:'BSD/386'),
    (N:$B7; S:'BSDI fs'),
    (N:$B8; S:'BSDI swap'),
    (N:$C7; S:'Syrinx'),
    (N:$DB; S:'CP/M'),
    (N:$E1; S:'DOS access'),
    (N:$E3; S:'DOS R/O'),
    (N:$F2; S:'DOS 2nd'),
    (N:$FF; S:'BBT'),
  (N:$FFFF; S:'**UNKNOWN**'));

  YesNo: array[boolean] of string[4] = ('no  ','Yes ');

  PatchNops: array[0..4] of byte = ($90, $90, $90, $90, $90);
  PatchMove: array[0..3] of byte = ($C6, $85, $C2, $01);

function IdStr (Id: integer): string;
var
  i: integer;
const
  Sp: string[15] = '               ';
begin
  if Id = HiddenId then
  begin
    IdStr := '** Hidden ID **    ';
    exit;
  end;
  for i:=0 to High (PartName) do with PartName[i] do if N = Id then
  begin
    Sp[0] := char (13 - Length(S));
    IdStr := '($' + HexB (Id) + ') ' + S + Sp;
    exit;
  end;
  IdStr := BadIdStr;
end;

var
  P: ^TPartEntry;
  Q: ^TPartData;
  F: file;
  C: char;
  S, S2: string;
  Len: byte absolute S;
  Attr: word;
  DescNum, PartNum, ErrCode, I, J: integer;
  DriveNo: byte;
  Change, Bad, IgnoreOld, Refresh, MkSave: boolean;
  Buffer: SectBuffer;
  SaveFile: PathStr;
  PatchAddr: PByteArray;

function SearchPatch (var Pattern; Len: word): pointer;
begin
  SearchPatch := SearchBytes (Buffer.Loader, LoaderSize, Pattern, Len);
end;

label
  againId;

begin
  writeln ('XBOOT 2.0 (c) 1996 by EBCEEB, inc.');
  if ParamCount = 0 then Syntax('');
  for I:=1 to ParamCount do
  begin
    S := ParamStr(i);
    if (Length(S) > 1) and (S[1] = '/') then
        for J:=2 to Length(S) do case UpCase(S[J]) of
      '?': Syntax('');
      'I': IgnoreOld := True;
      'R': Refresh := True;
      'D': if J >= Length(S) then Syntax(BadHddNum) else case S[J+1] of
        '0', '1', '2', '3': begin
          DriveNo := ord(S[J+1]) - ord('0');
          inc (J);
        end;
        else Syntax(BadHddNum);
      end;
      'H': begin
        Val (Copy (S, J+1, 255), HiddenId, ErrCode);
        if (ErrCode <> 0) or (HiddenId < -1) or (HiddenId > 255) then
          Syntax('Disk id must be -1 .. 255');
        J := Length(S);
      end;
      'B': MkSave := True;
      '/':;
    end {for/case} else
  { if not MkSave and (BootFile = '') then BootFile := S else }
    if SaveFile <> '' then Syntax (BadNames) else
    SaveFile := S;
  end;
  if Refresh then IgnoreOld:=True;
{ if BootFile = '' then BootFile := 'XBOOT.BIN'; }
  if (SaveFile = '') and MkSave then SaveFile := 'OLDMBR.BIN';

  writeln ('Use <Control-Break> to abort install'+LF);
  if not BootIO (DriveNo, ReadSect, Buffer) then
    HaltStr (2, 'Cannot read boot-sector for edit');

  if SaveFile <> '' then
  begin
    Assign (F, SaveFile);
    Rewrite (F, 1);
    BlockWrite (F, Buffer, SectSize);
    Close (F);
    Assign (F, SaveFile);
    GetFAttr (F, Attr);
    SetFAttr (F, Attr or (ReadOnly + Archive));
    IOHaltStr (3, 'Cannot save current MBR into ', SaveFile);
  end;

  if (Buffer.Signature = XBootId) then
  begin
    if not IgnoreOld then
    begin
      PatchAddr := SearchPatch (PatchMove, sizeof(PatchMove));
      if PatchAddr <> nil then
        HiddenId := PatchAddr^[sizeof(PatchMove)] else
      begin
        PatchAddr := SearchPatch (PatchNops, sizeof(PatchNops));
        if PatchAddr <> nil
          then HiddenId := -1
          else HaltStr (4, 'installed XBOOT has invalid (???) format');
      end;
      for i:=0 to MaxPartitions-1 do with Buffer.Data.PartDesc[i] do
        if Partition <> 0 then
          Buffer.Data.PartEntry[Partition-1].SystemId := TrueSys;
    end;
  end else
  if Refresh then HaltStr (5, 'Cannot refresh: installed XBOOT not found');

  if not Refresh then
  begin
{   Assign (F, BootFile);
    Reset (F, 1);
    BlockRead (F, Buffer.Loader, LoaderSize);
    Close (F);
    IOHaltStr (6, 'Cannot read new boot-loader from ', BootFile);
}   Move (Addr(MBR_CODE)^, Buffer.Loader, LoaderSize);
    PatchAddr := SearchPatch (PatchMove, sizeof(PatchMove));
{   if PatchAddr = nil then HaltStr (7, BootFile+' contains invalid XBoot-image');}
  end;

  if Refresh then
  begin
    writeln ('Entry  Old id               New id');
    writeln ('=====  ===================  ===================');
    for I:=0 to MaxPartitions-1 do
    begin
      Q := @Buffer.Data.PartDesc[i];
      if Q^.Partition <> 0 then
      begin
        P := @Buffer.Data.PartEntry[Q^.Partition-1];
        J := P^.SystemId;
        write (I+1:3,'    ', IdStr(Q^.TrueSys), '  ', IdStr(J), '  Refresh? [');
        Bad := (J <> HiddenId) and (J <> Q^.TrueSys);
        if Bad then write ('Y/n') else write ('y/N');
        write (']: ');
        Bad := False;
        repeat
          C := upcase(readkey);
          case C of
            'Y', 'N':;
            #27: C := 'N';
            #13: if Bad then C := 'Y' else C := 'N';
            else
              Bad := True;
              if C = #0 then ReadKey;
          end;
        until not Bad;
        writeln (C);
        if C = 'Y' then
        begin
          if (HiddenId <> -1) and (P^.BootIndicator <> isBoot) then
            P^.SystemId := HiddenId;
          Q^.TrueSys := J;
          Change := True;
        end;
      end; { Q^.Partition <> 0 }
    end; { ForEach PartDesc }
  end { Refresh } else
  begin
    writeln ('Valid values of system id:');
    for i:=0 to High(PartName)-2 do write (IdStr(PartName[i].N), ' ');
    writeln;
    writeln;
    writeln ('Now edit multi-boot table, used by XBOOT after reset.');
    writeln ('<Enter> at description edit skips this partition entry.');
    writeln ('<Enter> at id edit saves current system id for this entry.');
    writeln;
    writeln ('Entry Boot Id                  ?Desc             ?New id');
    writeln ('===== ==== =================== ================= ===================');
    DescNum := 0;
    for PartNum:=0 to MaxEntryes-1 do
      if DescNum < MaxPartitions then
    begin
      P := @Buffer.Data.PartEntry[PartNum];
      Q := @Buffer.Data.PartDesc[DescNum];
      Q^.Partition := 0;
      for I:=0 to High(PartName)-1 do if PartName[i].N = P^.SystemId then break;
      write (PartNum+1 : 3, '   ');
      if P^.SystemId = ExtendedPart then
      begin
        writeln ('*** EXTENDED partition - skipped ***');
        continue;
      end;
      write (YesNo[P^.BootIndicator = IsBoot], ' ', IdStr (P^.SystemId), ' :');
      readln (S);
      if S <> '' then
      begin
againId:;
        gotoxy (50, WhereY-1);
        ClrEol;
        write (':');
        readln (S2);
        if S2 <> '' then
        begin
          Val (S2, J, ErrCode);
          if (ErrCode <> 0) or (J < 0) or (J > 255) then goto againId;
          P^.SystemId := J;
        end;
        gotoxy (50, WhereY-1);
        writeln (IdStr (P^.SystemId));
        Q^.TrueSys := P^.SystemId;
        Q^.Partition := Lo(PartNum+1);
        Q^.Term := #$80;
        if (HiddenId <> -1) and (P^.BootIndicator <> isBoot) then
          P^.SystemId := HiddenId;
        FillChar (Q^.Text, PartTextLen, ' ');
        if Len > PartTextLen then Len := PartTextLen;
        Move (s[1], Q^.Text, Len);
        Change := True;
        inc (DescNum);
      end else
      begin
        gotoxy (32, WhereY - 1);
        ClrEOL;
        writeln (' *** Skipped ***');
      end;
    end; { for }
  end; { install new }

  writeln;
  if Change then
  begin
    write ('Press <Enter> to update MBR, <Ctrl>-<Break> to abort...');
    readln;
    if HiddenId = -1
      then Move (PatchNops, PatchAddr^, sizeof(PatchNops))
      else PatchAddr^[sizeof(PatchMove)] := byte(HiddenId);
    if not BootIO (DriveNo, SaveSect, Buffer)
      then HaltStr (8, 'Cannot write new boot-sector to disk')
      else writeln ('Boot sector updated.');
  end else
  writeln ('Nothing to do!');
end.
