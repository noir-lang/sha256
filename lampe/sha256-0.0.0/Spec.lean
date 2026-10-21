-- Specification for SHA-256 variable-length hashing
--
-- This module defines the mathematical correctness criterion for `sha256_var`.
-- The formal proof obligation is to show that the Lampe translation of
-- `sha256_var` in Extracted/Sha256.lean returns the SHA-256 digest of the
-- first `message_size` bytes of `msg`.

import «sha256-0.0.0».Extracted
import Stdlib.Field.Mod
import Stdlib.Cmp

open Lampe

namespace Sha256.Spec

-- ============================================================
-- 1.  Types and constants
-- ============================================================

/-- The 8-word SHA-256 intermediate hash state. -/
abbrev State := List.Vector (U 32) 8

/-- A 16-word (512-bit) SHA-256 message block. -/
abbrev MsgBlock := List.Vector (U 32) 16

/-- The 32-byte SHA-256 digest. -/
abbrev Hash := List.Vector (U 8) 32

/-- SHA-256 initial hash values H₀: the first 32 bits of the fractional parts
    of the square roots of the first 8 prime numbers. -/
def initialState : State :=
  ⟨[1779033703, 3144134277, 1013904242, 2773480762,
    1359893119, 2600822924, 528734635, 1541459225], rfl⟩

/-- Block size in bytes: 64 = 512 bits. -/
def BLOCK_SIZE : ℕ := 64

/-- Size of one u32 word in bytes. -/
def INT_SIZE : ℕ := 4

/-- Byte offset into a 64-byte block at which the 8-byte length field begins. -/
def MSG_SIZE_PTR : ℕ := 56

/-- Word index (in the 16-word block) of the start of the 8-byte length field:
    56 / 4 = 14. -/
def INT_SIZE_PTR : ℕ := 14

-- ============================================================
-- 2.  Abstract sha256Compression primitive
-- ============================================================

/-- Abstract SHA-256 compression function: maps a (message-block, state) pair
    to a new state according to the SHA-256 round function.
    This is the opaque model of the `#_sha256Compression` Noir/Lampe builtin. -/
noncomputable opaque sha256CompressionFn (block : MsgBlock) (state : State) : State

/-- `Sha256CompressionSpec p Γ` asserts that the `sha256Compression` Lampe
    builtin behaves as `sha256CompressionFn` in environment `Γ`. -/
abbrev Sha256CompressionSpec (p : Prime) (Γ : Env) : Prop :=
  ∀ (block : MsgBlock) (state : State),
    STHoare p Γ ⟦⟧
      (.callBuiltin [.array (.u 32) 16, .array (.u 32) 8] (.array (.u 32) 8)
        .sha256Compression h![block, state])
      (fun r => r = sha256CompressionFn block state)

-- ============================================================
-- 3.  Reference implementation helpers
-- ============================================================

section

/-- Construct a `List.Vector α n` from a function `Fin n → α`. -/
def vecOfFn {α : Type*} {n : ℕ} (f : Fin n → α) : List.Vector α n :=
  ⟨List.ofFn f, by simp⟩

/-- A `List.Vector` of `n` copies of `a`. -/
def vecReplicate {α : Type*} (n : ℕ) (a : α) : List.Vector α n :=
  ⟨List.replicate n a, by simp⟩

/-- Build one 16-word message block from `bytes[msg_start .. msg_start + 64)`,
    treating bytes at index ≥ `message_size` as 0.
    Word `i` packs `bytes[msg_start + 4*i .. msg_start + 4*i + 4)` big-endian. -/
def buildMsgBlockRef (bytes : List (U 8)) (message_size msg_start : ℕ) : MsgBlock :=
  vecOfFn (fun (i : Fin 16) =>
    let off  := msg_start + INT_SIZE * i.val
    let byte := fun j => if off + j < message_size then (bytes.getD (off + j) 0).toNat else 0
    BitVec.ofNat 32 (byte 0 * 2^24 + byte 1 * 2^16 + byte 2 * 2^8 + byte 3))

/-- Process all complete 64-byte blocks in `bytes[0..message_size)` by
    repeatedly applying `sha256CompressionFn`, starting from `h₀`.
    Returns the resulting intermediate state and the first partial (un-compressed)
    message block. -/
def processFullBlocksWith
    (compress : MsgBlock → State → State)
    (bytes : List (U 8)) (message_size : ℕ) (h₀ : State) : State × MsgBlock :=
  let num_full_blocks := message_size / BLOCK_SIZE
  let h :=
    (List.range num_full_blocks).foldl
      (fun h i =>
        compress (buildMsgBlockRef bytes message_size (BLOCK_SIZE * i)) h)
      h₀
  let msg_byte_ptr := message_size % BLOCK_SIZE
  let partialBlock :=
    if msg_byte_ptr ≠ 0 then
      buildMsgBlockRef bytes message_size (BLOCK_SIZE * num_full_blocks)
    else
      vecReplicate 16 0
  (h, partialBlock)

noncomputable def processFullBlocksRef :=
  processFullBlocksWith sha256CompressionFn

/-- The value added to a u32 word to set the 0x80 bit at byte position
    `msg_byte_ptr % 4` within that word.  Mirrors `PADDING_BIT_TABLE`. -/
def paddingWordNat (msg_byte_ptr : ℕ) : ℕ :=
  match msg_byte_ptr % 4 with
  | 0 => 0x80000000  -- 0x80 in most-significant byte
  | 1 => 0x00800000
  | 2 => 0x00008000
  | _ => 0x00000080  -- 0x80 in least-significant byte

/-- Insert the 0x80 padding byte at byte position `msg_byte_ptr` in `block`,
    then optionally flush and zero the block if there is insufficient room for
    the 8-byte length field (`msg_byte_ptr ≥ 56`).
    Precondition: `msg_byte_ptr < 64`. -/
