# MIT License
# 
# Copyright (c) 2020-2021 Francesco Cameli
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import macros, strutils, omni_invalid

macro omni_def_inner*(function_signature : untyped, code_block : untyped, omni_current_module_def : typed, struct_args : varargs[typed] = nil) : untyped =
    var 
        function_signature = function_signature #allows modification in case of "def a:" without explicit call
        function_signature_kind = function_signature.kind

        proc_and_template = nnkStmtList.newTree()

        proc_def = nnkProcDef.newTree()
        proc_return_type : NimNode
        proc_name : NimNode
        proc_name_str : string
        proc_generic_params = nnkGenericParams.newTree()
        proc_formal_params  = nnkFormalParams.newTree()

        template_def = nnkTemplateDef.newTree()
        template_name : NimNode
        #template_proc_call : NimNode
        template_body_call = nnkCall.newTree()

        proc_omni_def_export : NimNode

        generics : seq[NimNode]
        checkValidTypes = nnkStmtList.newTree()   

    #module where def is defined
    let current_module = omni_current_module_def.owner

    if current_module.kind != nnkSym and current_module.kind != nnkIdent:
        error ("def " & repr(function_signature) & ": can't retrieve its current module")

    #def a:
    if function_signature_kind == nnkIdent:
        function_signature = nnkCall.newTree(
            function_signature
        )
        function_signature_kind = nnkCall
    
    if function_signature_kind == nnkCommand or function_signature_kind == nnkObjConstr or function_signature_kind == nnkCall or function_signature_kind == nnkInfix:
        
        var name_with_args : NimNode

        #Missing the return type entirely OR not providing any infos at all.
        #Defaults to returning auto. This also allows void for no return specified.
        if function_signature_kind == nnkObjConstr or function_signature_kind == nnkCall:
            name_with_args = function_signature
            proc_return_type = newIdentNode("auto")
        
        #def a() float:
        elif function_signature_kind == nnkCommand:
            name_with_args   = function_signature[0]
            proc_return_type = function_signature[1]
        
        #def a() -> float:
        elif function_signature_kind == nnkInfix:
            if function_signature[0].strVal() != "->":
                error "def: Invalid return operator: '" & $function_signature[0] & "'. Use '->'."
            
            name_with_args   = function_signature[1]
            proc_return_type = function_signature[2]

        var first_statement : NimNode

        #support for def a: instead of def a():
        if name_with_args.kind == nnkIdent:
            first_statement = name_with_args
            name_with_args  = nnkCall.newTree(
                name_with_args
            )
        else:
            first_statement = name_with_args[0]

        let first_statement_kind = first_statement.kind

        #Generics
        if first_statement_kind == nnkBracketExpr:
            #template_proc_call = nnkBracketExpr.newTree()

            for index, entry in first_statement.pairs():
                #Name of function
                if index == 0:
                    proc_name = entry
                    #template_proc_call.add(proc_name)
                    continue

                if entry.kind != nnkIdent:
                    error "def " & repr(proc_name) & ": Invalid generic '" & repr(entry) & "'"
                
                #Generics (for now) can only be SomeNumber
                proc_generic_params.add(
                    nnkIdentDefs.newTree(
                        entry,
                        newIdentNode("SomeNumber"),
                        newEmptyNode()
                    )
                )

                generics.add(entry)
                #template_proc_call.add(entry)
        
        #No Generics
        elif first_statement_kind == nnkIdent:
            proc_name = first_statement

        #Perhaps at least support `+` in the future (nnkAccQuoted)
        if proc_name.kind != nnkIdent and proc_name.kind != nnkSym:
            error "def: Invalid name: '" & repr(first_statement) & "'"

        #Check name validity
        proc_name_str = proc_name.strVal()

        for invalid_ends_with in omni_invalid_ends_with:
            if proc_name_str.endsWith(invalid_ends_with):
                error("def: Can't define a def that ends with '" & invalid_ends_with & "': it's reserved for internal use.")

        #Formal params
        proc_formal_params.add(proc_return_type) 

        #Add template and proc names
        template_name = proc_name

        #moduleName_procName_omni_def121241231 (if needing a unique identifier for any reason)
        #let proc_name_sym = genSym(ident=current_module.strVal() & "_" & proc_name_str & "_omni_def)
        #proc_name = parseStmt(repr(proc_name_sym))[0]

        #new name for proc_name: moduleName_procName_omni_def
        proc_name = newIdentNode(current_module.strVal() & "_" & proc_name_str & "_omni_def")
        
        #This is for the WIP generics defs: https://github.com/vitreo12/omni/issues/118
        #[ if generics.len > 0:
            template_proc_call[0] = proc_name
        else:
            template_proc_call = proc_name 
        
        template_body_call.add(
            template_proc_call
        ) ]#
        
        #Add proc name to template call
        template_body_call.add(proc_name)
        
        let args_block = name_with_args[1..name_with_args.len-1]
        
        for index, statement in args_block.pairs():
            var 
                arg_name  : NimNode
                arg_type  : NimNode
                arg_value : NimNode
                
                new_arg   : NimNode

            let statement_kind = statement.kind

            #a float = 0.5 -> a : float = 0.5 / a = 0.5 -> a : auto = 0.5
            if statement_kind == nnkExprEqExpr:                
                assert statement.len == 2

                #a float = 0.5
                if statement[0].kind == nnkCommand:
                    assert statement[0].len == 2
                    
                    arg_name = statement[0][0]
                    arg_type = statement[0][1]
                
                #a = 0.5
                else:
                    arg_name = statement[0]
                    arg_type = newIdentNode("auto")
                
                arg_value = statement[1]
            
            #a float -> a : float
            elif statement_kind == nnkCommand:
                
                assert statement.len == 2

                arg_name = statement[0]
                arg_type = statement[1]
                arg_value = newEmptyNode()

            #a -> a : auto
            elif statement_kind == nnkIdent:
                arg_name = statement
                arg_type = newIdentNode("auto")
                arg_value = newEmptyNode()
                
            else:
                error("def " & proc_name_str & ": Invalid syntax for argument '" & repr(statement) & "'")

            var arg_type_is_generic = false

            #Check if any of the argument is a generic (e.g, phase T, freq Y)
            if generics.len > 0:
                if arg_type in generics:
                    arg_type_is_generic = true

            #only add check for current type if is not a generic one
            if not arg_type_is_generic:
                #This is a struct that has generics in it (e.g, Phasor[T])
                var arg_type_without_generics : NimNode
                if arg_type.kind == nnkBracketExpr:
                    arg_type_without_generics = arg_type[0]
                else:
                    arg_type_without_generics = arg_type

                #Add validity type checks to output. arg_name needs to be passed as a string literal.
                checkValidTypes.add(
                    nnkCall.newTree(
                        newIdentNode("omni_check_valid_type_macro"),
                        arg_type_without_generics,
                        newLit(arg_name.strVal()), 
                        newLit(true),
                        newLit(false),
                        newLit(false),
                        newLit(proc_name_str)
                    )
                )

            #Fully parametrize unparametrized arguments...
            #This is essential for exported modules, as unparametrized arguments might not be found in defs definitions!
            let struct_arg = struct_args[index]
            if struct_arg.kind != nnkNilLit: #already parametrized
                let 
                    struct_arg_impl = struct_arg.getImpl()
                    struct_arg_impl_generic_params = struct_arg_impl[1]
                if struct_arg_impl_generic_params.kind == nnkGenericParams:
                    arg_type = nnkBracketExpr.newTree(
                        arg_type
                    )
                    for generic_param in struct_arg_impl_generic_params:
                        arg_type.add(
                            newIdentNode("auto")
                        )

            #error astGenRepr arg_type

            #new arg
            new_arg = nnkIdentDefs.newTree(
                arg_name,
                arg_type,
                arg_value
            )
            
            #add to formal params
            proc_formal_params.add(new_arg)

            #Add arg name to template call
            template_body_call.add(arg_name)
        
        # ========== #
        # BUILD PROC #
        # ========== #

        #Add name of func (with _inner appended) with * for export
        proc_def.add(
            nnkPostfix.newTree(
                newIdentNode("*"),
                proc_name
            )
        )

        #Add generics
        if proc_generic_params.len > 0:
            proc_def.add(
                newEmptyNode(),
                proc_generic_params
            )
        else:
            proc_def.add(
                newEmptyNode(),
                newEmptyNode()
            )

        #Add samplerate / bufsize / omni_auto_mem : Omni_AutoMem / omni_call_type : Omni_CallType = Omni_InitCall
        proc_formal_params.add(
            nnkIdentDefs.newTree(
                newIdentNode("samplerate"),
                newIdentNode("float"),
                newEmptyNode()
            ),

            nnkIdentDefs.newTree(
                newIdentNode("bufsize"),
                newIdentNode("int"),
                newEmptyNode()
            ),

            nnkIdentDefs.newTree(
                newIdentNode("omni_auto_mem"),
                newIdentNode("Omni_AutoMem"),
                newEmptyNode()
            ),

            nnkIdentDefs.newTree(
                newIdentNode("omni_call_type"),
                nnkBracketExpr.newTree(
                    newIdentNode("typedesc"),
                    newIdentNode("Omni_CallType")
                ),
                newIdentNode("Omni_InitCall")
            )
        )

        #Add formal args
        proc_def.add(proc_formal_params)
        
        #Add inline, noSideEffect and raises:[]
        proc_def.add(
            nnkPragma.newTree(
                newIdentNode("inline"),
                newIdentNode("noSideEffect"),
                nnkExprColonExpr.newTree(
                    newIdentNode("raises"),
                    nnkBracket.newTree()
                )
            ),
            newEmptyNode()
        )   

        #Pass the proc body to the omni_parse_block_untyped macro to parse it
        let proc_body = nnkStmtList.newTree(
            nnkCall.newTree(
                newIdentNode("omni_parse_block_untyped"),
                code_block,
                nnkExprEqExpr.newTree(
                    newIdentNode("is_def_block_typed"),
                    newLit(true)
                ),
                nnkExprEqExpr.newTree(
                    newIdentNode("extra_data"),
                    proc_return_type #pass return type as "extra_data"
                )
            )
        ) 
        
        #Add function body (with checks for var/lets macro)
        proc_def.add(proc_body)

        # ================= #
        # BUILD EXPORT PROC #
        # ================= #

        proc_omni_def_export       = proc_def.copy()
        proc_omni_def_export[4]    = newEmptyNode() #remove pragmas
        proc_omni_def_export[0][1] = newIdentNode(proc_name_str & "_omni_def_export") #change name
        
        #error astGenRepr proc_omni_def_export
        
        #Can't remove these things because the generated code will be then == to the one generated in the dummy proc with a def with no args!!
        #[ var proc_omni_def_export_formal_params = proc_omni_def_export[3]
        proc_omni_def_export_formal_params.del(proc_omni_def_export_formal_params.len - 1) #delete omni_call_type
        proc_omni_def_export_formal_params.del(proc_omni_def_export_formal_params.len - 1) #table shifted, delete omni_auto_mem now
        proc_omni_def_export_formal_params.del(proc_omni_def_export_formal_params.len - 1) #table shifted, delete bufsize now
        proc_omni_def_export_formal_params.del(proc_omni_def_export_formal_params.len - 1) #table shifted, delete samplerate now ]#
        
        proc_omni_def_export[^1] = proc_name #template_body_call.copy()

        # ============== #
        # BUILD TEMPLATE #
        # ============== #

        #Add name with * for export
        template_def.add(
            nnkPostfix.newTree(
                newIdentNode("*"),
                template_name
            )
        )

        #Add generics
        if proc_generic_params.len > 0:
            template_def.add(
                newEmptyNode(),
                proc_generic_params
            )
        else:
            template_def.add(
                newEmptyNode(),
                newEmptyNode()
            )

        #re-use proc's formal params, but replace the fist entry (return type) with untyped and remove last two entries, which are omni_auto_mem and omni_call_type
        let template_formal_params = proc_formal_params.copy
        template_formal_params.del(template_formal_params.len - 1) #delete omni_call_type
        template_formal_params.del(template_formal_params.len - 1) #table shifted, delete omni_auto_mem now
        template_formal_params.del(template_formal_params.len - 1) #table shifted, delete bufsize now
        template_formal_params.del(template_formal_params.len - 1) #table shifted, delete samplerate now
        template_formal_params[0] = newIdentNode("untyped")
        template_def.add(
            template_formal_params,
            newEmptyNode(),
            newEmptyNode()
        )

        #Add samplerate / bufsize / omni_auto_mem / omni_call_type to template call
        template_body_call.add(
            newIdentNode("samplerate"),
            newIdentNode("bufsize"),
            newIdentNode("omni_auto_mem"),
            newIdentNode("omni_call_type")
        )
        
        #Add body (just call _inner proc, adding "omni_auto_mem" and "omni_call_type" at the end)
        template_def.add(
            nnkStmtList.newTree(
                template_body_call
            )
        )

    else:
        error "def: Invalid syntax for 'def " & repr(function_signature) & "'"

    #This dummy stuff is needed for nim to catch all the references to defs when using modules... Weird bug
    #Otherwise, proc won't overload and import on modules won't work correctly! Trust me, don't delete this!!!
    #when not declared(""" & proc_name_str & """_omni_def_dummy):
    #    proc """ & proc_name_str & """_omni_def_dummy*() = discard
    #    proc """ & proc_name_str & """_omni_def_export*() = discard
    let 
        proc_dummy_name = newIdentNode(proc_name_str & "_omni_def_dummy")
        proc_dummy_export = newIdentNode(proc_name_str & "_omni_def_export")
        proc_dummy = nnkWhenStmt.newTree(
            nnkElifBranch.newTree(
                nnkPrefix.newTree(
                    newIdentNode("not"),
                    nnkCall.newTree(
                        newIdentNode("declared"),
                        proc_dummy_name
                    )
                ),
                nnkStmtList.newTree(
                    nnkProcDef.newTree(
                        nnkPostfix.newTree(
                            newIdentNode("*"),
                            proc_dummy_name
                        ),
                        newEmptyNode(),
                        newEmptyNode(),
                        nnkFormalParams.newTree(
                            newEmptyNode()
                        ),
                        newEmptyNode(),
                        newEmptyNode(),
                        nnkStmtList.newTree(
                            nnkDiscardStmt.newTree(
                                newEmptyNode()
                            )
                        )
                    ),
                    nnkProcDef.newTree(
                        nnkPostfix.newTree(
                            newIdentNode("*"),
                            proc_dummy_export
                        ),
                        newEmptyNode(),
                        newEmptyNode(),
                        nnkFormalParams.newTree(
                            newEmptyNode()
                        ),
                        newEmptyNode(),
                        newEmptyNode(),
                        nnkStmtList.newTree(
                            nnkDiscardStmt.newTree(
                                newEmptyNode()
                            )
                        )
                    ),
                )
            )
        )

    proc_and_template.add(proc_dummy)
    proc_and_template.add(proc_def)
    proc_and_template.add(proc_omni_def_export)
    proc_and_template.add(template_def)

    #error repr proc_and_template

    return quote do:
        #Run validity type check on each argument of the def
        `checkValidTypes`

        #Actually instantiate def (proc + template)
        `proc_and_template`

