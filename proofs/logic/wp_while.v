(* -------------------------------------------------------------------- *)
From mathcomp Require Import all_ssreflect.

Require Import Morphisms ZArith.

Require Import utils type var.
Require Import expr sem Ssem Ssem_props wp.
Require Import memory.

Import UnsafeMemory.

(* -------------------------------------------------------------------- *)
Set   Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.
Unset SsrOldRewriteGoalsOrder.

Local Open Scope Z_scope.
Local Open Scope svmap_scope.

(* -------------------------------------------------------------------- *)
Hint Resolve 0 SEskip.
Hint Resolve SEseq : ssem.

Notation strue  := (SVbool true).
Notation sfalse := (SVbool false).

(* -------------------------------------------------------------------- *)
Inductive dupI (P : Prop) := Dup of P & P.

Lemma dup (P : Prop) : P -> dupI P.
Proof. by move=> hP; constructor. Qed.

(* -------------------------------------------------------------------- *)
Notation e2b s e := (eval_texpr s (texpr_of_pexpr sbool' e)).

(* -------------------------------------------------------------------- *)
Lemma ssem_app_inv prg s c1 c2 s' :
  ssem prg s (c1 ++ c2) s' ->
    exists2 si : sestate, ssem prg s c1 si & ssem prg si c2 s'.
Proof.
elim: c1 s => /= [|i c1 ih] s c; first by exists s.
by case/ssem_inv: c => si [?] /ih []; eauto with ssem.
Qed.

(* -------------------------------------------------------------------- *)
Lemma ssem_inv1_r prg s i s' : ssem prg s [:: i] s' -> ssem_I prg s i s'.
Proof. by case/ssem_inv=> si [? /ssem_inv ->]. Qed.

(* -------------------------------------------------------------------- *)
Lemma ssem_inv1 prg z s i s' : ssem prg s [:: MkI z i] s' -> ssem_i prg s i s'.
Proof. by case/ssem_inv1_r/ssem_I_inv=> [ir] [ii] [] [_ ->]. Qed.

(* -------------------------------------------------------------------- *)
Lemma hoare_seq prg R P Q c1 c2 :
  hoare prg P c1 R -> hoare prg R c2 Q -> hoare prg P (c1 ++ c2) Q.
Proof. by move=> h1 h2 s s' /ssem_app_inv[si hc1 hc2]; eauto. Qed.

(* -------------------------------------------------------------------- *)
Lemma hoare_rcons prg R P Q c i :
  hoare prg P c R -> hoare prg R [:: i] Q -> hoare prg P (rcons c i) Q.
Proof. by move=> h1 h2; rewrite -cats1; apply: (@hoare_seq _ R). Qed.

(* -------------------------------------------------------------------- *)
Lemma hoare_while prg z I e c :
   hoare prg (fun s => I s /\ e2b s e) c I
-> hoare prg I [:: MkI z (Cwhile e c)]
         (fun s => I s /\ ~~ e2b s e).
Proof.
move=> h s s' /ssem_inv1; move: {-2}(Cwhile _ _) (erefl (Cwhile e c)).
move=> ir eq C; elim: C eq => // {s}; last first.
+ move=> s e' c' hlet [<- _] Is; split=> //.
  elim/rbindP: hlet => v he' /sto_bool_inv hv; subst v.
  by move: he' => /texpr_of_pexpr_bool ->.
move=> s1 s2 s3 e' c' hlet hc' _ ih [eqe eqc] Is1; subst e' c'.
apply/ih/(h s1) => //; split=> //; elim/rbindP: hlet.
move=> v he' /sto_bool_inv ?; subst v.
by move: he' => /texpr_of_pexpr_bool ->.
Qed.

(* -------------------------------------------------------------------- *)
Lemma hoare_while_seq prg z P I c0 e c :
   hoare prg P c0 I
-> hoare prg (fun s => I s /\ e2b s e) c I
-> hoare prg P (rcons c0 (MkI z (Cwhile e c)))
         (fun s => I s /\ ~~ e2b s e).
Proof. by move=> h0 h; apply: (hoare_rcons h0); apply: hoare_while. Qed.

(* -------------------------------------------------------------------- *)
Definition hoare_for prg x zs P c Q :=
  forall s s', ssem_for prg x zs s c s' -> P s -> Q s.

Local Notation "s `_ n" := (nth 0 s n).

Lemma hoare_genfor prg x zs (P : Z -> sestate -> Prop) c :
   (forall s1 s2 z, s1.(sevm) = s2.(sevm) [\ Sv.singleton x] ->
      P z s1 -> P z s2)
-> (forall n, (n.+1 < size zs)%nat ->
      hoare prg
        (fun s => P zs`_n s /\ sget_var s.(sevm) x = SVint zs`_n)
        c (P zs`_n.+1))
-> hoare_for prg x zs (P (head 0 zs)) c (P (last 0 zs)).
Proof.
move=> eqs h s s' C; elim: C h eqs => {x c s zs} // s1 s1' s2 s3 x z zs c.
move=> hwr h1 hfor ih h eqs /= Ps1; have Ps1': P z s1'.
+ apply: (eqs s1) => //.
Abort.