def addPaddingAndCompressWith
    (compress : MsgBlock → State → State)
    (block : MsgBlock) (msg_byte_ptr : ℕ) (hb : msg_byte_ptr < BLOCK_SIZE) (h : State)
    : State × MsgBlock :=
  have hw : msg_byte_ptr / 4 < 16 := by simp only [BLOCK_SIZE] at hb; omega
  let word_idx : Fin 16 := ⟨msg_byte_ptr / INT_SIZE, hw⟩
  let block' := block.set word_idx
    (block.get word_idx + BitVec.ofNat 32 (paddingWordNat msg_byte_ptr))
  if msg_byte_ptr ≥ MSG_SIZE_PTR then
    (compress block' h, vecReplicate 16 0)
  else
    (h, block')

noncomputable def addPaddingAndCompressRef :=
  addPaddingAndCompressWith sha256CompressionFn

/-- Encode `8 * message_size` (bit-length of the message) as two u32 limbs.
    Returns `(lo, hi)` such that `lo + hi * 2^32 = 8 * message_size`. -/
def encodeLenRef (message_size : ℕ) : ℕ × ℕ :=
  let bits := 8 * message_size
  (bits % 2 ^ 32, bits / 2 ^ 32)

/-- Write the 64-bit big-endian bit-length into the last two words of `block`:
    word 14 ← hi, word 15 ← lo, where `hi * 2^32 + lo = 8 * message_size`. -/
def attachLenRef (block : MsgBlock) (message_size : ℕ) : MsgBlock :=
  let (lo, hi) := encodeLenRef message_size
  (block.set ⟨14, by norm_num⟩ (BitVec.ofNat 32 hi)).set ⟨15, by norm_num⟩ (BitVec.ofNat 32 lo)

/-- Serialise the 8-word state to a 32-byte hash by unpacking each word in
    big-endian byte order: byte `4j + k` = bits `[32-8k-8 .. 32-8k)` of word `j`. -/
def stateToHashRef (state : State) : Hash :=
  vecOfFn (fun (i : Fin 32) =>
    let word  := (state.get ⟨i.val / 4, by omega⟩).toNat
    let shift := 8 * (3 - i.val % 4)
    BitVec.ofNat 8 ((word >>> shift) % 256))

/-- Finalize the hash after all full blocks have been processed:
    1. Append the 0x80 padding byte; flush the block if necessary.
    2. Write the big-endian 64-bit message bit-length into words 14–15.
    3. Compress the final padded block.
    4. Serialise the resulting 8-word state to 32 bytes. -/
def finalizeSha256BlocksWith
    (compress : MsgBlock → State → State)
    (message_size : ℕ) (h : State) (block : MsgBlock) : Hash :=
  let msg_byte_ptr := message_size % BLOCK_SIZE
  have hb : msg_byte_ptr < BLOCK_SIZE := Nat.mod_lt _ (by norm_num [BLOCK_SIZE])
  let (h', block') := addPaddingAndCompressWith compress block msg_byte_ptr hb h
  let block'' := attachLenRef block' message_size
  stateToHashRef (compress block'' h')

noncomputable def finalizeSha256BlocksRef :=
  finalizeSha256BlocksWith sha256CompressionFn

end

-- ============================================================
-- 4.  Top-level reference function and specification predicate
-- ============================================================

/-- SHA-256 pipeline parametric over the compression function. -/
def sha256With (compress : MsgBlock → State → State)
    (bytes : List (U 8)) (message_size : ℕ) : Hash :=
  let (h, block) := processFullBlocksWith compress bytes message_size initialState
  finalizeSha256BlocksWith compress message_size h block

/-- Reference SHA-256 computation for `bytes[0..message_size)`. -/
noncomputable def sha256Ref := sha256With sha256CompressionFn

/-- `sha256VarSpec msg message_size` is the SHA-256 digest of the first
    `message_size` bytes of the N-byte array `msg`.
    This is the value that a correct `sha256_var` must return. -/
noncomputable def sha256VarSpec {N : ℕ} (msg : List.Vector (U 8) N) (message_size : ℕ) : Hash :=
  sha256Ref msg.toList message_size

-- ============================================================
-- 4a. Proof infrastructure
-- ============================================================

/-- Big-step semantics of `letIn` is associative: running `{let x = a; b(x)}; c`
    is the same as running `let x = a; {b(x); c}`. -/
theorem _root_.Lampe.Omni.letIn_assoc {p : Prime} {Γ : Env} {st} {tp₁ tp₂ tp₃ : Tp}
    {a : Expr (Tp.denote p) tp₁}
    {b : Tp.denote p tp₁ → Expr (Tp.denote p) tp₂}
    {c : Tp.denote p tp₂ → Expr (Tp.denote p) tp₃} {Q} :
    Omni p Γ st ((a.letIn b).letIn c) Q ↔ Omni p Γ st (a.letIn (fun x => (b x).letIn c)) Q := by
  constructor
  · intro h
    cases h with
    | letIn h1 h2 h3 =>
      cases h1 with
      | letIn ha hb hn =>
        apply Omni.letIn ha
        · intro v st hv
          exact Omni.letIn (hb v st hv) h2 h3
        · intro hnone; exact h3 (hn hnone)
  · intro h
    cases h with
    | letIn ha h2 h3 =>
      apply Omni.letIn (Q₁ := fun r => match r with
        | none => Q none
        | some (st, v) => Omni p Γ st (c v) Q)
      · apply Omni.letIn (Q₁ := fun r => match r with
          | none => Q none
          | some (st, v) => Omni p Γ st ((b v).letIn c) Q)
        · apply ha.consequence
          intro v hv
          match v with
          | none => exact h3 hv
          | some (st, v) => exact h2 v st hv
        · intro v st hv
          cases hv with
          | letIn hb hc hbn =>
            apply hb.consequence
            intro w hw
            match w with
            | none => exact hbn hw
            | some (st', w) => exact hc w st' hw
        · exact id
      · intro v st hv
        exact hv
      · exact id

/-- `STHoare`-level counterpart of `Omni.letIn_assoc`: applying `.mpr` flattens the
    nested block that `lampe` generates for a Noir brace block sitting at the head
    of the program, so that `steps` can process its statements sequentially. -/
theorem _root_.Lampe.STHoare.letIn_assoc {p : Prime} {Γ : Env} {tp₁ tp₂ tp₃ : Tp}
    {P : SLP (Lampe.State p)}
    {a : Expr (Tp.denote p) tp₁}
    {b : Tp.denote p tp₁ → Expr (Tp.denote p) tp₂}
    {c : Tp.denote p tp₂ → Expr (Tp.denote p) tp₃}
    {Q : Tp.denote p tp₃ → SLP (Lampe.State p)} :
    STHoare p Γ P ((a.letIn b).letIn c) Q ↔ STHoare p Γ P (a.letIn (fun x => (b x).letIn c)) Q := by
  unfold STHoare THoare
  constructor <;> intro h H st hst
  · rw [← Omni.letIn_assoc]; exact h H st hst
  · rw [Omni.letIn_assoc]; exact h H st hst

/-- One round of: substitute resolved variables, re-associate the nested block
    at the head (if any), and continue symbolic execution. -/
macro "block_steps" "[" ts:term,* "]" : tactic =>
  `(tactic| (subst_vars; (try apply STHoare.letIn_assoc.mpr); steps [$ts,*]))

/-- `steps` closer for the `uGeq` builtin (missing from the tactic's table). -/
def uGeq_intro := STHoare.genericTotalPureBuiltin_intro Builtin.uGeq rfl

-- ============================================================
-- 4b. Constant specs
-- ============================================================

/-- `MSG_SIZE_PTR` constant evaluates to 56. -/
theorem MSG_SIZE_PTR_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::MSG_SIZE_PTR».call h![] h![])
      (fun r => r = (56 : U 32)) := by
  enter_decl
  steps
  norm_cast

/-- `INT_SIZE` constant evaluates to 4. -/
theorem INT_SIZE_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::INT_SIZE».call h![] h![])
      (fun r => r = (4 : U 32)) := by
  enter_decl
  steps
  norm_cast

/-- `INT_SIZE_PTR` constant evaluates to 14 = 56 / 4. -/
theorem INT_SIZE_PTR_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::INT_SIZE_PTR».call h![] h![])
      (fun r => r = (14 : U 32)) := by
  enter_decl
  steps [MSG_SIZE_PTR_const_spec, INT_SIZE_const_spec]
  subst_vars
  rfl

/-- `TWO_POW_8` constant evaluates to 256. -/
theorem TWO_POW_8_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::TWO_POW_8».call h![] h![])
      (fun r => r = (256 : U 32)) := by
  enter_decl
  steps
  norm_cast

/-- `TWO_POW_16` constant evaluates to 65536. -/
theorem TWO_POW_16_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::TWO_POW_16».call h![] h![])
      (fun r => r = (65536 : U 32)) := by
  enter_decl
  steps [TWO_POW_8_const_spec]
  subst_vars
  rfl

/-- `TWO_POW_24` constant evaluates to 2^24. -/
theorem TWO_POW_24_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::TWO_POW_24».call h![] h![])
      (fun r => r = (16777216 : U 32)) := by
  enter_decl
  steps [TWO_POW_16_const_spec]
  subst_vars
  rfl

/-- `TWO_POW_32` constant evaluates to 2^32 as a field element. -/
theorem TWO_POW_32_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::TWO_POW_32».call h![] h![])
      (fun r => r = (4294967296 : Fp p)) := by
  enter_decl
  steps [TWO_POW_24_const_spec]
  subst_vars
  simp
  norm_num

set_option maxRecDepth 65536 in
set_option maxHeartbeats 1000000 in
/-- `PADDING_BIT_TABLE` evaluates to the four u32 words that carry the 0x80
    padding byte in each of the four byte positions. -/
theorem PADDING_BIT_TABLE_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::PADDING_BIT_TABLE».call h![] h![])
      (fun r => r = ⟨[0x80000000, 0x00800000, 0x00008000, 0x00000080], rfl⟩) := by
  enter_decl
  steps [TWO_POW_24_const_spec, TWO_POW_16_const_spec, TWO_POW_8_const_spec]
  subst_vars
  apply List.Vector.eq
  simp [HList.toVec, HList.toList]
  have hc1 : (((1:ℤ) : U 32)) = 1 := by rfl
  refine ⟨?_, ?_, ?_, ?_⟩ <;> rw [hc1] <;> rfl

/-- `vecOfFn` agrees with Mathlib's `List.Vector.ofFn`. -/
lemma vecOfFn_eq_ofFn {α : Type*} {n : ℕ} (f : Fin n → α) :
    vecOfFn f = List.Vector.ofFn f := by
  apply List.Vector.eq
  simp [vecOfFn, List.Vector.toList_ofFn]

/-- `BLOCK_SIZE` constant evaluates to 64 : U 32. Needed so that `steps` can
    process the `let #v = BLOCK_SIZE()` binding in `finalize_sha256_blocks`. -/
theorem BLOCK_SIZE_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::BLOCK_SIZE».call h![] h![])
      (fun r => r = (64 : U 32)) := by
  enter_decl
  steps
  norm_cast

/-- `encode_len` is an unconstrained oracle: it returns some pair of u32s about
    which nothing is known. Its output is pinned down by the caller's assert. -/
theorem encode_len_spec {p : Prime} (message_size : U 32) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::encode_len».call h![] h![message_size])
      (fun _ => True) := by
  enter_decl
  steps

-- ============================================================
-- 5.  Sub-lemmas
-- ============================================================

/-! ### Reference helpers for the `build_msg_block` verification loop -/

/-- The byte value the constrained loop reads at absolute position `j`:
    the message byte when `j < message_size`, 0 otherwise. -/
def byteAt (bytes : List (U 8)) (ms j : ℕ) : ℕ :=
  if j < ms then (bytes.getD j 0).toNat else 0

lemma byteAt_lt (bytes : List (U 8)) (ms j : ℕ) : byteAt bytes ms j < 256 := by
  unfold byteAt
  split
  · exact (bytes.getD j 0).isLt
  · norm_num

/-- Big-endian accumulation of the bytes `[lo, hi)` (Horner form). -/
def accBytes (bytes : List (U 8)) (ms : ℕ) : (lo hi : ℕ) → ℕ
  | _, 0 => 0
  | lo, hi + 1 => if lo ≤ hi then accBytes bytes ms lo hi * 256 + byteAt bytes ms hi else 0

lemma accBytes_empty (bytes : List (U 8)) (ms lo : ℕ) (h : hi ≤ lo) :
    accBytes bytes ms lo hi = 0 := by
  cases hi with
  | zero => rfl
  | succ n =>
    conv_lhs => rw [accBytes]
    rw [if_neg (by omega)]

lemma accBytes_step (bytes : List (U 8)) (ms lo hi : ℕ) (h : lo ≤ hi) :
    accBytes bytes ms lo (hi + 1) = accBytes bytes ms lo hi * 256 + byteAt bytes ms hi := by
  conv_lhs => rw [accBytes]
  rw [if_pos h]

lemma accBytes_lt (bytes : List (U 8)) (ms lo hi : ℕ) :
    accBytes bytes ms lo hi < 256 ^ (hi - lo) := by
  induction hi with
  | zero => unfold accBytes; positivity
  | succ n ih =>
    unfold accBytes
    split
    · rename_i hle
      have hb := byteAt_lt bytes ms n
      have : 256 ^ (n + 1 - lo) = 256 ^ (n - lo) * 256 := by
        rw [← pow_succ]
        congr 1
        omega
      rw [this]
      omega
    · positivity

/-- The value of 32-bit word `w` of the block starting at `msg_start`. -/
def wordVal (bytes : List (U 8)) (ms mst w : ℕ) : ℕ :=
  accBytes bytes ms (mst + 4 * w) (mst + 4 * w + 4)

lemma wordVal_lt (bytes : List (U 8)) (ms mst w : ℕ) :
    wordVal bytes ms mst w < 2 ^ 32 := by
  have := accBytes_lt bytes ms (mst + 4 * w) (mst + 4 * w + 4)
  simp only [show mst + 4 * w + 4 - (mst + 4 * w) = 4 by omega] at this
  calc wordVal bytes ms mst w < 256 ^ 4 := this
  _ ≤ 2 ^ 32 := by norm_num

/-- `wordVal` matches the big-endian formula of `buildMsgBlockRef`. -/
lemma wordVal_eq_ref (bytes : List (U 8)) (ms mst : ℕ) (w : Fin 16) :
    (buildMsgBlockRef bytes ms mst).get w = BitVec.ofNat 32 (wordVal bytes ms mst w.val) := by
  simp only [buildMsgBlockRef, vecOfFn_eq_ofFn, List.Vector.get_ofFn]
  congr 1
  show (if mst + INT_SIZE * w.val + 0 < ms then (bytes.getD (mst + INT_SIZE * w.val + 0) 0).toNat else 0) * 2^24
      + (if mst + INT_SIZE * w.val + 1 < ms then (bytes.getD (mst + INT_SIZE * w.val + 1) 0).toNat else 0) * 2^16
      + (if mst + INT_SIZE * w.val + 2 < ms then (bytes.getD (mst + INT_SIZE * w.val + 2) 0).toNat else 0) * 2^8
      + (if mst + INT_SIZE * w.val + 3 < ms then (bytes.getD (mst + INT_SIZE * w.val + 3) 0).toNat else 0)
    = wordVal bytes ms mst w.val
  simp only [INT_SIZE]
  unfold wordVal
  have e0 : mst + 4 * w.val + 4 = (mst + 4 * w.val + 3) + 1 := by omega
  have e1 : mst + 4 * w.val + 3 = (mst + 4 * w.val + 2) + 1 := by omega
  have e2 : mst + 4 * w.val + 2 = (mst + 4 * w.val + 1) + 1 := by omega
  have e3 : mst + 4 * w.val + 1 = (mst + 4 * w.val) + 1 := by omega
  rw [e0, accBytes_step _ _ _ _ (by omega),
      e1, accBytes_step _ _ _ _ (by omega),
      e2, accBytes_step _ _ _ _ (by omega),
      e3, accBytes_step _ _ _ _ (by omega),
      accBytes_empty _ _ _ (le_refl _)]
  unfold byteAt
  ring

/-- `u32` implements the stdlib `Ord` trait. -/
lemma u32_ord_hasImpl : Lampe.Stdlib.Cmp.Ord.hasImpl «std-1.0.0-beta.14».env (.u 32) := by
  resolve_trait bySearch

/-- `std::cmp::min` on `u32` computes the minimum. -/
theorem min_u32_spec {p : Prime} (a b : U 32) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («std-1.0.0-beta.14::cmp::min».call h![Tp.u 32] h![a, b])
      (fun r => r = if compare a b = .gt then b else a) := by
  steps [Lampe.Stdlib.Cmp.Ord.min_pure_spec
    (T_ord := u32_ord_hasImpl)
    (T_ord_emb := compare)
    (T_ord_f := fun _ _ => Lampe.Stdlib.Cmp.Ord.u32_ord_spec)]
  assumption

/-- `build_msg_block_helper` is an unconstrained oracle: nothing is known about
    its result; the caller constrains it. -/
theorem build_msg_block_helper_spec {p : Prime} {N : U 32}
    (msg : List.Vector (U 8) N.toNat) (message_size msg_start : U 32) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::build_msg_block_helper».call h![N] h![msg, message_size, msg_start])
      (fun _ => True) := by
  enter_decl
  steps

/-- Below the read cap, capping the message size does not change the byte read. -/
lemma byteAt_min (bytes : List (U 8)) (ms mst j : ℕ) (h : j < mst + 64) :
    byteAt bytes (min ms (mst + 64)) j = byteAt bytes ms j := by
  unfold byteAt
  split_ifs <;> omega

/-- Capping the message size at the block end does not change in-block accumulation. -/
lemma accBytes_min (bytes : List (U 8)) (ms mst lo hi : ℕ) (hhi : hi ≤ mst + 64) :
    accBytes bytes (min ms (mst + 64)) lo hi = accBytes bytes ms lo hi := by
  induction hi with
  | zero => rfl
  | succ n ih =>
    by_cases hle : lo ≤ n
    · rw [accBytes_step _ _ _ _ hle, accBytes_step _ _ _ _ hle, ih (by omega),
          byteAt_min _ _ _ _ (by omega)]
    · rw [accBytes_empty _ _ _ (by omega), accBytes_empty _ _ _ (by omega)]

/-- Capping the message size at the block end does not change in-block words. -/
lemma wordVal_min (bytes : List (U 8)) (ms mst w : ℕ) (hw : w < 16) :
    wordVal bytes (min ms (mst + 64)) mst w = wordVal bytes ms mst w := by
  unfold wordVal
  exact accBytes_min _ _ _ _ _ (by omega)

/-- The u32→u32 cast the extractor emits is the identity. -/
lemma castU_id {p : Prime} (x : U 32) :
    (@Builtin.CastTp.cast (.u 32) (.u 32) Builtin.instCastTpU p x) = x :=
  BitVec.setWidth_eq x

/-- At a word boundary, the accumulator window covers exactly the finished word. -/
lemma accBytes_boundary (bytes : List (U 8)) (ms mst k : ℕ)
    (h_align : mst % 4 = 0) (hmod : k % 4 = 0) (hd4 : 4 ≤ k - mst) (hlo : mst ≤ k) :
    accBytes bytes ms (mst + 4 * ((k - mst - 1) / 4)) k
      = wordVal bytes ms mst ((k - mst) / 4 - 1) := by
  unfold wordVal
  have e1 : mst + 4 * ((k - mst - 1) / 4) = mst + 4 * ((k - mst) / 4 - 1) := by omega
  have e2 : k = mst + 4 * ((k - mst) / 4 - 1) + 4 := by omega
  rw [e1]
  congr 1 <;> omega

/-- A u32 equal (as a field element, in a large field) to a word value is that word. -/
lemma word_of_field_eq {p : Prime} (h_p : 2 ^ 64 < p.natVal) (x : U 32) (v : ℕ)
    (hv : v < 2 ^ 32)
    (heq : ((x.toNat : ℕ) : Fp p) = ((v : ℕ) : Fp p)) :
    x = BitVec.ofNat 32 v := by
  have hmod := (ZMod.natCast_eq_natCast_iff _ _ _).mp heq
  have h1 : x.toNat < p.natVal := by have := x.isLt; omega
  have h2 : v < p.natVal := by omega
  have := Nat.ModEq.eq_of_lt_of_lt hmod h1 h2
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt hv]
  exact this