#Define a dummy proc to retrieve current module by passing it as a typed parameter
#and calling .owner on it
macro def*(function_signature : untyped, code_block : untyped) : untyped =
    let function_signature_kind = function_signature.kind
    
    var 
        temp_generics : seq[string]
        
        call_omni_def_inner = nnkCall.newTree(
            newIdentNode("omni_def_inner"),
            function_signature,
            code_block,
            newIdentNode("omni_current_module_def"),
        )

        function_signature_call : NimNode
        function_signature_call_kind : NimNodeKind
    
    #Has return type, just take first part
    if function_signature_kind == nnkCommand:
        function_signature_call = function_signature[0]
        function_signature_call_kind = function_signature_call.kind

    #Has return type with infix operator ->>
    elif function_signature_kind == nnkInfix:
        function_signature_call = function_signature[1]
        function_signature_call_kind = function_signature_call.kind

    #Perhaps invalid if it's not nnkCall. Checked afterwards
    else:
        function_signature_call = function_signature
        function_signature_call_kind = function_signature_kind
    
    #Extract argument types from function signature
    if function_signature_call_kind == nnkCall:
        for i, arg in function_signature_call:
            let arg_kind = arg.kind
            var arg_type = newNilLit()

            #Name of func and generics
            if i == 0:
                #Generics, extract them
                if arg_kind == nnkBracketExpr:
                    for generic_param in arg:
                        if generic_param.kind == nnkIdent:
                            temp_generics.add(generic_param.strVal())
                continue
            
            if arg_kind == nnkCommand:
                let arg_type_temp = arg[1]
                if arg_type_temp.kind == nnkIdent:
                    #Don't add generics!
                    if not(arg_type_temp.strVal() in temp_generics):
                        arg_type = arg_type_temp
            
            call_omni_def_inner.add(arg_type)
    else:
        error "def: invalid function signature: '" & $repr(function_signature) & "'"

    return quote do:
        when not declared(omni_current_module_def):
            proc omni_current_module_def() = discard

        `call_omni_def_inner`