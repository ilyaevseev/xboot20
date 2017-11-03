program TakeSomeMemoryAndStayResident;

{$M 1024, 0, 0}

uses DOS;

var
  i: word;
  j: integer;

begin
  Val(ParamStr(1), i, j);
  if i > 0 then
  asm
     mov   bx, i
     add   bx, $F
     mov   cl, 4
     shr   bx, cl
     push  bx
     mov   dx, PrefixSeg
     dec   dx
     mov   es, dx
     add   bx, es:[3]
     inc   dx
     mov   es, dx
     mov   ah, 4Ah
     push  es
     int   21h
     pop   es
     pop   bx
     jc    @1
     add   es:[2], bx
@1:  end;
  SwapVectors;
  Keep(0);
end.