/-- Extending the pinned-words fact across a boundary iteration. -/
lemma pins_extend (bytes : List (U 8)) (ms mst k : ℕ) (blk : MsgBlock)
    (hmod : k % 4 = 0) (hd4 : 4 ≤ k - mst)
    (hpins : ∀ w : Fin 16, w.val < (k - mst - 1) / 4 →
        blk.get w = BitVec.ofNat 32 (wordVal bytes ms mst w.val))
    (idxlt : (k - mst) / 4 - 1 < 16)
    (hnew : blk.get ⟨(k - mst) / 4 - 1, idxlt⟩
        = BitVec.ofNat 32 (wordVal bytes ms mst ((k - mst) / 4 - 1))) :
    ∀ w : Fin 16, w.val < (k - mst) / 4 →
        blk.get w = BitVec.ofNat 32 (wordVal bytes ms mst w.val) := by
  intro w hw
  by_cases hwo : w.val < (k - mst - 1) / 4
  · exact hpins w hwo
  · have hv : w.val = (k - mst) / 4 - 1 := by omega
    have hfe : w = ⟨(k - mst) / 4 - 1, idxlt⟩ := Fin.ext hv
    rw [hfe, hnew]

theorem build_msg_block_spec {p : Prime} {N : U 32}
    (h_p : 2 ^ 64 < p.natVal)
    (msg : List.Vector (U 8) N.toNat)
    (message_size : U 32)
    (msg_start : U 32)
    (h_align : msg_start.toNat % 4 = 0) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::build_msg_block».call h![N] h![msg, message_size, msg_start])
      (fun r => r = buildMsgBlockRef msg.toList message_size.toNat msg_start.toNat) := by
  enter_decl
  apply STHoare.letIn_assoc.mpr
  steps [build_msg_block_helper_spec, BLOCK_SIZE_const_spec, min_u32_spec]
  block_steps [build_msg_block_helper_spec, BLOCK_SIZE_const_spec, min_u32_spec]
  any_goals exact ()
  subst_vars
  apply STHoare.letIn_intro (Q := fun _ =>
    ⟦∀ w : Fin 16, msg_block.get w
        = (buildMsgBlockRef msg.toList message_size.toNat msg_start.toNat).get w⟧)
  · apply STHoare.ite_intro_of_true (by rfl)
    steps [BLOCK_SIZE_const_spec, min_u32_spec]
    loop_inv nat (fun k _ _ =>
      [msg_item ↦ ⟨Tp.field,
        ((accBytes msg.toList (min message_size.toNat (msg_start.toNat + 64))
            (msg_start.toNat + 4 * ((k - msg_start.toNat - 1) / 4)) k : ℕ) : Fp p)⟩] ⋆
      ⟦∀ w : Fin 16, w.val < (k - msg_start.toNat - 1) / 4 →
          msg_block.get w = BitVec.ofNat 32
            (wordVal msg.toList (min message_size.toNat (msg_start.toNat + 64))
              msg_start.toNat w.val)⟧)
    · -- loop entry, pure part: no words pinned yet (vacuous)
      intro w hw
      omega
    · -- loop entry, heap part: the accumulator starts at 0 (empty window)
      rw [accBytes_empty _ _ _ (by omega)]
      norm_num
    · -- loop bounds
      subst_vars
      have h1Z : ((1:ℤ) : U 32) = (1 : U 32) := rfl
      rw [h1Z] at *
      simp only [BitVec.toNat_add, show BitVec.toNat (1:U 32) = 1 from rfl,
                 show BitVec.toNat (64:U 32) = 64 from rfl] at *
      omega
    · intro k hlo hhi
      steps [INT_SIZE_const_spec]
      any_goals exact ()
      subst_vars
      steps [INT_SIZE_const_spec]
      -- the boundary-check `if`: prove it against the mid-state invariant
      apply STHoare.letIn_intro (Q := fun _ =>
        [msg_item ↦ ⟨Tp.field,
          ((accBytes msg.toList (min message_size.toNat (msg_start.toNat + 64))
              (msg_start.toNat + 4 * ((k - msg_start.toNat) / 4)) k : ℕ) : Fp p)⟩] ⋆
        ⟦∀ w : Fin 16, w.val < (k - msg_start.toNat) / 4 →
            msg_block.get w = BitVec.ofNat 32
              (wordVal msg.toList (min message_size.toNat (msg_start.toNat + 64))
                msg_start.toNat w.val)⟧)
      · subst_vars
        apply STHoare.ite_intro <;> intro hcond
        · -- boundary iteration: the assert pins word (k-mst)/4 - 1
          steps [INT_SIZE_const_spec]
          simp only [decide_eq_true_eq, beq_iff_eq, Bool.and_eq_true, castU_id,
                     show ((1:ℤ) : U 32) = 1 from rfl,
                     show ((0:ℤ) : U 32) = 0 from rfl,
                     show BitVec.toNat (16 : U 32) = 16 from rfl,
                     show BitVec.toNat (64 : U 32) = 64 from rfl,
                     show BitVec.toNat (1 : U 32) = 1 from rfl,
                     BitVec.toNat_ofNatLT] at *
          obtain ⟨hne, hmod⟩ := hcond
          have hkne : k ≠ msg_start.toNat := by
            intro h
            apply hne
            apply BitVec.eq_of_toNat_eq
            simpa [BitVec.toNat_ofNatLT] using h
          have hkmod : k % 4 = 0 := by
            have := congrArg BitVec.toNat hmod
            simpa [BitVec.toNat_umod, BitVec.toNat_ofNatLT,
                   show BitVec.toNat (0 : U 32) = 0 from rfl,
                   show (4 : U 32).toNat = 4 from rfl] using this
          have hlo' : msg_start.toNat ≤ k := hlo
          have hd4 : 4 ≤ k - msg_start.toNat := by omega
          subst msg_block_index
          have h1Z : ((1:ℤ) : U 32) = 1 := rfl
          rw [h1Z] at hhi
          have hk65 : k < msg_start.toNat + 65 := by
            simp only [BitVec.toNat_add, show BitVec.toNat (1 : U 32) = 1 from rfl,
                       show BitVec.toNat (64 : U 32) = 64 from rfl] at hhi
            omega
          have hk32 : k < 2 ^ 32 := by omega
          have hle' : msg_start ≤ (BitVec.ofNatLT k hk32 : U 32) := by
            rw [BitVec.le_def]
            simpa [BitVec.toNat_ofNatLT] using hlo
          have hsub : ((BitVec.ofNatLT k hk32 : U 32) - msg_start).toNat
              = k - msg_start.toNat := by
            rw [BitVec.toNat_sub_of_le hle']
            simp [BitVec.toNat_ofNatLT]
          have hge1' : (1 : U 32) ≤ BitVec.udiv ((BitVec.ofNatLT k hk32 : U 32) - msg_start) 4 := by
            rw [BitVec.le_def, BitVec.udiv_eq, BitVec.toNat_udiv, hsub]
            simp only [show (4:U 32).toNat = 4 from rfl, show (1:U 32).toNat = 1 from rfl]
            omega
          have hidx_val : (BitVec.udiv ((BitVec.ofNatLT k hk32 : U 32) - msg_start) 4
              - 1).toNat = (k - msg_start.toNat) / 4 - 1 := by
            rw [BitVec.toNat_sub_of_le hge1', BitVec.udiv_eq, BitVec.toNat_udiv, hsub]
            simp [show (4:U 32).toNat = 4 from rfl, show (1:U 32).toNat = 1 from rfl]
          simp only [hidx_val] at *
          · -- pure part: extend the pinned words with the newly asserted one
            refine pins_extend _ _ _ _ _ hkmod hd4 (by assumption) (by omega) ?_
            refine word_of_field_eq h_p _ _ (wordVal_lt _ _ _ _) ?_
            rw [← accBytes_boundary _ _ _ _ h_align hkmod hd4 hlo']
            assumption
          · -- heap part: msg_item reset to 0 = empty new window
            simp only [decide_eq_true_eq, Bool.and_eq_true] at hcond
            obtain ⟨hne, hmod⟩ := hcond
            have hkmod : k % 4 = 0 := by
              have := congrArg BitVec.toNat hmod
              simpa [BitVec.toNat_umod, BitVec.toNat_ofNatLT,
                     show ((0:ℤ) : U 32).toNat = 0 from rfl,
                     show (4 : U 32).toNat = 4 from rfl] using this
            have hlo' : msg_start.toNat ≤ k := hlo
            rw [accBytes_empty _ _ _
              (show k ≤ msg_start.toNat + 4 * ((k - msg_start.toNat) / 4) by omega)]
            norm_num
        · -- non-boundary iteration: nothing is asserted; the state carries over
          steps
          simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not, decide_eq_true_eq,
                     not_not] at hcond
          have hcase : k = msg_start.toNat ∨ k % 4 ≠ 0 := by
            rcases hcond with h | h
            · left
              have := congrArg BitVec.toNat h
              simpa [BitVec.toNat_ofNatLT] using this
            · right
              intro hk4
              apply h
              apply BitVec.eq_of_toNat_eq
              simp [BitVec.toNat_umod, BitVec.toNat_ofNatLT,
                    show ((0:ℤ) : U 32).toNat = 0 from rfl,
                    show (4 : U 32).toNat = 4 from rfl, hk4]
          have hlo' : msg_start.toNat ≤ k := hlo
          have hdiv : (k - msg_start.toNat) / 4 = (k - msg_start.toNat - 1) / 4 := by
            rcases hcase with h | h <;> omega
          · -- pure part: same pinned words
            intro w hw
            apply_assumption
            omega
          · -- heap part: same accumulator window
            simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not, decide_eq_true_eq,
                       not_not] at hcond
            have hcase : k = msg_start.toNat ∨ k % 4 ≠ 0 := by
              rcases hcond with h | h
              · left
                have := congrArg BitVec.toNat h
                simpa [BitVec.toNat_ofNatLT] using this
              · right
                intro hk4
                apply h
                apply BitVec.eq_of_toNat_eq
                simp [BitVec.toNat_umod, BitVec.toNat_ofNatLT,
                      show ((0:ℤ) : U 32).toNat = 0 from rfl,
                      show (4 : U 32).toNat = 4 from rfl, hk4]
            have hlo' : msg_start.toNat ≤ k := hlo
            have hdiv : (k - msg_start.toNat) / 4 = (k - msg_start.toNat - 1) / 4 := by
              rcases hcase with h | h <;> omega
            rw [hdiv]
      · intro _
        steps
        apply STHoare.letIn_intro (Q := fun (b : Tp.denote p (Tp.u 8)) =>
          ⟦b.toNat = byteAt msg.toList (min message_size.toNat (msg_start.toNat + 64)) k⟧ ⋆
          [msg_item ↦ ⟨Tp.field,
            ((accBytes msg.toList (min message_size.toNat (msg_start.toNat + 64))
                (msg_start.toNat + 4 * ((k - msg_start.toNat) / 4)) k : ℕ) : Fp p)⟩])
        · -- the byte fetch `if`
          apply STHoare.ite_intro <;> intro hb
          · -- in range: the byte comes from the message array
            steps
            subst_vars
            simp only [decide_eq_true_eq, BitVec.lt_def, castU_id,
                       BitVec.toNat_ofNatLT] at hb
            have hov : msg_start.toNat + 64 < 2 ^ 32 := by
              simpa [show BitVec.toNat (64 : U 32) = 64 from rfl] using
                ‹BitVec.toNat msg_start + BitVec.toNat (64 : U 32) < 2 ^ 32›
            have hadd : (msg_start + (64:U 32)).toNat = msg_start.toNat + 64 := by
              rw [BitVec.toNat_add]
              simp only [show BitVec.toNat (64 : U 32) = 64 from rfl]
              omega
            have hmr : (if compare message_size (msg_start + 64) = Ordering.gt
                then msg_start + 64 else message_size).toNat
                = min message_size.toNat (msg_start.toNat + 64) := by
              rcases Nat.lt_trichotomy message_size.toNat ((msg_start + 64)).toNat with h | h | h
              · have hlt : message_size < msg_start + 64 := by rw [BitVec.lt_def]; exact h
                simp only [compare, compareOfLessAndEq, hlt, if_pos, reduceCtorEq, if_true,
                           if_false]
                simp only [hadd] at h ⊢
                omega
              · have heqv : message_size = msg_start + 64 := by
                  apply BitVec.eq_of_toNat_eq; exact h
                simp [compare, compareOfLessAndEq, heqv]
                simp only [hadd] at h ⊢
                omega
              · have hnlt : ¬ message_size < msg_start + 64 := by
                  rw [BitVec.lt_def]; omega
                have hne : message_size ≠ msg_start + 64 := by
                  intro hE; rw [hE] at h; omega
                have hgt : compare message_size (msg_start + 64) = Ordering.gt := by
                  simp only [compare, compareOfLessAndEq]
                  rw [if_neg hnlt, if_neg hne]
                rw [if_pos hgt, hadd]
                simp only [hadd] at h
                omega
            rw [hmr] at hb
            simp only [castU_id, BitVec.toNat_ofNatLT] at *
            simp only [byteAt, if_pos (show k < _ from hb)]
            have hget : ∀ (pf : k < N.toNat),
                (msg.get ⟨k, pf⟩ : U 8) = msg.toList.getD k (0 : U 8) := by
              intro pf
              have hkN : k < msg.toList.length := by
                simp only [List.Vector.toList_length]
                exact pf
              first
                | (rw [List.getD_eq_getElem _ _ hkN]; rfl)
                | (unfold List.getD; simp [List.getElem?_eq_getElem hkN]; rfl)
            exact congrArg BitVec.toNat (hget _)
          · -- out of range: the byte is 0
            steps
            subst_vars
            simp only [decide_eq_false_iff_not, BitVec.lt_def, castU_id,
                       BitVec.toNat_ofNatLT, not_lt] at hb
            have hov : msg_start.toNat + 64 < 2 ^ 32 := by
              simpa [show BitVec.toNat (64 : U 32) = 64 from rfl] using
                ‹BitVec.toNat msg_start + BitVec.toNat (64 : U 32) < 2 ^ 32›
            have hadd : (msg_start + (64:U 32)).toNat = msg_start.toNat + 64 := by
              rw [BitVec.toNat_add]
              simp only [show BitVec.toNat (64 : U 32) = 64 from rfl]
              omega
            have hmr : (if compare message_size (msg_start + 64) = Ordering.gt
                then msg_start + 64 else message_size).toNat
                = min message_size.toNat (msg_start.toNat + 64) := by
              rcases Nat.lt_trichotomy message_size.toNat ((msg_start + 64)).toNat with h | h | h
              · have hlt : message_size < msg_start + 64 := by rw [BitVec.lt_def]; exact h
                simp only [compare, compareOfLessAndEq, hlt, if_pos, reduceCtorEq, if_true,
                           if_false]
                simp only [hadd] at h ⊢
                omega
              · have heqv : message_size = msg_start + 64 := by
                  apply BitVec.eq_of_toNat_eq; exact h
                simp [compare, compareOfLessAndEq, heqv]
                simp only [hadd] at h ⊢
                omega
              · have hnlt : ¬ message_size < msg_start + 64 := by
                  rw [BitVec.lt_def]; omega
                have hne : message_size ≠ msg_start + 64 := by
                  intro hE; rw [hE] at h; omega
                have hgt : compare message_size (msg_start + 64) = Ordering.gt := by
                  simp only [compare, compareOfLessAndEq]
                  rw [if_neg hnlt, if_neg hne]
                rw [if_pos hgt, hadd]
                simp only [hadd] at h
                omega
            rw [hmr] at hb
            simp [byteAt, show ¬ k < min message_size.toNat (msg_start.toNat + 64) by omega]
        · intro b
          steps [TWO_POW_8_const_spec]
          · -- pinned words carry over unchanged
            intro w hw
            refine (by assumption : ∀ w : Fin 16, ↑w < (k - BitVec.toNat msg_start) / 4 →
                List.Vector.get msg_block w = BitVec.ofNat 32
                  (wordVal msg.toList
                    (min (BitVec.toNat message_size) (BitVec.toNat msg_start + 64))
                    (BitVec.toNat msg_start) ↑w)) w (by omega)
          · -- the accumulator absorbs the byte (Horner step)
            simp only [Lens.modify, Option.get_some]
            have hwin : msg_start.toNat + 4 * ((k + 1 - msg_start.toNat - 1) / 4)
                = msg_start.toNat + 4 * ((k - msg_start.toNat) / 4) := by omega
            rw [hwin]
            rw [accBytes_step _ _ _ _ (by omega)]
            push_cast
            rw [show (Builtin.CastTp.cast (256 : U 32) : Fp p) = (256 : Fp p) from by
                  rw [show (Builtin.CastTp.cast (256:U 32) : Fp p)
                      = ((BitVec.toNat (256:U 32) : ℕ) : Fp p) from rfl,
                     show BitVec.toNat (256 : U 32) = 256 from rfl]
                  norm_num,
                show (Builtin.CastTp.cast b : Fp p) = ((b.toNat : ℕ) : Fp p) from rfl]
            rw [show b.toNat = byteAt msg.toList
                (min message_size.toNat (msg_start.toNat + 64)) k from by assumption]
    · -- post-loop: all 16 words are pinned, so the block equals the reference
      subst_vars
      steps
      have hov : msg_start.toNat + 64 < 2 ^ 32 := by
        simpa [show BitVec.toNat (64 : U 32) = 64 from rfl] using
          ‹BitVec.toNat msg_start + BitVec.toNat (64 : U 32) < 2 ^ 32›
      have h65 : (msg_start + 64 + ((1:ℤ) : U 32)).toNat = msg_start.toNat + 65 := by
        rw [show ((1:ℤ) : U 32) = 1 from rfl, BitVec.toNat_add, BitVec.toNat_add]
        simp only [show BitVec.toNat (64 : U 32) = 64 from rfl,
                   show BitVec.toNat (1 : U 32) = 1 from rfl]
        omega
      intro w
      rw [wordVal_eq_ref, ← wordVal_min _ _ _ _ w.isLt]
      refine (by assumption : ∀ w : Fin 16,
          ↑w < (BitVec.toNat (msg_start + 64 + ((1:ℤ) : U 32)) - BitVec.toNat msg_start - 1) / 4 →
            List.Vector.get msg_block w = BitVec.ofNat 32
              (wordVal msg.toList
                (min (BitVec.toNat message_size) (BitVec.toNat msg_start + 64))
                (BitVec.toNat msg_start) ↑w)) w ?_
      rw [h65]
      omega
  · intro _
    steps
    subst_vars
    apply List.Vector.ext
    intro w
    apply_assumption

/-! ### Helpers for the `process_full_blocks` table construction -/

/-- The intermediate state after compressing the first `j` full blocks. -/
def foldState (compress : MsgBlock → State → State) (bytes : List (U 8)) (ms : ℕ)
    (h₀ : State) (j : ℕ) : State :=
  (List.range j).foldl
    (fun h i => compress (buildMsgBlockRef bytes ms (BLOCK_SIZE * i)) h) h₀

lemma foldState_zero (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) :
    foldState compress bytes ms h₀ 0 = h₀ := rfl

lemma foldState_succ (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) (j : ℕ) :
    foldState compress bytes ms h₀ (j + 1)
      = compress (buildMsgBlockRef bytes ms (BLOCK_SIZE * j))
          (foldState compress bytes ms h₀ j) := by
  unfold foldState
  rw [List.range_succ, List.foldl_append]
  rfl

/-- A block built entirely past the end of the message is all zeroes. -/
lemma buildMsgBlockRef_of_le (bytes : List (U 8)) (ms start : ℕ) (h : ms ≤ start) :
    buildMsgBlockRef bytes ms start = vecReplicate 16 0 := by
  apply List.Vector.ext
  intro i
  simp only [buildMsgBlockRef, vecOfFn_eq_ofFn, List.Vector.get_ofFn]
  have hrep : (vecReplicate 16 (0:U 32)).get i = 0 := by
    simp only [vecReplicate, List.Vector.get, List.get_eq_getElem]
    exact List.getElem_replicate _
  rw [hrep]
  simp only [if_neg (show ¬ start + INT_SIZE * i.val + 0 < ms by omega),
             if_neg (show ¬ start + INT_SIZE * i.val + 1 < ms by omega),
             if_neg (show ¬ start + INT_SIZE * i.val + 2 < ms by omega),
             if_neg (show ¬ start + INT_SIZE * i.val + 3 < ms by omega)]
  rfl

lemma vecReplicate_eq {α : Type} (n : ℕ) (a : α) :
    vecReplicate n a = List.Vector.replicate n a := by
  apply List.Vector.eq
  rfl

/-- The states table after `i` loop iterations: entry `j ≤ i` holds the fold of
    the first `j` blocks; later entries still hold the initial state. -/
def statesVec (compress : MsgBlock → State → State) (bytes : List (U 8)) (ms : ℕ)
    (h₀ : State) (n i : ℕ) : List.Vector State n :=
  List.Vector.ofFn (fun j =>
    if j.val ≤ i then foldState compress bytes ms h₀ j.val else h₀)

/-- The blocks table after `i` loop iterations: entry `j < i` holds block `j`;
    later entries are still zeroed. -/
def blocksVec (bytes : List (U 8)) (ms n i : ℕ) : List.Vector MsgBlock n :=
  List.Vector.ofFn (fun j =>
    if j.val < i then buildMsgBlockRef bytes ms (BLOCK_SIZE * j.val)
    else vecReplicate 16 0)

lemma statesVec_zero (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) (n : ℕ) :
    statesVec compress bytes ms h₀ n 0 = List.Vector.replicate n h₀ := by
  apply List.Vector.ext
  intro j
  simp only [statesVec, List.Vector.get_ofFn, List.Vector.get_replicate]
  by_cases h : j.val ≤ 0
  · rw [if_pos h, show j.val = 0 by omega]
    rfl
  · rw [if_neg h]

lemma blocksVec_zero (bytes : List (U 8)) (ms n : ℕ) :
    blocksVec bytes ms n 0 = List.Vector.replicate n (List.Vector.replicate 16 0) := by
  apply List.Vector.ext
  intro j
  simp only [blocksVec, List.Vector.get_ofFn, List.Vector.get_replicate,
             if_neg (by omega : ¬ j.val < 0), vecReplicate_eq]

lemma statesVec_get (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) (n i : ℕ)
    (j : Fin n) (h : j.val ≤ i) :
    (statesVec compress bytes ms h₀ n i).get j = foldState compress bytes ms h₀ j.val := by
  simp only [statesVec, List.Vector.get_ofFn, if_pos h]

lemma statesVec_set (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) (n i : ℕ)
    (hn : i + 1 < n) :
    (statesVec compress bytes ms h₀ n i).set ⟨i + 1, hn⟩
        (compress (buildMsgBlockRef bytes ms (BLOCK_SIZE * i))
          (foldState compress bytes ms h₀ i))
      = statesVec compress bytes ms h₀ n (i + 1) := by
  apply List.Vector.ext
  intro j
  by_cases hj : j = ⟨i + 1, hn⟩
  · subst hj
    rw [List.Vector.get_set_same]
    simp only [statesVec, List.Vector.get_ofFn, if_pos (le_refl _)]
    exact (foldState_succ compress bytes ms h₀ i).symm
  · rw [List.Vector.get_set_of_ne (Ne.symm hj)]
    have hjv : j.val ≠ i + 1 := fun hc => hj (Fin.ext hc)
    simp only [statesVec, List.Vector.get_ofFn]
    by_cases hle : j.val ≤ i
    · rw [if_pos hle, if_pos (by omega)]
    · rw [if_neg hle, if_neg (by omega)]

lemma blocksVec_set (bytes : List (U 8)) (ms n i : ℕ) (hn : i < n) :
    (blocksVec bytes ms n i).set ⟨i, hn⟩ (buildMsgBlockRef bytes ms (BLOCK_SIZE * i))
      = blocksVec bytes ms n (i + 1) := by
  apply List.Vector.ext
  intro j
  by_cases hj : j = ⟨i, hn⟩
  · subst hj
    rw [List.Vector.get_set_same]
    simp only [blocksVec, List.Vector.get_ofFn, if_pos (by omega : (i:ℕ) < i + 1)]
  · rw [List.Vector.get_set_of_ne (Ne.symm hj)]
    have hjv : j.val ≠ i := fun hc => hj (Fin.ext hc)
    simp only [blocksVec, List.Vector.get_ofFn]
    by_cases hlt : j.val < i
    · rw [if_pos hlt, if_pos (by omega)]
    · rw [if_neg hlt, if_neg (by omega)]

lemma blocksVec_get (bytes : List (U 8)) (ms n i : ℕ) (j : Fin n) :
    (blocksVec bytes ms n i).get j
      = if j.val < i then buildMsgBlockRef bytes ms (BLOCK_SIZE * j.val)
        else vecReplicate 16 0 := by
  simp [blocksVec, List.Vector.get_ofFn]

lemma statesVec_step (compress) (bytes : List (U 8)) (ms : ℕ) (h₀ : State) (n i : ℕ)
    (hn : i + 1 < n) (pf : i < n) :
    (statesVec compress bytes ms h₀ n i).set ⟨i + 1, hn⟩
      (compress (buildMsgBlockRef bytes ms (BLOCK_SIZE * i))
        ((statesVec compress bytes ms h₀ n i).get ⟨i, pf⟩))
    = statesVec compress bytes ms h₀ n (i + 1) := by
  rw [statesVec_get _ _ _ _ _ _ _ (le_refl i)]
  exact statesVec_set _ _ _ _ _ _ hn

theorem process_full_blocks_spec {p : Prime} {N : U 32}
    (h_p : 2 ^ 64 < p.natVal)
    (msg : List.Vector (U 8) N.toNat)
    (message_size : U 32)
    (initial_state : State)
    (h_size : message_size.toNat ≤ N.toNat)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::process_full_blocks».call h![N]
        h![msg, message_size, initial_state])
      (fun r =>
        let (h, block) := processFullBlocksRef msg.toList message_size.toNat initial_state
        r = (h, block, ())) := by
  enter_decl
  steps
  any_goals exact ()
  apply STHoare.ite_intro_of_false (by rfl)
  steps [BLOCK_SIZE_const_spec, uGeq_intro]
  apply STHoare.letIn_intro (Q := fun (v : Tp.denote p (Tp.u 32)) =>
    ⟦v.toNat = message_size.toNat / 64⟧ ⋆
    ([states ↦ ⟨((Tp.u 32).array 8).array ((BitVec.udiv N 64).add 1),
      List.Vector.replicate ((BitVec.udiv N 64).add 1).toNat initial_state⟩] ⋆
     [blocks ↦ ⟨((Tp.u 32).array 16).array ((BitVec.udiv N 64).add 1),
      Tp.zero p (((Tp.u 32).array 16).array ((BitVec.udiv N 64).add 1))⟩]))
  · apply STHoare.ite_intro <;> intro hge
    · steps [BLOCK_SIZE_const_spec]
      subst_vars
      show (BitVec.udiv message_size 64).toNat = _
      rw [BitVec.udiv_eq, BitVec.toNat_udiv]
      rfl
    · steps
      subst_vars
      simp only [decide_eq_false_iff_not, ge_iff_le, BitVec.le_def] at hge
      rw [show ((0:ℤ) : U 32) = 0 from rfl]
      have hz : message_size.toNat / 64 = 0 := by
        have h64 : BitVec.toNat (64 : U 32) = 64 := rfl
        rw [h64] at hge
        omega
      rw [hz]
      rfl
  · intro first
    steps
    loop_inv nat (fun i _ _ =>
      [states ↦ ⟨((Tp.u 32).array 8).array ((BitVec.udiv N 64).add 1),
        statesVec sha256CompressionFn msg.toList message_size.toNat initial_state
          ((BitVec.udiv N 64).add 1).toNat i⟩] ⋆
      [blocks ↦ ⟨((Tp.u 32).array 16).array ((BitVec.udiv N 64).add 1),
        blocksVec msg.toList message_size.toNat ((BitVec.udiv N 64).add 1).toNat i⟩])
    · -- blocks entry: zeroed = blocksVec 0
      rw [show BitVec.toNat (((0:ℤ)) : U 32) = 0 from rfl, blocksVec_zero]
      rfl
    · -- states entry: replicate initial = statesVec 0
      rw [show BitVec.toNat (((0:ℤ)) : U 32) = 0 from rfl, statesVec_zero]
      rfl
    · -- loop lower bound
      rw [show ((0:ℤ) : U 32) = 0 from rfl]
      exact Nat.zero_le _
    · -- loop body
      intro i hlo hhi
      steps [BLOCK_SIZE_const_spec]
      steps [build_msg_block_spec, h_comp]
      · -- states table extended at i+1
        subst_vars
        have hN64 : BitVec.toNat (64 : U 32) = 64 := rfl
        have h1 : BitVec.toNat (1 : U 32) = 1 := rfl
        have hn : ((BitVec.udiv N 64).add 1).toNat = N.toNat / 64 + 1 := by
          show ((BitVec.udiv N 64) + 1).toNat = _
          rw [BitVec.toNat_add, BitVec.udiv_eq, BitVec.toNat_udiv, hN64, h1]
          have hN := N.isLt
          omega
        have hhi' : i < N.toNat / 64 := by
          rw [BitVec.udiv_eq, BitVec.toNat_udiv, hN64] at hhi
          exact hhi
        have hms : ((64 : U 32) * BitVec.ofNatLT i (by omega)).toNat = 64 * i := by
          rw [BitVec.toNat_mul, BitVec.toNat_ofNatLT, hN64]
          rw [hN64, BitVec.toNat_ofNatLT] at *
          omega
        have hi1 : ((BitVec.ofNatLT i (by omega) : U 32) + ((1:ℤ) : U 32)).toNat = i + 1 := by
          rw [show ((1:ℤ) : U 32) = 1 from rfl, BitVec.toNat_add, BitVec.toNat_ofNatLT, h1]
          omega
        have hbnd : i + 1 < ((BitVec.udiv N 64).add 1).toNat := by rw [hn]; omega
        simp only [castU_id, BitVec.toNat_ofNatLT, Lens.modify, Lens.get, Access.modify,
                   hms, hi1] at *
        simp only [dif_pos hbnd, Option.pure_def, Option.bind_eq_bind, Option.bind_some]
        exact congrArg _ (statesVec_step _ _ _ _ _ _ hbnd (by omega))
      · -- blocks table extended at i
        subst_vars
        have hN64 : BitVec.toNat (64 : U 32) = 64 := rfl
        have hn : ((BitVec.udiv N 64).add 1).toNat = N.toNat / 64 + 1 := by
          show ((BitVec.udiv N 64) + 1).toNat = _
          rw [BitVec.toNat_add, BitVec.udiv_eq, BitVec.toNat_udiv, hN64,
              show BitVec.toNat (1 : U 32) = 1 from rfl]
          have hN := N.isLt
          omega
        have hhi' : i < N.toNat / 64 := by
          rw [BitVec.udiv_eq, BitVec.toNat_udiv, hN64] at hhi
          exact hhi
        have hms : ((64 : U 32) * BitVec.ofNatLT i (by omega)).toNat = 64 * i := by
          rw [BitVec.toNat_mul, BitVec.toNat_ofNatLT, hN64]
          rw [hN64, BitVec.toNat_ofNatLT] at *
          omega
        have hbnd : i < ((BitVec.udiv N 64).add 1).toNat := by rw [hn]; omega
        simp only [castU_id, BitVec.toNat_ofNatLT, Lens.modify, Lens.get, Access.modify,
                   hms] at *
        simp only [dif_pos hbnd, Option.pure_def, Option.bind_eq_bind, Option.bind_some]
        exact congrArg _ (blocksVec_set _ _ _ _ hbnd)
      · exact h_p
      · subst_vars
        rw [BitVec.toNat_mul]
        have h64 : BitVec.toNat (64 : U 32) = 64 := rfl
        rw [h64, BitVec.toNat_ofNatLT]
        omega
    · -- after the loop
      steps [BLOCK_SIZE_const_spec]
      apply STHoare.letIn_intro (Q := fun _ =>
        [states ↦ ⟨((Tp.u 32).array 8).array ((BitVec.udiv N 64).add 1),
          statesVec sha256CompressionFn msg.toList message_size.toNat initial_state
            ((BitVec.udiv N 64).add 1).toNat (BitVec.udiv N 64).toNat⟩] ⋆
        [blocks ↦ ⟨((Tp.u 32).array 16).array ((BitVec.udiv N 64).add 1),
          blocksVec msg.toList message_size.toNat ((BitVec.udiv N 64).add 1).toNat
            (N.toNat / 64 + if N.toNat % 64 ≠ 0 then 1 else 0)⟩])
      · apply STHoare.ite_intro <;> intro hcond
        · steps [BLOCK_SIZE_const_spec]
          steps [build_msg_block_spec]
          · -- states unchanged
            subst num_blocks
            rfl
          · -- blocks extended with the final partial block
            subst_vars
            simp only [decide_eq_true_eq] at hcond
            have hne : N.toNat % 64 ≠ 0 := by
              intro h0
              apply hcond
              apply BitVec.eq_of_toNat_eq
              simp [BitVec.toNat_umod, show ((0:ℤ) : U 32).toNat = 0 from rfl,
                    show BitVec.toNat (64 : U 32) = 64 from rfl, h0]
            rw [if_pos hne]
            have hN := N.isLt
            have hnb : (BitVec.udiv N 64).toNat = N.toNat / 64 := by
              rw [BitVec.udiv_eq, BitVec.toNat_udiv]
              rfl
            have hn : ((BitVec.udiv N 64).add 1).toNat = N.toNat / 64 + 1 := by
              show ((BitVec.udiv N 64) + 1).toNat = _
              rw [BitVec.toNat_add, hnb, show BitVec.toNat (1 : U 32) = 1 from rfl]
              omega
            have hmul : ((64 : U 32) * BitVec.udiv N 64).toNat = 64 * (N.toNat / 64) := by
              rw [BitVec.toNat_mul, hnb, show BitVec.toNat (64 : U 32) = 64 from rfl]
              omega
            have hbnd : N.toNat / 64 < ((BitVec.udiv N 64).add 1).toNat := by
              rw [hn]
              omega
            simp only [Lens.modify, Lens.get, Access.modify, hmul, hnb,
                       Option.bind_eq_bind, Option.bind_some]
            simp only [dif_pos hbnd, Option.bind_eq_bind, Option.bind_some]
            exact congrArg _ (blocksVec_set _ _ _ _ hbnd)
          · exact h_p
          · -- alignment of the final block start
            subst num_blocks
            rw [BitVec.toNat_mul]
            have h64 : BitVec.toNat (64 : U 32) = 64 := rfl
            rw [h64]
            omega
        · steps
          · -- states unchanged
            subst num_blocks
            rfl
          · -- blocks unchanged (no partial block)
            subst_vars
            simp only [decide_eq_false_iff_not, not_not] at hcond
            have hz : N.toNat % 64 = 0 := by
              have := congrArg BitVec.toNat hcond
              simpa [BitVec.toNat_umod, show ((0:ℤ) : U 32).toNat = 0 from rfl,
                     show BitVec.toNat (64 : U 32) = 64 from rfl,
                     show BitVec.toNat (0 : U 32) = 0 from rfl] using this
            rw [if_neg (by omega)]
            rfl
      · intro _
        steps
        subst_vars
        have hfirst : BitVec.toNat first = BitVec.toNat message_size / 64 := by assumption
        have hN := N.isLt
        have hnb : (BitVec.udiv N 64).toNat = N.toNat / 64 := by
          rw [BitVec.udiv_eq, BitVec.toNat_udiv]
          rfl
        have hdle : message_size.toNat / 64 ≤ N.toNat / 64 :=
          Nat.div_le_div_right h_size
        simp only [castU_id, hfirst, HList.toTuple,
                   processFullBlocksRef, processFullBlocksWith, BLOCK_SIZE,
                   Prod.mk.injEq]
        refine Prod.ext ?_ (Prod.ext ?_ rfl)
        · -- intermediate state component
          dsimp only
          have hle' : message_size.toNat / 64 ≤ (BitVec.udiv N 64).toNat := by
            rw [hnb]; exact hdle
          exact (statesVec_get _ _ _ _ _ _ _ hle').trans rfl
        · -- partial block component
          dsimp only
          refine (blocksVec_get _ _ _ _ _).trans ?_
          dsimp only
          by_cases hz : message_size.toNat % 64 = 0
          · rw [if_neg (show ¬ message_size.toNat % 64 ≠ 0 from by omega)]
            by_cases hc : message_size.toNat / 64
                < N.toNat / 64 + (if N.toNat % 64 ≠ 0 then 1 else 0)
            · rw [if_pos hc, buildMsgBlockRef_of_le _ _ _ (by simp only [BLOCK_SIZE]; omega)]
            · rw [if_neg hc]
          · rw [if_pos hz]
            rw [if_pos (by
              by_cases hNz : N.toNat % 64 ≠ 0
              · rw [if_pos hNz]
                have := Nat.div_le_div_right (c := 64) h_size
                omega
              · rw [if_neg hNz]
                have h2 : N.toNat % 64 = 0 := not_not.mp hNz
                have h3 : message_size.toNat ≤ N.toNat := h_size
                omega)]
            rfl


/-- `attach_len_to_msg_block` writes the encoded bit-length into words 14 and 15.

    Proof strategy: the unconstrained `encode_len` produces a witness `(lo, hi)`;
    the assertion `8 * message_size = lo + hi * 2^32` pins the values uniquely
    (since both limbs fit in u32), so the result equals `attachLenRef`. -/
theorem attach_len_to_msg_block_spec {p : Prime}
    (h_p          : 2 ^ 64 < p.natVal)
    (block        : MsgBlock)
    (message_size : U 32) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::attach_len_to_msg_block».call h![] h![block, message_size])
      (fun r => r = attachLenRef block message_size.toNat) := by
  enter_decl
  steps
  apply STHoare.letIn_assoc.mpr
  steps [encode_len_spec, TWO_POW_32_const_spec, INT_SIZE_PTR_const_spec]
  block_steps [encode_len_spec, TWO_POW_32_const_spec, INT_SIZE_PTR_const_spec]
  block_steps [INT_SIZE_PTR_const_spec]
  block_steps [INT_SIZE_PTR_const_spec]
  block_steps [INT_SIZE_PTR_const_spec]
  block_steps [INT_SIZE_PTR_const_spec]
  block_steps [INT_SIZE_PTR_const_spec]
  subst_vars
  -- Name the two u32 limbs returned by the `encode_len` oracle.
  generalize hhi : Builtin.indexTpl _ Member.head.tail = hi at *
  generalize hlo : Builtin.indexTpl _ Member.head = lo at *
  simp only [Builtin.CastTp.cast, decide_eq_true_eq, beq_iff_eq] at *
  rename_i hassert
  have hms_lt := message_size.isLt
  have hlo_lt := lo.isLt
  have hhi_lt := hi.isLt
  have h32 : (2:ℕ) ^ 32 = 4294967296 := by norm_num
  have h64 : (2:ℕ) ^ 64 = 18446744073709551616 := by norm_num
  -- The asserted field equation lifts to ℕ because both sides are < p.
  have h8 : 8 * message_size.toNat = lo.toNat + hi.toNat * 2 ^ 32 := by
    have hcast : ((8 * message_size.toNat : ℕ) : Fp p)
        = ((lo.toNat + hi.toNat * 2 ^ 32 : ℕ) : Fp p) := by
      push_cast
      push_cast at hassert
      rw [hassert]
    have hmod := (ZMod.natCast_eq_natCast_iff _ _ _).mp hcast
    have h1 : 8 * message_size.toNat < p.natVal := by omega
    have h2 : lo.toNat + hi.toNat * 2 ^ 32 < p.natVal := by omega
    exact Nat.ModEq.eq_of_lt_of_lt hmod h1 h2
  -- The ℕ equation pins both limbs, since each fits in 32 bits.
  have hhi_eq : hi = BitVec.ofNat 32 (8 * message_size.toNat / 4294967296) := by
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_ofNat]
    omega
  have hlo_eq : lo = BitVec.ofNat 32 (8 * message_size.toNat % 4294967296) := by
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_ofNat]
    omega
  simp [attachLenRef, encodeLenRef, hhi_eq, hlo_eq]
  rfl

