From mathcomp Require Import all_ssreflect all_algebra.
From mathcomp Require Import word_ssrZ.

Require Import
  arch_params
  compiler_util
  expr
  fexpr.
Require Import
  linearization
  lowering
  stack_alloc
  slh_lowering.
Require Import
  arch_decl
  arch_extra
  asm_gen.
Require Import
  x86_decl
  x86_extra
  x86_instr_decl
  x86_lowering.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Section Section.
Context {atoI : arch_toIdent}.

(* Used to set up stack. *)
Definition x86_op_align (x : var_i) (ws : wsize) (al : wsize) : fopn_args :=
  let f_to_lvar x := LLvar (mk_var_i (to_var x)) in
  let eflags := map f_to_lvar [:: OF; CF; SF; PF; ZF ] in
  let ex := Rexpr (Fvar x) in
  let emask := fconst ws (- wsize_size al) in
  (eflags ++ [:: LLvar x ], Ox86 (AND ws), [:: ex; Rexpr emask ]).

(* ------------------------------------------------------------------------ *)
(* Stack alloc parameters. *)

Definition lea_ptr x y tag ofs : instr_r :=
  Copn [:: x] tag (Ox86 (LEA Uptr)) [:: add y (cast_const ofs)].

Definition x86_mov_ofs x tag vpk y ofs :=
  let addr :=
    if mk_mov vpk is MK_LEA
    then
      lea_ptr x y tag ofs
    else
      if ofs == 0%Z
      then mov_ws Uptr x y tag
      else lea_ptr x y tag ofs
  in
  Some addr.

Definition x86_immediate x z :=
  mov_ws Uptr (Lvar x) (cast_const z) AT_none.

Definition x86_saparams : stack_alloc_params :=
  {|
    sap_mov_ofs := x86_mov_ofs;
    sap_immediate := x86_immediate;
  |}.

(* ------------------------------------------------------------------------ *)
(* Linearization parameters. *)

Section LINEARIZATION.

Notation vtmpi := (mk_var_i (to_var RAX)).

Definition x86_allocate_stack_frame (rspi: var_i) (sz: Z) :=
  let p := Fapp2 (Osub (Op_w Uptr)) (Fvar rspi) (fconst Uptr sz) in
  ([:: LLvar rspi ], Ox86 (LEA Uptr), [:: Rexpr p ]).

Definition x86_free_stack_frame (rspi: var_i) (sz: Z) :=
  let p := Fapp2 (Oadd (Op_w Uptr)) (Fvar rspi) (fconst Uptr sz) in
  ([:: LLvar rspi ], Ox86 (LEA Uptr), [:: Rexpr p ]).

(* TODO: consider using VMOVDQA when the address is known to be aligned *)
Definition x86_lassign (x: lexpr) (ws: wsize) (e: rexpr) :=
  let op := if (ws <= U64)%CMP
            then MOV ws
            else VMOVDQU ws
  in ([:: x ], Ox86 op, [:: e ]).

Definition x86_set_up_sp_register
  (rspi : var_i) (sf_sz : Z) (al : wsize) (r : var_i) : seq fopn_args :=
  let i0 := x86_lassign (LLvar r) Uptr (Rexpr (Fvar rspi)) in
  let i2 := x86_op_align rspi Uptr al in
  i0 :: rcons (if sf_sz != 0 then [:: x86_allocate_stack_frame rspi sf_sz ] else [::]) i2.

Definition x86_set_up_sp_stack
  (rspi : var_i) (sf_sz : Z) (al : wsize) (off : Z) : seq fopn_args :=
  let vtmpg := Fvar vtmpi in
  let i := x86_lassign (Store Uptr rspi (fconst Uptr off)) Uptr (Rexpr vtmpg) in
  x86_set_up_sp_register rspi sf_sz al vtmpi ++ [:: i ].

Definition x86_liparams : linearization_params :=
  {|
    lip_tmp := vname (v_var vtmpi);
    lip_not_saved_stack := [::];
    lip_allocate_stack_frame := x86_allocate_stack_frame;
    lip_free_stack_frame := x86_free_stack_frame;
    lip_set_up_sp_register :=
      fun rspi sf_sz al r => Some (x86_set_up_sp_register rspi sf_sz al r);
    lip_set_up_sp_stack :=
      fun rspi sf_sz al off => Some (x86_set_up_sp_stack rspi sf_sz al off);
    lip_lassign := fun x ws e => Some (x86_lassign x ws e);
  |}.

End LINEARIZATION.

(* ------------------------------------------------------------------------ *)
(* Lowering parameters. *)

Definition x86_loparams : lowering_params lowering_options :=
  {|
    lop_lower_i := lower_i;
    lop_fvars_correct := fvars_correct;
  |}.


(* ------------------------------------------------------------------------ *)
(* Speculative execution operator lowering parameters. *)

Definition lflags := nseq 5 (Lnone dummy_var_info sbool).

