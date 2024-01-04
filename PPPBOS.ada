with Ada.Text_IO;
with Ada.Calendar; use Ada.Calendar;
with Ada.Environment_Variables;

procedure adaLr is
   type Array_Elements is array (Long_Long_Integer range <>) of Long_Long_Integer;
   type Array_Elements_Access is access Array_Elements;

   type Threading_Proc_Context is record
      Elements : Array_Elements_Access;
      Elements_Size, Worker_Index, Total_Workers : Long_Long_Integer;
   end record;

   package Threading is
      type Thread_Pool is tagged private;

      procedure Init (Self : in out Thread_Pool; Num_Threads : Natural);
      type Task_Proc is access procedure (Context : Threading_Proc_Context);
      procedure Add_Task (Self : Thread_Pool; Proc : Task_Proc; Context : Threading_Proc_Context);
      procedure Wait (Self : Thread_Pool);

   private
      task type Thread is
         entry Run (Pool : Thread_Pool; Proc : Task_Proc; Context : Threading_Proc_Context);
      end Thread;

      type Array_Threads is array (Long_Long_Integer range <>) of Thread;
      type Array_Threads_Access is access Array_Threads;

      protected type Counter_Semaphore is
         entry Wait;
         procedure Increment;
         procedure Decrement;
      private
         Counter : Natural := 0;
      end Counter_Semaphore;
      type Counter_Semaphore_Access is access Counter_Semaphore;

      type Thread_Pool is tagged record
         Num_Threads : Natural;
         Array_Threads_Inst : Array_Threads_Access := null;
         Semaphore : Counter_Semaphore_Access;
      end record;
   end Threading;

   package body Threading is
      procedure Init (Self : in out Thread_Pool; Num_Threads : Natural) is
      begin
         Self.Num_Threads := Num_Threads;
         Self.Array_Threads_Inst := new Array_Threads (0 .. Long_Long_Integer (Num_Threads) - 1);
         Self.Semaphore := new Counter_Semaphore;
      end Init;

      procedure Add_Task (Self : Thread_Pool; Proc : Task_Proc; Context : Threading_Proc_Context) is
      begin
         Self.Semaphore.Increment;
         Self.Array_Threads_Inst (Context.Worker_Index).Run (Self, Proc, Context);
      end Add_Task;

      procedure Wait (Self : Thread_Pool) is
      begin
         Self.Semaphore.Wait;
      end Wait;

      task body Thread is
         Ref_Pool : Thread_Pool;
         Ref_Proc : Task_Proc := null;
         Ref_Context : Threading_Proc_Context;
      begin
         loop
            select
               accept Run (Pool : Thread_Pool; Proc : Task_Proc; Context : Threading_Proc_Context) do
                  Ref_Pool := Pool;
                  Ref_Proc := Proc;
                  Ref_Context := Context;
               end Run;
               Ref_Proc (Ref_Context);
               Ref_Pool.Semaphore.Decrement;
            or
               terminate;
            end select;
         end loop;
      end Thread;

      protected body Counter_Semaphore is
         entry Wait when Counter = 0 is
         begin
            null;
         end Wait;

         procedure Increment is
         begin
            Counter := Counter + 1;
         end Increment;

         procedure Decrement is
         begin
            Counter := Counter - 1;
         end Decrement;
      end Counter_Semaphore;
   end Threading;

   procedure Print_Array (Elements : Array_Elements_Access) is
      NoPrint : constant Boolean := Ada.Environment_Variables.Exists ("NOPRINT");
   begin
      if NoPrint then
         return;
      end if;

      for I in Elements'Range loop
         Ada.Text_IO.Put (Elements (I)'Image);
      end loop;
      Ada.Text_IO.New_Line;
   end Print_Array;

   procedure Run_Wave (Context : Threading_Proc_Context) is
      pragma Suppress (Overflow_Check);
      I : Long_Long_Integer := Context.Worker_Index;
   begin
      while I < Context.Elements_Size / 2 loop
         Context.Elements (I) := Context.Elements (I) + Context.Elements (Context.Elements_Size - 1 - I);
         I := I + Context.Total_Workers;
      end loop;
   end Run_Wave;

   procedure Solve_Multicore (Elements : Array_Elements_Access; Num_Threads : Natural) is
      Pool : Threading.Thread_Pool;
      Context : Threading_Proc_Context;
      Elements_Size : Long_Long_Integer := Elements'Length;
   begin
      Threading.Init (Pool, Num_Threads => Num_Threads);
      while Elements_Size > 1 loop
         for I in 0 .. Num_Threads - 1 loop
            Context.Elements := Elements;
            Context.Elements_Size := Elements_Size;
            Context.Worker_Index := Long_Long_Integer (I);
            Context.Total_Workers := Long_Long_Integer (Num_Threads);
            Threading.Add_Task (Pool, Run_Wave'Access, Context);
         end loop;
         Threading.Wait (Pool);
         Elements_Size := (Elements_Size + 1) / 2;
         Print_Array (Elements);
      end loop;
   end Solve_Multicore;

   procedure Solve_Singlecore (Elements : Array_Elements_Access) is
      Context : Threading_Proc_Context;
      Elements_Size : Long_Long_Integer := Elements'Length;
   begin
      while Elements_Size > 1 loop
         Context.Elements := Elements;
         Context.Elements_Size := Elements_Size;
         Context.Worker_Index := 0;
         Context.Total_Workers := 1;
         Run_Wave (Context);
         Elements_Size := (Elements_Size + 1) / 2;
         Print_Array (Elements);
      end loop;
   end Solve_Singlecore;

   function Checksum (Elements : Array_Elements_Access) return Long_Long_Integer is
      pragma Suppress (Overflow_Check);
      Result : Long_Long_Integer := 0;
   begin
      for I in Elements'Range loop
         Result := Result + Elements (I);
      end loop;
      return Result;
   end Checksum;

   Elements : Array_Elements_Access := null;
   Elements_Size : Long_Long_Integer;
   Num_Threads : Natural;
   Correct_result : Long_Long_Integer;
   Start_Time, End_Time : Ada.Calendar.Time;
   milliS : Integer;
   Is_Singlecore_Set : constant Boolean := Ada.Environment_Variables.Exists ("SINGLECORE");
begin
   Num_Threads := 8;
   Elements_Size := 8;

   if Ada.Environment_Variables.Exists ("N") then
      declare
         Value_String : constant String := Ada.Environment_Variables.Value ("N");
         N_Value : Long_Long_Integer := 0;
      begin
         if Value_String'Length > 0 then
            N_Value := Long_Long_Integer'Value (Value_String);
         end if;
         if N_Value > 0 then
            Elements_Size := N_Value;
         end if;
      end;
   end if;

   Ada.Text_IO.Put_Line ("Генерація масиву розміром " & Elements_Size'Image & "");
   Elements := new Array_Elements (0 .. Elements_Size - 1);

   for I in Elements'Range loop
      Elements (I) := Long_Long_Integer (I + 1);
   end loop;

   Correct_result := Checksum (Elements);
   Print_Array (Elements);

   Start_Time := Ada.Calendar.Clock;

   if Is_Singlecore_Set then
      Ada.Text_IO.Put_Line ("Обчислення одним потоком");
      Solve_Singlecore (Elements);
   else
      Ada.Text_IO.Put_Line ("Обчислення за допомогою потоків по к-ті ядер");
      Solve_Multicore (Elements, Num_Threads);
   end if;

   End_Time := Ada.Calendar.Clock;
   milliS := Integer ((End_Time - Start_Time) * 1000);

   Ada.Text_IO.Put_Line ("Обчислення відбувалося протягом " & milliS'Image & " мілісекунд");
   Ada.Text_IO.Put_Line ("Результат першого обчислення: " & Correct_result'Image);
   Ada.Text_IO.Put_Line ("Результат другого обчислення: " & Elements (0)'Image);
end adaLr;