/-- The first `n` bytes of `stateToHashRef s`, with the remaining bytes 0. -/
def hashPrefix (s : State) (n : ℕ) : Hash :=
  List.Vector.ofFn (fun (i : Fin 32) => if i.val < n then (stateToHashRef s).get i else (0:U 8))

lemma hashPrefix_get (s : State) (n : ℕ) (i : Fin 32) :
    (hashPrefix s n).get i = if i.val < n then (stateToHashRef s).get i else 0 := by
  simp [hashPrefix, List.Vector.get_ofFn]

lemma stateToHashRef_get (s : State) (i : Fin 32) :
    (stateToHashRef s).get i
      = BitVec.ofNat 8 (((s.get ⟨i.val / 4, by omega⟩).toNat >>> (8 * (3 - i.val % 4))) % 256) := by
  simp only [stateToHashRef, vecOfFn_eq_ofFn, List.Vector.get_ofFn]

lemma hashPrefix_zero (s : State) : hashPrefix s 0 = List.Vector.replicate 32 0 := by
  apply List.Vector.ext
  intro i
  simp only [hashPrefix_get, List.Vector.get_replicate]
  simp

lemma hashPrefix_full (s : State) : hashPrefix s 32 = stateToHashRef s := by
  apply List.Vector.ext
  intro i
  simp [hashPrefix_get, i.isLt]

