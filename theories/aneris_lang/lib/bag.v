From iris Require Import invariants.
From iris.algebra Require Import excl.
From iris.base_logic.lib Require Export invariants.
From iris.program_logic Require Export weakestpre.
From iris.proofmode Require Import coq_tactics reduction.
From aneris Require Import lang lifting tactics proofmode notation.
From aneris.aneris_lang.lib Require Import lock.

Definition newbag : ground_lang.val :=
  λ: <>, let: "ℓ" := ref NONE in
         let: "v" := newlock #() in ("ℓ", "v").

Definition insert : ground_lang.val :=
  λ: "x", λ: "e", let: "ℓ" := Fst "x" in
                  let: "lock" := Snd "x" in
                  acquire "lock" ;;
                    "ℓ" <- SOME ("e", !"ℓ") ;;
                  release "lock".

Definition remove : ground_lang.val :=
  λ: "x", let: "ℓ" := Fst "x" in
          let: "lock" := Snd "x" in
          (acquire "lock" ;;
           let: "r" := !"ℓ" in
           let: "res" :=
              match: "r" with
                NONE => NONE
              | SOME "p" => "ℓ" <- Snd "p" ;; SOME (Fst "p")
              end in
           (release "lock" ;; "res")).

Section spec.
  Context `{!distG Σ, !lockG Σ} (N : namespace).

  Local Notation iProp := (iProp Σ).

  Fixpoint bagList (Ψ : ground_lang.val → iProp) (v : ground_lang.val) : iProp :=
    match v with
    | NONEV => ⌜True⌝%I
    | SOMEV (x, r) => (Ψ x ∗ bagList Ψ r)%I
    | _ => ⌜False⌝%I
    end.

  Definition isBag (n : Network.ip_address) (v : ground_lang.val) (Ψ : ground_lang.val → iProp) :=
    (∃ (l : loc) v' γ, ⌜v = PairV #l v'⌝ ∗ is_lock N n γ v' (∃ u, l ↦[n] u ∗ bagList Ψ u))%I.

  Global Instance bag_persistent n v Ψ: Persistent (isBag n v Ψ).
  Proof. apply _. Qed.

  Lemma newbag_spec n Ψ :
     {{{ IsNode n }}} ⟨n; newbag #()⟩ {{{ v, RET 〈n;v〉; isBag n v Ψ }}}.
  Proof.
    iIntros (Φ) "Hn HΦ".
    wp_lam; wp_alloc ℓ as "Hℓ"; wp_let.
    wp_bind (newlock _)%E.
    iApply ((newlock_spec N n (∃ u, ℓ ↦[n] u ∗ bagList Ψ u)%I) with "[Hn Hℓ]").
    - iFrame. iExists NONEV. iFrame.
    - iNext. iIntros (v γ) "IL". wp_pures.
      iApply "HΦ". iExists ℓ, v, γ. iSplit; auto.
  Qed.

  Lemma bag_insert_spec n v Ψ e:
    {{{ isBag n v Ψ ∗ Ψ e }}} ⟨n; insert v e⟩ {{{ v, RET 〈n;v〉; True }}}.
  Proof.
    iIntros (Φ) "[#HC HΨ] HΦ".
    iDestruct "HC" as (ℓ u γ) "[% #HLock]"; subst.
    wp_lam. wp_pures. wp_bind (acquire _)%E.
    iApply (acquire_spec _ _ _ _ (∃ u0, ℓ ↦[n] u0 ∗ bagList Ψ u0))%I; first by iFrame "#".
    iNext. iIntros (v) "(-> & HLocked &  HInv)".
    iDestruct "HInv" as (u') "[Hpt Hisbag]".
    wp_pures. wp_load; wp_store; wp_seq.
    iApply (release_spec _ _ _ _ (∃ u0, ℓ ↦[n] u0 ∗ bagList Ψ u0)
              with "[-HΦ]")%I.
    - iFrame; iFrame "#". iExists (SOMEV (e, u')) ; iFrame.
    - iNext. iIntros (?) "->". by iApply "HΦ".
  Qed.

  Lemma bag_remove_spec n v Ψ:
    {{{ isBag n v Ψ }}} ⟨n; remove v⟩ {{{ v, RET 〈n;v〉; ⌜v = NONEV⌝ ∨ ∃ x, ⌜v = SOMEV x⌝ ∗ Ψ x }}}.
  Proof.
    iIntros (Φ) "HC HΦ".
    iDestruct "HC" as (ℓ u γ) "[% #HLock]"; subst.
    wp_lam. wp_pures. wp_bind (acquire _)%E.
    iApply (acquire_spec _ _ _ _ (∃ u0, ℓ ↦[n] u0 ∗ bagList Ψ u0))%I; first by iFrame "#".
    iNext. iIntros (v) "(-> & HLocked &  HInv)".
    iDestruct "HInv" as (u') "[Hpt Hisbag]".
    wp_pures. wp_load. wp_pures.
    destruct u'; try (iDestruct "Hisbag" as "%" ; contradiction).
    - wp_pures. wp_bind (release _)%E.
      iApply (release_spec _ _ _ _ (∃ u0, ℓ ↦[n] u0 ∗ bagList Ψ u0)
                with "[-HΦ]")%I; iFrame "#"; iFrame.
      + iExists (InjLV u') ; iFrame.
      + iNext. iIntros (v) "-> /=". wp_pures.
        iApply "HΦ". eauto.
    - wp_pures.
      destruct u'; try (iDestruct "Hisbag" as "%" ; contradiction).
      wp_pures; wp_store; wp_pures. wp_bind (release _)%E.
      iDestruct "Hisbag" as "[HΨ Hisbag]".
      iApply (release_spec _ _ _ _ (∃ u0, ℓ ↦[n] u0 ∗ bagList Ψ u0)
                with "[HLocked Hisbag Hpt]")%I; iFrame "#"; iFrame.
      + iExists u'2. iFrame.
      + iNext. iIntros (?) "-> /=". wp_pures.
        iApply "HΦ". iRight.
        iExists _. by iFrame.
  Qed.

End spec.
