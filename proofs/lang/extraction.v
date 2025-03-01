Require jasmin_compiler.
(* Do not “Require” other modules from Jasmin here:
   expand the jasmin_compiler module instead. *)

From Coq Require ExtrOcamlBasic.
From Coq Require ExtrOcamlString.
From Coq Require ExtrOCamlInt63.

(* This is a hack to force the extraction to keep the singleton here,
   This need should be removed if we add more constructor to syscall_t *)
Extract Inductive syscall.syscall_t => "BinNums.positive Syscall_t.syscall_t" ["Syscall_t.RandomBytes"].

Extraction Inline ssrbool.is_left.
Extraction Inline ssrbool.predT ssrbool.pred_of_argType.
Extraction Inline ssrbool.idP.

Extraction Inline utils.assert.
Extraction Inline utils.Result.bind.
Extraction Inline Datatypes.implb.

Extract Constant strings.ascii_beq => "Char.equal".
Extract Constant strings.ascii_cmp =>
  "(fun x y -> let c = Char.compare x y in if c = 0 then Datatypes.Eq else if c < 0 then Datatypes.Lt else Datatypes.Gt)".

Extract Constant expr.VarInfo.t => "Location.t".
Extract Constant expr.VarInfo.witness => "Location._dummy".
Extract Constant expr.var_info => "Location.t".
Extract Constant expr.InstrInfo.t => "IInfo.t".
Extract Constant expr.InstrInfo.witness => "IInfo.dummy".
Extract Constant expr.InstrInfo.with_location => "IInfo.with_location".
Extract Constant expr.instr_info => "IInfo.t".
Extract Constant expr.fun_info => "FInfo.t".
Extract Constant waes.MixColumns => "(fun _ -> failwith ""MixColumns is not implemented"")".
Extract Constant waes.InvMixColumns => "(fun _ -> failwith ""InvMixColumns not implemented"")".

(* Extraction for Var.FunName *)
Extract Constant var.FunName.t   => "CoreIdent.funname".
Extract Constant var.funname     => "CoreIdent.funname".
Extract Constant var.FunName.tag => "CoreIdent.funname_tag".

(* Module Cident *)

Extract Constant ident.Cident.t       => "CoreIdent.Cident.t".
Extract Constant ident.Cident.name    => "CoreIdent.Cident.name".
Extract Constant ident.WrapIdent.t    => "CoreIdent.Cident.t".
Extract Constant ident.WrapIdent.name => "CoreIdent.Cident.name".


Extract Constant ident.Cident.tag     => "CoreIdent.Cident.tag".
Extract Constant ident.Cident.id_name => "CoreIdent.Cident.id_name".
Extract Constant ident.Cident.id_kind => "CoreIdent.Cident.id_kind".

Extract Constant ident.Cident.name_of_string => "CoreIdent.Cident.name_of_string".
Extract Constant ident.Cident.string_of_name => "CoreIdent.Cident.string_of_name".


Cd  "lang/ocaml".

Extraction Blacklist String List Nat Utils Var Array.

Separate Extraction
  utils
  warray_
  sem_type
  sopn
  expr
  psem_defs
  sem_params_of_arch_extra
  arch_decl
  arch_extra
  x86_decl_core
  x86_decl
  x86_instr_decl
  x86_extra
  x86_params
  arm_decl_core
  arm_decl
  arm_instr_decl
  arm_extra
  arm_params
  compiler.

Cd  "../..".