lemma hashPrefix_set (s : State) (n : ℕ) (h : n < 32) :
    (hashPrefix s n).set ⟨n, h⟩ ((stateToHashRef s).get ⟨n, h⟩) = hashPrefix s (n+1) := by
  apply List.Vector.ext
  intro i
  by_cases hi : i = ⟨n, h⟩
  · subst hi
    rw [List.Vector.get_set_same, hashPrefix_get]
    simp
  · rw [List.Vector.get_set_of_ne (Ne.symm hi)]
    have hne : i.val ≠ n := fun hc => hi (Fin.ext hc)
    simp only [hashPrefix_get]
    by_cases hlt : i.val < n
    · simp [hlt, show i.val < n + 1 by omega]
    · simp [hlt, show ¬ i.val < n + 1 by omega]

/-- Byte `k` of the 4-byte big-endian decomposition of `w < 256^4`. -/
lemma toDigitsBE_get_byte (w : ℕ) (hw : w < 256 ^ 4) (k : ℕ) (hk : k < 4) :
    ((RadixVec.toDigitsBE (r := ⟨256, by norm_num⟩) (⟨w, hw⟩ : RadixVec _ 4)).map
      BitVec.ofFin).get ⟨k, hk⟩
      = BitVec.ofNat 8 ((w >>> (8 * (3 - k))) % 256) := by
  have h4 : k = 0 ∨ k = 1 ∨ k = 2 ∨ k = 3 := by omega
  rcases h4 with h4 | h4 | h4 | h4 <;> subst h4 <;>
    (simp [RadixVec.toDigitsBE, RadixVec.msd, RadixVec.lsds, List.Vector.get,
           Nat.shiftRight_eq_div_pow]
     apply BitVec.eq_of_toNat_eq
     simp [BitVec.toNat_ofNat]
     omega)

