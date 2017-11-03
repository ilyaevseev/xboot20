program FlopBoot;

{$A-,I-,S-,V-}

uses Strings, DOS;

type
  Boot2 = object
    abJmpCode: array[1..3] of byte;{JMP opcode to start of boot code}
    abOem: array[1..8] of byte;    {e.g., "MSDOS6.0" or "IBM  4.0"}
    wSectSize: word;               {bytes per sector (usually 512; 200H)}
    bClustSects: byte;             {sectors per allocation unit (cluster)}
    wResSects: word;               {boot and reserved sectors}
    bFatCnt: byte;                 {number of File Allocation Tables}
    wRootEntries: word;            {max number of 32-byte DirEntryRecs in root}
    wTotSects: word;               {total number of sectors in media}
    bMedia: byte;                  {media descriptor (same as 1st byte in FAT)}
    wFatSects: word;               {number of sectors in one FAT }
  end;

  Boot3 = object (Boot2)
    wSectsPerTrk: word;         {sectors per track}
    wHeads: word;               {number of read/write heads}
    lHidSectsLo: word;          {hidden sectors (ignore hiword in pre-DOS 4.0)}
  end;

  Boot4 = object(Boot3)
    lHidSectsHi: word;          {hidden sectors (hiword)}
    lBigTotSects: longint;      {32-bit TotSects in volume (partitions > 32M)}
    bDrvNo: byte;               {80H=first hard disk (used internally by DOS)}
    res1: byte;                 {(reserved)}
    bExtBootSig: byte;          {Extended boot record signature (always 29H)}
    lSerNo: longint;            {Volume Serial Number (based on when formatted)}
    abVolLabel: array[1..11] of char;   {Volume Label (blank padded)}
    abFileSysID: array[1..8] of char;   {contains 'FAT12   ' or 'FAT16   '}
  end;

  TAlign = (dos2align, dos3align, dos4align);

const
  BootSize = 512;

  ReadSect = 2;
  SaveSect = 3;

  LF = #13#10;

{
binobj boot_hd._a_  boot_hd.obj  BootCode
binobj boot_dos._a_ boot_dos.obj StandardBoot
}
{$L boot_hd.obj}
procedure BootCode; far; external;

{$L boot_dos.obj}
procedure StandardBoot; far; external;

function BootIO (DiskNo: integer; Op: byte; var Buffer): boolean;  assembler;
asm
        mov     AH,Op                   { Get iotype   }
        mov     AL,1                    { Read/Write 1 track }
        les     BX,buffer               { Get buffer address }
        mov     DX,DiskNo               { Head 0, Drive number }
        mov     CX,1                    { Cyl 0, sector 1 }
        int     13h                     { perform I/O  }
        mov     al,1                    { Assume true  }
        jnc     @goback
        dec     al                      { Assume false }
@goback:
end;

procedure Syntax;
begin
  writeln (
    'Syntax: FLOPBOOT [bootfile.ext] [/0..3] [/d2..3] [/r] [/s] [/y]'+LF+
    '   /0..3   : drive (0=A, 1=B, 2=third FDD, 3=fourth FDD)'+LF+
    '   /d2..3  : boot-sector align for DOS 2.0, DOS 3.0'+LF+
    '   /r      : write FROM boot-sector TO file');
  writeln (
    '   /s      : write STANDARD DOS image TO boot-sector'+LF+
    '   /y      : no pause before begin'+LF+LF+
    'Default: drive 0, align DOS 4.0+, write built-in image => boot-sector');
  Halt(1);
end;

procedure Error (const St: string);
begin
  writeln('FLOPBOOT: ', St, #7);
  Halt(2);
end;

function dosInkey: word;  assembler;
asm
  mov  ah, 8
  int  21h
  cmp  al, 0
  jne  @Normal
  int  21h
  mov  ah, al
  mov  al, 0
  jmp  @Done
@Normal:
  mov  ah, 0
@Done:
end;

var
  BootBuffer: array[1..BootSize] of byte;
  fixBoot: Boot4 absolute BootBuffer;
  FileName: PathStr;
  Buffer: string;
  I: integer;
  C: char;
  F: file;

const
  MakeFile: boolean = false;
  DiskNo:   integer = 0;
  Align:    TAlign  = dos4align;
  Request:  boolean = true;
  Standard: boolean = false;
  FileBuffer: pointer = @BootCode;

  Direct: array[boolean] of string[4] = ('FROM','INTO');
  TblSize: array[TAlign] of integer = (sizeof(Boot2),sizeof(Boot3),sizeof(Boot4));
  DiskFileMsg: string[16] = 'Disk: # '+LF+'File: ';
  DiskNumPos = 8;

begin
  writeln ('FLOPBOOT 1.0 (c) 1995 by EBCEEB, inc.'+LF);
  if ParamCount = 0 then Syntax;
  for i:=1 to ParamCount do {*}
  begin
    Buffer := ParamStr(i);
    C := Upcase(Buffer[2]);
    case Buffer[1] of {**}
      '/', '-': case Length(Buffer) of {***}
        2: case C of
          '0','1','2','3': DiskNo:=ord(C)-ord('0');
          'R': MakeFile:=true;
          'Y': Request:=false;
          'S': Standard:=true;
          else Syntax;
        end;
        3: case C of
          'D': case Buffer[3] of
            '2','3': Align:=TAlign (ord(Buffer[3]) - ord('2'));
            else Syntax;
          end;
        end;
        else Syntax;
      end; {***}
    else
      if FileName = '' then FileName := FExpand(Buffer)
      else Syntax;
    end; {**}
  end; {*}

  if Standard then
  begin
    if (FileName <> '') or MakeFile then Syntax;
    FileBuffer := @StandardBoot;
  end;

  DiskFileMsg[DiskNumPos] := char(DiskNo + ord('0'));
  write (DiskFileMsg);
    if Standard then writeln('(use standard built-in)')
    else if FileName = '' then writeln('(use built-in)')
    else writeln (FileName);
  write ('Direction: ');  write(direct[MakeFile]);
    writeln(' file'+LF);

  {!!! if not IsATTY(StdOut) then Request:=false; }
  if Request then
  begin
    write('Hit any key...');
    dosInkey;
    write(#13);
  end;

  if not BootIO(DiskNo, ReadSect, BootBuffer) then
    Error('Cannot load boot-sector.');

  if MakeFile then
  begin
    if FileName = '' then Error('Destination filename required.');
    Assign (F, FileName);
    Rewrite (F, 1);
    if IOResult <> 0 then Error('Cannot create destination file.');
    BlockWrite (F, BootBuffer, BootSize);
    if IOResult <> 0 then Error('Cannot write destination file.');
    Close (F);
    writeln ('Done. Image file created.');
  end else
  begin
    if FileName <> '' then
    begin
      Assign (F, FileName);
      Reset (F, 1);
      if IOResult <> 0 then Error('Cannot open source file.');
      if FileSize(F) <> BootSize then
        Error('Source file has invalid length.');
      BlockRead (F, FileBuffer^, BootSize);
      if IOResult <> 0 then Error('Cannot read from source file.');
      Close (F);
    end;
    Move (fixBoot.abOem, Boot2(FileBuffer^).abOem, tblSize[Align]-3);
    if BootIO(DiskNo, SaveSect, FileBuffer^) then
      writeln('Done. Boot-sector updated.')
    else Error('Cannot update boot-sector.');
  end;
end.
