(*
    Copyright David C. J. Matthews 2009
    Largely extracted from STRUCTURES_.ML

    Copyright (c) 2000
        Cambridge University Technical Services Limited
        
    Modified D.C.J. Matthews 2001-2009

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.
    
    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.
    
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*)

(*
    Title:      Module Structure and Operations.
    Author:     Dave Matthews, Cambridge University Computer Laboratory
    Copyright   Cambridge University 1985
*)

functor SIGNATURES (
    structure LEX : LEXSIG
    structure STRUCTVALS : STRUCTVALSIG;
    structure EXPORTTREE: EXPORTTREESIG
    structure PRETTY : PRETTYSIG
    structure COPIER: COPIERSIG
    structure TYPETREE : TYPETREESIG
    structure PARSETREE : PARSETREESIG
    structure VALUEOPS : VALUEOPSSIG;

    structure UNIVERSALTABLE:
    sig
        type universal = Universal.universal
        type univTable
        type 'a tag = 'a Universal.tag

        val univEnter:  univTable * 'a tag * string * 'a -> unit;
        val univLookup: univTable * 'a tag * string -> 'a option;
        val univFold:   univTable * (string * universal * 'a -> 'a) * 'a -> 'a;
    end;

    structure DEBUG :
    sig
        val errorDepthTag : int Universal.tag
        val getParameter :
               'a Universal.tag -> Universal.universal list -> 'a 
    end;

    structure UTILITIES :
    sig
        val noDuplicates: (string * 'a * 'a -> unit) -> 
             { apply: (string * 'a -> unit) -> unit,
               enter:  string * 'a -> unit,
               lookup: string -> 'a option };

        val searchList: unit -> { apply: (string * 'a -> unit) -> unit,
                                enter:  string * 'a -> unit,
                                lookup: string -> 'a option };
    end;

    sharing LEX.Sharing = TYPETREE.Sharing = PARSETREE.Sharing
        = PRETTY.Sharing = EXPORTTREE.Sharing = STRUCTVALS.Sharing = COPIER.Sharing
        = VALUEOPS.Sharing = UNIVERSALTABLE

) : SIGNATURESSIG =
struct
    open Misc (* Open this first because it contains Value. *)
    open LEX STRUCTVALS EXPORTTREE PRETTY COPIER TYPETREE PARSETREE UNIVERSALTABLE DEBUG
    open VALUEOPS UTILITIES Universal

    datatype sigs =
        SignatureIdent of string * location * location option ref  (* A signature name *)

    |   SigDec         of specs list * location (* sig ... end *)

    |   WhereType      of whereTypeStruct    (* type realisation. *)

    and specs =
        StructureSig   of structSigBind list * location

    |   ValSig         of (* Signature of a value. *)
            { name: string * location, typeof: typeParsetree, line: location }

    |   ExSig          of (* Signature of an exception.  May be a nullary exception. *)
            { name: string * location, typeof: typeParsetree option, line: location }

    |   CoreType      of (* Any other decln. *)
        {
            dec:   parsetree,           (* The value *)
            location: location
        }

    |   Sharing        of shareConstraint    (* Sharing constraints. *)

    |   IncludeSig     of sigs list * location       (* Include. *)

  withtype shareConstraint =
      {
        isType: bool,
        shares: (string * location) list,
        line:   location
      }

  and structSigBind =
      {
        name:      string,         (* The name of the structure *)
        nameLoc:   location,
        sigStruct: sigs * bool * location,
        line:      location
      }

  and whereTypeStruct =
      {
        sigExp: sigs,
        typeVars: typeVarForm list,
        typeName: string,
        realisation: types,
        line: location
      }

    fun mkSigIdent(name, nameLoc) = SignatureIdent(name, nameLoc, ref NONE);
  
    fun mkCoreType (dec, location) =
        CoreType { dec = dec, location = location };
  
    fun mkValSig (nameLoc, typeof, line) = 
      ValSig 
        {
          name    = nameLoc,
          typeof  = typeof,
          line    = line
        };
  
    fun mkExSig (nameLoc, typeof, line) = 
       ExSig
        {
          name    = nameLoc,
          typeof  = typeof,
          line    = line
        };
  
    fun mkSharing (isType, shares, line) = 
        Sharing {
          isType = isType,
          shares = shares,
          line   = line
        };

    fun mkWhereType (sigexp, typeVars, name, types, line) = 
        WhereType {
          sigExp      = sigexp,
		  typeVars    = typeVars,
          typeName    = name,
          realisation = types,
          line        = line
        };

	val mkInclude = IncludeSig
    and mkStructureSig = StructureSig
    and mkSig = SigDec

    fun mkStructureSigBinding ((name, nameLoc), signat, fullLoc):structSigBind  =
        {
            name      = name,
            nameLoc   = nameLoc,
            sigStruct = signat,
            line      = fullLoc
        }

    (* Make a signature for initialisating variables and for
       undeclared signature variables. *)
    val noLocation =
        { file="", startLine=0, startPosition=0, endLine=0, endPosition=0 }
    val undefinedSignature =
       makeSignature("UNDEFINED", makeSignatureTable(),
                0, 0, noLocation, fn _ => raise Subscript, []);

    fun displayList ([], _, _) _ = []
    
    |   displayList ([v], _, depth) dodisplay =
            if depth <= 0
            then [PrettyString "..."]
            else [dodisplay (v, depth)]
      
    |   displayList (v::vs, separator, depth) dodisplay =
            if depth <= 0
            then [PrettyString "..."]
            else
            let
                val brk = if separator = "," orelse separator = ";" then 0 else 1
            in
                PrettyBlock (0, false, [],
                    [
                        dodisplay (v, depth),
                        PrettyBreak (brk, 0),
                        PrettyString separator
                    ]
                ) ::
                PrettyBreak (1, 0) ::
                displayList (vs, separator, depth - 1) dodisplay
            end (* displayList *)

    val displayType = TYPETREE.display;

    fun displaySigs (str, depth) =
        if depth <= 0 (* elide further text. *)
        then PrettyString "..."

        else
        case str of
           SignatureIdent (name : string, _, _) =>
            PrettyString name

        |   SigDec (structList : specs list, _) =>
            PrettyBlock (1, true, [],
                PrettyString "sig" ::
                PrettyBreak (1, 0) ::
                displayList (structList, "", depth) displaySpecs @
                [ PrettyBreak (1, 0), PrettyString "end"]
            )

        |   WhereType { sigExp, typeVars, typeName, realisation, ... } =>
            PrettyBlock (3, false, [],
                displaySigs (sigExp, depth) ::
                PrettyBreak (1, 0) ::
                PrettyString "where" ::
                PrettyBreak (1, 0) ::
                PrettyString "type" ::
                PrettyBreak (1, 0) ::
                displayTypeVariables (typeVars, depth) @
                [
                    PrettyString typeName,
                    PrettyBreak (1, 0),
                    PrettyString "=",
                    PrettyBreak (1, 0),
                    displayType (realisation, depth - 1, emptyTypeEnv)
                ]
            )

    and displaySpecs (specs, depth) =
        if depth <= 0 (* elide further text. *)
        then PrettyString "..."

        else
        case specs of
            StructureSig (structList : structSigBind list, _) =>
            let
                    fun displaySigsBind (
                            {name, sigStruct=(sigStruct, opaque, _), ...}: structSigBind, depth) =
                        PrettyBlock (3, false, [],
                            [
                                PrettyString name,
                                PrettyString (if opaque then " :>" else " :"),
                                PrettyBreak (1, 0),
                                displaySigs (sigStruct, depth - 1)
                            ]
                        )
            in
                PrettyBlock (3, false, [],
                    PrettyString "structure" ::
                    PrettyBreak (1, 0) ::
                    displayList (structList, "and", depth) displaySigsBind
                )
            end

        |   ValSig {name = (name, _), typeof, ...} =>
            PrettyBlock (0, false, [],
                [
                    PrettyString "val",
                    PrettyBreak (1, 1),
                    PrettyString (name ^ " :"),
                    PrettyBreak (1, 0),
                    displayType (typeFromTypeParse typeof, depth - 1, emptyTypeEnv)
                ]
            )

        |   ExSig {name = (name, _), typeof = NONE, ...} =>
            PrettyBlock (0, false, [],
                [
                    PrettyString "exception",
                    PrettyBreak (1, 1),
                    PrettyString (name)
                ]
            )
 
        |   ExSig {name = (name, _), typeof = SOME typeof, ...} =>
            PrettyBlock (0, false, [],
                [
                    PrettyString "exception",
                    PrettyBreak (1, 1),
                    PrettyString (name ^ " :"),
                    PrettyBreak (1, 0),
                    displayType (typeFromTypeParse typeof, depth - 1, emptyTypeEnv)
                ]
            )

        |   Sharing { isType, shares, ... } =>
            PrettyBlock (3, false, [],
                PrettyString "sharing" ::
                PrettyBreak (1, 0) ::
                (
                    if not isType then []
                    else [ PrettyString "type", PrettyBreak (1, 0) ]
                ) @
                displayList (shares, "=", depth) (fn ((name, _), _) => PrettyString name)
            )

        |   IncludeSig (structList : sigs list, _) =>
            PrettyBlock (3, true, [],
                PrettyString "include" ::
                PrettyBreak (1, 0) ::
                displayList (structList, "", depth - 1) displaySigs
            )

        |   CoreType {dec, ...} =>
                ptDisplay (dec, depth - 1)
      (* End displaySigs *)

    fun sigExportTree(navigation, s: sigs) =
    let
         (* Common properties for navigation and printing. *)
        val commonProps =
            PTprint(fn d => displaySigs(s, d)) ::
            exportNavigationProps navigation

        fun asParent () = sigExportTree(navigation, s)
    in
        case s of
            SignatureIdent(_, loc, ref decLoc) =>
                (loc,
                    (case decLoc of NONE => [] | SOME decl => [PTdeclaredAt decl]) @ commonProps)

        |   SigDec(structList, location) =>
                (location, exportList(specExportTree, SOME asParent) structList @ commonProps)

        |   WhereType _ => (nullLocation, commonProps)
    end
 
    and specExportTree(navigation, s: specs) =
    let
         (* Common properties for navigation and printing. *)
        val commonProps =
            PTprint(fn d => displaySpecs(s, d)) ::
            exportNavigationProps navigation

        fun asParent () = specExportTree(navigation, s)
    in
        case s of
            StructureSig(sbl, location) =>
            let
                fun exportSB(navigation, sb as {name, nameLoc, sigStruct=(theSig, _, _), line, ...}) =
                    let
                        fun exportThis () = exportSB(navigation, sb)
                        fun getName () =
                            getStringAsTree({parent=SOME exportThis, previous=NONE, next=SOME getSigStruct}, name, nameLoc, [])
                        
                        and getSigStruct () =
                            sigExportTree({parent=SOME exportThis, previous=SOME getName, next=NONE}, theSig)
                    in
                        (line, PTfirstChild getName :: exportNavigationProps navigation)
                    end

                val expChild = exportList(exportSB, SOME asParent) sbl
            in
                (location, expChild @ commonProps)
            end

        |   ValSig{name=(name, nameLoc), typeof, line, ...} =>
            let
                (* The first position is the value name, the second the type. *)
                (* TODO: Include the actual type as PTtype? *)
                fun getName () =
                    getStringAsTree({parent=SOME asParent, previous=NONE, next=SOME getType}, name, nameLoc, [])
                and getType () =
                    typeExportTree({parent=SOME asParent, previous=SOME getName, next=NONE}, typeof)
            in
                (line, PTfirstChild getName :: commonProps)
            end

        |   ExSig{name=(name, nameLoc), typeof = NONE, line, ...} =>
            let
                (* The first position is the value name, the second the type. *)
                fun getName () =
                    getStringAsTree({parent=SOME asParent, previous=NONE, next=NONE}, name, nameLoc, [])
            in
                (line, PTfirstChild getName :: commonProps)
            end

        |   ExSig{name=(name, nameLoc), typeof = SOME typeof, line, ...} =>
            let
                (* The first position is the value name, the second the type. *)
                (* TODO: Include the actual type as PTtype? *)
                fun getName () =
                    getStringAsTree({parent=SOME asParent, previous=NONE, next=SOME getType}, name, nameLoc, [])
                and getType () =
                    typeExportTree({parent=SOME asParent, previous=SOME getName, next=NONE}, typeof)
            in
                (line, PTfirstChild getName :: commonProps)
            end

        |   CoreType {dec, ...} => (* A value parse-tree entry. *)
                getExportTree(navigation, dec)

        |   Sharing _ => (nullLocation, commonProps)

        |   IncludeSig (sigs, loc) =>
                (loc, exportList(sigExportTree, SOME asParent) sigs @ commonProps)
    end

    (* Puts out an error message and then prints the piece of tree. *)
    fun errorMsgNear (lex, hard, near, lno, message) : unit =
    let
        val parameters = debugParams lex
        val errorDepth = getParameter errorDepthTag parameters
    in
        reportError lex
        {
            hard = hard, location = lno, message = message,
            context = SOME(near errorDepth)
        }
    end

    fun errorNear(lex, hard, near, lno, message: string) =
        errorMsgNear (lex, hard, near, lno,
            PrettyBlock (0, false, [], [PrettyString message]))

    fun giveError (sVal : sigs, lno : LEX.location, lex : lexan) : string -> unit =
        fn (message : string) => errorNear (lex, true, fn n => displaySigs(sVal, n), lno, message)

    and giveSpecError(sVal : specs, lno : LEX.location, lex : lexan) : string -> unit =
        fn (message : string) => errorNear (lex, true, fn n => displaySpecs(sVal, n), lno, message);

    val makeEnv = fn x => let val Env e = makeEnv x in e end;

    fun printId(Free{description, ...}) = printDesc description
    |   printId(Bound{description, ...}) = printDesc description
    |   printId(TypeFunction(_, typeResult)) =
            display(typeResult, 10000, emptyTypeEnv)

    and printDesc{ location: location, name: string, description = "" } =
            PrettyBlock(0, false, [ContextLocation location], [PrettyString name])
    |   printDesc{ location: location, name: string, description: string } =
            PrettyBlock(0, false, [ContextLocation location],
                [PrettyString name, PrettyBreak(1, 0), PrettyString ("(*" ^ description ^ "*)")])

    (* Formal paramater to a functor - either value or exception. *)
    fun mkFormal (name : string, class, typ, addr, locations) =
  	    Value{class=class, name=name, typeOf=typ, access=Formal addr, locations=locations, references = NONE}

      (* Get the value from a signature-returning expression
         (either the name of a signature or sig ... end.
         The type IDs in the signature are bound names. *)
    fun sigVal(str           : sigs,
             initTypeId    : int,
             outerTypeIdEnv: int->typeId,
             Env globalEnv : env,
             lex,
             lno           : LEX.location
            ) : signatures =
    let
        datatype varId =
            SharedWith of int (* Index of shared ID, always less than current index. *)
        |   VariableSlot of { boundId: typeId, descriptions: string list }
        |   FreeSlot of typeId (* Bound to a Free type ID. *)
        |   Unset

        val idCount = ref initTypeId
        val mapArray = StretchArray.stretchArray(10 (* Guess initial size. *), Unset)
        val sourceArray = StretchArray.stretchArray(10 (* Guess initial size. *), NONE)

        fun makeVariableId(isEq, isDt, requireUpdate, { location, name, description }, structPath) =
        let
            val fullName = structPath^name
            val descr = { location=location, name=fullName, description=description}
            (* Make a new bound ID after any existing ones. *)
            val newIdNumber = !idCount before (idCount := !idCount+1)
            val newId =
                (if requireUpdate then makeBoundIdWithEqUpdate else makeBoundId)
                    (Formal 0 (* Not used. *), newIdNumber, isEq, isDt, descr)
            (* Enter a variable entry in the array. *)
            val arrayEntry = VariableSlot{ boundId=newId, descriptions = [fullName] }
            val () = StretchArray.update(mapArray, newIdNumber-initTypeId, arrayEntry)
            val () = StretchArray.update(sourceArray, newIdNumber-initTypeId, SOME newId)
        in
            newId
        end

        (* Follow a chain of shared IDs.  This should terminate because we always
           point down the array. *)
        fun realId n =
            case StretchArray.sub(mapArray, n) of
                SharedWith m =>
                    if m >= n
                    then raise InternalError "realId: Sharing loop"
                    else realId m
            |   id => id

        fun isVariableId(Bound{offset, ...}) =
            if offset < initTypeId then false (* Outside the signature. *)
            else
            (
                case realId(offset-initTypeId) of
                    VariableSlot _ => true
                |   FreeSlot _ => false
                |   _ => raise InternalError "isVar"
            )
        |   isVariableId _ (* Free or TypeFunction *) = false

        (* The internal type ID map after mapping to the internal Bound IDs but before the application of
           any "where types" or sharing. *)
        fun typeIdEnv () =
        let
            val v = Vector.tabulate(!idCount-initTypeId, fn n => valOf(StretchArray.sub(sourceArray, n)))
        in
            fn n =>
                if n < initTypeId
                then outerTypeIdEnv n
                else Vector.sub(v, n-initTypeId)
        end
        
        fun linkFlexibleTypeIds(typeId1, typeId2) =
        (* Link together and share two IDs.  The result is an equality type if either
           was an equality type and a datatype if either was a datatype. *)
        case (typeId1, typeId2) of
            (Bound{offset=offset1, ...}, Bound{offset=offset2, ...}) =>
        (
            case (realId(offset1-initTypeId), realId(offset2-initTypeId)) of
                (VariableSlot{descriptions = desc1,
                              boundId=Bound{eqType=eqType1, offset=off1, isDatatype=isDatatype1, description, ...}},
                 VariableSlot{descriptions = desc2,
                              boundId=Bound{eqType=eqType2, offset=off2, isDatatype=isDatatype2, ...}}) =>
            if off1 = off2
            then () (* They may already share. *)
            else
            let
                val resOffset = Int.min(off1, off2)
                val setOffset = Int.max(off1, off2)
                val isDatatype = isDatatype1 orelse isDatatype2
                val newId =
                    makeBoundId(Formal 0, resOffset, pling eqType1 orelse pling eqType2, isDatatype, description (* Not used *))
                val newEntry =
                    VariableSlot{ boundId=newId, descriptions = desc1 @ desc2 }
            in
                StretchArray.update(mapArray, resOffset-initTypeId, newEntry);
                StretchArray.update(mapArray, setOffset-initTypeId, SharedWith(resOffset-initTypeId))
            end
            |   _ => raise InternalError "linkFlexibleTypeIds: not variable"
        )
        |   _ => raise InternalError "linkFlexibleTypeIds: not bound"

        local (* Sharing *)
            fun shareTypes(typeA, aPath, aMap, typeB, bPath, bMap, lno, nearStruct) =
            let
                fun cantShare reason =
                let
                    fun showTypeCons(t, p) =
                    let
                        val context =
                            case List.find(fn DeclaredAt _ => true | _ => false) (tcLocations t) of
                                SOME(DeclaredAt loc) => [ContextLocation loc]
                            |   _ => []
                    in
                        PrettyBlock(0, false, context, [PrettyString(p ^ tcName t)])
                    end
                in
                    errorMsgNear (lex, true, fn n => displaySigs(nearStruct, n), lno,
                        PrettyBlock(3, false, [],
                            [
                                PrettyString "Cannot share type",
                                PrettyBreak(1, 2),
                                showTypeCons(typeA, aPath),
                                PrettyBreak(1, 0),
                                PrettyString "with type",
                                PrettyBreak(1, 0),
                                showTypeCons(typeB, bPath),
                                PrettyBreak(0, 0),
                                PrettyString ".",
                                PrettyBreak(1, 0),
                                reason
                            ]))
                end
 
                fun alreadyBound(path, typeName, tcId) =
                    cantShare (
                        PrettyBlock(3, false, [],
                            [
                                PrettyString(path ^ typeName),
                                PrettyBreak(1, 0),
                                PrettyString "is already defined as",
                                PrettyBreak(1, 0),
                                printId tcId
                            ]))
            in
                if isUndefinedTypeConstr typeA orelse isUndefinedTypeConstr typeB
                then ()
                else if tcArity typeA <> tcArity typeB (* Check arity. *)
                then cantShare(PrettyString "The type constructors take different numbers of arguments.")
                else
                let
                    fun mapId (map, Bound{offset, ...}) = map offset
                    |   mapId (_, id) = id
                    val aId = mapId(aMap, tcIdentifier typeA)
                    and bId = mapId(bMap, tcIdentifier typeB)
                in
                    (* The type constructors are only looked up in the signature but they
                       already may be set to another type through a "where type" or they may
                       have been created with Free IDs through type t=s declarations.  This
                       could be a free identifier or a type function.  *)
                    if not (isVariableId aId)
                    then alreadyBound(aPath, tcName typeA, aId)
                    else if not (isVariableId bId)
                    then alreadyBound(bPath, tcName typeB, bId)
                    else linkFlexibleTypeIds(aId, bId)
                end
            end (* shareTypes *);

            (* Find all the structures and type constructors in one structure. *)
            fun structsAndTypes((structVal, path, oldMap), start) =
            let
                val Signatures { tab, typeIdMap, ... } = structSignat structVal
                val newMap = composeMaps(typeIdMap, oldMap)
                fun get(name, dVal, (ts, ss)) =
                    if tagIs structVar dVal
                    then (ts, (name, (tagProject structVar dVal, path ^ name ^ ".", newMap)) :: ss)
                    else if tagIs typeConstrVar dVal
                    then ((name, (tagProject typeConstrVar dVal, path, newMap)) :: ts, ss)
                    else (ts, ss)
            in
                univFold (tab, get, start)
            end

            (* Get all the structures and type constructors in a list of structures. *)
            fun allStructsAndTypes structs = List.foldl structsAndTypes ([], []) structs

            (* Turn a list of names and structures/types into a list of lists. Each entry in
               the result list is all those structures/types with the same name. *)
            fun getMatchedEntries entries =
            let
                (* Sort the items so that items with the same name are brought together.
                   A signature is not allowed to have items of the same kind with the
                   same name so this means that we are bringing together items from
                   different structures.  Then filter the result to produce sets of items
                   with the same name.  Discard singletons in the result. *)
                val sortedEntries = quickSort (fn (s1, _) => fn (s2, _) => s1 <= s2) entries
                (* *)
                fun getEquals([], _, [], res) = res (* End of empty list. *)
                |   getEquals([], _, [_], res) = res (* Last item was singleton: discard *)
                |   getEquals([], _, acc, res) = acc :: res (* Return last item. *)

                |   getEquals((s, t) :: r, a: string, acc, res) =
                        if a = s then getEquals(r, a, t :: acc, res) (* Same name as last item. *)
                        else case acc of (* Different from last item: *)
                            [] => getEquals(r, s, [t], res) (* No previous item. *)
                       |    [_] => getEquals(r, s, [t], res) (* Last was singleton: discard. *)
                       |    acc => getEquals(r, s, [t], acc :: res)
            in
                getEquals(sortedEntries, "", [], [])
            end

            (* Recursively apply the sharing constraints to corresponding types in a list of
               structures. *)
            fun structureSharing(structs, line, near) =
            let
                fun shareStructs structs =
                let
                    val (allTypes, allSubstructs) = allStructsAndTypes structs
                    (* Get the lists of structures and types to share. *)
                    val matchedTypes = getMatchedEntries allTypes
                    val matchedStructs = getMatchedEntries allSubstructs
                in
                    List.app(fn types => (* Share types. *)
                        case types of
                            [] => raise List.Empty
                        |   (hd, hdName, hdMap) :: tl => (* Share the rest of the list with the first item. *)
                                List.app(fn (t, tName, tMap) =>
                                    shareTypes(hd, hdName, hdMap, t, tName, tMap, line, near)) tl) matchedTypes;
                    List.app shareStructs matchedStructs (* Recursively share sub-structures. *)
                end
            in
                shareStructs(List.map(fn s => (s, structName s ^ ".", typeIdEnv())) structs)
            end
        in

            (* Process a sharing constraint. *)
            fun applySharingConstraint({shares, isType, line}, Env tEnv, near) : unit =
            let
                (* When looking up the structure and type names we look only
                   in the signature in ML97.  We add this to make it clear that
                   we are only looking up in the signature otherwise we get
                   confusing messages such as "type (int) has not been declared". *)
                fun lookupFailure locn msg =
                     giveError (str, locn, lex) (msg ^ " in signature.")
            in
                if isType
                then
                let (* Type sharing. *)
                    fun lookupSharing (name, locn) = 
                    lookupTyp
                       ({ 
                          lookupType   = #lookupType   tEnv,
                          lookupStruct = #lookupStruct tEnv
                        },
                        name, lookupFailure locn)
                in
                    case shares of
                        nil => raise Empty
                    |   hd :: tl =>
                        let
                            val first  = lookupSharing hd
                        in
                            if isUndefinedTypeConstr first
                            then ()
                            else List.app (fn typ =>
                                    shareTypes (lookupSharing typ, "", typeIdEnv(), first, "", typeIdEnv(), line, near)) tl
                        end
                end
                else
                let (* structure sharing. *)
                    fun getStruct(name, locn) = lookupStructureAsSignature (#lookupStruct tEnv, name, lookupFailure locn)
                in  (* Now share all these signatures. *)
                    structureSharing(map getStruct shares, line, near)
                end
            end (* applySharingConstraint *)
        end (* Sharing *)

        (* Look up a signature.  Signatures can only be in the global environment. *)
        fun lookSig (name : string, lno : LEX.location) : signatures =
            case #lookupSig globalEnv name of
                SOME v => v
            |   NONE =>
                    (
                        giveError (str, lno, lex)("Signature (" ^ name ^ ") has not been declared");
                        undefinedSignature
                    )

        (* Construct a signature.  All the type IDs within the signature are variables. *)
        fun sigValue (str : sigs, Env env : env, _ : LEX.location, structPath) =
            case str of
                SignatureIdent(name, loc, declLoc) =>
                    signatureIdentValue(name, loc, declLoc, Env env, structPath)

            |   WhereType {sigExp, typeVars, typeName, realisation, line, ...} =>
                    signatureWhereType(sigExp, typeVars, typeName, realisation, line, Env env, structPath)

            |   SigDec(sigList, lno) =>
                    makeSigInto(sigList, Env env, lno, 0, structPath)

        and signatureIdentValue(name, loc, declLoc, _, structPath) =
        let
            (* Look up the signature and copy it to turn bound IDs into variables.
               This is needed because we may have sharing. *)
            val Signatures { name, tab, typeIdMap, minTypes, boundIds, declaredAt, ...} = lookSig(name, loc);
            (* Remember the declaration location for possible browsing. *)
            val () = declLoc := SOME declaredAt
            val startNewIds = ! idCount

            (* Create a new variable ID for each bound ID. *)
            fun makeNewId(oldId as Bound { description, isDatatype, ...}) =
                    makeVariableId(isEquality oldId, isDatatype, false, description, structPath)
            |   makeNewId _ = raise InternalError "Map does not return Bound Id"

            val v = Vector.fromList(List.map makeNewId boundIds)
            (* Map bound IDs only. *)
            val mapIds =
                if minTypes = startNewIds orelse null boundIds
                then typeIdMap (* Optimisation to reduce space: don't add map if it's not needed. *)
                else
                let
                    fun mapId n =
                        if n < minTypes then outerTypeIdEnv n
                        else Vector.sub (v, n - minTypes)
                in
                    composeMaps(typeIdMap, mapId)
                end
        in
            makeSignature(name, tab, !idCount, !idCount, declaredAt, mapIds, [])
        end

        and signatureWhereType(sigExp, typeVars, typeName, realisation, line, Env globalEnv, structPath) =
        let
            (* We construct the signature into the result signature.  When we apply the
               "where" we need to look up the types (and structures) only within the
               signature constrained by the "where" and not in the surrounding signature.
               e.g. If we have sig type t include S where type t = ... end
               we need to generate an error if S does not include t.  Of course
               if it does that's also an error since t would be rebound!
               Equally, we must look up the right hand side of a where type
               in the surrounding scope, which will consist of the global environment
               and the signature excluding the entries we're adding here. *)

            val resSig as Signatures { typeIdMap = idMap, ... } = sigValue(sigExp, Env globalEnv, lno, structPath)
            val sigEnv = makeEnv(sigTab resSig)

            fun lookupFailure msg =
                giveError (str, line, lex) (msg ^ " in signature.")

            (* Look up the type constructor in the signature. *)
            val sigTypeConstr =
                lookupTyp
                  ({
                    lookupType   = #lookupType sigEnv,
                    lookupStruct = #lookupStruct sigEnv
                   },
                 typeName,
                 lookupFailure);

            (* The type, though, is looked up in the surrounding environment. *)
            fun lookupGlobal(s, locn) =
                lookupTyp
                  ({
                    lookupType   = #lookupType globalEnv,
                    lookupStruct = #lookupStruct globalEnv
                   },
                 s,
                 giveError (str, locn, lex))

            (* Process the type, looking up any type constructors. *)
            val () = assignTypes (realisation, lookupGlobal, lex);

            fun cantSet(reason1, reason2) =
            let
                val typeEnv =
                {
                    lookupType = fn s => case #lookupType globalEnv s of NONE => NONE | SOME t => SOME(t, NONE),
                    lookupStruct = fn s => case #lookupStruct globalEnv s of NONE => NONE | SOME t => SOME(t, NONE)
                }
            in
                errorMsgNear (lex, true, fn n => displaySigs(sigExp, n), lno,
                    PrettyBlock(3, false, [],
                        [
                            PrettyString "Cannot apply type realisation.",
                            PrettyBreak(1, 2),
                            PrettyString("``" ^ typeName ^ "''"),
                            PrettyBreak(1, 0),
                            PrettyString reason1,
                            PrettyBreak(1, 0),
                            display(realisation, 1000, typeEnv),
                            PrettyBreak(0, 0),
                            PrettyString reason2
                        ]))
            end
         in
            (* Now try to set the target type to the type function. *)
            if isUndefinedTypeConstr sigTypeConstr
            then () (* Probably because looking up the type constructor name failed. *)
            else
            let
                (* Map the type identifier to be set. *)
                val typeId =
                    case tcIdentifier sigTypeConstr of
                        Bound{offset, ...} => idMap offset
                    |   id => id
            in
                if not (isVariableId typeId)
                then (* May have been declared as type t=int or bound by a where type already. *)
                    errorMsgNear (lex, true, fn n => displaySigs(sigExp, n), lno,
                        PrettyBlock(3, false, [],
                            [
                                PrettyString "Cannot apply type realisation.",
                                PrettyBreak(1, 2),
                                PrettyString("``" ^ typeName ^ "''"),
                                PrettyBreak(1, 0),
                                PrettyString " has already been set to",
                                PrettyBreak(1, 0),
                                printId typeId
                            ]))
                else
                case typeId of
                    Bound { offset, ... } =>
                    (
                        case realId(offset-initTypeId) of
                            VariableSlot {boundId=varId as Bound{eqType, offset, isDatatype, ...}, ... } =>
                            (
                               (* The rule for "where type" says that we must check that an eqtype
                                  is only set to a type that permits equality and that the result
                                  is "well-formed".  This seems to mean that if the type we're
                                  setting is a datatype (has constructors) it can only be set to
                                  a type that is a type name and not a general type function. *)
                                if pling eqType andalso not(typePermitsEquality realisation)
                                then cantSet ("is an eqtype but", "does not permit equality.")
                                else case typeNameRebinding (typeVars, realisation) of
                                    SOME typeId =>
                                        (* Renaming an existing constructor e.g. type t = s.  Propagate the id.
                                           "s" may be free or it may be within the signature and equivalent to
                                           a sharing constraint.
                                           e.g. sig type t structure S: sig type s end where type s = t end. *)
                                        if isVariableId typeId
                                        then linkFlexibleTypeIds(typeId, varId)
                                        else StretchArray.update(mapArray, offset-initTypeId, FreeSlot typeId)
                                |   NONE =>
                                        if isDatatype
                                            (* The type we're trying to set is a datatype but the type
                                               we're setting it to isn't. *)
                                        then cantSet ("is a datatype but", "is not a simple type.")
                                        else
                                            StretchArray.update(mapArray, offset-initTypeId,
                                                FreeSlot(TypeFunction(typeVars, realisation)))
                            )
                        |   _ => (* Already checked. *) raise InternalError "setWhereType"
                    )
                |   _ => (* Already checked. *) raise InternalError "setWhereType"
            end;
            resSig
        end (* signatureWhereType *)

        (* Constructs a signature and inserts it into an environment at a given offset.
           Generally offset will be zero except if we are including a signature.
           All the type IDs corresponding to local types are variables.  There may be free
           IDs (and bound IDs?) as a result of "where type" constraints. *)
        and makeSigInto(sigsList: specs list,
                        Env globalEnv, (* The surrounding environment excluding this sig. *)
                        lno: LEX.location, offset: int, structPath): signatures =
        let
            (* Make a new signature. *)
            val newTable = makeSignatureTable();
            (* Copy everything into the new signature. *)

            local
                (* ML 97 does not allow multiple declarations in a signature. *)
                fun checkAndEnter (enter, lookup, kind, locs) (s: string, v) =
                case lookup s of
                    SOME _ => (* Already there. *)
                    let
                        fun getDecLoc(DeclaredAt loc :: _) = loc
                        |   getDecLoc [] = lno
                        |   getDecLoc(_::rest) = getDecLoc rest
                        (* TODO: This shows the location of the identifier that is the duplicate.
                           It would be nice if it could also show the original location. *)
                    in
                        errorNear (lex, true, fn n => displaySigs(str, n), getDecLoc(locs v), 
                            kind ^ " (" ^ s ^ ") is already present in this signature.")
                    end
                |   NONE => enter(s, v)

                val structEnv = makeEnv newTable;
            in
                val structEnv = 
                {
                    lookupVal     = #lookupVal    structEnv,
                    lookupType    = #lookupType   structEnv,
                    lookupFix     = #lookupFix    structEnv,
                    lookupStruct  = #lookupStruct structEnv,
                    lookupSig     = #lookupSig    structEnv,
                    lookupFunct   = #lookupFunct  structEnv,
                    enterVal      =
                      checkAndEnter (#enterVal structEnv, #lookupVal structEnv, "Value",
                        fn (Value{ locations, ...}) => locations),
                    enterType     =
                      checkAndEnter (#enterType structEnv, #lookupType structEnv, "Type", tcLocations),
                    enterStruct   =
                      checkAndEnter (#enterStruct structEnv, #lookupStruct structEnv, "Structure", structLocations),
                    (* These next three can't occur. *)
                    enterFix      = fn _ => raise InternalError "Entering fixity in signature",
                    enterSig      = fn _ => raise InternalError "Entering signature in signature",
                    enterFunct    = fn _ => raise InternalError "Entering functor in signature"
                }
            end

            (* Process the entries in the signature and allocate an address
               to each. *)
            fun processSig (signat: specs, offset : int, lno : LEX.location) : int =
              case signat of
                StructureSig (structList : structSigBind list, _) =>
                let
                  (* Each element in the list should be a structure binding. *)
                  fun pStruct [] offset = offset
                    | pStruct (({name, sigStruct = (sigStruct, _, _), line, ...}: structSigBind) :: t) offset =
                    let
                      (* Create a new surrounding environment to include the surrounding
                         structure.  This is the scope for any structures or types.
                         Specifically, if we look up a type defined by a "where type"
                         we use this environment and not the signature we're creating. *)
                      val newEnv = 
                         {
                          lookupVal     = #lookupVal    structEnv,
                          lookupType    =
                            lookupDefault (#lookupType structEnv) (#lookupType globalEnv),
                          lookupFix     = #lookupFix    structEnv,
                          lookupStruct  =
                            lookupDefault (#lookupStruct structEnv) (#lookupStruct globalEnv),
                          lookupSig     = #lookupSig    structEnv,
                          lookupFunct   = #lookupFunct  structEnv,
                          enterVal      = #enterVal structEnv,
                          enterType     = #enterType structEnv,
                          enterStruct   = #enterStruct structEnv,
                          enterFix      = #enterFix structEnv,
                          enterSig      = #enterSig structEnv,
                          enterFunct    = #enterFunct structEnv
                         };
                      val resSig = sigValue (sigStruct, Env newEnv, line, structPath ^ name ^ ".");
                      (* Process the rest of the list before declaring
                         the structure. *)
                      val result = pStruct t (offset + 1);
                      (* Make a structure. *)
                      val resStruct = makeFormalStruct (name, resSig, offset, [DeclaredAt lno]);
                      val () = #enterStruct structEnv (name, resStruct);
                    in
                      result (* One slot for each structure. *)
                    end
                in
                  pStruct structList offset
                end
                
              | ValSig {name=(name, nameLoc), typeof, line, ...} =>
                let
                    val typeof = typeFromTypeParse typeof
                  val errorFn = giveSpecError (signat, line, lex);
                
                  fun lookup(s, locn) =
                    lookupTyp
                      ({
                        lookupType   =
                            lookupDefault (#lookupType structEnv) (#lookupType globalEnv),
                        lookupStruct =
                            lookupDefault (#lookupStruct structEnv) (#lookupStruct globalEnv)
                       },
                     s,
                     giveSpecError (signat, locn, lex));
                in  (* If the type is not found give an error. *)
                  (* Check for rebinding of built-ins.  "it" is allowed here. *)
                    if name = "true" orelse name = "false" orelse name = "nil"
                    orelse name = "::" orelse name = "ref"
                  then errorFn("Specifying \"" ^ name ^ "\" is illegal.")
                  else ();
                  assignTypes (typeof, lookup, lex);
                  (* The type is copied before being entered in the environment.
                     This isn't logically necessary but has the effect of removing
                     ref we put in for type constructions. *)
                  #enterVal structEnv (name,
                    mkFormal (name, SimpleValue,
                        copyType (typeof, fn x => x, fn x => x), offset, [DeclaredAt nameLoc]));
                  (offset + 1)
                end
               
              | ExSig {name=(name, nameLoc), typeof, line, ...} =>
                let
                  val errorFn = giveSpecError (signat, line, lex);
                
                  fun lookup(s, _) =
                    lookupTyp
                      ({
                        lookupType   =
                            lookupDefault (#lookupType structEnv) (#lookupType globalEnv),
                        lookupStruct =
                            lookupDefault (#lookupStruct structEnv) (#lookupStruct globalEnv)
                       },
                     s,
                     errorFn);

                  val exType =
                    case typeof of
                        NONE => exnType
                    |   SOME typeof =>
                        let
                            val ty = typeFromTypeParse typeof
                        in
                            assignTypes (ty, lookup, lex);
                            mkFunctionType (ty, exnType)
                        end
                in  (* If the type is not found give an error. *)
                  (* Check for rebinding of built-ins. "it" is not allowed. *)
                    if name = "true" orelse name = "false" orelse name = "nil"
                  orelse name = "::" orelse name = "ref" orelse name = "it"
                  then errorFn("Specifying \"" ^ name ^ "\" is illegal.")
                  else ();
                  #enterVal structEnv (name, mkFormal (name, Exception, exType, offset, [DeclaredAt nameLoc]));
                  (offset + 1)
                end
               
              | IncludeSig (structList : sigs list, _) =>
                let
                    (* include sigid ... sigid or include sigexp.  For
                       simplicity we handle the slightly more general case
                       of a list of signature expressions.
                       The contents of the signature are added to the environment. *)
                    fun includeSigExp (str: sigs, offset) =
                    let
                        val address = ref offset
                        (* The environment for the signature being included must at least include local types.  *)
                        val includeEnv =
                        {
                            lookupVal     = #lookupVal structEnv,
                            lookupType    =
                                lookupDefault (#lookupType structEnv) (#lookupType globalEnv),
                            lookupFix     = #lookupFix structEnv,
                            lookupStruct  =
                                lookupDefault (#lookupStruct structEnv) (#lookupStruct globalEnv),
                            lookupSig     = #lookupSig    structEnv,
                            lookupFunct   = #lookupFunct  structEnv,
                            enterVal      = #enterVal structEnv,
                            enterType     = #enterType structEnv,
                            enterStruct   = #enterStruct structEnv,
                            enterFix      = #enterFix structEnv,
                            enterSig      = #enterSig structEnv,
                            enterFunct    = #enterFunct structEnv
                        }

                        val resultSig = sigValue(str, Env includeEnv, lno, structPath)

                        (* Renumber the run-time offsets for Values and Structures as we enter them
                           into the surrounding signature. *)
                        fun newAccess(Formal _) =
                            let val addr = !address in address := addr+1; Formal addr end
                        |   newAccess _ = raise InternalError "newAccess: Not Formal"

                        val tsvEnv =
                        {
                            enterType   = #enterType structEnv,
                            enterStruct =
                                fn (name, str) =>
                                    #enterStruct structEnv
                                        (name, Struct{ name = structName str, signat = structSignat str,
                                                access = newAccess(structAccess str),
                                                locations = structLocations str}),
                            enterVal =
                                fn (dName, Value { name, typeOf, access, class, locations, ... }) =>
                                    #enterVal structEnv (dName,
                                        Value{name=name, typeOf = typeOf, access=newAccess access,
                                              class=class, locations=locations, references=NONE})
                        }
                        val () = openSignature(resultSig, tsvEnv, "")
                    in
                        ! address
                    end
                in
                    List.foldl includeSigExp offset structList
                end

              | Sharing (share : shareConstraint) =>
                  (* Sharing constraint. *)
                  let
                     (* In ML90 it was possible to share with any identifier
                        in scope.  In ML97 sharing is restricted to identifiers
                        in the "spec". *)
                       val envForSharing = Env structEnv
                  in
                     applySharingConstraint (share, envForSharing, str);
                     offset (* No entry *)
                  end
                
              | CoreType {dec, ...} =>
              let (* datatype or type binding(s) *)
                (* This pass puts the data constructors into the environment. *)
                val addrs = ref offset
                (* Pass2 creates value constructors of datatypes as global values.
                   Rather than complicate pass2 by trying to make formal values
                   in this case it's easier to trap the value constructors at
                   this point. N.B. We may get constructors from a datatype
                   declaration or from datatype replication. *)
                fun enterVal(name, Value{class=class, typeOf, locations, ...}) =
                    let
                        val addr = !addrs
                        val _ = addrs := addr+1
                    in
                        (#enterVal structEnv)(name,
                            Value{class=class, typeOf=typeOf, access=Formal addr, name=name,
                                  locations=locations, references=NONE})
                    end

                (* Record all the datatypes we declare. *)
                val datatypeList = ref []
                fun enterType(name, tyCons) =
                (
                    datatypeList := tyCons :: !datatypeList;
                    #enterType structEnv (name, tyCons)
                )

               val newEnv = 
                 {
                  lookupVal     = #lookupVal    structEnv,
                  lookupType    =
                    lookupDefault (#lookupType structEnv) (#lookupType globalEnv),
                  lookupFix     = #lookupFix    structEnv,
                  lookupStruct  =
                    lookupDefault (#lookupStruct structEnv) (#lookupStruct globalEnv),
                  lookupSig     = #lookupSig    structEnv,
                  lookupFunct   = #lookupFunct  structEnv,
                  enterVal      = enterVal,
                  enterType     = enterType,
                  enterStruct   = #enterStruct structEnv,
                  enterFix      = #enterFix structEnv,
                  enterSig      = #enterSig structEnv,
                  enterFunct    = #enterFunct structEnv
                 };

                fun makeId (eq, isdt, loc) = makeVariableId(eq, isdt, true, loc, structPath)
                val _ : types = pass2 (dec, makeId, Env newEnv, lex);
                (* Replace the constructor list for the datatype with the modified
                   constructors.  All the constructors should be in the set.  Is
                   it possible that one might not be because of an error? *)
                fun findConstr(v: values): values =
                    getOpt((#lookupVal structEnv)(valName v), v)
                fun updateConstrList tyCons =
                    if null (tcConstructors tyCons)
                    then ()
                    else tcSetConstructors(tyCons, List.map findConstr (tcConstructors tyCons))
                val _ = List.app updateConstrList (!datatypeList)
              in
                ! addrs
              end
            (* end processSig *);
            
            val _ =
                List.foldl (fn (signat, offset) => processSig (signat, offset, lno))
                    offset sigsList
        in
            makeSignature("", newTable, ! idCount, ! idCount, lno, typeIdEnv (), [])
        end

        (* Process the contents of the signature. *)
        val resultSig = sigValue (str, Env globalEnv, lno, "")

        (* After the signature has been built and any sharing or "where type"
           constraints have been applied we replace the remaining variable stamps
           by bound stamps. *) 
        val nextAddress = getNextRuntimeOffset resultSig
        val typeCounter = ref initTypeId;
        val addrCounter = ref nextAddress

        (* Construct final bound IDs for each distinct type ID in the array. *)
        local
            fun mapIds n =
            if n = !idCount-initTypeId
            then ([], [])
            else
            (
                (* Process lowest numbered IDs first since they represent
                   the result of any sharing. *)
                case realId n of
                    VariableSlot {
                        boundId = Bound{eqType, description = { name, location, description}, isDatatype, ... },
                        descriptions, ...} =>
                    let (* Need to make a new ID. *)
                        (* If we have sharing we want to produce a description that expresses that. *)
                        val descript =
                            case descriptions of
                                descs as _ :: _ :: _ => "sharing " ^ String.concatWith "," descs
                            |   _ => description (* Original description. *)
                        val newId =
                        let
                            (* For each ID we need a new entry in the ID vector.  We also
                               need an entry in the run-time vector for the structure so that
                               we can pass the equality/print value at run-time. *)
                            val n = !typeCounter
                            val () = typeCounter := n + 1
                            val addr = ! addrCounter
                            val () = addrCounter := addr + 1
                            val description =
                                { name = name, location = location, description = descript }
                        in
                            makeBoundId(Formal addr, n, pling eqType, isDatatype, description)
                        end
                        (* Update the entry for any sharing. *)
                        val () = StretchArray.update(mapArray, n, FreeSlot newId)
                        val (distinctIds, mappedIds) = mapIds (n+1)
                    in
                        (newId :: distinctIds, newId :: mappedIds)
                    end

                |   FreeSlot (TypeFunction(args, equiv)) =>
                    let
                        val (distinctIds, mappedIds) = mapIds (n+1)
                        (* Generally, IDs in a FreeSlot will be either Bound or Free but
                           they could be TypeFunctions as a result of a "where type" and
                           the function could involve type IDs within the signature.  We
                           have to copy the ID now after all the new IDs have been created. *)
                        fun copyTypeConstr tcon =
                            case tcIdentifier tcon of
                                Bound { offset, ...} =>
                                if offset < initTypeId then tcon
                                else
                                let
                                    (* At this stage we've overwritten all entries with FreeSlots. *)
                                    val newId =
                                        case realId(offset-initTypeId) of
                                            FreeSlot id => id
                                        |   _ => raise InternalError "mapIds:copyTypeConstr"
                                in
                                    makeFrozenTypeConstrs(
                                        tcName tcon, tcTypeVars tcon, newId, 0, tcLocations tcon)
                                end
                            |   _ => tcon
                        val copiedEquiv = copyType(equiv, fn x => x, copyTypeConstr)
                        val copiedId = TypeFunction(args, copiedEquiv)
                    in
                        (distinctIds, copiedId :: mappedIds)
                    end

                |   FreeSlot id => (* Free or shares with existing type ID. *)
                    let
                        val (distinctIds, mappedIds) = mapIds (n+1)
                    in
                        (distinctIds, id :: mappedIds)
                    end

                |   _ => raise InternalError "mapIds"
            )
            val (distinctIds, mappedIds) = mapIds 0
            val mapVector = Vector.fromList mappedIds
            val resVector = Vector.fromList distinctIds
        in
            fun mapFunction n =
                if n < initTypeId
                then outerTypeIdEnv n
                else Vector.sub(mapVector, n-initTypeId)
            val distinctIds = distinctIds
            val allMapped = Vector.length mapVector = Vector.length resVector
        end
    in
        let
            val Signatures { tab, name, declaredAt, typeIdMap, ... } = resultSig
            (* We have allocated Bound Ids starting at initTypeId.  If there has not been any sharing or
               where type constraints these Ids will correspond exactly to the bound Ids of the signature
               and we can use the result without any further mapping.  This is particularly the case if
               we have simply used a named signature here.  If there have been some sharing or where type
               we have to produce a new map so that the boundId list consists of contiguously numbered
               items.   This is an optimisation to reduce the space of the final signature. *)
            val finalMap =
                if allMapped then typeIdMap else composeMaps(typeIdMap, mapFunction)
        in
            makeSignature(name, tab, initTypeId, initTypeId + List.length distinctIds, declaredAt,
                finalMap, distinctIds)
        end
    end (* sigVal *);

    structure Sharing =
    struct
        type sigs           = sigs
        type structSigBind  = structSigBind
        type types          = types
        type parsetree      = parsetree
        type typeParsetree  = typeParsetree
        type typeVarForm    = typeVarForm
        type pretty         = pretty
        type ptProperties   = ptProperties
        type env            = env
        type signatures     = signatures
        type lexan          = lexan
        type typeId         = typeId
        type specs          = specs
    end

end;