/-- One iteration of the byte-serialisation loop: writing byte `k` of word `i`
    (obtained from `to_be_bytes`) at position `4*i + k` extends the prefix. -/
lemma hashPrefix_step (s : State) (i k w : ℕ) (hi : i < 8) (hk : k < 4)
    (hw : w = (s.get ⟨i, hi⟩).toNat)
    (pf : w < 256 ^ 4) (pf2 : k < 4) (h32 : 4 * i + k < 32) :
    (hashPrefix s (4 * i + k)).set ⟨4 * i + k, h32⟩
      ((List.Vector.map BitVec.ofFin (RadixVec.toDigitsBE (r := ⟨256, by norm_num⟩)
        (⟨w, pf⟩ : RadixVec _ 4))).get ⟨k, pf2⟩)
      = hashPrefix s (4 * i + (k + 1)) := by
  subst hw
  rw [toDigitsBE_get_byte _ _ _ hk]
  have hbyte : BitVec.ofNat 8 (((s.get ⟨i, hi⟩).toNat >>> (8 * (3 - k))) % 256)
      = (stateToHashRef s).get ⟨4 * i + k, h32⟩ := by
    rw [stateToHashRef_get]
    have h1 : (4 * i + k) / 4 = i := by omega
    have h2 : (4 * i + k) % 4 = k := by omega
    simp only [h1, h2]
  rw [hbyte, hashPrefix_set]
  rfl

