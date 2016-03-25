(*
    Copyright David C. J. Matthews 2010, 2012, 2016

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License version 2.1 as published by the Free Software Foundation.
    
    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.
    
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*)

signature X86CODESIG =
sig
    type machineWord = Address.machineWord
    type short = Address.short
    type address = Address.address

    type code

    val sameCode: code * code -> bool

    datatype genReg = GeneralReg of Word8.word * bool
    and fpReg = FloatingPtReg of Word8.word
    
    datatype reg =
        GenReg of genReg
    |   FPReg of fpReg

    val isX64: bool

    val eax: genReg and ebx: genReg and ecx: genReg and edx: genReg
    and edi: genReg and esi: genReg and esp: genReg and ebp: genReg
    and r8:  genReg and r9:  genReg and r10: genReg and r11: genReg
    and r12: genReg and r13: genReg and r14: genReg and r15: genReg
    and fp0: fpReg and fp1: fpReg and fp2: fpReg and fp3: fpReg
    and fp4: fpReg and fp5: fpReg and fp6: fpReg and fp7: fpReg
    (* For vector indexing we provide a numbering for the registers. *)
    val regs:   int
    val regN:   int -> reg
    val nReg:   reg -> int

    val regRepr: reg -> string
    
    type addrs and labList
    val addrZero: addrs

    structure RegSet:
    sig
        eqtype regSet
        val singleton: reg -> regSet
        val allRegisters: regSet (* All registers: data, address, floating pt. *)
        val generalRegisters: regSet (* Registers checked by the GC. *)
        val floatingPtRegisters: regSet
        val noRegisters: regSet
        val isAllRegs: regSet->bool
        val regSetUnion: regSet * regSet -> regSet
        val regSetIntersect: regSet * regSet -> regSet
        val listToSet: reg list -> regSet
        val setToList: regSet -> reg list
        val regSetMinus: regSet * regSet -> regSet
        val inSet: reg * regSet -> bool
        val cardinality: regSet -> int
        val regSetRepr: regSet -> string
        val oneOf: regSet -> reg
    end

    datatype arithOp = ADD | OR (*|ADC | SBB*) | AND | SUB | XOR | CMP
    and      shiftType = SLL | SRL | SRA
    and      repOps = CMPSB | MOVSB | MOVSL | STOSB | STOSL
    and      fpOps = FADD | FMUL | FCOM | FCOMP | FSUB | FSUBR | FDIV | FDIVR
    and      fpUnaryOps = FABS | FCHS | FSQRT | FSIN | FCOS | FPATAN | FLD1 | FLDZ
    and      group3Ops = NOT | NEG | MUL | IMUL | DIV | IDIV

    datatype branchOps = JO | JNO | JE | JNE | JL | JGE | JLE | JG | JB | JNB | JNA | JA

    datatype callKinds =
        Recursive
    |   ConstantClosure of machineWord
    |   ConstantCode of machineWord
    |   FullCall
    |   DirectReg of genReg

    datatype label =
        Labels of
        {
            forward: labList ref,
            reverse: addrs ref,
            labId: int ref,
            uses: int ref,
            chain: label option ref
        }

    val mkLabel: unit -> label

    datatype indexType =
        NoIndex | Index1 of genReg | Index2 of genReg | Index4 of genReg | Index8 of genReg

    datatype memoryAddress =
        BaseOffset of { base: genReg, offset: int, index: indexType }
    |   ConstantAddress of machineWord

    datatype branchPrediction = PredictNeutral | PredictTaken | PredictNotTaken

    datatype operation =
        MoveRR of { source: genReg, output: genReg }
    |   MoveConstR of { source: LargeInt.int, output: genReg }
    |   MoveConstFPR of { source: LargeInt.int, output: fpReg }
    |   MoveLongConstR of { source: machineWord, output: genReg }
    |   LoadMemR of { source: memoryAddress, output: genReg }
    |   LoadByteR of { source: memoryAddress, output: genReg }
    |   PushR of genReg
    |   PushConst of LargeInt.int
    |   PushLongConst of machineWord
    |   PushMem of { base: genReg, offset: int }
    |   PopR of genReg
    |   ArithRR of { opc: arithOp, output: genReg, source: genReg }
    |   ArithRConst of { opc: arithOp, output: genReg, source: LargeInt.int }
    |   ArithRLongConst of { opc: arithOp, output: genReg, source: machineWord }
    |   ArithRMem of { opc: arithOp, output: genReg, offset: int, base: genReg }
    |   ArithMemConst of { opc: arithOp, offset: int, base: genReg, source: LargeInt.int }
    |   ArithMemLongConst of { opc: arithOp, offset: int, base: genReg, source: machineWord }
    |   ShiftConstant of { shiftType: shiftType, output: genReg, shift: Word8.word }
    |   ShiftVariable of { shiftType: shiftType, output: genReg } (* Shift amount is in ecx *)
    |   ConditionalBranch of { test: branchOps, label: label, predict: branchPrediction }
    |   LockMutableSegment of genReg
    |   LoadAddress of { output: genReg, offset: int, base: genReg option, index: indexType }
    |   TestTagR of genReg
    |   TestByteMem of { base: genReg, offset: int, bits: word }
    |   CallRTS of int
    |   StoreRegToMemory of { toStore: genReg, address: memoryAddress }
    |   StoreConstToMemory of { toStore: LargeInt.int, address: memoryAddress }
    |   StoreLongConstToMemory of { toStore: machineWord, address: memoryAddress }
    |   StoreByteRegToMemory of { toStore: genReg, address: memoryAddress }
    |   StoreByteConstToMemory of { toStore: Word8.word, address: memoryAddress }
    |   AllocStore of { size: int, output: genReg, saveRegs: genReg list }
    |   AllocStoreVariable of { output: genReg, saveRegs: genReg list }
    |   StoreInitialised
    |   CallFunction of callKinds
    |   JumpToFunction of callKinds
    |   ReturnFromFunction of int
    |   RaiseException
    |   UncondBranch of label
    |   ResetStack of int
    |   InterruptCheck
    |   JumpLabel of label
    |   TagValue of { source: genReg, output: genReg }
        (* Some of these operations are higher-level and should be reduced. *)
    |   LoadHandlerAddress of { handlerLab: addrs ref, output: genReg }
    |   StartHandler of { handlerLab: addrs ref }
    |   IndexedCase of { testReg: genReg, workReg: genReg, min: word, cases: label list }
    |   FreeRegisters of RegSet.regSet
    |   MakeSafe of genReg
    |   RepeatOperation of repOps
    |   Group3Ops of genReg * group3Ops
    |   AtomicXAdd of {base: genReg, output: genReg}
    |   FPLoadFromGenReg of genReg
    |   FPLoadFromFPReg of { source: fpReg, lastRef: bool }
    |   FPLoadFromConst of real
    |   FPStoreToFPReg of { output: fpReg, andPop: bool }
    |   FPStoreToMemory of { base: genReg, offset: int, andPop: bool }
    |   FPArithR of { opc: fpOps, source: fpReg }
    |   FPArithConst of { opc: fpOps, source: machineWord }
    |   FPArithMemory of { opc: fpOps, base: genReg, offset: int }
    |   FPUnary of fpUnaryOps
    |   FPStatusToEAX
    |   FPLoadIntAndPop
    |   FPFree of fpReg
    |   PreAddDetag of genReg
    |   TestOverflow
    |   SignedMultiply of { source: genReg, output: genReg }

    type operations = operation list
    val printOperation: operation * (string -> unit) -> unit

    val codeCreate: string * machineWord * Universal.universal list -> code  (* makes the initial segment. *)
    (* Code generate operations and construct the final code. *)
    val createCodeSegment: operations * code -> address

    val procName:   code -> string      (* Name of the procedure. *)

    val memRegLocalMPointer: int
    and memRegHandlerRegister: int
    and memRegLocalMbottom: int
    and memRegRaiseOverflow: int
    and memRegThreadSelf: int
    and memRegStackLimit: int
    and memRegStackOverflowCall: int
    and memRegStackOverflowCallEx: int
    and memRegSize: int

    val argLocalMpointer: int
    and argLocalMbottom: int
    and argExceptionPacket: int

    (* Debugging controls and streams for optimiser. *)
    val lowLevelOptimise: code -> bool
    val printLowLevelCode: operation list * code -> unit

    structure Sharing:
    sig
        type code           = code
        and  reg            = reg
        and  genReg         = genReg
        and  fpReg          = fpReg
        and  addrs          = addrs
        and  operation      = operation
        and  regSet         = RegSet.regSet
        and  label          = label
        and  labList        = labList
    end
end;
