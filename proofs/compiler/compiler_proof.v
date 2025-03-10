From mathcomp Require Import all_ssreflect all_algebra.

Require Import
  arch_params_proof
  compiler
  compiler_util
  psem
  psem_facts.
Require Import
  allocation_proof
  inline_proof
  dead_calls_proof
  makeReferenceArguments_proof
  array_copy
  array_copy_proof
  array_init_proof
  unrolling_proof
  constant_prop_proof
  propagate_inline_proof
  dead_code_proof
  array_expansion
  array_expansion_proof
  remove_globals_proof
  stack_alloc_proof_2
  tunneling_proof
  linearization_proof
  merge_varmaps_proof
  psem_of_sem_proof
  slh_lowering_proof
  direct_call_proof.

Require Import
  arch_decl
  arch_extra
  arch_sem
  asm_gen_proof
  sem_params_of_arch_extra.
Import Utf8.
Import wsize.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

#[local] Existing Instance withsubword.

Section PROOF.

Context
  {syscall_state : Type} {sc_sem : syscall.syscall_sem syscall_state}
  `{asm_e : asm_extra} {call_conv : calling_convention} {asm_scsem : asm_syscall_sem}
  {lowering_options : Type}
  (aparams : architecture_params lowering_options)
  (haparams : h_architecture_params aparams)
  (cparams : compiler_params lowering_options).

Hypothesis print_uprogP : forall s p, cparams.(print_uprog) s p = p.
Hypothesis print_sprogP : forall s p, cparams.(print_sprog) s p = p.
Hypothesis print_linearP : forall s p, cparams.(print_linear) s p = p.

#[local]
Existing Instance progUnit.

Lemma postprocessP {dc : DirectCall} (p p': uprog) ev scs m fn va scs' m' vr va' :
  dead_code_prog (ap_is_move_op aparams) (const_prop_prog p) false = ok p' →
  sem_call p ev scs m fn va scs' m' vr →
  List.Forall2 value_uincl va va' →
  exists2 vr',
    sem_call p' ev scs m fn va' scs' m' vr'
    & List.Forall2 value_uincl vr vr'.
Proof.
  move => ok_p' E A.
  have [ vr1 [ {} E R1 ] ] := const_prop_callP E A.
  have! [ vr2 [ E' R2 ] ] :=
    (dead_code_callPu
      (hap_is_move_opP haparams)
      ok_p'
      (List_Forall2_refl _ value_uincl_refl)
      E).
  exists vr2; first exact: E'.
  apply: Forall2_trans R1 R2.
  exact: value_uincl_trans.
Qed.

Lemma unrollP  {dc : DirectCall} (fn : funname) (p p' : prog) ev scs mem va va' scs' mem' vr :
  unroll_loop (ap_is_move_op aparams) p = ok p'
  -> sem_call p ev scs mem fn va scs' mem' vr
  -> List.Forall2 value_uincl va va'
  -> exists vr',
       sem_call p' ev scs mem fn va' scs' mem' vr'
       /\ List.Forall2 value_uincl vr vr'.
Proof.
  rewrite /unroll_loop; t_xrbindP.
  elim: Loop.nb p va va' vr => //= n Hn p va va' vr p1 ok_p1.
  case e: unroll_prog => [ p2 [] ]; last first.
  { move/ok_inj => {n Hn} <- E A.
    have [ vr' {} E R ] := postprocessP ok_p1 E A.
    by exists vr'. }
  t_xrbindP => p3 ok_p3 ok_p' E A.
  have [ vr1 {} E R1 ] := postprocessP ok_p1 E (List_Forall2_refl _ value_uincl_refl).
  have := unroll_callP E.
  rewrite e /= => {} E.
  have [ vr2 [] {} E R2 ] := Hn _ _ _ _ _ ok_p3 ok_p' E A.
  exists vr2; split; first exact: E.
  apply: Forall2_trans R1 R2.
  exact: value_uincl_trans.
Qed.

Definition compose_pass : ∀ vr (P Q: _ → Prop),
        (∀ vr', P vr' → Q vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & P vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & Q vr')
    := λ vr P Q h x, let 'ex_intro2 vr' u p := x in ex_intro2 _ _ vr' u (h vr' p).

Definition compose_pass_uincl : ∀ vr (P Q: _ → Prop),
        (∀ vr, P vr → ∃ vr', Q vr' ∧ List.Forall2 value_uincl vr vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & P vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & Q vr')
  :=
      λ vr P Q h x,
      let 'ex_intro2 vr1 u p := x in
      let 'ex_intro vr2 (conj q v) := h _ p in
      ex_intro2 _ _ vr2 (Forall2_trans value_uincl_trans u v) q.

Definition compose_pass_uincl' : ∀ vr (P Q: _ → Prop),
        (∀ vr, P vr → exists2 vr', List.Forall2 value_uincl vr vr' & Q vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & P vr') →
        (exists2 vr', List.Forall2 value_uincl vr vr' & Q vr')
  :=
      λ vr P Q h x,
      let 'ex_intro2 vr1 u p := x in
      let 'ex_intro2 vr2 v q := h _ p in
      ex_intro2 _ _ vr2 (Forall2_trans value_uincl_trans u v) q.

Lemma live_range_splittingP {dc : DirectCall} (p p': uprog) scs m fn va scs' m' vr :
  live_range_splitting aparams cparams p = ok p' →
  sem_call p tt scs m fn va scs' m' vr →
  exists2 vr',
      List.Forall2 value_uincl vr vr' &
      sem_call p' tt scs m fn va scs' m' vr'.
Proof.
  rewrite /live_range_splitting; t_xrbindP.
  rewrite !print_uprogP => ok_p' pa ok_pa.
  rewrite print_uprogP => ? exec_p; subst pa.
  have va_refl := List_Forall2_refl va value_uincl_refl.
  apply: compose_pass_uincl.
  - move=> vr' Hvr'.
    apply: (dead_code_callPu (hap_is_move_opP haparams) ok_pa va_refl).
    exact: Hvr'.
  apply: compose_pass_uincl;
    first by move => vr';
             apply: (alloc_call_uprogP (sip := sip_of_asm_e) ok_p').
  exists vr.
  - exact: (List_Forall2_refl _ value_uincl_refl).
  by rewrite surj_prog.
Qed.

Lemma values_uincl_refl vs :
  List.Forall2 value_uincl vs vs.
Proof. exact: List_Forall2_refl value_uincl_refl. Qed.

Lemma inliningP (to_keep: seq funname) (p p': uprog) scs m fn va scs' m' vr :
  inlining cparams to_keep p = ok p' →
  fn \in to_keep →
  sem_call (wsw := withsubword) (dc := indirect_c) p tt scs m fn va scs' m' vr →
  exists2 vr', List.Forall2 value_uincl vr vr' & sem_call (dc := indirect_c) p' tt scs m fn va scs' m' vr'.
Proof.
  rewrite /inlining /=; t_xrbindP => pa.
  rewrite print_uprogP => ok_pa pb ok_pb.
  rewrite print_uprogP => <- {p'} ok_fn h.
  apply: compose_pass.
  - by move => vr'; exact: (dead_calls_err_seqP (sip := sip_of_asm_e) (sCP := sCP_unit) ok_pb).
  exact: (inline_call_errP ok_pa (values_uincl_refl va) h).
Qed.

Lemma compiler_first_partP entries (p: prog) (p': uprog) scs m fn va scs' m' vr :
  compiler_first_part aparams cparams entries p = ok p' →
  fn \in entries →
  sem_call (wsw:= nosubword) (dc:=indirect_c) p tt scs m fn va scs' m' vr →
  exists2 vr',
    List.Forall2 value_uincl vr vr' &
    sem_call (dc:=direct_c) p' tt scs m fn va scs' m' vr'.
Proof.
  rewrite /compiler_first_part; t_xrbindP => pa0.
  rewrite print_uprogP => ok_pa0 pa.
  rewrite print_uprogP => ok_pa pc ok_pc.
  rewrite !print_uprogP => pd ok_pd.
  rewrite !print_uprogP => pe ok_pe.
  rewrite !print_uprogP => pf ok_pf.
  rewrite !print_uprogP => pg ok_pg.
  rewrite !print_uprogP => ph ok_ph pi ok_pi.
  rewrite !print_uprogP => ok_fvars pj ok_pj pp.
  rewrite !print_uprogP => ok_pp <- {p'} ok_fn exec_p.

  have va_refl := List_Forall2_refl va value_uincl_refl.
  apply: compose_pass_uincl.
  - move=> vr'; apply: (pi_callP (sCP := sCP_unit) ok_pp va_refl).
   apply: compose_pass.
  - move=> vr'.
    assert (h := lower_slh_prog_sem_call (dc:=direct_c) (hap_hshp haparams) (ev:= tt) ok_pj).
    apply h => //.
  apply: compose_pass.
  - move => vr'.
    exact:
      (hlop_lower_callP
         (hap_hlop haparams)
         (lowering_opt cparams)
         (warning cparams)
         ok_fvars).
  apply: compose_pass; first by move => vr'; apply: (RGP.remove_globP ok_pi).
  apply: compose_pass_uincl'.
  - move => vr'; apply: (live_range_splittingP ok_ph).
  apply: compose_pass.
  - move=> vr' hvr'. assert (h := expand_callP (sip := sip_of_asm_e) ok_pg); apply h => //; apply hvr'.
  apply: compose_pass_uincl'.
  - by move=>  vr'; apply: indirect_to_direct.
  apply: compose_pass.
  - by move=> vr'; apply: (makeReferenceArguments_callP (siparams := sip_of_asm_e) ok_pf).
  apply: compose_pass_uincl; first by move =>vr'; apply: (remove_init_fdPu _ va_refl).
  apply: compose_pass_uincl'.
  - move => vr' Hvr'.
    apply: (live_range_splittingP ok_pe); exact: Hvr'.
  apply: compose_pass.
  - by move => vr'; exact: (dead_calls_err_seqP (sip := sip_of_asm_e) (sCP := sCP_unit) ok_pd).
  apply: compose_pass_uincl; first by move=> vr' Hvr'; apply: (unrollP ok_pc _ va_refl); exact: Hvr'.
  apply: compose_pass_uincl'; first by move => vr' Hvr'; apply: (inliningP ok_pa ok_fn); exact: Hvr'.
  apply: compose_pass; first by move => vr'; apply: (add_init_fdP).
  apply: compose_pass_uincl.
  - by move=> vr'; apply:(array_copy_fdP (sCP := sCP_unit) ok_pa0 va_refl).
  apply: compose_pass; first by move => vr'; exact: psem_call_u.
  exists vr => //.
  exact: (List_Forall2_refl _ value_uincl_refl).
Qed.

Lemma check_removereturnP entries remove_return b :
  check_removereturn entries remove_return = ok b →
  ∀ fn, fn \in entries → remove_return fn = None.
Proof.
  move => /assertP /eqP h fn /(in_pmap remove_return).
  case: (remove_return fn) => // r.
  by rewrite h.
Qed.

Lemma compiler_third_partP entries (p p' : @sprog _pd _ _asmop) :
  compiler_third_part aparams cparams entries p = ok p' →
  [/\
    ∀ fn (gd: pointer) scs m va scs' m' vr,
      fn \in entries →
      sem_call (dc:= direct_c) p gd scs m fn va scs' m' vr →
      exists2 vr',
      List.Forall2 value_uincl vr vr' &
      sem_call (dc:= direct_c) p' gd scs m fn va scs' m' vr' &
    ∀ fn m,
      alloc_ok p' fn m → alloc_ok p fn m
  ].
Proof.
  rewrite /compiler_third_part; t_xrbindP=> /check_removereturnP ok_rr pa ok_pa.
  rewrite !print_sprogP => ok_pb pc ok_pc.
  rewrite print_sprogP => <- {p'}.
  split.
  + move => fn gd scs m va scs' m' vr ok_fn exec_p.
    have va_refl : List.Forall2 value_uincl va va.
    - exact: List_Forall2_refl.
    apply: compose_pass_uincl.
    - move => vr'.
      apply: (dead_code_callPs (dc:= direct_c) (hap_is_move_opP haparams) ok_pc va_refl).
    apply: compose_pass_uincl;
      first by move => vr';
        apply:
          (alloc_call_sprogP (ep := ep_of_asm_e) (sip := sip_of_asm_e) ok_pb).
    rewrite surj_prog.
    have! [vr' [exec_pa]] :=
      (dead_code_tokeep_callPs (hap_is_move_opP haparams) ok_pa va_refl exec_p).
    rewrite /fn_keep_only (ok_rr _ ok_fn) => vr_vr'.
    by exists vr'.
  rewrite /alloc_ok => fn m alloc_pc fd get_fd.
  have! [fda ok_fda get_fda] :=
    (dead_code_prog_tokeep_get_fundef ok_pa get_fd).
  have [fdb [get_fdb ok_fdb]] :=
    allocation_proof.all_checked (sip := sip_of_asm_e) ok_pb get_fda.
  have! [fdc ok_fdc get_fdc] :=
    (dead_code_prog_tokeep_get_fundef ok_pc get_fdb).
  move: (alloc_pc _ get_fdc).
  have [_ _ ->]:= dead_code_fd_meta ok_fdc.
  have [ <- <- <- ] := @check_fundef_meta _ _ _ _ _ _ _ (_, fda) _ _ _ ok_fdb.
  have [_ _ ->]:= dead_code_fd_meta ok_fda.
  done.
Qed.

Lemma compiler_third_part_meta entries (p p' : sprog) :
  compiler_third_part aparams cparams entries p = ok p' →
  p_extra p' = p_extra p.
Proof.
  rewrite /compiler_third_part.
  t_xrbindP => _ pa hpa _ pb hpb.
  have! [_ ok_pa] := (dead_code_prog_tokeep_meta hpa).
  have! [] := (dead_code_prog_tokeep_meta hpb).
  rewrite !print_sprogP /= => _ ok_pb <- {p'}.
  by rewrite ok_pb ok_pa.
Qed.

(* TODO: move *)
Remark sp_globs_stack_alloc rip rsp data ga la (p: uprog) (p': sprog) :
  alloc_prog (ap_shp aparams) (ap_sap aparams) (fresh_var_ident cparams (Reg (Normal, Direct)) dummy_instr_info) rip rsp data ga la p = ok p' →
  sp_globs (p_extra p') = data.
Proof.
  by rewrite /alloc_prog; t_xrbindP => ???? _ <-.
Qed.

Lemma compiler_third_part_alloc_ok entries (p p' : sprog) (fn: funname) (m: mem) :
  compiler_third_part aparams cparams entries p = ok p' →
  alloc_ok p' fn m →
  alloc_ok p fn m.
Proof. case/compiler_third_partP => _; exact. Qed.

Lemma check_no_ptrP entries ao u fn :
  check_no_ptr entries ao = ok u →
  fn \in entries →
  allNone (sao_params (ao fn)) ∧ allNone (sao_return (ao fn)).
Proof.
  clear.
  case: u => /allMP h /InP ok_fn; move: (h _ ok_fn).
  by t_xrbindP.
Qed.

Lemma allNone_nth {A} (m: seq (option A)) i :
  allNone m ->
  nth None m i = None.
Proof.
  elim: m i.
  - by move => ? _; exact: nth_nil.
  by case => // m ih [].
Qed.

Lemma sem_call_length {dc:DirectCall}(p: uprog) scs m fn va scs' m' vr :
  sem_call p tt scs m fn va scs' m' vr →
  ∃ fd,
    [/\ get_fundef (p_funcs p) fn = Some fd,
     size (f_params fd) = size va,
     size (f_tyin fd) = size va,
     size (f_tyout fd) = size vr &
     size (f_res fd) = size vr].
Proof.
  move=> h; have := sem_callE h => -[] fd [] -> [] va' [] ? [] ? [] ? [] vr' [] ok_args [] _ ok_va' _ [] /size_mapM ok_vr' ok_res _.
  have := size_fold2 ok_va'.
  have [<- <-] := size_mapM2 ok_args.
  have [size_vr' <-] := size_mapM2 ok_res.
  rewrite {2}size_vr' -ok_vr' => {1}<-.
  by exists fd.
Qed.

Lemma compiler_front_endP
  entries
  (p: prog)
  (p': @sprog _pd _ _asmop)
  (gd : pointer)
  scs m mi fn va scs' m' vr :
  compiler_front_end aparams cparams entries p = ok p' →
  fn \in entries →
  sem_call (dc:=indirect_c) (wsw:= nosubword) p tt scs m fn va scs' m' vr →
  extend_mem m mi gd (sp_globs (p_extra p')) →
  alloc_ok p' fn mi →
  ∃ vr' mi',
    [/\
     List.Forall2 value_uincl vr vr',
     sem_call (dc:=direct_c) p' gd scs mi fn va scs' mi' vr' &
     extend_mem m' mi' gd (sp_globs (p_extra p'))
    ].
Proof.
  rewrite /compiler_front_end;
  t_xrbindP => p1 ok_p1 /check_no_ptrP checked_entries p2 ok_p2 p3.
  rewrite print_sprogP => ok_p3 <- {p'} ok_fn exec_p.
  rewrite (compiler_third_part_meta ok_p3) => m_mi ok_mi.
  assert (ok_mi' : alloc_ok (sip := sip_of_asm_e) p2 fn mi).
  - exact: compiler_third_part_alloc_ok ok_p3 ok_mi.
  have := compiler_first_partP ok_p1 ok_fn exec_p.
  case => {p ok_p1 exec_p} vr1 vr_vr1 exec_p1.
  have gd2 := sp_globs_stack_alloc ok_p2.
  rewrite -gd2 in ok_p2.
  case/sem_call_length: (exec_p1) => fd [] ok_fd size_params size_tyin size_tyout size_res.
  have! [mglob ok_mglob] := (alloc_prog_get_fundef ok_p2).
  move=> /(_ _ _ ok_fd)[] fd' /alloc_fd_checked_sao[] ok_sao_p ok_sao_r ok_fd'.
  move: checked_entries => /(_ _ ok_fn) [] params_noptr return_noptr.
  assert (ok_va : wf_args (sp_globs (p_extra p2)) gd (ao_stack_alloc (stackalloc cparams p1)) m mi fn va va).
  - move: params_noptr ok_sao_p.
    rewrite size_params /wf_args.
    move: (sao_params _); clear.
    elim: va.
    + by case => // _ _; constructor.
    by move => v va ih [] // [] // pa /= /ih{}ih /succn_inj /ih{}ih; constructor.
  have disjoint_va : disjoint_values (sao_params (ao_stack_alloc (stackalloc cparams p1) fn)) va va.
  - rewrite /disjoint_values => i1 pi1 w1 i2 pi2 w2.
    by rewrite (allNone_nth _ params_noptr).
  have := alloc_progP _ (hap_hsap haparams) ok_p2 exec_p1 m_mi.
  move => /(_ (hap_hshp haparams) va ok_va disjoint_va ok_mi').
  case => mi' [] vr2 [] exec_p2 [] m'_mi' [] ok_vr2 ?.
  have [] := compiler_third_partP ok_p3.
  case/(_ _ _ _ _ _ _ _ _ ok_fn exec_p2) => vr3 vr2_vr3 exec_p3.
  exists vr3, mi'; split.
  - apply: (Forall2_trans value_uincl_trans); first exact vr_vr1.
    apply: (Forall2_trans value_uincl_trans); last exact vr2_vr3.
    suff -> : vr1 = vr2 by exact: List_Forall2_refl.
    move: ok_sao_r ok_vr2 return_noptr.
    rewrite /wf_results size_res.
    move: (sao_return _); clear.
    elim: vr1 vr2.
    + by case => // ??[] // _ /List_Forall3_inv.
    move => r vr ih vr2 [] // [] // ns /= /succn_inj /ih{}ih /List_Forall3_inv.
    by case: vr2 => // r2 vr2 [] /= -> /ih{}ih /ih ->.
  - exact: exec_p3.
  exact: m'_mi'.
Qed.

Lemma compiler_back_end_meta entries (p: sprog) (tp: lprog) :
  compiler_back_end aparams cparams entries p = ok tp →
  [/\
     lp_rip tp = p.(p_extra).(sp_rip),
     lp_rsp tp = p.(p_extra).(sp_rsp) &
     lp_globs tp = p.(p_extra).(sp_globs)
  ].
Proof.
  rewrite /compiler_back_end; t_xrbindP => _ _ lp ok_lp p2.
  rewrite !print_linearP => ok_tp ?; subst p2.
  have! [<- [<- [<- _]]] := (tunnel_program_invariants ok_tp).
  split.
  - exact: lp_ripE ok_lp.
  - exact: lp_rspE ok_lp.
  exact: lp_globsE ok_lp.
Qed.

Lemma compiler_back_end_to_asm_meta entries (p : sprog) (xp : asm_prog) :
  compiler_back_end_to_asm aparams cparams entries p = ok xp
  -> asm_globs xp = (sp_globs (p_extra p)).
Proof.
  rewrite /compiler_back_end_to_asm.
  t_xrbindP=> tp /compiler_back_end_meta[] _ _ <-.
  by move=> /assemble_progP [_ <-].
Qed.

(* The memory has an allocated stack region that is large enough to hold the local variables of the function and all functions it may call.
  The stack region is described by two pointers: [top-stack m] at the bottom and [root] (held in RSP) at the top
 *)
Definition enough_stack_space
  (xp : asm_prog) (fn : funname) (root : pointer) (m : mem) : Prop :=
  forall fd : asm_fundef,
    get_fundef xp.(asm_funcs) fn = Some fd
    -> let stk_sz := (wunsigned root - wunsigned (top_stack m))%Z in
       (0 <= asm_fd_total_stack fd <= stk_sz)%Z.

Lemma enough_stack_space_alloc_ok
  entries (sp : sprog) (xp : asm_prog) (fn : funname) (m m' : mem) :
  compiler_back_end_to_asm aparams cparams entries sp = ok xp
  -> fn \in entries
  -> (wunsigned (stack_limit m) <= wunsigned (top_stack m'))%Z
  -> enough_stack_space xp fn (top_stack m) m'
  -> alloc_ok sp fn m.
Proof.
  rewrite /compiler_back_end_to_asm /compiler_back_end.
  t_xrbindP => ? /allMP ok_export _ lp ok_lp tp.
  rewrite !print_linearP => ok_tp <- ok_xp /InP ok_fn M S.
  move => fd ok_fd.
  move: ok_export => /(_ _ ok_fn); rewrite ok_fd => /assertP /eqP export.
  split; last by rewrite export.
  have! h0 := (get_fundef_p' ok_lp ok_fd).
  have! h1 := (get_fundef_tunnel_program ok_tp h0).
  have! [fd' ok_fd'] := (ok_get_fundef ok_xp h1).
  case/assemble_fdI => _ _ [] ? [] ? [] ? [] _ _ _ ?; subst fd'.
  move: ok_fd' => /S /=.
  rewrite /allocatable_stack.
  move: (wunsigned (stack_limit m)) (wunsigned (top_stack m)) (wunsigned (top_stack m')) M => L T T'.
  Lia.lia.
Qed.

Import sem_one_varmap.

Lemma compiler_back_endP
  entries
  (p : @sprog _pd _ _asmop)
  (tp : lprog)
  (rip : word Uptr)
  (scs : syscall_state)
  (m : mem)
  (scs' : syscall_state)
  (m' : mem)
  (fn : funname)
  args
  res :
  compiler_back_end aparams cparams entries p = ok tp →
  fn \in entries →
  psem.sem_call (dc:= direct_c) p rip scs m fn args scs' m' res →
  ∃ fd : lfundef,
    [/\
      get_fundef tp.(lp_funcs) fn = Some fd,
      fd.(lfd_export) &
      ∀ lm vm,
        vm.[vid tp.(lp_rsp)] = Vword (top_stack m) →
        match_mem m lm →
        List.Forall2 value_uincl args (map (λ x : var_i, vm.[x]) fd.(lfd_arg)) →
        vm.[vid tp.(lp_rip)] = Vword rip →
        vm_initialized_on vm (var_tmp aparams :: lfd_callee_saved fd) →
        ∃ vm' lm',
          [/\
            lsem_exportcall tp scs lm fn vm scs' lm' vm',
            match_mem m' lm' &
            List.Forall2 value_uincl res (map (λ x : var_i, vm'.[x]) fd.(lfd_res))
          ]
      ].
Proof.
  rewrite /compiler_back_end; t_xrbindP => ok_export checked_p lp ok_lp tp'.
  rewrite !print_linearP => ok_tp ? /InP ok_fn exec_p; subst tp'.
  set vtmp := var_tmp aparams.
  have vtmp_not_magic : ~~ Sv.mem vtmp (magic_variables p).
  - apply/Sv_memP; exact: var_tmp_not_magic checked_p.
  have p_call :
    sem_export_call p vtmp rip scs m fn args scs' m' res.
  - apply: (merge_varmaps_export_callP checked_p _ exec_p).
    move/allMP: ok_export => /(_ _ ok_fn).
    rewrite /is_export.
    case: get_fundef => // fd /assertP /eqP Export.
    by exists fd.
  have :=
    linear_exportcallP
      (hap_hlip haparams)
      vtmp_not_magic
      ok_lp
      p_call.
  case => fd [] ok_fd Export lp_call.
  exists (tunneling.tunnel_lfundef fn fd); split.
  - exact: get_fundef_tunnel_program ok_tp ok_fd.
  - exact: Export.
  move=> lm vm H0 H1 H3 H4 H5.
  have H2 := get_var_is_allow_undefined vm (lfd_arg fd).
  have {lp_call} := lp_call lm vm _ _ H1 H2 H3 _ H5.
  have! [-> [-> _]] := (tunnel_program_invariants ok_tp).
  move => /(_ H0 H4) [] vm' [] lm' [] res' [] lp_call M'.
  rewrite get_var_is_allow_undefined => -[] <- res_res'.
  exists vm', lm'; split; cycle 1.
  - exact: M'.
  - exact: res_res'.
  clear -lp_call ok_tp.
  case: lp_call => fd ok_fd Export lp_exec ok_callee_saved.
  exists (tunneling.tunnel_lfundef fn fd).
  - exact: get_fundef_tunnel_program ok_tp ok_fd.
  - exact: Export.
  have! [|] := (lsem_run_tunnel_program ok_tp lp_exec).
  - by exists fd.
  - move => tp_exec _.
    rewrite /lfd_body size_tunnel_lcmd.
    exact: tp_exec.
  exact: ok_callee_saved.
Qed.

Lemma compiler_back_end_to_asmP
  entries
  (p : @sprog _pd _ _asmop)
  (xp : asm_prog)
  (rip : word Uptr)
  scs (m : mem) scs' (m' : mem)
  (fn: funname)
  args
  res :
  compiler_back_end_to_asm aparams cparams entries p = ok xp
  -> fn \in entries
  -> psem.sem_call (dc:=direct_c) p rip scs m fn args scs' m' res
  -> exists xd : asm_fundef,
      [/\ get_fundef (asm_funcs xp) fn = Some xd
        , asm_fd_export xd
        & forall xm,
               xm.(asm_scs) = scs
            -> xm.(asm_rip) = rip
            -> asm_reg xm ad_rsp = top_stack m
            -> match_mem m xm.(asm_mem)
            -> List.Forall2 value_uincl args (get_typed_reg_values xm xd.(asm_fd_arg))
            -> exists xm',
                [/\ asmsem_exportcall xp fn xm xm'
                  , match_mem m' xm'.(asm_mem), xm'.(asm_scs) = scs'
                  & List.Forall2 value_uincl res (get_typed_reg_values xm' xd.(asm_fd_res))
                ]
      ].
Proof.
  rewrite /compiler_back_end_to_asm.
  t_xrbindP=> lp ok_lp ok_xp.
  move=> ok_fn p_call.
  have [fd [] ok_fd fd_export lp_call] := compiler_back_endP ok_lp ok_fn p_call.
  have [xd ->] := ok_get_fundef ok_xp ok_fd.
  have [disj_rip ok_lp_rsp ok_globs get_xfun] := assemble_progP ok_xp.
  case/assemble_fdI =>
    rsp_not_arg /allP ok_callee_saved
    [] xbody
    [] xargs
    [] xres
    [] ok_xbody ok_xargs ok_xres
    -> {xd}.
  eexists; split; first reflexivity.
  - by rewrite fd_export.
  move=> xm ok_scs ok_rip ok_rsp M /= ok_args.

  set s :=
    estate_of_asm_mem
      (top_stack m)
      (lp_rip lp)
      (lp_rsp lp)
      xm.

  assert (LM :=
    lom_eqv_estate_of_asm_mem
      (top_stack m)
      (lp_rsp lp)
      xm
      disj_rip).

  assert (XM :=
    get_var_vmap_of_asm_mem
      (top_stack m)
      (lp_rip lp)
      (lp_rsp lp)
      xm).

  have := lp_call _ _ _ M.
  move=> /(_ (vmap_of_asm_mem (top_stack m) (lp_rip lp) (lp_rsp lp) xm)).
  case.
  - assert (Hrsp := XM (ARReg ad_rsp)).
    move: Hrsp.
    by rewrite /= /to_var /= ok_lp_rsp /rtype /= ok_rsp.
  - have -> //:
      [seq (vmap_of_asm_mem (top_stack m) (lp_rip lp) (lp_rsp lp) xm).[v_var x] | x <- lfd_arg fd] =
      (get_typed_reg_values xm xargs).
    elim: (lfd_arg fd) (xargs) ok_xargs => //= [ | [x ?] xs hrec]; t_xrbindP; first by move=> _ <-.
    by move=> ?? h ? /hrec -> <- /=; rewrite -XM (asm_typed_reg_of_varI h).
  - case: LM => _ _ Y _ _ _ _.
    by move: Y => /= ->; rewrite ok_rip.
  - move => /=.
    apply/andP; split.
    + rewrite /var_tmp.
      have [tmp_r htmp] := ok_lip_tmp haparams.
      rewrite -(of_identI htmp) /get_var (XM (ARReg _)).
      by rewrite /get_typed_reg_value /= truncate_word_u.

    apply/allP => x /ok_callee_saved hin.
    have [r ->]: exists2 r, x = (var_of_asm_typed_reg r) & vtype x != sbool.
    + by move/andP: hin => [->] /is_okP [] r /asm_typed_reg_of_varI ->; exists r.
    rewrite /get_var XM /=.
    by case: r => //= ?; rewrite truncate_word_u.
  move=>
      vm'
      [] lm'
      [] {} lp_call M' res_res'.
  subst scs.
  have :=
    asm_gen_exportcall
      (hap_hagp haparams)
      ok_xp
      lp_call
      _
      LM.
  case.
  - apply/allP => ? /mapP [] r hin ->.
    rewrite /get_var (XM r) /=.
    assert (H:= callee_saved_not_bool); move/allP: H => /(_ _ hin) {hin}.
    by case: r => //= r _; rewrite truncate_word_u.

  move=> xm' xp_call LM'.
  have : List.Forall2 value_uincl res (get_typed_reg_values xm' xres).
  + elim: (lfd_res fd) (xres) ok_xres (res) res_res' => [ | [x ?] xs hrec] //=; t_xrbindP.
    + by move=> ? <- res' h; inversion_clear h => /=.
    move=> ? r h ? /hrec{}hrec <- res' /List_Forall2_inv; case: res' => // v res' [hr /hrec] /=.
    apply/List.Forall2_cons/(value_uincl_trans hr).
    rewrite (asm_typed_reg_of_varI h) /=.
    case: LM' => /= _ _ _ _ R RX X F.
    case: (r) => //=.
  exists xm'; split => //.
  - by case: LM' => /= _ <-.
  - by case: LM' => <-.
Qed.

(* Agreement relation between source and target memories.
   Expressed in a way that streamlines the composition of compiler-correctness theorems (front-end and back-end).
  TODO: There might be an equivalent definition that is clearer.
*)

Record mem_agreement_with_ghost (m m': mem) (gd: pointer) (data: seq u8) (ma_ghost: mem) : Prop :=
  { ma_extend_mem : extend_mem m ma_ghost gd data
  ; ma_match_mem : match_mem ma_ghost m'
  ; ma_stack_stable : stack_stable m ma_ghost
  ; ma_stack_range : (wunsigned (stack_limit ma_ghost) <= wunsigned (top_stack m'))%Z
  }.

Definition mem_agreement (m m': mem) (gd: pointer) (data: seq u8) : Prop :=
  ∃ ma_ghost, mem_agreement_with_ghost m m' gd data ma_ghost.

Lemma compile_prog_to_asmP
  entries
  (p : prog)
  (xp : asm_prog)
  scs (m : mem) scs' (m' : mem)
  (fn: funname)
  va
  vr
  xm :
  compile_prog_to_asm aparams cparams entries p = ok xp
  -> fn \in entries
  -> psem.sem_call (dc:= indirect_c) (wsw:=nosubword) p tt scs m fn va scs' m' vr
  -> mem_agreement m (asm_mem xm) (asm_rip xm) (asm_globs xp)
  -> enough_stack_space xp fn (top_stack m) (asm_mem xm)
  -> exists xd : asm_fundef,
      [/\
         get_fundef (asm_funcs xp) fn = Some xd
        , asm_fd_export xd
        &   asm_scs xm = scs
            -> asm_reg xm ad_rsp = top_stack m
            -> List.Forall2 value_uincl va (get_typed_reg_values xm (asm_fd_arg xd))
            -> exists xm',
                [/\ asmsem_exportcall xp fn xm xm'
                  , mem_agreement m' (asm_mem xm') (asm_rip xm') (asm_globs xp), asm_scs xm' = scs'
                  & List.Forall2 value_uincl vr (get_typed_reg_values xm' (asm_fd_res xd))
                ]
      ].
Proof.
  rewrite /compile_prog_to_asm; t_xrbindP => sp ok_sp ok_xp ok_fn p_call [] mi.
  have -> := compiler_back_end_to_asm_meta ok_xp.
  case=> mi1 mi2 mi3 mi4.
  rewrite (ss_top_stack mi3).
  move=> /(enough_stack_space_alloc_ok ok_xp ok_fn mi4) ok_mi.
  have := compiler_front_endP ok_sp ok_fn p_call mi1 ok_mi.
  case => vr' [] mi' [] vr_vr' sp_call m1.
  have := compiler_back_end_to_asmP ok_xp ok_fn sp_call.
  case => xd [] ok_xd export /(_ _ _ erefl _ mi2) xp_call.
  exists xd; split => //.
  move=> ok_scs ok_rsp va_args'.
  have := xp_call ok_scs ok_rsp va_args'.
  case => xm' [] {} xp_call m2 ok_scs' vr'_res'.
  exists xm'; split => //;
    last exact: Forall2_trans value_uincl_trans vr_vr' vr'_res'.
  case: xp_call => _ _ _ /= _ /asmsem_invariantP /= xm_xm' _.
  exists mi'; split.
  - rewrite -(asmsem_invariant_rip xm_xm').
    exact: m1.
  - exact: m2.
  - transitivity mi;
      last exact: (sem_call_stack_stable_sprog sp_call).
    transitivity m; last exact: mi3.
    symmetry. exact: (sem_call_stack_stable_uprog p_call).
  rewrite
    -(ss_limit (sem_call_stack_stable_sprog sp_call))
    -(ss_top_stack (asmsem_invariant_stack_stable xm_xm')).
  exact: mi4.
Qed.

End PROOF.