/-- `hash_final_block` compresses `block` against `state` via `sha256Compression`,
    then unpacks the resulting 8-word state into 32 bytes big-endian.

    Proof strategy:
    1. Apply `h_comp` to rewrite the `#_sha256Compression` builtin call to
       `sha256CompressionFn block state`, binding the resulting state to `state'`.
    2. Unfold the two nested loops (outer `j : 0..8`, inner `k : 0..4`): each
       iteration writes `(to_be_bytes state'[j])[k]` into `out_h[4*j+k]`.
    3. Show that big-endian byte `k` of word `w` equals
       `(w.toNat >>> (8 * (3 - k))) % 256`, matching the `stateToHashRef`
       formula `BitVec.ofNat 8 ((word >>> shift) % 256)` with `shift = 8*(3-k)`.
    4. Conclude by element-wise equality across all 32 output positions (`vecOfFn`). -/
theorem hash_final_block_spec {p : Prime}
    (h_p : 2 ^ 64 < p.natVal)
    (block : MsgBlock)
    (st : State)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::hash_final_block».call h![] h![block, st])
      (fun r => r = stateToHashRef (sha256CompressionFn block st)) := by
  enter_decl
  steps
  block_steps [h_comp]
  loop_inv nat (fun j _ _ =>
    [state ↦ ⟨(«sha256-0.0.0::sha256::constants::STATE» h![]), sha256CompressionFn block st⟩] ⋆
    [out_h ↦ ⟨(Tp.u 8).array 32, hashPrefix (sha256CompressionFn block st) (4 * j)⟩])
  · have h0 : ((0:ℤ) : U 32) = 0 := rfl
    have h8 : ((8:ℤ) : U 32) = 8 := rfl
    rw [h0, h8]
    decide
  · intro i hlo hhi
    steps [Lampe.Stdlib.Field.to_be_bytes_intro]
    loop_inv nat (fun k _ _ =>
      [out_h ↦ ⟨(Tp.u 8).array 32,
        hashPrefix (sha256CompressionFn block st) (4 * i + k)⟩])
    · have h0 : ((0:ℤ) : U 32) = 0 := rfl
      have h4 : ((4:ℤ) : U 32) = 4 := rfl
      rw [h0, h4]
      decide
    · intro k hk0 hk4
      steps
      subst_vars
      have h4Z : ((4:ℤ) : U 32) = (4 : U 32) := rfl
      have h8Z : ((8:ℤ) : U 32) = (8 : U 32) := rfl
      have hi8 : i < 8 := by rw [h8Z] at hhi; simpa using hhi
      have hk4' : k < 4 := by rw [h4Z] at hk4; simpa using hk4
      have hidx32 : 4 * i + k < 32 := by omega
      simp only [h4Z, Builtin.CastTp.cast, BitVec.setWidth_eq, BitVec.toNat_ofNatLT] at *
      have hval : ∀ (word : U 32), (((word.toNat : ℕ)) : Fp p).val = word.toNat :=
        fun word => ZMod.val_natCast_of_lt (by
          have h1 := word.isLt
          have h2 : (2:ℕ) ^ 32 ≤ 2 ^ 64 := by norm_num
          omega)
      have hidx : ((4 : U 32) * (BitVec.ofNatLT i (by omega)) + BitVec.ofNatLT k (by omega)
          : U 32).toNat = 4 * i + k := by
        simp [BitVec.toNat_add, BitVec.toNat_mul, BitVec.toNat_ofNatLT]
        omega
      simp only [Lens.modify, Lens.get, Access.modify, hidx] at *
      simp only [show BitVec.toNat (32 : U 32) = 32 from rfl] at *
      simp only [dif_pos hidx32]
      refine congrArg _ (hashPrefix_step (sha256CompressionFn block st) i k _ _ hk4'
        (hval _)
        (lt_of_eq_of_lt (hval _) (lt_of_lt_of_le (BitVec.isLt _) (by norm_num)))
        hk4' hidx32)
    · -- after the inner loop: conclude the outer invariant at i+1
      steps
      done
  · -- continuation after the outer loop: read out_h and conclude
    steps
    subst_vars
    rw [show (4 * BitVec.toNat (((8:ℤ)):U 32)) = 32 from rfl, hashPrefix_full]
    done

/-- `add_padding_byte_and_compress_if_needed` inserts the 0x80 padding byte at
    `msg_byte_ptr` and conditionally flushes the block, matching
    `addPaddingAndCompressRef`.

    Proof strategy:
    1. Evaluate `PADDING_BIT_TABLE[msg_byte_ptr % INT_SIZE]`: since
       `msg_byte_ptr % 4 ∈ {0,1,2,3}` and the table holds
       `[0x80000000, 0x00800000, 0x00008000, 0x00000080]`, show the looked-up
       value equals `paddingWordNat msg_byte_ptr` in each case.
    2. Show the in-place word update at `index = msg_byte_ptr / INT_SIZE` matches
       `block.set word_idx (block.get word_idx + BitVec.ofNat 32 (paddingWordNat msg_byte_ptr))`,
       yielding `block'`.
    3. Case-split on `msg_byte_ptr ≥ MSG_SIZE_PTR` (i.e. `msg_byte_ptr ≥ 56`):
       - **True branch**: apply `h_comp` to reduce the `#_sha256Compression` call
         to `sha256CompressionFn block' state`, and show the reset
         `msg_block = [0; 16]` equals `vecReplicate 16 0`; the result matches
         `addPaddingAndCompressRef` in the `≥ MSG_SIZE_PTR` branch.
       - **False branch**: no compression occurs; the pair `(state, block')` directly
         matches `addPaddingAndCompressRef` in the `< MSG_SIZE_PTR` branch. -/
theorem add_padding_and_compress_spec {p : Prime}
    (block        : MsgBlock)
    (msg_byte_ptr : U 32)
    (h_bnd        : msg_byte_ptr.toNat < BLOCK_SIZE)
    (state        : State)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::add_padding_byte_and_compress_if_needed».call h![]
        h![block, msg_byte_ptr, state])
      (fun r =>
        let (h', block') := addPaddingAndCompressRef block msg_byte_ptr.toNat h_bnd state
        r = (h', block', ())) := by
  enter_decl
  steps
  block_steps [INT_SIZE_const_spec, PADDING_BIT_TABLE_const_spec]
  block_steps [MSG_SIZE_PTR_const_spec, uGeq_intro]
  subst_vars
  apply STHoare.ite_intro <;> intro hcond
  -- Both branches: execute the straight-line code, then align the resulting
  -- state/block pair with the corresponding branch of `addPaddingAndCompressRef`.
  all_goals (
    first | steps [h_comp] | steps
    subst_vars
    simp only [decide_eq_true_eq, decide_eq_false_iff_not, ge_iff_le, not_le,
               BitVec.le_def, BitVec.lt_def] at hcond
    norm_num at hcond
    have hidx : msg_byte_ptr.toNat / 4 < 16 := by
      simp only [BLOCK_SIZE] at h_bnd; omega
    simp only [HList.toTuple, Builtin.CastTp.cast,
               BitVec.toNat_udiv, BitVec.toNat_umod] at *
    norm_num at *
    have h56 : (56 : U 32).toNat = 56 := rfl
    rw [h56] at hcond
    have h4 : msg_byte_ptr.toNat % 4 = 0 ∨ msg_byte_ptr.toNat % 4 = 1 ∨
              msg_byte_ptr.toNat % 4 = 2 ∨ msg_byte_ptr.toNat % 4 = 3 := by omega
    first
      | have hif : 56 ≤ msg_byte_ptr.toNat := by omega
      | have hif : ¬ 56 ≤ msg_byte_ptr.toNat := by omega
    -- The padding word: case on the byte position within the u32 word.
    simp [Lens.modify, Access.modify, hidx, addPaddingAndCompressRef, addPaddingAndCompressWith,
          MSG_SIZE_PTR, INT_SIZE, hif, paddingWordNat]
    rcases h4 with h4 | h4 | h4 | h4 <;> simp [h4] <;> rfl
    done)

/-- `finalize_sha256_blocks` pads the partial block, writes the length, performs
    the final compression, and serialises the state — matching
    `finalizeSha256BlocksRef`.

    Proof strategy: compose `add_padding_and_compress_spec`,
    `attach_len_to_msg_block_spec`, `hash_final_block_spec`. -/
theorem finalize_sha256_blocks_spec {p : Prime}
    (h_p          : 2 ^ 64 < p.natVal)
    (message_size : U 32)
    (h            : State)
    (block        : MsgBlock)
    (h_comp : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::finalize_sha256_blocks».call h![] h![message_size, h, block])
      (fun r => r = finalizeSha256BlocksRef message_size.toNat h block) := by
  enter_decl
  steps [BLOCK_SIZE_const_spec,
         add_padding_and_compress_spec,
         attach_len_to_msg_block_spec,
         hash_final_block_spec]
  · -- Props goal: r = finalizeSha256BlocksRef ... with r = stateToHashRef X in context.
    simp_all [finalizeSha256BlocksRef, finalizeSha256BlocksWith, addPaddingAndCompressRef,
              BLOCK_SIZE, BitVec.toNat_umod]
    -- The tuple projections `Builtin.indexTpl (h, block, ()) Member.head[.tail]` reduce definitionally.
    rfl
  -- Side goals: Sha256CompressionSpec (for hash_final_block / add_padding), the field
  -- size bound (for attach_len), and msg_byte_ptr < BLOCK_SIZE (for add_padding).
  all_goals first
    | exact h_comp
    | exact h_p
    | (simp_all [BLOCK_SIZE, BitVec.toNat_umod]; exact Nat.mod_lt _ (by norm_num))