Definition x86_sh_lower
  (lvs : seq lval)
  (slho : slh_op)
  (es : seq pexpr) :
  option copn_args :=
  let O x := Oasm (ExtOp x) in
  match slho with
  | SLHinit   => Some (lvs, O Ox86SLHinit, es)

  | SLHupdate => Some (Lnone dummy_var_info ty_msf :: lvs, O Ox86SLHupdate, es)

  | SLHmove   => Some (lvs, O (Ox86SLHmove), es)

  | SLHprotect ws =>
    let extra := if (ws <= U64)%CMP then lflags else [:: Lnone dummy_var_info (sword ws)] in
    Some (extra ++ lvs, O (Ox86SLHprotect ws), es)

  | SLHprotect_ptr _ | SLHprotect_ptr_fail _ => None (* Taken into account by stack alloc *)
  end.

Definition x86_shparams : sh_params :=
  {|
    shp_lower := x86_sh_lower;
  |}.

(* ------------------------------------------------------------------------ *)
(* Assembly generation parameters. *)

Definition not_condt (c : condt) :=
  match c with
  | O_ct => NO_ct
  | NO_ct => O_ct
  | B_ct => NB_ct
  | NB_ct => B_ct
  | E_ct => NE_ct
  | NE_ct => E_ct
  | BE_ct => NBE_ct
  | NBE_ct => BE_ct
  | S_ct => NS_ct
  | NS_ct => S_ct
  | P_ct => NP_ct
  | NP_ct => P_ct
  | L_ct => NL_ct
  | NL_ct => L_ct
  | LE_ct => NLE_ct
  | NLE_ct => LE_ct
  end.

Definition or_condt ii e c1 c2 : cexec condt :=
  match c1, c2 with
  | L_ct, E_ct => ok LE_ct
  | E_ct, L_ct => ok LE_ct
  | B_ct, E_ct => ok BE_ct
  | E_ct, B_ct => ok BE_ct
  | _, _ => Error (E.berror ii e "Invalid condition (OR)")
  end.

Definition and_condt ii e c1 c2 :=
  match c1, c2 with
  | NB_ct, NE_ct => ok NBE_ct
  | NE_ct, NB_ct => ok NBE_ct
  | NE_ct, NL_ct => ok NLE_ct
  | NL_ct, NE_ct => ok NLE_ct
  | _, _ => Error (E.berror ii e "Invalid condition (AND)")
  end.

Definition of_var_e_bool ii (v: var_i) : cexec rflag :=
  match of_var v with
  | Some r => ok r
  | None => Error (asm_gen.E.invalid_flag ii v)
  end.

Fixpoint assemble_cond_r ii (e : fexpr) : cexec condt :=
  match e with
  | Fvar v =>
      Let r := of_var_e_bool ii v in
      match r with
      | OF => ok O_ct
      | CF => ok B_ct
      | ZF => ok E_ct
      | SF => ok S_ct
      | PF => ok P_ct
      end

  | Fapp1 Onot e =>
      Let c := assemble_cond_r ii e in
      ok (not_condt c)

  | Fapp2 Oor e1 e2 =>
      Let c1 := assemble_cond_r ii e1 in
      Let c2 := assemble_cond_r ii e2 in
      or_condt ii e c1 c2

  | Fapp2 Oand e1 e2 =>
      Let c1 := assemble_cond_r ii e1 in
      Let c2 := assemble_cond_r ii e2 in
      and_condt ii e c1 c2

  | Fapp2 Obeq (Fvar x1) (Fvar x2) =>
      Let r1 := of_var_e_bool ii x1 in
      Let r2 := of_var_e_bool ii x2 in
      if ((r1 == SF) && (r2 == OF)) || ((r1 == OF) && (r2 == SF))
      then ok NL_ct
      else Error (E.berror ii e "Invalid condition (NL)")

  | _ => Error (E.berror ii e "don't known how to compile the condition")

  end.

Definition assemble_cond ii (e: fexpr) : cexec condt :=
  assemble_cond_r ii e.

Definition x86_agparams : asm_gen_params :=
  {|
    agp_assemble_cond := assemble_cond;
  |}.


(* ------------------------------------------------------------------------ *)
(* Shared parameters. *)

Definition x86_is_move_op (o : asm_op_t) :=
  match o with
  | BaseOp (None, MOV _) => true
  | BaseOp (None, VMOVDQA _) => true
  | BaseOp (None, VMOVDQU _) => true
  | ExtOp Ox86SLHmove => true
  | _ => false
  end.

(* ------------------------------------------------------------------------ *)

Definition x86_params : architecture_params lowering_options :=
  {|
    ap_sap := x86_saparams;
    ap_lip := x86_liparams;
    ap_lop := x86_loparams;
    ap_agp := x86_agparams;
    ap_shp := x86_shparams;
    ap_is_move_op := x86_is_move_op;
  |}.

End Section.