-- ============================================================
-- 6.  Main correctness theorem
-- ============================================================

/-- `INITIAL_STATE` constant evaluates to `initialState`. Needed so that `steps`
    can process the `let #v = INITIAL_STATE()` binding in `sha256_var`. -/
theorem INITIAL_STATE_const_spec {p : Prime} :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::constants::INITIAL_STATE».call h![] h![])
      (fun r => r = initialState) := by
  enter_decl
  steps
  simp_all [initialState, HList.toVec]
  norm_cast

/-- `sha256_var` is correct: given a byte array `msg` of capacity `N` and a
    runtime `message_size ≤ N`, it returns the SHA-256 digest of the first
    `message_size` bytes of `msg`.

    The proof proceeds by:
    1. Applying `process_full_blocks_spec` to relate the constrained block
       loop to `processFullBlocksRef`.
    2. Applying `finalize_sha256_blocks_spec` to relate the padding and final
       compression to `finalizeSha256BlocksRef`.
    3. Unfolding `sha256VarSpec` and `sha256Ref` to conclude.

    Prerequisite:
    · `h_comp` — the `sha256Compression` Lampe builtin behaves as
      `sha256CompressionFn`. -/
theorem sha256_var_correct {p : Prime} {N : U 32}
    (h_p          : 2 ^ 64 < p.natVal)
    (msg          : List.Vector (U 8) N.toNat)
    (message_size : U 32)
    (h_bound      : message_size.toNat ≤ N.toNat)
    (h_comp       : Sha256CompressionSpec p «sha256-0.0.0».env) :
    STHoare p «sha256-0.0.0».env ⟦⟧
      («sha256-0.0.0::sha256::sha256_var».call h![N] h![msg, message_size])
      (fun result => result = sha256VarSpec msg message_size.toNat) := by
  enter_decl
  steps [INITIAL_STATE_const_spec,
         process_full_blocks_spec,
         finalize_sha256_blocks_spec]
  · -- Props goal: result = sha256VarSpec msg message_size.toNat.
    -- simp_all rewrites using the postcondition equalities accumulated in context,
    -- then unfolds sha256VarSpec / sha256Ref / sha256With to conclude.
    simp_all [sha256VarSpec, sha256Ref, sha256With, finalizeSha256BlocksRef, processFullBlocksRef]
    -- The tuple projections `Builtin.indexTpl (h, block, ()) Member.head[.tail]` reduce definitionally.
    rfl
  -- Side goals: Sha256CompressionSpec (×2), the field/size bounds.
  all_goals first
    | exact h_comp
    | exact h_p
    | exact h_bound

-- ============================================================
-- 7.  Checked tests for computable helpers
-- ============================================================

section Tests

-- ---- paddingWordNat ----

-- 0x80 lands in the correct byte position within the u32 word.
#guard paddingWordNat 0 == 0x80000000   -- most-significant byte
#guard paddingWordNat 1 == 0x00800000
#guard paddingWordNat 2 == 0x00008000
#guard paddingWordNat 3 == 0x00000080   -- least-significant byte

-- ---- encodeLenRef ----

-- 1 byte of message → 8 bits; fits in lo, hi = 0.
#guard encodeLenRef 0 == (0, 0)
#guard encodeLenRef 1 == (8, 0)

-- ---- buildMsgBlockRef ----

-- Noir test_build_msg_block_start_0: 22-byte input "from:runner.leagues.0", block at byte 0.
private def bytes22 : List (U 8) :=
  [102, 114, 111, 109, 58, 114, 117, 110,
   110, 105, 101, 114, 46, 108, 101, 97,
   103, 117, 101, 115, 46, 48]

-- word 0 = 0x66726F6D ("from"), word 1 = 0x3A72756E (":run"),
-- word 5 = 0x2E300000 (".0\0\0"), word 6 = 0 (past message_size)
example : (buildMsgBlockRef bytes22 22 0).get ⟨0, by norm_num⟩ = (1718775661 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨1, by norm_num⟩ = (980579694 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨5, by norm_num⟩ = (774897664 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes22 22 0).get ⟨6, by norm_num⟩ = (0 : U 32) := by
  native_decide

-- Noir test_build_msg_block_start_1: 68-byte input, block starting at byte 64.
private def bytes68 : List (U 8) :=
  [102, 114, 111, 109, 58, 114, 117, 110, 110, 105, 101, 114, 46, 108, 101, 97,
   103, 117, 101, 115, 46, 48, 106, 64, 105, 99, 108, 111, 117, 100, 46, 99,
   111, 109, 13, 10, 99, 111, 110, 116, 101, 110, 116, 45, 116, 121, 112, 101,
   58, 116, 101, 120, 116, 47, 112, 108, 97, 105, 110, 59, 32, 99, 104, 97,
   114, 115, 101, 116]

-- word 0 = 0x72736574 ("rset"), word 1 = 0 (bytes 68-71 are past message_size)
example : (buildMsgBlockRef bytes68 68 64).get ⟨0, by norm_num⟩ = (1920165236 : U 32) := by
  native_decide
example : (buildMsgBlockRef bytes68 68 64).get ⟨1, by norm_num⟩ = (0 : U 32) := by
  native_decide

-- ---- attachLenRef ----

-- Noir test_attach_len_to_msg_block: message_size = 1 → bit-length = 8.
-- Words 14–15 are replaced by hi=0 and lo=8; words 0–13 are preserved.
private def blockBefore : MsgBlock :=
  ⟨[2152555847, 1397309779, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1849316213, 1651139939], rfl⟩

example : (attachLenRef blockBefore 1).get ⟨14, by norm_num⟩ = (0 : U 32) := by native_decide
example : (attachLenRef blockBefore 1).get ⟨15, by norm_num⟩ = (8 : U 32) := by native_decide

-- Words 0–13 are unchanged after attachLenRef.
example : (attachLenRef blockBefore 1).get ⟨0, by norm_num⟩ =
          blockBefore.get ⟨0, by norm_num⟩ := by native_decide

-- ---- stateToHashRef ----

-- FIPS 180-4 §5.3.3: initial hash values H₀ serialised as 32 big-endian bytes.
-- H₀[0] = 0x6A09E667 → [106, 9, 230, 103]; H₀[1] = 0xBB67AE85 → [187, 103, 174, 133]; …
example : stateToHashRef initialState =
    ⟨[106,   9, 230, 103,
      187, 103, 174, 133,
       60, 110, 243, 114,
      165,  79, 245,  58,
       81,  14,  82, 127,
      155,   5, 104, 140,
       31, 131, 217, 171,
       91, 224, 205,  25], rfl⟩ := by native_decide

end Tests

-- ============================================================
-- 8.  Computable reference for sha256CompressionFn
-- ============================================================

section Sha256Round

-- FIPS 180-4 §4.1.2: functions on 32-bit words.
private abbrev W := U 32
private def rotr (n : Nat) (x : W) : W := (x >>> n) ||| (x <<< (32 - n))
private def ch   (x y z : W) : W := (x &&& y) ^^^ (~~~x &&& z)
private def maj  (x y z : W) : W := (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)
private def bigSigma0  (x : W) : W := rotr 2  x ^^^ rotr 13 x ^^^ rotr 22 x
private def bigSigma1  (x : W) : W := rotr 6  x ^^^ rotr 11 x ^^^ rotr 25 x
private def smallSigma0 (x : W) : W := rotr 7  x ^^^ rotr 18 x ^^^ (x >>> 3)
private def smallSigma1 (x : W) : W := rotr 17 x ^^^ rotr 19 x ^^^ (x >>> 10)

-- FIPS 180-4 §4.2.2: SHA-256 round constants K[0..63].
private def kConst : Array W :=
  #[0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

/-- SHA-256 compression function (FIPS 180-4 §6.2.2).
    Computable counterpart to the opaque `sha256CompressionFn`. -/
def sha256CompressionImpl (block : MsgBlock) (state : State) : State :=
  -- Step 1: extend the 16-word block into a 64-word message schedule.
  let w : Array W :=
    (List.range 48).foldl
      (fun w i =>
        let t := i + 16
        w.push (smallSigma1 w[t - 2]! + w[t - 7]! + smallSigma0 w[t - 15]! + w[t - 16]!))
      (Array.mk block.toList)
  -- Steps 2–3: initialise working variables and run 64 rounds.
  let s : Array W := (List.range 64).foldl
      (fun s t =>
        let a := s[0]!; let b := s[1]!; let c := s[2]!; let d := s[3]!
        let e := s[4]!; let f := s[5]!; let g := s[6]!; let h := s[7]!
        let t1 := h + bigSigma1 e + ch e f g + kConst[t]! + w[t]!
        let t2 := bigSigma0 a + maj a b c
        #[t1 + t2, a, b, c, d + t1, e, f, g])
      (Array.mk state.toList)
  -- Step 4: add compressed chunk to current hash value.
  vecOfFn fun i => state.get i + s[i.val]!

-- FIPS 180-4 §B.1: SHA-256 of "abc" fits in one block.
-- Padded: "abc" + 0x80 byte, 13 zero words, 64-bit big-endian bit-length 24.
private def abcBlock : MsgBlock :=
  ⟨[0x61626380, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x18], rfl⟩

example : stateToHashRef (sha256CompressionImpl abcBlock initialState) =
    ⟨[0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
      0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
      0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
      0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad], rfl⟩ := by native_decide

/-- Computable end-to-end SHA-256: `sha256With` instantiated with the concrete
    compression function instead of the opaque builtin. -/
def sha256VarImpl := sha256With sha256CompressionImpl

-- ---- Known test vectors ----

-- Empty message (NIST / Noir `empty_sha256` test).
example : sha256VarImpl [] 0 =
    ⟨[0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
      0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
      0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
      0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55], rfl⟩ := by native_decide

-- Single byte 0xBD (Noir `smoke_test`).
example : sha256VarImpl [0xBD] 1 =
    ⟨[0x68, 0x32, 0x57, 0x20, 0xaa, 0xbd, 0x7c, 0x82,
      0xf3, 0x0f, 0x55, 0x4b, 0x31, 0x3d, 0x05, 0x70,
      0xc9, 0x5a, 0xcc, 0xbb, 0x7d, 0xc4, 0xb5, 0xaa,
      0xe1, 0x12, 0x04, 0xc0, 0x8f, 0xfe, 0x73, 0x2b], rfl⟩ := by native_decide

-- FIPS 180-4 §B.1: SHA-256("abc") — one block.
example : sha256VarImpl [0x61, 0x62, 0x63] 3 =
    ⟨[0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
      0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
      0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
      0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad], rfl⟩ := by native_decide

-- FIPS 180-4 §B.2: SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").
-- 56 bytes: the 0x80 byte falls at word 14, forcing a block flush before the length word.
private def b2msg : List (U 8) :=
  [97, 98, 99, 100, 98, 99, 100, 101, 99, 100, 101, 102, 100, 101, 102, 103,
   101, 102, 103, 104, 102, 103, 104, 105, 103, 104, 105, 106, 104, 105, 106, 107,
   105, 106, 107, 108, 106, 107, 108, 109, 107, 108, 109, 110, 108, 109, 110, 111,
   109, 110, 111, 112, 110, 111, 112, 113]

example : sha256VarImpl b2msg 56 =
    ⟨[0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
      0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
      0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
      0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1], rfl⟩ := by native_decide

end Sha256Round

end Sha256.Spec
